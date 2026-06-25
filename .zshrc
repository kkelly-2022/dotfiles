# To link to your home dir, run
# ln -sf ~/Developer/dotfiles/.zshrc ~/.zshrc

. "$HOME/.local/bin/env"

# Bun globals (including `pi`)
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export BROWSER="/Applications/Firefox.app/Contents/MacOS/firefox"

# Load local secrets (API keys, tokens, etc.) — not committed to git
# Auto-export assignments so child processes inherit them.
if [[ -f ~/Developer/dotfiles/.env.local ]]; then
  set -a
  source ~/Developer/dotfiles/.env.local
  set +a
fi

# Quality of life
setopt AUTO_CD              # Type a directory name to cd into it
setopt NO_CASE_GLOB         # Case-insensitive globbing
setopt EXTENDED_GLOB        # More powerful pattern matching

# History settings for zsh  
export HISTFILE="$HOME/.zsh_history"  
export HISTSIZE=999999999  
export SAVEHIST=$HISTSIZE  
  
# Zsh history options  
setopt HIST_IGNORE_DUPS        # Don't save duplicate commands  
setopt HIST_IGNORE_ALL_DUPS    # Delete old duplicate entries  s
setopt HIST_FIND_NO_DUPS       # Don't display duplicates when searching  
setopt HIST_SAVE_NO_DUPS       # Don't save duplicates to history file  
setopt HIST_REDUCE_BLANKS      # Remove unnecessary blanks  
setopt INC_APPEND_HISTORY      # Save commands immediately  
setopt SHARE_HISTORY           # Share history between sessions  
setopt HIST_EXPIRE_DUPS_FIRST  # Expire duplicates first when trimming  
setopt HIST_VERIFY             # Show command with history expansion

# Filter noise and secrets from history
zshaddhistory() {
  [[ $1 != *debugpy/launcher* ]] &&
  [[ $1 != *AWS_SESSION_TOKEN=* ]] &&
  [[ $1 != *AWS_SECRET_ACCESS_KEY=* ]] &&
  [[ $1 != *AWS_ACCESS_KEY_ID=* ]]
}

# Case-insensitive tab completion
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Initialize fzf for fuzzy finding
# This sets up Ctrl+R for history search, Ctrl+T for file search, and Alt+C for cd
eval "$(fzf --zsh)"

# Initialize Starship prompt
eval "$(starship init zsh)"
eval "$(fnm env --use-on-cd)"

# zsh-autosuggestions — suggests commands as you type (accept with right arrow)
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# zsh-syntax-highlighting — colors valid/invalid commands as you type
[[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# zsh-history-substring-search — type a partial command and use up/down arrows to search history for matches
# Must be sourced after syntax-highlighting
source /opt/homebrew/share/zsh-history-substring-search/zsh-history-substring-search.zsh
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# eza — modern ls with git integration and tree view
alias ls="eza"
alias ll="eza -lahF --git"
alias la="eza -a"
alias lt="eza --tree --level=2"

# bat — syntax-highlighted cat
export BAT_THEME="Nord"
alias cat="bat --style=plain --paging=never"
alias catn="bat"  # with line numbers and full styling

function grep() {
  local args=()
  for arg in "$@"; do
    case "$arg" in
      -E) ;;                    # rg uses ERE by default
      -r) args+=("--replace");;
      -R) args+=("-r");;        # grep -R (recursive) → rg -r... but rg is recursive by default
      *) args+=("$arg");;
    esac
  done
  command rg "${args[@]}"
}
function find() { command fd "$@"; }

# caffeinate — prevent sleep in a background tmux session
alias caffeine="tmux new-session -d -s caffeine 'caffeinate -di'"
alias kill-caffeine="tmux kill-session -t caffeine"
alias check-caffeine="tmux has-session -t caffeine 2>/dev/null && echo 'Caffeine is running' || echo 'Caffeine is not running'"

# Graphite — per-branch diff stats for current stack
gt-stack-stats() {
  local total_ins=0 total_del=0 total_files=0
  # Strip only the tree-art prefix for display labels so Graphite markers like
  # (frozen), (needs restack), and worktree names remain visible. Keep an
  # aligned marker-free ref array for Git, because `git diff` needs real branch
  # refs and cannot resolve labels such as `branch-name (needs restack)`.
  local -a branches branch_labels stack_rows
  stack_rows=("${(@f)$(gt log short --stack --no-interactive 2>&1 \
    | sed -E 's/^[^[:alnum:]_]*//')}")

  local row clean_ref
  for row in "${stack_rows[@]}"; do
    [[ -z "$row" ]] && continue
    clean_ref=$(printf "%s\n" "$row" | sed -E 's/([[:space:]]+\([^)]*\))+[[:space:]]*$//')
    [[ -z "$clean_ref" ]] && continue
    branches+=("$clean_ref")
    branch_labels+=("$row")
  done

  # `gt log --stack` is linear (current → trunk), so each branch's parent is
  # the next clean ref in the array and the last entry is the trunk. Skipping
  # `gt branch info` (the slow part — ~1s for 16 branches) lets rows stream
  # live as `git diff` finishes each one.
  local total=$((${#branches[@]} - 1))
  [[ $total -lt 1 ]] && return 0

  local idx
  for ((idx=1; idx<=total; idx++)); do
    local branch="${branches[idx]}"
    local parent="${branches[idx+1]}"
    local branch_label="${branch_labels[idx]}"
    local stats=$(git diff --shortstat "$parent...$branch" 2>/dev/null)
    local files=$(echo "$stats" | rg -o '[0-9]+ file' | awk '{print $1}')
    local ins=$(echo "$stats" | rg -o '[0-9]+ insertion' | awk '{print $1}')
    local del=$(echo "$stats" | rg -o '[0-9]+ deletion' | awk '{print $1}')
    total_files=$((total_files + ${files:-0}))
    total_ins=$((total_ins + ${ins:-0}))
    total_del=$((total_del + ${del:-0}))
    local file_word="files"
    [ "${files:-0}" = "1" ] && file_word="file "
    printf "%2d. | %3d %s | %7s | %7s | %s\n" \
      $((total - idx + 1)) "${files:-0}" "$file_word" \
      "+${ins:-0}" "-${del:-0}" "$branch_label"
  done

  printf "%s\n" "----+-----------+---------+---------+----------------"
  printf "    | %3d files | %7s | %7s | %d PRs Total\n" \
    "$total_files" "+$total_ins" "-$total_del" "$total"
}

# gt-find-worktrees — list worktrees and the Graphite branches they have checked out
# Usage:
#   gt-find-worktrees [gt ls args...]
#
# Uses `gt ls` ordering, then cross-references Git's worktree metadata to show
# each listed branch's worktree name. With no args, includes all trunks and
# untracked branches visible to Graphite.
gt-find-worktrees() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "gt-find-worktrees: must be run inside a Git repository" >&2
    return 1
  }

  local -A worktree_by_branch
  local line worktree branch
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        worktree="${line#worktree }"
        ;;
      branch\ refs/heads/*)
        branch="${line#branch refs/heads/}"
        worktree_by_branch[$branch]="$worktree"
        ;;
    esac
  done < <(git -C "$repo_root" worktree list --porcelain 2>/dev/null)

  local -a gt_args rows found
  if [[ $# -eq 0 ]]; then
    gt_args=(--all --show-untracked)
  else
    gt_args=("$@")
  fi

  rows=("${(@f)$(gt ls --no-interactive "${gt_args[@]}" 2>/dev/null \
    | sed -E $'s/\\x1b\\[[0-9;]*m//g; s/^[^[:alnum:]_.\\/-]*//')}")

  local row clean_ref wt_path wt_name
  for row in "${rows[@]}"; do
    [[ -z "$row" ]] && continue
    clean_ref=$(printf "%s\n" "$row" | sed -E 's/([[:space:]]+\([^)]*\))+[[:space:]]*$//')
    [[ -z "$clean_ref" ]] && continue
    wt_path="${worktree_by_branch[$clean_ref]}"
    [[ -z "$wt_path" ]] && continue
    wt_name="${wt_path:t}"
    found+=("${wt_name}"$'\t'"${clean_ref}")
  done

  if [[ ${#found[@]} -eq 0 ]]; then
    echo "gt-find-worktrees: no gt ls branches are checked out in worktrees" >&2
    return 1
  fi

  printf '%s\n' "${found[@]}" | column -t -s $'\t'
}

# gt-restack-all — restack every clean worktree in the current repo
# Usage:
#   gt-restack-all
#
# Runs `gt restack --interactive` in each worktree for the current Git repo.
# Worktrees with staged, unstaged, or untracked changes are skipped. On the
# first restack failure/conflict, the loop stops so you can resolve it there.
gt-restack-all() {
  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "gt-restack-all: must be run inside a Git repository" >&2
    return 1
  }

  local -a worktrees restacked skipped
  local failed_worktree="" failed_branch=""
  worktrees=("${(@f)$(git -C "$repo_root" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / { sub(/^worktree /, ""); print }')}")

  if [[ ${#worktrees[@]} -eq 0 ]]; then
    echo "gt-restack-all: no worktrees found for $repo_root" >&2
    return 1
  fi

  echo "Restacking ${#worktrees[@]} worktree(s) for $repo_root"

  local worktree branch worktree_status restack_status
  for worktree in "${worktrees[@]}"; do
    branch=$(git -C "$worktree" branch --show-current 2>/dev/null)
    [[ -z "$branch" ]] && branch="detached:$(git -C "$worktree" rev-parse --short HEAD 2>/dev/null)"

    echo ""
    echo "--- $branch ---"
    echo "$worktree"

    worktree_status=$(git -C "$worktree" status --porcelain --untracked-files=all)
    if [[ -n "$worktree_status" ]]; then
      echo "Skipping: worktree has staged, unstaged, or untracked changes"
      skipped+=("$branch ($worktree)")
      continue
    fi

    (cd "$worktree" && gt restack --interactive)
    restack_status=$?
    if [[ $restack_status -ne 0 ]]; then
      failed_worktree="$worktree"
      failed_branch="$branch"
      echo ""
      echo "gt-restack-all: stopped after restack failed in $worktree"
      echo "Resolve the Graphite/Git state there, then continue from that worktree:"
      echo "  cd '$worktree'"
      echo "  # resolve conflicts, then: gt add <file> ... && gt continue"
      echo "  # or abort with: gt abort"
      break
    fi

    restacked+=("$branch ($worktree)")
  done

  echo ""
  echo "========================================="
  echo "Restacked: ${#restacked[@]} worktree(s)"
  [[ ${#restacked[@]} -gt 0 ]] && printf '  %s\n' "${restacked[@]}"
  echo "Skipped dirty: ${#skipped[@]} worktree(s)"
  [[ ${#skipped[@]} -gt 0 ]] && printf '  %s\n' "${skipped[@]}"
  if [[ -n "$failed_worktree" ]]; then
    echo "Failed/stopped: $failed_branch ($failed_worktree)"
    echo "========================================="
    return $restack_status
  fi
  echo "========================================="
}

# box — file/dir clipboard with absolute path preservation
BOX_DIR="$HOME/.box"
box() {
  for arg in "$@"; do
    local abs_path="${arg:a}"
    local key="${abs_path#$HOME/}"
    mkdir -p "$BOX_DIR/${key:h}"
    rm -rf "$BOX_DIR/$key"
    cp -r "$abs_path" "$BOX_DIR/$key"
    echo "Boxed → ~/.box/$key"
  done
}
unbox() {
  for arg in "$@"; do
    local abs_path="${arg:a}"
    local key="${abs_path#$HOME/}"
    [[ ! -e "$BOX_DIR/$key" ]] && echo "Nothing in box at $key" && continue
    rm -rf "$abs_path"
    cp -r "$BOX_DIR/$key" "$abs_path"
    rm -rf "$BOX_DIR/$key"
    echo "Unboxed ← ~/.box/$key"
  done
}
lsbox() { eza --tree --all --level="${1:-4}" "$BOX_DIR" 2>/dev/null || echo "Box is empty"; }

# Global beads dir
export BEADS_DIR="$HOME/Developer/beads/.beads"

DOTFILE_REPO=~/Developer/dotfiles
alias code-dotfiles="code $DOTFILE_REPO"
alias code-plans="code ~/.claude/plans"
alias cd-dotfiles="cd $DOTFILE_REPO"

# ─── State Affairs workflow functions ─────────────────────────────────────────

SA=~/Developer/state-affairs
SA_FRONTEND=$SA/frontend
SA_BACKEND=$SA/backend
SA_ADMIN=$SA/admin
SA_CRONS=$SA/crons
SA_DATACORE=$SA/datacore
SA_QUEUE=$SA/queue-consumer
SA_MOBILE=$SA/mobile
SA_KAFKA=$SA/kafka

alias code-frontend="code $SA_FRONTEND"
alias code-backend="code $SA_BACKEND"
alias code-admin="code $SA_ADMIN"
alias code-datacore="code $SA_DATACORE"
alias code-crons="code $SA_CRONS"
alias code-queue="code $SA_QUEUE"
alias code-mobile="code $SA_MOBILE"
alias code-kafka="code $SA_KAFKA"
alias cd-frontend="cd $SA_FRONTEND"
alias cd-backend="cd $SA_BACKEND"
alias cd-admin="cd $SA_ADMIN"
alias cd-datacore="cd $SA_DATACORE"
alias cd-crons="cd $SA_CRONS"
alias cd-queue="cd $SA_QUEUE"
alias cd-mobile="cd $SA_MOBILE"

alias datacore-prepush-ruff="(cd $SA_DATACORE && uv run ruff check && uv run ruff format --check)"
alias datacore-prepush-ruff-fix="(cd $SA_DATACORE && uv run ruff check --fix && uv run ruff format)"
alias datacore-prepush-ty="(cd $SA_DATACORE && bash scripts/ty_check_pr_files.sh)"
alias datacore-prepush-uv="(cd $SA_DATACORE && uv lock --check)"
alias datacore-prepush-src="(cd $SA_DATACORE && bash scripts/lint_src_imports.sh --ratchet)"
alias datacore-prepush-tests="(cd $SA_DATACORE && uv run python -m tests.run_unit_tests)"
alias datacore-prepush=".githooks/pre-push"
alias datacore-prepush-ci="SKIP=unit-tests uv run pre-commit run --hook-stage pre-push --from-ref origin/main --to-ref HEAD && uv run python -m tests.run_unit_tests --ci"


alias psql-local="psql -h localhost -U postgres -d postgres"


# Strips ` CONCURRENTLY` from multi-statement migration SQL files for the
# duration of the wrapped command, then restores. Works around Prisma's
# shadow-DB transaction wrapping, which only kicks in for files with 2+
# statements. Single-statement CONCURRENTLY migrations are left alone so
# their checksums don't drift against already-applied rows.
strip-concurrent-migrations-around() {
  local migrations_dir="$SA_BACKEND/src/prisma/migrations"
  local backup_dir
  backup_dir=$(mktemp -d)
  local -a patched
  for f in "$migrations_dir"/*/migration.sql; do
    grep -q "CONCURRENTLY" "$f" || continue
    [[ $(grep -c ';' "$f") -lt 2 ]] && continue
    local name
    name=$(basename "$(dirname "$f")")
    cp "$f" "$backup_dir/$name.sql"
    sed -i '' 's/ CONCURRENTLY//g' "$f"
    patched+=("$f|$backup_dir/$name.sql")
  done
  "$@"
  local exit_code=$?
  for entry in "${patched[@]}"; do
    cp "${entry##*|}" "${entry%%|*}"
  done
  rm -rf "$backup_dir"
  return $exit_code
}

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

codegen-backend() {
  (
    cd $SA_BACKEND &&
    npm run prisma:migrate &&
    npx prisma format &&
    npm run prisma:generate &&
    npm run generate:schema
  )
}

gql-sync() {
  (
    cd $SA_BACKEND &&
    npx graphql-inspector introspect http://localhost:3000/graphql \
      --header "operationname: IntrospectionQuery" &&
    cp graphql.schema.json $SA_DATACORE/utils/graphql/dc/graphql/generated/schema.json &&
    cd $SA_DATACORE &&
    uv run sgqlc-codegen schema utils/graphql/dc/graphql/generated/schema.json utils/graphql/dc/graphql/generated/generated_schema.py &&
    ruff format utils/graphql/dc/graphql/generated/generated_schema.py
  )
}

# refresh-cleanup — run pre-migration data fixes on the local dev DB.
# Invoked by refresh-apps between snapshot restore and prisma migrate,
# but safe to run standalone after a failed migration.
refresh-cleanup() {
  local sql_file="$DOTFILE_REPO/scripts/refresh-cleanup.sql"
  if [[ ! -f "$sql_file" ]]; then
    echo "No cleanup file at $sql_file — skipping"
    return 0
  fi
  PGPASSWORD=root psql -h localhost -p 5432 -U postgres -d dev \
    -v ON_ERROR_STOP=1 -f "$sql_file"
}

# dev-sync — Migrate, generate, and codegen in one command
# Runs backend migrations + Prisma generate, then triggers GraphQL codegen
# across frontend, admin, and mobile (if the backend server is running).
#
# Pass --cached to reuse the previously downloaded/extracted greenmask
# dump at ~/.cache/sa-greenmask/extracted (falls back to a fresh
# download if the cache is missing). Without --cached, always refetches
# from S3 and overwrites the cache.
refresh-apps() {
  local use_cache=false
  [[ "$1" == "--cached" ]] && use_cache=true && shift

  local cache_dir="$HOME/.cache/sa-greenmask"
  local extracted="$cache_dir/extracted"
  local tarball="$cache_dir/greenmask_dump.tar.gz"
  local s3_path="s3://sa-rds-dev-dump/greenmask_dump.tar.gz"

  if ! $use_cache || [[ ! -d "$extracted/dumps" ]]; then
    mkdir -p "$cache_dir"
    rm -rf "$extracted" && mkdir -p "$extracted"
    echo "Downloading greenmask dump from S3..."
    aws s3 cp "$s3_path" "$tarball" || return 1
    tar -xzf "$tarball" -C "$extracted" || return 1
    if [[ ! -d "$extracted/dumps" && -d "$extracted/greenmask/dumps" ]]; then
      mv "$extracted/greenmask"/* "$extracted/" && rmdir "$extracted/greenmask"
    fi
    [[ ! -f "$extracted/greenmask" ]] && cp "$SA_BACKEND/.infra/greenmask/greenmask" "$extracted/"
    [[ ! -f "$extracted/config.yml" ]] && cp "$SA_BACKEND/.infra/greenmask/config.yml" "$extracted/" 2>/dev/null || true
  else
    echo "Using cached greenmask dump at $extracted"
  fi

  (cd $SA_BACKEND && prisma-clean-migrations . && npm run db:refresh -- -g "$extracted" -w root -f && refresh-cleanup && strip-concurrent-migrations-around codegen-backend && pnpm run proto:generate && pnpm i)
  (cd $SA_FRONTEND && npm i)
  (cd $SA_ADMIN && npm i)
  (cd $SA_DATACORE && uv sync --locked --all-extras --dev && ENV=local uv run -m database.bootstrap --migrate)
}

# run-apps — Start backend, frontend, and admin in a zellij session
# Each app gets its own pane with logs teed to ~/Developer/dotfiles/logs/sa-*.log
# Usage: run-apps (attach with `zellij attach sa` if detached)
# Dependency installs are handled by refresh-apps.
SA_LOGS=~/Developer/dotfiles/logs
run-apps() {
  zellij delete-session sa --force 2>/dev/null || true
  mkdir -p $SA_LOGS

  local layout_dir layout_file
  layout_dir=$(mktemp -d "${TMPDIR:-/tmp}/sa-zellij-layout.XXXXXX") || return 1
  layout_file="$layout_dir/layout.kdl"

  command cat > "$layout_file" <<EOF
layout {
  pane split_direction="Vertical" {
    pane command="bash" {
      args "-lc" "cd $SA_BACKEND && pnpm run dev 2>&1 | tee $SA_LOGS/backend.log"
    }
    pane split_direction="Horizontal" {
      pane command="bash" {
        args "-lc" "until curl -sf http://localhost:3000/api/health > /dev/null 2>&1; do sleep 2; done; cd $SA_FRONTEND && npm run dev 2>&1 | tee $SA_LOGS/frontend.log"
      }
      pane command="bash" {
        args "-lc" "until curl -sf http://localhost:3000/api/health > /dev/null 2>&1; do sleep 2; done; cd $SA_ADMIN && npm run dev 2>&1 | tee $SA_LOGS/admin.log"
      }
    }
  }
}
EOF

  zellij --new-session-with-layout "$layout_file" --session sa
  rm -rf "$layout_dir"
}

alias logs-backend="tail -f -n 200 $SA_LOGS/backend.log"
alias logs-frontend="tail -f -n 200 $SA_LOGS/frontend.log"
alias logs-admin="tail -f -n 200 $SA_LOGS/admin.log"
alias logs-all="tail -f -n 200 $SA_LOGS/backend.log $SA_LOGS/frontend.log $SA_LOGS/admin.log"
kill-apps() { zellij delete-session sa --force 2>/dev/null || true; }

# sync-repos — Pull and sync all repos at once
# Fetches and pulls main across all State Affairs repos, runs gt sync,
# and safely skips any repo with uncommitted changes.
sync-repos() {
  local repos=(
    $SA_FRONTEND
    $SA_BACKEND
    $SA_CRONS
    $SA_DATACORE
    $SA_ADMIN
    $SA_QUEUE
    $SA_MOBILE
    $SA_KAFKA
  )

  local synced=()
  local fetch_only=()

  for repo in "${repos[@]}"; do
    local name=$(basename "$repo")
    echo "\n--- $name ---"

    git -C "$repo" fetch

    if [[ -n $(git -C "$repo" status --porcelain) ]]; then
      echo "  Uncommitted changes — fetch only"
      fetch_only+=("$name")
      continue
    fi

    local branch=$(git -C "$repo" branch --show-current)

    if [[ "$branch" == "main" ]]; then
      git -C "$repo" pull && (cd "$repo" && gt sync)
    else
      git -C "$repo" checkout main && git -C "$repo" pull && (cd "$repo" && gt sync)
      git -C "$repo" checkout "$branch"
    fi
    synced+=("$name")
  done

  echo "\n========================================="
  echo "Synced: ${#synced[@]}/${#repos[@]} repos"
  [[ ${#synced[@]} -gt 0 ]] && echo "  Synced: ${(j:, :)synced}"
  [[ ${#fetch_only[@]} -gt 0 ]] && echo "  Fetch only: ${(j:, :)fetch_only}"
  echo "========================================="
}

# dc-worktree — create / park / remove a Graphite worktree under datacore/.worktrees.
# Logic lives in the versioned script; this is a thin wrapper.
#   dc-worktree <name> [base]          create .worktrees/<name> parked on wt/<name> off <base> (default main)
#   dc-worktree --park <name>          idle the worktree on its empty wt/<name> branch
#   dc-worktree --track-parked [base]  track existing wt/* parking branches in Graphite (default main)
#   dc-worktree --rm [-f] <name>       remove the worktree and delete wt/<name>
dc-worktree() {
  "$DOTFILE_REPO/scripts/dc-worktree.sh" "$@"
}