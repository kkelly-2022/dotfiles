# To link to your home dir, run
# ln -sf ~/Developer/dotfiles/.zshrc ~/.zshrc

. "$HOME/.local/bin/env"

# Bun globals (including `pi`)
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export BROWSER="/Applications/Firefox.app/Contents/MacOS/firefox"

# Load local secrets (API keys, tokens, etc.) — not committed to git
[[ -f ~/Developer/dotfiles/.env.local ]] && source ~/Developer/dotfiles/.env.local

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
  local i=0 total_ins=0 total_del=0 total_files=0
  local branches=("${(@f)$(gt log short --stack --no-interactive 2>&1 | awk '{print $NF}')}")
  for branch in "${branches[@]}"; do
    local parent=$(gt branch info "$branch" --no-interactive 2>/dev/null | awk '/Parent:/{print $2}')
    if [ -n "$parent" ]; then
      i=$((i + 1))
      local stats=$(git diff --shortstat "$parent...$branch" 2>/dev/null)
      local files=$(echo "$stats" | rg -o '[0-9]+ file' | awk '{print $1}')
      local ins=$(echo "$stats" | rg -o '[0-9]+ insertion' | awk '{print $1}')
      local del=$(echo "$stats" | rg -o '[0-9]+ deletion' | awk '{print $1}')
      total_files=$((total_files + ${files:-0}))
      total_ins=$((total_ins + ${ins:-0}))
      total_del=$((total_del + ${del:-0}))
      printf "%2d. %-52s %s\n" "$i" "$branch" "$stats"
    fi
  done
  if [ "$i" -gt 0 ]; then
    printf "%s\n" "---"
    printf "    %-52s %d PRs, %d files, +%d/-%d lines\n" "Total" "$i" "$total_files" "$total_ins" "$total_del"
  fi
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
alias datacore-prepush="uv run pre-commit run --hook-stage pre-push --from-ref origin/main --to-ref HEAD"
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

  (cd $SA_BACKEND && prisma-clean-migrations . && npm run db:refresh -- -g "$extracted" -w root -f && refresh-cleanup && strip-concurrent-migrations-around codegen-backend && npm i)
  (cd $SA_FRONTEND && npm i)
  (cd $SA_ADMIN && npm i)
  (cd $SA_DATACORE && uv sync && ENV=local uv run -m database.bootstrap --migrate)
}

# run-apps — Start backend, frontend, and admin in a zellij session
# Each app gets its own pane with logs teed to ~/Developer/dotfiles/logs/sa-*.log
# Usage: run-apps (attach with `zellij attach sa` if detached)
SA_LOGS=~/Developer/dotfiles/logs
run-apps() {
  kill-apps && mkdir -p $SA_LOGS

  (cd $SA_BACKEND && npm i)
  (cd $SA_FRONTEND && npm i)
  (cd $SA_ADMIN && npm i)

  local layout_file
  layout_file=$(mktemp "${TMPDIR:-/tmp}/sa-zellij-layout.XXXXXX.kdl")

  cat > "$layout_file" <<EOF
layout {
  pane split_direction="Vertical" {
    pane command="bash" {
      args "-lc" "cd $SA_BACKEND && npm run dev 2>&1 | tee $SA_LOGS/backend.log"
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
  rm -f "$layout_file"
}

alias logs-backend="tail -f -n 200 $SA_LOGS/backend.log"
alias logs-frontend="tail -f -n 200 $SA_LOGS/frontend.log"
alias logs-admin="tail -f -n 200 $SA_LOGS/admin.log"
alias logs-all="tail -f -n 200 $SA_LOGS/backend.log $SA_LOGS/frontend.log $SA_LOGS/admin.log"
alias kill-apps="zellij delete-session sa --force 2>/dev/null || true"

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

# dc-worktree — create/remove a Graphite worktree under datacore/.worktrees
# Usage:
#   dc-worktree <name>              create .worktrees/<name> on branch wt/<name>
#   dc-worktree --rm [-f] <name>    remove worktree and its wt/<name> branch
dc-worktree() {
  if [[ "$(git rev-parse --show-toplevel 2>/dev/null)" != "$SA_DATACORE" ]]; then
    echo "dc-worktree: must be run from $SA_DATACORE" >&2
    return 1
  fi

  (
    emulate -L bash
    set -euo pipefail

    local REPO_ROOT="$SA_DATACORE"
    local WT_DIR="$REPO_ROOT/.worktrees"
    local SYMLINK_FILES=(.env .env.local)
    local SYMLINK_DIRS=(.venv output)

    usage() {
      cat <<EOF
Usage:
  dc-worktree <name>              Create a worktree for a feature
  dc-worktree --rm [-f] <name>    Remove a worktree and its workspace branch

Creates .worktrees/<name> with branch wt/<name> on the Graphite stack.
EOF
      exit 1
    }

    create_worktree() {
      local name="$1"
      local wt_path="$WT_DIR/$name"
      local branch="wt/$name"

      if [[ -d "$wt_path" ]]; then
        echo "Error: worktree already exists at $wt_path" >&2
        exit 1
      fi

      gt create "$branch"
      gt checkout -

      mkdir -p "$WT_DIR"
      git worktree add "$wt_path" "$branch"

      local f
      for f in "${SYMLINK_FILES[@]}"; do
        if [[ -f "$REPO_ROOT/$f" ]]; then
          ln -s "../../$f" "$wt_path/$f"
        fi
      done

      local d
      for d in "${SYMLINK_DIRS[@]}"; do
        if [[ -d "$REPO_ROOT/$d" ]]; then
          ln -s "../../$d" "$wt_path/$d"
        fi
      done

      echo ""
      echo "Worktree ready at $wt_path"
      echo ""
      echo "  cd $wt_path"
      echo "  gt create <first-branch-name>"
      echo ""
      echo "Before submitting, restack your first PR onto its target:"
      echo "  gt move <first-branch> --onto <target>"
    }

    remove_worktree() {
      local force=false
      if [[ "${1:-}" == "-f" ]]; then
        force=true
        shift
      fi

      local name="${1:-}"
      if [[ -z "$name" ]]; then
        usage
      fi

      local wt_path="$WT_DIR/$name"
      local branch="wt/$name"

      if [[ ! -d "$wt_path" ]]; then
        echo "Error: no worktree at $wt_path" >&2
        exit 1
      fi

      if ! $force; then
        local status
        status="$(git -C "$wt_path" status --porcelain)"
        if [[ -n "$status" ]]; then
          echo "Error: worktree has uncommitted changes. Use -f to force." >&2
          echo "$status" >&2
          exit 1
        fi
      fi

      local f
      for f in "${SYMLINK_FILES[@]}" "${SYMLINK_DIRS[@]}"; do
        [[ -L "$wt_path/$f" ]] && rm "$wt_path/$f"
      done

      if $force; then
        git worktree remove --force "$wt_path"
      else
        git worktree remove "$wt_path"
      fi

      git branch -D "$branch" 2>/dev/null || true

      echo "Removed worktree $name and branch $branch"
      echo ""
      echo "If you submitted PRs from this worktree, clean them up:"
      echo "  gt branch delete <branch-name>"
    }

    if [[ $# -eq 0 ]]; then
      usage
    fi

    case "$1" in
      --rm)
        shift
        remove_worktree "$@"
        ;;
      -h|--help)
        usage
        ;;
      *)
        if [[ $# -ne 1 ]]; then
          usage
        fi
        create_worktree "$1"
        ;;
    esac
  )
}