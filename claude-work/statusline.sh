#!/usr/bin/env bash
# Comprehensive developer statusline for Claude Code
# Line 1: Account | Git user (Claude) | Model + flags + mode | Version | Session id | Dir | Git branch/sync/status | PR
# Line 2: Context bar | Rate limits | Cost | Duration | Lines changed
#
# Setup: Copy to each account's config directory and set the account label:
#   for a in personal work dev; do cp statusline.sh ~/.claude-$a/statusline.sh; done
#   Labels: PERSONAL (cyan)  WORK (yellow)  DEV (green)
# Then edit the ACCOUNT_NAME and ACCOUNT_COLOR variables below per account.

input=$(cat)

# ── CONFIG (edit per account) ────────────────────────────────────────
ACCOUNT_NAME="WORK"         # or "PERSONAL" / "DEV"
ACCOUNT_COLOR=$'\033[33m'   # Yellow WORK, $'\033[36m' Cyan PERSONAL, $'\033[32m' Green DEV
# ─────────────────────────────────────────────────────────────────────
# Those two assignments must stay on lines 14 and 15: CI diffs each account
# copy against this file with `sed '14,15d'` on both, so a header edit that
# shifts them makes the drift check compare the wrong lines and fail.

# A caller (e.g. the ~/.claude router) can override the label when the session
# is not running under one of the named account dirs, so the line never claims
# to be an account it is not.
if [ -n "$ACCOUNT_LABEL_OVERRIDE" ]; then
  ACCOUNT_NAME="$ACCOUNT_LABEL_OVERRIDE"
  ACCOUNT_COLOR=$'\033[37m'  # neutral white — not one of the account colours
fi

# -- ANSI colors --
# ANSI-C quoting ($'...') puts the real ESC byte in the variable at assignment
# time, so the final lines print with `printf '%s'`. With `%b` instead, printf
# expands backslash escapes in *every* interpolated value, including the cwd,
# the branch name and the git email: a directory named `bad\tdir` rendered a
# literal tab, and a `\n` or `\e` in a path broke the layout or injected
# arbitrary escape codes. Keep these as $'...' and never print them with %b.
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# -- Extract every field in one jq pass (one fork instead of ten) --
# Numeric fields that may be absent use -1 as the sentinel so a real 0
# stays distinguishable from "not sent".
# `mapfile` is bash 4+; macOS ships bash 3.2, so read the lines in a loop.
# The redirect keeps the loop in the current shell, so F survives it.
F=()
while IFS= read -r _f; do F+=("$_f"); done < <(printf '%s' "$input" | jq -r '
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
    (.rate_limits.seven_day.resets_at       // -1),
    .session_id                                    // "",
    .permission_mode                               // ""
  ] | .[] | tostring' 2>/dev/null)

model="${F[0]}";        cwd="${F[1]}";           pct="${F[2]}"
cost="${F[3]}";         duration_ms="${F[4]}";   lines_added="${F[5]}"
lines_removed="${F[6]}"; version="${F[7]}";      cw_size="${F[8]}"
effort="${F[9]}";       thinking="${F[10]}";     fast_mode="${F[11]}"
pr_number="${F[12]}"
rl_5h="${F[13]}";       rl_5h_at="${F[14]}"
rl_7d="${F[15]}";       rl_7d_at="${F[16]}"
session_id="${F[17]}";  permission_mode="${F[18]}"

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
# The -v2 is the cache *format* version. The line gained three fields
# (conflicts, upstream, ahead/behind); reading those from a file written by the
# old four-field format would leave upstream empty and render a wrong
# "no-upstream" until the entry aged out, so the new format gets a new name.
CACHE_FILE="/tmp/claude-statusline-git-v2-${UID}-${safe_cwd}"
# The cache exists to absorb the burst of renders inside a single turn, not to
# serve the scheduled refresh: with "refreshInterval": 60 in settings.json those
# are 60s apart, so they always find a stale cache and always pay full price.
# That is deliberate (a 60s cache would show stale branch state for a minute),
# and it is affordable now that the miss costs one git fork instead of six.
# 10s covers a turn's renders without the line lying for long.
CACHE_MAX_AGE=10

# BSD and GNU stat spell "mtime as epoch" differently, and guessing wrong is
# not a clean no-op: GNU's -f is --file-system, so `stat -f %m FILE` treats %m
# and FILE as two operands, prints a filesystem block to stdout AND exits
# non-zero. In a `||` chain that block gets captured alongside the real mtime
# and the arithmetic below dies. Dispatch on the platform instead of probing.
# $OSTYPE is set by bash itself, so this costs no fork.
case "$OSTYPE" in
  darwin*|*bsd*|FreeBSD*) _mtime() { stat -f %m "$1" 2>/dev/null || echo 0; } ;;
  *)                      _mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; } ;;
esac

cache_is_stale() {
  [ ! -f "$CACHE_FILE" ] || \
  [ $((now - $(_mtime "$CACHE_FILE"))) -gt $CACHE_MAX_AGE ]
}

if cache_is_stale && [ -n "$cwd" ]; then
  # One `status --porcelain=v2 --branch` replaces the six forks this used to
  # cost (rev-parse, symbolic-ref, two diffs, ls-files and a rev-parse
  # fallback): it reports the branch, the head oid, the upstream, ahead/behind
  # and every file state together.
  #
  # Measured on a 449-file repo: the git work drops from 15ms (1+2+2+6+4) to
  # 4ms, taking a cache miss from ~39ms to ~29ms end to end. The rest of a
  # miss is two jq forks and `git config user.email`, not this.
  #
  # -uall is required, not cosmetic: without it untracked *directories* collapse
  # to one `?` line each, where `ls-files --others` counted the files inside.
  #
  # --no-optional-locks is a git-level option and must precede the subcommand,
  # otherwise git treats it as an argument and never skips the index lock.
  #
  # Field 2 of a `1`/`2` line is the XY state pair, X staged and Y unstaged,
  # with `.` for unchanged, so XY reproduces the old two-diff counts exactly
  # (verified: 3/2/2 both ways on a mixed tree). The one case that differs is a
  # conflict, where the old code reported a bogus `+1 ~2` for a single file;
  # porcelain reports it once as `u`, which is why conflicts are counted and
  # shown separately below rather than silently vanishing.
  branch=""; head_oid=""; upstream=""; ahead=0; behind=0
  staged=0; modified=0; untracked=0; conflicts=0
  while IFS= read -r _line; do
    case "$_line" in
      '# branch.oid '*)      head_oid="${_line#\# branch.oid }" ;;
      '# branch.head '*)     branch="${_line#\# branch.head }" ;;
      '# branch.upstream '*) upstream="${_line#\# branch.upstream }" ;;
      '# branch.ab '*)
        _ab="${_line#\# branch.ab }"
        ahead="${_ab%% *}"; ahead="${ahead#+}"
        behind="${_ab##* }"; behind="${behind#-}"
        ;;
      '1 '*|'2 '*)
        _xy="${_line:2:2}"
        [ "${_xy:0:1}" != "." ] && staged=$((staged + 1))
        [ "${_xy:1:1}" != "." ] && modified=$((modified + 1))
        ;;
      'u '*) conflicts=$((conflicts + 1)) ;;
      '? '*) untracked=$((untracked + 1)) ;;
    esac
  done < <(git --no-optional-locks -C "$cwd" status --porcelain=v2 --branch -uall 2>/dev/null)

  # An empty `upstream` means the branch is not tracking anything, which is
  # worth flagging ("nothing is pushed") only in a repo that HAS a remote. In a
  # local-only repo it is permanent and unactionable, so confirm a remote
  # exists first. This second fork runs only on the no-upstream path, so a
  # branch that is tracking still costs exactly one git call.
  #
  # Checked before the detached-HEAD substitution below, because a detached
  # HEAD has no upstream by definition and flagging that says nothing useful.
  no_upstream=0
  if [ -n "$branch" ] && [ -z "$upstream" ] && [ "$branch" != "(detached)" ]; then
    [ -n "$(git --no-optional-locks -C "$cwd" remote 2>/dev/null)" ] && no_upstream=1
  fi

  # A detached HEAD reports `# branch.head (detached)`; show the short oid
  # instead, as the old rev-parse fallback did. An unborn branch reports
  # `(initial)` as the oid, so only substitute something that looks like a sha.
  if [ "$branch" = "(detached)" ]; then
    case "$head_oid" in
      '('*) branch="detached" ;;
      *)    branch="${head_oid:0:7}" ;;
    esac
  fi
  # Outside a work tree git writes nothing, so branch stays empty and the
  # cache line is all-empty: the same signal the old `else` branch wrote.
  printf '%s|%s|%s|%s|%s|%s|%s\n' "$branch" "$staged" "$modified" "$untracked" \
    "$conflicts" "$no_upstream" "${ahead}/${behind}" > "$CACHE_FILE.$$"
  # Rename is atomic, so a concurrent reader never sees a half-written line.
  mv -f "$CACHE_FILE.$$" "$CACHE_FILE" 2>/dev/null || rm -f "$CACHE_FILE.$$"
fi

git_branch=""; git_staged=0; git_modified=0; git_untracked=0
git_conflicts=0; git_no_upstream=0; git_ab=""
if [ -f "$CACHE_FILE" ]; then
  IFS='|' read -r git_branch git_staged git_modified git_untracked \
    git_conflicts git_no_upstream git_ab < "$CACHE_FILE"
fi
git_ahead="${git_ab%%/*}"; git_behind="${git_ab##*/}"

# -- Build git status indicators --
# Order: branch, then sync state (how it sits against the remote), then dirty
# state (how it sits against the index). A branch with no upstream is called
# out because in a branch-and-PR-per-task workflow it means nothing is pushed
# and no PR can exist yet, which otherwise looks identical to being in sync.
git_info=""
if [ -n "$git_branch" ]; then
  git_parts=()
  if [ "${git_no_upstream:-0}" = "1" ]; then
    git_parts+=("${YELLOW}no-upstream${RESET}")
  else
    [ "${git_ahead:-0}" -gt 0 ] 2>/dev/null && git_parts+=("${YELLOW}^${git_ahead}${RESET}")
    [ "${git_behind:-0}" -gt 0 ] 2>/dev/null && git_parts+=("${CYAN}v${git_behind}${RESET}")
  fi
  [ "${git_staged:-0}" -gt 0 ] 2>/dev/null && git_parts+=("${GREEN}+${git_staged}${RESET}")
  [ "${git_modified:-0}" -gt 0 ] 2>/dev/null && git_parts+=("${YELLOW}~${git_modified}${RESET}")
  [ "${git_untracked:-0}" -gt 0 ] 2>/dev/null && git_parts+=("${RED}?${git_untracked}${RESET}")
  [ "${git_conflicts:-0}" -gt 0 ] 2>/dev/null && git_parts+=("${BOLD}${RED}!${git_conflicts}${RESET}")
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

# -- Permission mode --
# Carried on the payload as .permission_mode. "default" is the ordinary case
# and stays silent so the line only speaks up when the session is NOT asking
# before it acts. Full enum in 2.1.318: default, acceptEdits, plan,
# bypassPermissions, dontAsk, auto. bypassPermissions gets bold red because it
# auto-approves every tool call except explicit deny rules.
perm_info=""
case "$permission_mode" in
  plan)              perm_info=" ${CYAN}plan${RESET}" ;;
  acceptEdits)       perm_info=" ${YELLOW}auto-edit${RESET}" ;;
  auto)              perm_info=" ${YELLOW}auto${RESET}" ;;
  dontAsk)           perm_info=" ${YELLOW}dont-ask${RESET}" ;;
  bypassPermissions) perm_info=" ${BOLD}${RED}BYPASS${RESET}" ;;
esac

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

# -- Session id (first 8 chars: enough for claude-handoff; --resume needs the full id) --
id_info=""
if [ -n "$session_id" ]; then
  id_info=" ${DIM}id:${RESET}${session_id:0:8}"
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

# -- LINE 1: Account | Git user (Claude account) | Model + flags + mode | Version | Session id | Dir | Git | PR --
# %s, never %b: the colours already hold real ESC bytes, and %b would expand
# backslash escapes inside the cwd, branch name and email too (see ANSI colors).
printf '%s\n' "${account_label}  ${gh_prefix}${claude_prefix}  ${BOLD}[${model}]${RESET}${cw_label}${flags_info}${perm_info}${ver_info}${id_info}  ${short_dir}${git_info}${pr_info}"

# -- LINE 2: Context bar | Rate limits | Cost | Duration | Lines --
printf '%s' "${bar_color}${bar}${RESET} ${pct}%${rl_info} | ${YELLOW}${cost_fmt}${RESET} | ${time_fmt}${lines_info}"
