#!/usr/bin/env zsh
# refresh-apps — Refresh local State Affairs dependencies, database state, and clients.
#
# Usage: scripts/refresh-apps.zsh [--cached] [--from <step-or-number>]
# Run `refresh-apps --help` from a configured shell for stage details.

SCRIPT_DIR="${0:A:h}"
DOTFILE_REPO="${DOTFILE_REPO:-${SCRIPT_DIR:h}}"
SA="${SA:-$HOME/Developer/state-affairs}"
SA_FRONTEND="${SA_FRONTEND:-$SA/frontend}"
SA_BACKEND="${SA_BACKEND:-$SA/backend}"
SA_ADMIN="${SA_ADMIN:-$SA/admin}"
SA_DATACORE="${SA_DATACORE:-$SA/datacore}"

# Support direct invocation as well as the .zshrc wrapper.
if [[ -f "$DOTFILE_REPO/.env.local" ]]; then
  set -a
  source "$DOTFILE_REPO/.env.local"
  set +a
fi

prisma-clean-migrations() {
  local dir="${1:-.}/src/prisma/migrations"
  [[ ! -d "$dir" ]] && echo "No migrations dir at $dir" && return 1
  local removed=0
  for d in "$dir"/*/; do
    if [[ ! -s "$d/migration.sql" ]]; then
      echo "Removing $(basename "$d")"
      rm -rf "$d"
      ((removed++))
    fi
  done
  echo "Removed $removed empty migration(s)"
}

# Discard backend changes only when every changed path is a Prisma migration or
# the generated root schema.graphql.
discard-backend-migration-only-changes() {
  local changed_output changed_path
  local -a changed_paths non_migration_paths

  changed_output=$({
    git -C "$SA_BACKEND" diff --name-only
    git -C "$SA_BACKEND" diff --name-only --cached
    git -C "$SA_BACKEND" ls-files --others --exclude-standard
  } | sort -u) || return

  [[ -z "$changed_output" ]] && return 0
  changed_paths=("${(@f)changed_output}")

  for changed_path in "${changed_paths[@]}"; do
    case "$changed_path" in
      src/prisma/migrations/*|schema.graphql) ;;
      *) non_migration_paths+=("$changed_path") ;;
    esac
  done

  if (( ${#non_migration_paths[@]} > 0 )); then
    echo "Backend has changes outside refresh-generated files; refusing to discard anything:" >&2
    printf '  %s\n' "${non_migration_paths[@]}" >&2
    return 1
  fi

  echo "Discarding refresh-generated backend changes:"
  printf '  %s\n' "${changed_paths[@]}"
  git -C "$SA_BACKEND" restore --staged --worktree -- src/prisma/migrations schema.graphql || return
  git -C "$SA_BACKEND" clean -fd -- src/prisma/migrations || return
}

# Greenmask's migration ledger can differ from the checked-out schema; the local
# DB is disposable, so synchronize it with Prisma rather than migrate dev.
codegen-backend() {
  (
    cd "$SA_BACKEND" &&
    npx prisma db push --accept-data-loss &&
    npx prisma format &&
    npm run prisma:generate &&
    npm run generate:schema
  )
}

refresh-backend-pre-migrate() {
  local sql_file="$DOTFILE_REPO/scripts/refresh-backend-pre-migrate.sql"
  if [[ ! -f "$sql_file" ]]; then
    echo "No backend pre-migrate file at $sql_file — skipping"
    return 0
  fi
  PGPASSWORD=root psql -h localhost -p 5432 -U postgres -d dev \
    -v ON_ERROR_STOP=1 -f "$sql_file"
}

refresh-backend-post-migrate() {
  local sql_file="$DOTFILE_REPO/scripts/refresh-backend-post-migrate.sql"
  if [[ ! -f "$sql_file" ]]; then
    echo "No backend post-migrate file at $sql_file — skipping"
    return 0
  fi
  PGPASSWORD=root psql -h localhost -p 5432 -U postgres -d dev \
    -v ON_ERROR_STOP=1 -f "$sql_file"
}

refresh-backend-migrate() {
  discard-backend-migration-only-changes || return
  refresh-backend-pre-migrate || return
  codegen-backend || return
  refresh-backend-post-migrate
}

main() {
  local use_cache=false from_step="" show_help=false resume_cache_flag=""
  local cache_dir="$HOME/.cache/sa-greenmask"
  local extracted="$cache_dir/extracted"
  local tarball="$cache_dir/greenmask_dump.tar.gz"
  local s3_path="s3://sa-rds-dev-dump/greenmask_dump.tar.gz"
  local -a stage_names completed skipped not_run
  stage_names=(
    greenmask
    backend-install
    backend-clean-migrations
    backend-restore
    backend-migrate
    backend-generate
    frontend
    admin
    datacore
  )

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cached)
        if $use_cache; then
          echo "refresh-apps: --cached may only be supplied once" >&2
          return 2
        fi
        use_cache=true
        ;;
      --from)
        if [[ -n "$from_step" ]]; then
          echo "refresh-apps: --from may only be supplied once" >&2
          return 2
        fi
        if [[ $# -lt 2 || "$2" == --* ]]; then
          echo "refresh-apps: --from requires a step name or number" >&2
          return 2
        fi
        from_step="$2"
        shift
        ;;
      --help|-h)
        if $show_help; then
          echo "refresh-apps: --help may only be supplied once" >&2
          return 2
        fi
        show_help=true
        ;;
      *)
        echo "refresh-apps: unknown argument: $1" >&2
        return 2
        ;;
    esac
    shift
  done

  if $show_help; then
    cat <<'EOF'
Usage: refresh-apps [--cached] [--from <step-or-number>]

Refresh steps:
  1. greenmask                  download/extract the Greenmask database dump
  2. backend-install            install backend dependencies
  3. backend-clean-migrations   remove local empty Prisma migrations
  4. backend-restore            restore the database dump
  5. backend-migrate            synchronize Prisma schema and run local hooks
  6. backend-generate           generate proto, Kafka, resource, and Connect clients
  7. frontend                   install frontend dependencies
  8. admin                      install admin dependencies
  9. datacore                   sync dependencies and run bootstrap migrations

Options:
  --cached       reuse the extracted Greenmask dump when starting at greenmask
  --from <step-or-number>  skip earlier steps and continue at a named step or number
  --help, -h     show this help

A --from target after greenmask requires a cached dump at ~/.cache/sa-greenmask/extracted.
EOF
    return 0
  fi

  if $use_cache; then
    resume_cache_flag=" --cached"
  fi

  local start_index=1 index step step_status
  if [[ -n "$from_step" ]]; then
    if [[ "$from_step" =~ '^[0-9]+$' ]]; then
      start_index=$((10#$from_step))
    else
      start_index=${stage_names[(i)$from_step]}
    fi

    if (( start_index < 1 || start_index > ${#stage_names} )); then
      echo "refresh-apps: unknown --from step: $from_step" >&2
      echo "Run 'refresh-apps --help' to see available steps." >&2
      return 2
    fi
    skipped=("${stage_names[@]:0:$((start_index - 1))}")

    if (( start_index > 1 )) && [[ ! -d "$extracted/dumps" ]]; then
      echo "refresh-apps: cannot resume at $from_step; Greenmask cache is missing: $extracted" >&2
      echo "Restart from Greenmask: refresh-apps${resume_cache_flag} --from greenmask" >&2
      echo "\nRefresh summary"
      echo "  Completed: none"
      [[ ${#skipped[@]} -gt 0 ]] && echo "  Skipped: ${(j:, :)skipped}"
      echo "  Failed: Greenmask cache prerequisite"
      return 1
    fi
  fi

  local total=${#stage_names}
  for ((index = start_index; index <= total; index++)); do
    step="${stage_names[index]}"
    echo "\n--- [$index/$total] $step ---"

    case "$step" in
      greenmask)
        if ! $use_cache || [[ ! -d "$extracted/dumps" ]]; then
          mkdir -p "$cache_dir" && rm -rf "$extracted" && mkdir -p "$extracted"
          step_status=$?
          if (( step_status == 0 )); then
            echo "Downloading greenmask dump from S3..."
            aws s3 cp "$s3_path" "$tarball"
            step_status=$?
          fi
          if (( step_status == 0 )); then
            tar -xzf "$tarball" -C "$extracted"
            step_status=$?
          fi
          if (( step_status == 0 )) && [[ ! -d "$extracted/dumps" && -d "$extracted/greenmask/dumps" ]]; then
            mv "$extracted/greenmask"/* "$extracted/" && rmdir "$extracted/greenmask"
            step_status=$?
          fi
          if (( step_status == 0 )) && [[ ! -f "$extracted/greenmask" ]]; then
            cp "$SA_BACKEND/.infra/greenmask/greenmask" "$extracted/"
            step_status=$?
          fi
          if (( step_status == 0 )) && [[ ! -f "$extracted/config.yml" ]]; then
            cp "$SA_BACKEND/.infra/greenmask/config.yml" "$extracted/" 2>/dev/null || true
          fi
        else
          echo "Using cached greenmask dump at $extracted"
          step_status=0
        fi
        ;;
      backend-install)
        (cd "$SA_BACKEND" && SKIP_POSTINSTALL=1 pnpm i)
        step_status=$?
        ;;
      backend-clean-migrations)
        (cd "$SA_BACKEND" && discard-backend-migration-only-changes && prisma-clean-migrations . && discard-backend-migration-only-changes)
        step_status=$?
        ;;
      backend-restore)
        (cd "$SA_BACKEND" && npm run db:refresh -- -g "$extracted" -w root -f)
        step_status=$?
        ;;
      backend-migrate)
        (cd "$SA_BACKEND" && refresh-backend-migrate)
        step_status=$?
        ;;
      backend-generate)
        (cd "$SA_BACKEND" && pnpm run proto:generate && pnpm run kafka:setup-local && pnpm run generate:frontend-resources && pnpm run generate:connect-apis)
        step_status=$?
        ;;
      frontend)
        (cd "$SA_FRONTEND" && npm i)
        step_status=$?
        ;;
      admin)
        (cd "$SA_ADMIN" && npm i)
        step_status=$?
        ;;
      datacore)
        (cd "$SA_DATACORE" && uv sync --locked --all-extras --dev && ENV=local uv run -m database.bootstrap --migrate)
        step_status=$?
        ;;
    esac

    if (( step_status != 0 )); then
      not_run=("${stage_names[@]:$index}")
      echo "\nRefresh summary"
      [[ ${#completed[@]} -gt 0 ]] && echo "  Completed: ${(j:, :)completed}" || echo "  Completed: none"
      [[ ${#skipped[@]} -gt 0 ]] && echo "  Skipped: ${(j:, :)skipped}" || echo "  Skipped: none"
      [[ ${#not_run[@]} -gt 0 ]] && echo "  Not run: ${(j:, :)not_run}"
      echo "  Failed: $step"
      echo "\nTo continue: refresh-apps${resume_cache_flag} --from $step"
      return $step_status
    fi

    completed+=("$step")
  done

  echo "\nRefresh summary"
  echo "  Completed: ${(j:, :)completed}"
  [[ ${#skipped[@]} -gt 0 ]] && echo "  Skipped: ${(j:, :)skipped}" || echo "  Skipped: none"
  echo "  Failed: none"
}

main "$@"
