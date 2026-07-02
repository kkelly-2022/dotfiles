#!/usr/bin/env bash
#
# gt-jira-prefix — prefix a Jira ticket onto every PR title in the current Graphite stack
#
# The State-Affairs CI gate (.buildkite/check-commits-have-jira.js) wants a valid
# ticket key (e.g. SA-1234) in each PR's title/body or one of its commits. This
# stamps "[TICKET]: " onto the title of every open PR in the current stack that
# doesn't already reference the key.
#
# Usage:
#   gt-jira-prefix <TICKET> [--apply]
#
#   <TICKET>   Jira key, PROJECT-NUMBER (e.g. SA-7066).
#   --apply    Actually edit titles. Without it, prints the plan (dry run).
#   -h         Show this help.
#
# "Current stack" = the current branch's PR, its ancestors down to trunk, and its
# descendants up to the tips — resolved from each PR's base branch. Branches
# without an open PR are skipped. Title edits do not re-trigger CI; re-run the
# affected builds afterwards.

set -euo pipefail

usage() {
  sed -n '3,21p' "$0" | sed 's/^#\{0,1\} \{0,1\}//'
  exit "${1:-1}"
}

ticket=""
apply=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage 0 ;;
    --apply) apply=1 ;;
    -*) echo "gt-jira-prefix: unknown option: $arg" >&2; usage 1 ;;
    *)
      if [[ -z "$ticket" ]]; then
        ticket="$arg"
      else
        echo "gt-jira-prefix: unexpected argument: $arg" >&2; usage 1
      fi
      ;;
  esac
done

[[ -n "$ticket" ]] || { echo "gt-jira-prefix: missing <TICKET>" >&2; usage 1; }
[[ "$ticket" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]] ||
  { echo "gt-jira-prefix: '$ticket' is not a PROJECT-NUMBER key" >&2; exit 1; }
command -v gh >/dev/null || { echo "gt-jira-prefix: gh not on PATH" >&2; exit 1; }

trunk="$(gt trunk 2>/dev/null || echo main)"
current="$(git branch --show-current)"
[[ -n "$current" ]] || { echo "gt-jira-prefix: not on a branch (detached HEAD)" >&2; exit 1; }

# Snapshot every open PR once (number, head, base, title) as TSV. One API call
# beats dozens of per-branch `gh pr view`s and the transient failures they invite.
# @tsv escapes any tab/newline inside a field, so columns stay clean.
prs="$(gh pr list --state open --limit 500 \
  --json number,headRefName,baseRefName,title \
  -q '.[] | [.number, .headRefName, .baseRefName, .title] | @tsv' 2>/dev/null)" || true
[[ -n "$prs" ]] || { echo "gt-jira-prefix: no open PRs found in this repo" >&2; exit 1; }

# field <branch> <col>  -> column (1=number, 3=base, 4=title) of that branch's PR.
field() { awk -F'\t' -v b="$1" -v c="$2" '$2==b {print $c; exit}' <<<"$prs"; }
children_of() { awk -F'\t' -v b="$1" '$3==b {print $2}' <<<"$prs"; }

# Membership via a space-delimited string (bash 3.2 has no associative arrays;
# git refs never contain spaces, so this is unambiguous).
seen=" "
order=()
add() { case "$seen" in *" $1 "*) ;; *) seen="$seen$1 "; order+=("$1") ;; esac; }

# Down: current + ancestors, following each PR's base branch until trunk.
branch="$current"
while [[ -n "$branch" && "$branch" != "$trunk" ]]; do
  base="$(field "$branch" 3)"
  [[ -n "$base" ]] || break          # no open PR for this branch -> stop
  add "$branch"
  branch="$base"
done

# Up: descendants of current (BFS over PRs whose base is an already-seen branch).
queue=("$current")
while ((${#queue[@]})); do
  head="${queue[0]}"; queue=("${queue[@]:1}")
  while IFS= read -r child; do
    [[ -n "$child" ]] || continue
    case "$seen" in *" $child "*) continue ;; esac
    add "$child"; queue+=("$child")
  done < <(children_of "$head")
done

((${#order[@]})) || { echo "gt-jira-prefix: '$current' has no open PR in this repo" >&2; exit 1; }

if ((apply)); then verb="edited"; else verb="would edit"; fi
echo "Ticket [$ticket] across the stack from '$current' (trunk: $trunk)"
((apply)) || echo "DRY RUN — re-run with --apply to edit titles."
echo

edits=0
skips=0
for branch in "${order[@]}"; do
  num="$(field "$branch" 1)"
  title="$(field "$branch" 4)"
  if [[ -z "$num" ]]; then
    printf '  - %-28s (no open PR)\n' "$branch"
    continue
  fi
  if [[ "$title" == *"$ticket"* ]]; then
    printf '  = #%-6s %-28s already references %s\n' "$num" "$branch" "$ticket"
    skips=$((skips + 1))
    continue
  fi
  new="[$ticket]: $title"
  if ((apply)); then
    gh pr edit "$num" --title "$new" >/dev/null
  fi
  printf '  > #%-6s %-28s -> %s\n' "$num" "$branch" "$new"
  edits=$((edits + 1))
done

echo
echo "$verb: $edits   already-tagged: $skips   total PRs: ${#order[@]}"
