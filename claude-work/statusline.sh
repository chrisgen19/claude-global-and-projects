#!/usr/bin/env bash
# Comprehensive developer statusline for Claude Code
# Line 1: Account | Git user (Claude account) | Model + flags | Version | Dir | Git branch/status | PR
# Line 2: Context bar | Rate limits | Cost | Duration | Lines changed
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
MAGENTA='\033[35m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# -- Extract every field in one jq pass (one fork instead of ten) --
# Numeric fields that may be absent use -1 as the sentinel so a real 0
# stays distinguishable from "not sent".
mapfile -t F < <(printf '%s' "$input" | jq -r '
  [ .model.display_name                            // "?",
    (.workspace.current_dir // .cwd)               // "",
    (.context_window.used_percentage // 0 | floor),
    .cost.total_cost_usd                           // 0,
    .cost.total_duration_ms                        // 0,
    .cost.total_lines_added                        // 0,
    .cost.total_lines_removed                      // 0,
    .version                                       // "",
    .context_window.context_window_size            // 0,
    .effort.level                                  // "",
    (.thinking.enabled // false),
    (.fast_mode // false),
    .pr.number                                     // "",
    (.rate_limits.five_hour.used_percentage // -1 | floor),
    (.rate_limits.five_hour.resets_at       // -1),
    (.rate_limits.seven_day.used_percentage // -1 | floor),
    (.rate_limits.seven_day.resets_at       // -1)
  ] | .[] | tostring' 2>/dev/null)

model="${F[0]}";        cwd="${F[1]}";           pct="${F[2]}"
cost="${F[3]}";         duration_ms="${F[4]}";   lines_added="${F[5]}"
lines_removed="${F[6]}"; version="${F[7]}";      cw_size="${F[8]}"
effort="${F[9]}";       thinking="${F[10]}";     fast_mode="${F[11]}"
pr_number="${F[12]}"
rl_5h="${F[13]}";       rl_5h_at="${F[14]}"
rl_7d="${F[15]}";       rl_7d_at="${F[16]}"

# -- Guard the numerics so a malformed payload can't break arithmetic --
_int() { local v="${!1}"; [[ "$v" =~ ^-?[0-9]+$ ]] || printf -v "$1" '%s' "$2"; }
_int pct 0
_int duration_ms 0
_int lines_added 0
_int lines_removed 0
_int cw_size 0
_int rl_5h -1
_int rl_5h_at -1
_int rl_7d -1
_int rl_7d_at -1
[[ "$model" ]] || model="?"

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

# -- Wall clock, read once and shared by the cache check and the reset countdowns --
now=$(date +%s)

# -- Git info (cached PER DIRECTORY) --
# The cache key includes the cwd and uid, so concurrent sessions in
# different repos can no longer overwrite each other's branch state.
safe_cwd="${cwd//\//_}"
safe_cwd="${safe_cwd//[^A-Za-z0-9_.-]/_}"
# Keep the tail (the distinctive part) if the path would overflow NAME_MAX.
# Guarded: a negative offset larger than the string yields "" in bash.
[ ${#safe_cwd} -gt 200 ] && safe_cwd="${safe_cwd: -200}"
CACHE_FILE="/tmp/claude-statusline-git-${UID}-${safe_cwd}"
CACHE_MAX_AGE=5

cache_is_stale() {
  [ ! -f "$CACHE_FILE" ] || \
  [ $((now - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]
}

if cache_is_stale && [ -n "$cwd" ]; then
  # --no-optional-locks is a git-level option and must precede the subcommand,
  # otherwise git treats it as an argument and never skips the index lock.
  if git --no-optional-locks -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
             || git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    staged=$(git --no-optional-locks -C "$cwd" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    modified=$(git --no-optional-locks -C "$cwd" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    untracked=$(git --no-optional-locks -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
    printf '%s|%s|%s|%s\n' "$branch" "$staged" "$modified" "$untracked" > "$CACHE_FILE.$$"
  else
    printf '|||\n' > "$CACHE_FILE.$$"
  fi
  # Rename is atomic, so a concurrent reader never sees a half-written line.
  mv -f "$CACHE_FILE.$$" "$CACHE_FILE" 2>/dev/null || rm -f "$CACHE_FILE.$$"
fi

git_branch=""; git_staged=0; git_modified=0; git_untracked=0
if [ -f "$CACHE_FILE" ]; then
  IFS='|' read -r git_branch git_staged git_modified git_untracked < "$CACHE_FILE"
fi

# -- Build git status indicators --
git_info=""
if [ -n "$git_branch" ]; then
  git_parts=()
  [ "${git_staged:-0}" -gt 0 ] 2>/dev/null && git_parts+=("${GREEN}+${git_staged}${RESET}")
  [ "${git_modified:-0}" -gt 0 ] 2>/dev/null && git_parts+=("${YELLOW}~${git_modified}${RESET}")
  [ "${git_untracked:-0}" -gt 0 ] 2>/dev/null && git_parts+=("${RED}?${git_untracked}${RESET}")
  git_info=" | ${CYAN}${git_branch}${RESET}"
  [ ${#git_parts[@]} -gt 0 ] && git_info="${git_info} ${git_parts[*]}"
fi

# -- Open PR / merge request for the current branch --
pr_info=""
[ -n "$pr_number" ] && pr_info="  ${MAGENTA}#${pr_number}${RESET}"

# -- Session mode flags: fast mode, reasoning effort, extended thinking --
flag_parts=()
[ "$fast_mode" = "true" ] && flag_parts+=("fast")
case "$effort" in
  low)    flag_parts+=("lo") ;;
  medium) flag_parts+=("med") ;;
  high)   flag_parts+=("hi") ;;
  xhigh)  flag_parts+=("xhi") ;;
  max)    flag_parts+=("max") ;;
esac
[ "$thinking" = "true" ] && flag_parts+=("think")
flags_info=""
[ ${#flag_parts[@]} -gt 0 ] && flags_info=" ${DIM}${flag_parts[*]}${RESET}"

# -- Context window size label (distinguishes 1M models from 200k) --
cw_label=""
if [ "$cw_size" -ge 1000000 ]; then
  cw_label=" ${DIM}1M${RESET}"
elif [ "$cw_size" -gt 0 ]; then
  cw_label=" ${DIM}$((cw_size / 1000))k${RESET}"
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
[ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
[ "$filled" -lt 0 ] && filled=0
empty=$((BAR_WIDTH - filled))
bar=""
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done

# -- Rate limits (Claude.ai Pro/Max only; absent windows are skipped) --
# The countdown is time-based, so set "refreshInterval": 60 alongside statusLine
# in settings.json or it only re-renders when an assistant message arrives.
# Internal names are underscore-prefixed so printf -v can never write to a
# local of the same name in the caller.
fmt_left() {  # $1=outvar  $2=epoch seconds when the window resets
  local _s=$(( $2 - now )) _d _h _m
  if [ "$_s" -le 0 ]; then printf -v "$1" '%s' ""; return; fi
  _d=$(( _s / 86400 )); _h=$(( (_s % 86400) / 3600 )); _m=$(( (_s % 3600) / 60 ))
  if   [ "$_d" -gt 0 ]; then printf -v "$1" '%dd%dh'  "$_d" "$_h"
  elif [ "$_h" -gt 0 ]; then printf -v "$1" '%dh%02dm' "$_h" "$_m"
  else                       printf -v "$1" '%dm'     "$_m"
  fi
}

fmt_rl() {  # $1=outvar  $2=label  $3=percent  $4=resets_at epoch (-1 if absent)
  local _c="$GREEN" left=""
  if [ "$3" -ge 90 ]; then _c="$RED"; elif [ "$3" -ge 70 ]; then _c="$YELLOW"; fi
  [ "$4" -ge 0 ] && fmt_left left "$4"
  [ -n "$left" ] && left=" ${DIM}(${left})${RESET}"
  printf -v "$1" '%s%s%s %s%s%%%s%s' "$DIM" "$2" "$RESET" "$_c" "$3" "$RESET" "$left"
}

rl_parts=()
if [ "$rl_5h" -ge 0 ]; then fmt_rl _rl5 "5h" "$rl_5h" "$rl_5h_at"; rl_parts+=("$_rl5"); fi
if [ "$rl_7d" -ge 0 ]; then fmt_rl _rl7 "7d" "$rl_7d" "$rl_7d_at"; rl_parts+=("$_rl7"); fi
rl_info=""
[ ${#rl_parts[@]} -gt 0 ] && rl_info=" | ${rl_parts[*]}"

# -- Format cost --
cost_fmt=$(printf '$%.2f' "$cost")

# -- Format duration --
duration_sec=$((duration_ms / 1000))
if [ "$duration_sec" -ge 3600 ]; then
  hrs=$((duration_sec / 3600))
  mins=$(((duration_sec % 3600) / 60))
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

# -- LINE 1: Account | Git user (Claude account) | Model + flags | Dir | Git | PR --
printf '%b\n' "${account_label}  ${gh_prefix}${claude_prefix}  ${BOLD}[${model}]${RESET}${cw_label}${flags_info}${ver_info}  ${short_dir}${git_info}${pr_info}"

# -- LINE 2: Context bar | Rate limits | Cost | Duration | Lines --
printf '%b' "${bar_color}${bar}${RESET} ${pct}%${rl_info} | ${YELLOW}${cost_fmt}${RESET} | ${time_fmt}${lines_info}"
