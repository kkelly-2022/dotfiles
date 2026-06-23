#!/usr/bin/env bash
#
# dc-worktree — create / park / remove a Graphite worktree under datacore/.worktrees
#
# Topology (sibling-parking): the parking branch wt/<name> is a sibling of the
# real work, never its parent. The worktree sits on the empty wt/<name> branch
# when idle so it doesn't pin a real branch during restacks. Removing a worktree
# deletes only wt/<name>; the real stack survives on its base.
#
# Usage:
#   dc-worktree <name> [base]       Create .worktrees/<name> parked on wt/<name> off <base> (default main)
#   dc-worktree --park <name>       Idle the worktree on its empty wt/<name> branch
#   dc-worktree --rm [-f] <name>    Remove the worktree and delete wt/<name> (real branches untouched)
#
# <name> may be a bare slug or a path; its basename is used so the worktree
# always lands under .worktrees/.

set -euo pipefail

REPO_ROOT="${SA_DATACORE:-$HOME/Developer/state-affairs/datacore}"
WT_DIR="$REPO_ROOT/.worktrees"
SYMLINK_PATHS=(.env .env.local output)

usage() {
  sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

require_datacore() {
  if [[ ! -d "$REPO_ROOT/.git" && ! -f "$REPO_ROOT/.git" ]]; then
    echo "dc-worktree: datacore repo not found at $REPO_ROOT" >&2
    exit 1
  fi
}

slug() {
  # basename of the arg, so `.worktrees/foo` or `foo/bar` → the canonical name
  printf '%s' "${1##*/}"
}

create_worktree() {
  local name base wt_path branch
  name=$(slug "${1:?name required}")
  base="${2:-main}"
  wt_path="$WT_DIR/$name"
  branch="wt/$name"

  if [[ -e "$wt_path" ]]; then
    echo "dc-worktree: worktree already exists at $wt_path" >&2
    exit 1
  fi
  if ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$base"; then
    echo "dc-worktree: base branch '$base' does not exist" >&2
    exit 1
  fi
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "dc-worktree: parking branch '$branch' already exists" >&2
    exit 1
  fi

  # Create the empty parking branch off <base> WITHOUT moving the root repo HEAD.
  git -C "$REPO_ROOT" branch "$branch" "$base"
  mkdir -p "$WT_DIR"
  git -C "$REPO_ROOT" worktree add "$wt_path" "$branch"

  local p
  for p in "${SYMLINK_PATHS[@]}"; do
    if [[ -e "$REPO_ROOT/$p" ]]; then
      ln -s "../../$p" "$wt_path/$p"
    fi
  done

  ( cd "$wt_path" && gt track --parent "$base" )

  echo ""
  echo "Building worktree venv (uv sync --locked --all-extras --dev)…"
  ( cd "$wt_path" && uv sync --locked --all-extras --dev )

  cat <<EOF

Worktree ready at $wt_path (parked on $branch, off $base)

  cd $wt_path
  gt create <first-branch>
  gt move <first-branch> --onto $base   # make the real stack a sibling of $branch

When idle:   dc-worktree --park $name
When done:   dc-worktree --rm $name
EOF
}

park_worktree() {
  local name wt_path branch
  name=$(slug "${1:?name required}")
  wt_path="$WT_DIR/$name"
  branch="wt/$name"

  if [[ ! -d "$wt_path" ]]; then
    echo "dc-worktree: no worktree at $wt_path" >&2
    exit 1
  fi
  ( cd "$wt_path" && gt checkout "$branch" )
  echo "Parked $name on $branch — real branches are free to restack."
}

remove_worktree() {
  local force=false
  if [[ "${1:-}" == "-f" ]]; then
    force=true
    shift
  fi

  local name wt_path branch
  name=$(slug "${1:?name required}")
  wt_path="$WT_DIR/$name"
  branch="wt/$name"

  if [[ ! -d "$wt_path" ]]; then
    echo "dc-worktree: no worktree at $wt_path" >&2
    exit 1
  fi

  if ! $force; then
    local dirty
    dirty=$(git -C "$wt_path" status --porcelain --untracked-files=all)
    if [[ -n "$dirty" ]]; then
      echo "dc-worktree: worktree has uncommitted changes — use -f to force" >&2
      echo "$dirty" >&2
      exit 1
    fi
  fi

  local p
  for p in "${SYMLINK_PATHS[@]}"; do
    [[ -L "$wt_path/$p" ]] && rm "$wt_path/$p"
  done

  if $force; then
    git -C "$REPO_ROOT" worktree remove --force "$wt_path"
  else
    git -C "$REPO_ROOT" worktree remove "$wt_path"
  fi
  git -C "$REPO_ROOT" branch -D "$branch" 2>/dev/null || true

  cat <<EOF
Removed worktree $name and parking branch $branch.

Real work branches (if any) survive on their base. Clean up abandoned ones with:
  gt branch delete <branch>
EOF
}

main() {
  require_datacore
  [[ $# -eq 0 ]] && usage 1

  case "$1" in
    --park)
      shift
      park_worktree "$@"
      ;;
    --rm)
      shift
      remove_worktree "$@"
      ;;
    -h | --help)
      usage 0
      ;;
    -*)
      echo "dc-worktree: unknown option '$1'" >&2
      usage 1
      ;;
    *)
      create_worktree "$@"
      ;;
  esac
}

main "$@"
