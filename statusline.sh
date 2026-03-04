#!/usr/bin/env bash
# Comprehensive developer statusline for Claude Code
# Line 1: Account | Git User (Claude Account) | Model | Dir | Git branch + status
# Line 2: Context bar (color-coded) | Cost | Duration | Lines changed
#
# Setup: Copy to each account's config directory and set the account label:
#   cp statusline.sh ~/.claude-personal/statusline.sh
#   cp statusline.sh ~/.claude-work/statusline.sh
# Then edit the ACCOUNT_NAME and ACCOUNT_COLOR variables below per account.

input=$(cat)

# ── CONFIG (edit per account) ────────────────────────────────────────
ACCOUNT_NAME="WORK"       # Change to "PERSONAL" for personal account
ACCOUNT_COLOR='\033[33m'  # Yellow for WORK, use '\033[36m' (Cyan) for PERSONAL
# ─────────────────────────────────────────────────────────────────────

# -- ANSI colors --
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# -- Extract fields from JSON --
model=$(echo "$input" | jq -r '.model.display_name // "?"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // ""')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // ""')
pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
version=$(echo "$input" | jq -r '.version // ""')

# -- Shorten directory (replace $HOME with ~) --
short_dir="${cwd/#$HOME/\~}"
# Show just folder name if too long (>30 chars)
if [ ${#short_dir} -gt 30 ]; then
  short_dir="${cwd##*/}"
fi

# -- Git email (reads local git config — respects includeIf per directory) --
gh_email=""
if [ -n "$cwd" ]; then
  gh_email=$(git -C "$cwd" config user.email 2>/dev/null || echo "")
fi

# -- Claude account email (from .claude.json in config dir) --
claude_email=""
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -f "$config_dir/.claude.json" ]; then
  claude_email=$(jq -r '.oauthAccount.emailAddress // ""' "$config_dir/.claude.json")
fi

# -- Git info (cached for performance) --
CACHE_FILE="/tmp/claude-statusline-git-cache"
CACHE_MAX_AGE=5

cache_is_stale() {
  [ ! -f "$CACHE_FILE" ] || \
  [ $(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]
}

if cache_is_stale && [ -n "$cwd" ]; then
  if git -C "$cwd" rev-parse --is-inside-work-tree --no-optional-locks >/dev/null 2>&1; then
    branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    staged=$(git -C "$cwd" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    modified=$(git -C "$cwd" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    untracked=$(git -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    echo "${branch}|${staged}|${modified}|${untracked}" > "$CACHE_FILE"
  else
    echo "|||" > "$CACHE_FILE"
  fi
fi

IFS='|' read -r git_branch git_staged git_modified git_untracked < "$CACHE_FILE" 2>/dev/null

# -- Build git status indicators --
git_info=""
if [ -n "$git_branch" ]; then
  git_indicators=""
  [ "$git_staged" -gt 0 ] 2>/dev/null && git_indicators="${GREEN}+${git_staged}${RESET}"
  [ "$git_modified" -gt 0 ] 2>/dev/null && git_indicators="${git_indicators} ${YELLOW}~${git_modified}${RESET}"
  [ "$git_untracked" -gt 0 ] 2>/dev/null && git_indicators="${git_indicators} ${RED}?${git_untracked}${RESET}"
  git_info=" | ${CYAN}${git_branch}${RESET}"
  [ -n "$git_indicators" ] && git_info="${git_info} ${git_indicators}"
fi

# -- Context bar (color-coded by usage) --
if [ "$pct" -ge 90 ]; then
  bar_color="$RED"
elif [ "$pct" -ge 70 ]; then
  bar_color="$YELLOW"
else
  bar_color="$GREEN"
fi

BAR_WIDTH=15
filled=$((pct * BAR_WIDTH / 100))
empty=$((BAR_WIDTH - filled))
bar=""
[ "$filled" -gt 0 ] && bar=$(printf "%${filled}s" | tr ' ' '█')
[ "$empty" -gt 0 ] && bar="${bar}$(printf "%${empty}s" | tr ' ' '░')"

# -- Format cost --
cost_fmt=$(printf '$%.2f' "$cost")

# -- Format duration --
duration_sec=$((duration_ms / 1000))
if [ "$duration_sec" -ge 3600 ]; then
  hrs=$((duration_sec / 3600))
  mins=$(((duration_sec % 3600) / 60))
  secs=$((duration_sec % 60))
  time_fmt="${hrs}h ${mins}m"
elif [ "$duration_sec" -ge 60 ]; then
  mins=$((duration_sec / 60))
  secs=$((duration_sec % 60))
  time_fmt="${mins}m ${secs}s"
else
  time_fmt="${duration_sec}s"
fi

# -- Lines changed --
lines_info=""
if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
  lines_info=" | ${GREEN}+${lines_added}${RESET} ${RED}-${lines_removed}${RESET}"
fi

# -- Version tag --
ver_info=""
if [ -n "$version" ]; then
  ver_info=" ${DIM}v${version}${RESET}"
fi

# -- Git email prefix (username only, strip @domain) --
gh_prefix=""
if [ -n "$gh_email" ]; then
  gh_prefix="${DIM}${gh_email%%@*}${RESET}"
fi

# -- Claude account prefix (username only, strip @domain) --
claude_prefix=""
if [ -n "$claude_email" ]; then
  claude_prefix=" ${DIM}(${claude_email%%@*})${RESET}"
fi

# -- Account label --
account_label="${BOLD}${ACCOUNT_COLOR}${ACCOUNT_NAME}${RESET}"

# -- LINE 1: Account | Git User (Claude Account) | Model | Dir | Git --
printf '%b\n' "${account_label}  ${gh_prefix}${claude_prefix}  ${BOLD}[${model}]${RESET}${ver_info}  ${short_dir}${git_info}"

# -- LINE 2: Context bar | Cost | Duration | Lines --
printf '%b' "${bar_color}${bar}${RESET} ${pct}% | ${YELLOW}${cost_fmt}${RESET} | ${time_fmt}${lines_info}"
