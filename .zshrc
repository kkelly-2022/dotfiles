# To link to your home dir, run
# ln -sf ~/Developer/dotfiles/.zshrc ~/.zshrc

. "$HOME/.local/bin/env"

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
lsbox() { eza --tree --level="${1:-4}" "$BOX_DIR" 2>/dev/null || echo "Box is empty"; }

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
alias datacore-prepush="datacore-prepush-ruff && datacore-prepush-ty && datacore-prepush-uv && datacore-prepush-src && datacore-prepush-tests"

alias psql-local="psql -h localhost -U postgres -d postgres"


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
    uv run sgqlc-codegen schema utils/graphql/dc/graphql/generated/schema.json utils/graphql/dc/graphql/generated/generated_schema.py
  )
}

# dev-sync — Migrate, generate, and codegen in one command
# Runs backend migrations + Prisma generate, then triggers GraphQL codegen
# across frontend, admin, and mobile (if the backend server is running).
refresh-apps() {
  (cd $SA_BACKEND && prisma-clean-migrations . && npm run db:refresh -- -w root -f && codegen-backend && npm i)
  (cd $SA_FRONTEND && npm i)
  (cd $SA_ADMIN && npm i)
  (cd $SA_DATACORE && uv sync)
}

# run-apps — Start backend, frontend, and admin in a tmux session
# Each app gets its own pane with logs teed to ~/.logs/sa-*.log
# Usage: run-apps (attach with `tmux attach -t sa` if detached)
SA_LOGS=~/Developer/dotfiles/logs
run-apps() {
  kill-apps && mkdir -p $SA_LOGS

  (cd $SA_BACKEND && npm i)
``
  tmux new-session -d -s sa -n apps \
    "cd $SA_BACKEND && npm run dev 2>&1 | tee $SA_LOGS/backend.log"

  echo "Waiting for backend to be ready..."
  until curl -sf http://localhost:3000/api/health > /dev/null 2>&1; do
    sleep 2
  done
  echo "Backend is up — starting frontend and admin."

  (cd $SA_FRONTEND && npm i)
  (cd $SA_ADMIN && npm i)

  tmux split-window -h -t sa:apps \
    "cd $SA_FRONTEND && npm run dev 2>&1 | tee $SA_LOGS/frontend.log"

  tmux split-window -v -t sa:apps.1 \
    "cd $SA_ADMIN && npm run dev 2>&1 | tee $SA_LOGS/admin.log"

  tmux select-layout -t sa:apps main-vertical
  tmux attach -t sa
}

alias logs-backend="tail -f -n 200 $SA_LOGS/backend.log"
alias logs-frontend="tail -f -n 200 $SA_LOGS/frontend.log"
alias logs-admin="tail -f -n 200 $SA_LOGS/admin.log"
alias logs-all="tail -f -n 200 $SA_LOGS/backend.log $SA_LOGS/frontend.log $SA_LOGS/admin.log"
alias kill-apps="tmux kill-session -t sa"

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