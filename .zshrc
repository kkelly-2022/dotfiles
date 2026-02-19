# To link to your home dir, run
# ln -sf ~/Developer/dotfiles/.zshrc ~/.zshrc

. "$HOME/.local/bin/env"

# Load local secrets (API keys, tokens, etc.) — not committed to git
[[ -f ~/Developer/dotfiles/.env.local ]] && source ~/Developer/dotfiles/.env.local

# Quality of life
setopt AUTO_CD              # Type a directory name to cd into it
setopt CORRECT              # Suggest corrections for typos
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

alias grep="rg"
alias find="fd"

# Global beads dir
export BEADS_DIR="$HOME/Developer/beads/.beads"

# ─── State Affairs workflow functions ─────────────────────────────────────────

SA=~/Developer/state-affairs
SA_FRONTEND=$SA/frontend
SA_BACKEND=$SA/backend
SA_ADMIN=$SA/admin
SA_CRONS=$SA/crons
SA_DATACORE=$SA/datacore
SA_QUEUE=$SA/queue-consumer
SA_MOBILE=$SA/mobile

alias code-frontend="code $SA_FRONTEND"
alias code-backend="code $SA_BACKEND"
alias code-admin="code $SA_ADMIN"
alias code-datacore="code $SA_DATACORE"
alias code-crons="code $SA_CRONS"
alias code-queue="code $SA_QUEUE"
alias code-mobile="code $SA_MOBILE"


codegen-backend() {
  (
    cd $SA_BACKEND &&
    npm run prisma:migrate &&
    npx prisma format &&
    npm run prisma:generate &&
    npm run generate:schema
  )
}


# dev-sync — Migrate, generate, and codegen in one command
# Runs backend migrations + Prisma generate, then triggers GraphQL codegen
# across frontend, admin, and mobile (if the backend server is running).
refresh-apps() {
  (cd $SA_BACKEND && npm run db:refresh -- -w root -f && codegen-backend && npm i)
  (cd $SA_FRONTEND && npm i)
  (cd $SA_ADMIN && npm i)
  (cd $SA_DATACORE && uv sync)
}

# run-apps — Start backend, frontend, and admin in a tmux session
# Each app gets its own pane with logs teed to ~/.logs/sa-*.log
# Usage: run-apps (attach with `tmux attach -t sa` if detached)
SA_LOGS=~/Developer/dotfiles/logs
run-apps() {
  mkdir -p $SA_LOGS

  (cd $SA_BACKEND && npm i)

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