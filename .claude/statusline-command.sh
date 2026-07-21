#!/usr/bin/env bash
# Claude Code status line — mirrors Starship Catppuccin Latte prompt elements.
# Receives JSON session data on stdin; prints one right-aligned status line.
# Layout (left→right): time | model level [vim] | $cost | rate-limit usage
# (with reset times) | context % + tokens | dir + branch. Context and each
# usage window are traffic-light colored (green ≤50%, yellow >50%, red >75%).
# The whole line is right-aligned to $COLUMNS (set by Claude Code v2.1.153+).

input=$(cat)

# --- pull every field in one jq pass, one value per line ---
# Sequential `read`s (not a single split) so empty fields stay aligned: a
# delimiter-based read collapses or misplaces empties. Each `read -r` consumes
# exactly one line, empty lines included.
{
    read -r raw_cwd
    read -r model
    read -r branch
    read -r used_pct
    read -r tokens
    read -r ctx_size
    read -r cost
    read -r rl5
    read -r rl5_reset
    read -r rl7
    read -r rl7_reset
    read -r vim_mode
    read -r effort_level
} < <(
    echo "$input" | jq -r '
        (.cwd // .workspace.current_dir // ""),
        (.model.display_name // ""),
        (.workspace.git_worktree // ""),
        (.context_window.used_percentage // ""),
        ((.context_window.total_input_tokens // 0)
           + (.context_window.total_output_tokens // 0)),
        (.context_window.context_window_size // ""),
        (.cost.total_cost_usd // ""),
        (.rate_limits.five_hour.used_percentage // ""),
        (.rate_limits.five_hour.resets_at // ""),
        (.rate_limits.seven_day.used_percentage // ""),
        (.rate_limits.seven_day.resets_at // ""),
        (.vim.mode // ""),
        (.effort.level // "")
    '
)

RESET=$'\033[0m'

# paint text (arg 2) by integer percentage (arg 1): red >75, yellow >50,
# no color otherwise (normal state emits no escape codes).
paint() {
    if [ "$1" -gt 75 ]; then
        printf '\033[31m%s%s' "$2" "$RESET"
    elif [ "$1" -gt 50 ]; then
        printf '\033[33m%s%s' "$2" "$RESET"
    else
        printf '%s' "$2"
    fi
}

now=$(date +%s)
# render time, doubles as a staleness marker: the line only re-renders on events
# (new message, /compact, permission/vim change), so a frozen clock = stale data.
clock=$(date -r "$now" '+%H:%M')

# elapsed % of a rate-limit window: reset epoch (arg 1), window seconds (arg 2)
elapsed_pct() {
    local reset=$1 window=$2 pct
    pct=$(( (window - (reset - now)) * 100 / window ))
    if [ "$pct" -lt 0 ]; then
        pct=0
    elif [ "$pct" -gt 100 ]; then
        pct=100
    fi
    printf '%d' "$pct"
}

# human-readable token count: 1234 -> 1.2k, 1000000 -> 1M (trailing .0 stripped)
humanize() {
    if [ "$1" -ge 1000000 ]; then
        awk -v n="$1" 'BEGIN { s = sprintf("%.1f", n / 1000000); sub(/\.0$/, "", s); printf "%sM", s }'
    elif [ "$1" -ge 1000 ]; then
        awk -v n="$1" 'BEGIN { s = sprintf("%.1f", n / 1000); sub(/\.0$/, "", s); printf "%sk", s }'
    else
        printf '%d' "$1"
    fi
}

# --- directory: basename only, ~ for $HOME ---
if [ "$raw_cwd" = "$HOME" ]; then
    dir="~"
else
    dir="${raw_cwd##*/}"
fi

# --- git branch: JSON field, else live git in the current dir (read-only) ---
if [ -z "$branch" ] && [ -n "$raw_cwd" ]; then
    branch=$(git -C "$raw_cwd" branch --show-current 2>/dev/null || true)
fi

# --- cost badge ---
cost_str=""
if [ -n "$cost" ]; then
    printf -v cost_str '$%.2f' "$cost"
fi

# --- rate-limit usage with reset times, colored per window ---
usage_plain=""
usage_disp=""
if [ -n "$rl5" ]; then
    printf -v r5 "%.0f" "$rl5"
    seg="5h: ${r5}%"
    if [ -n "$rl5_reset" ]; then
        printf -v ts "%.0f" "$rl5_reset"
        seg="$seg ($(date -r "$ts" '+%H:%M'), $(elapsed_pct "$ts" 18000)%)"
    fi
    usage_plain="$seg"
    usage_disp="$(paint "$r5" "$seg")"
fi
if [ -n "$rl7" ]; then
    printf -v r7 "%.0f" "$rl7"
    seg="7d: ${r7}%"
    if [ -n "$rl7_reset" ]; then
        printf -v ts "%.0f" "$rl7_reset"
        seg="$seg ($(date -r "$ts" '+%a %H:%M'), $(elapsed_pct "$ts" 604800)%)"
    fi
    seg_disp="$(paint "$r7" "$seg")"
    usage_plain="${usage_plain:+$usage_plain · }$seg"
    usage_disp="${usage_disp:+$usage_disp · }$seg_disp"
fi

# --- context % + tokens (rightmost cluster), colored by context usage ---
ctx=""
pct_int=""
if [ -n "$used_pct" ]; then
    printf -v pct_int "%.0f" "$used_pct"
    ctx="ctx: ${pct_int}%"
fi
tok_str=""
if [ -n "$tokens" ] && [ "$tokens" -gt 0 ] 2>/dev/null; then
    tok_str="$(humanize "$tokens")"
    if [ -n "$ctx_size" ] && [ "$ctx_size" -gt 0 ] 2>/dev/null; then
        tok_str="$tok_str/$(humanize "$ctx_size")"
    fi
fi
context_plain="$ctx"
if [ -n "$ctx" ] && [ -n "$tok_str" ]; then
    context_plain="$ctx · $tok_str"
elif [ -n "$tok_str" ]; then
    context_plain="$tok_str"
fi
context_disp="$context_plain"
if [ -n "$context_plain" ] && [ -n "$pct_int" ]; then
    context_disp="$(paint "$pct_int" "$context_plain")"
fi

# --- assemble (plain for width math, disp for display) ---
left="$dir"
if [ -n "$branch" ]; then
    left="${left:+$left · }$branch"
fi

model_group="$model"
[ -n "$effort_level" ] && model_group="${model_group:+$model_group · }$effort_level"
if [ -n "$vim_mode" ]; then
    model_group="${model_group:+$model_group · }[${vim_mode}]"
fi

sep=" | "
plain="$clock"
disp="$clock"
if [ -n "$model_group" ]; then
    plain="${plain:+$plain$sep}$model_group"
    disp="${disp:+$disp$sep}$model_group"
fi
if [ -n "$cost_str" ]; then
    plain="${plain:+$plain$sep}$cost_str"
    disp="${disp:+$disp$sep}$cost_str"
fi
if [ -n "$usage_plain" ]; then
    plain="${plain:+$plain$sep}$usage_plain"
    disp="${disp:+$disp$sep}$usage_disp"
fi
if [ -n "$context_plain" ]; then
    plain="${plain:+$plain$sep}$context_plain"
    disp="${disp:+$disp$sep}$context_disp"
fi
plain="${plain:+$plain$sep}$left"
disp="${disp:+$disp$sep}$left"

# --- right-align to the terminal width ($COLUMNS), measuring the plain string ---
cols="${COLUMNS:-0}"
if [ "$cols" -gt 0 ] 2>/dev/null && [ "$cols" -gt "${#plain}" ]; then
    printf "%*s%s\n" "$(( cols - ${#plain} ))" "" "$disp"
else
    printf "%s\n" "$disp"
fi
