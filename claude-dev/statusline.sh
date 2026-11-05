#!/usr/bin/env bash
# Comprehensive developer statusline for Claude Code
# Line 1: Account | Git user (Claude) | Model + flags + mode | Version | Session id + name | Dir | Git branch/sync/status | Worktree | PR | Dev servers
# Line 2: Context bar + tokens at 85% | Rate limits + spend limit + pace | Prompt cache expiry + hit rate | Cost | Duration | Lines
#
# Setup: Copy to each account's config directory and set the account label:
#   for a in personal work dev; do cp statusline.sh ~/.claude-$a/statusline.sh; done
#   Labels: PERSONAL (sky)  WORK (yellow)  DEV (green)
# Then edit the ACCOUNT_NAME and ACCOUNT_COLOR variables below per account.

input=$(cat)

# ── CONFIG (edit per account) ────────────────────────────────────────
ACCOUNT_NAME="DEV"          # or "PERSONAL" / "WORK"
ACCOUNT_COLOR=$'\033[38;2;166;227;161m'   # Catppuccin: DEV 166;227;161, PERSONAL 137;220;235, WORK 249;226;175
# ─────────────────────────────────────────────────────────────────────
# Those two assignments must stay on lines 14 and 15: CI diffs each account
# copy against this file with `sed '14,15d'` on both, so a header edit that
# shifts them makes the drift check compare the wrong lines and fail.

# A caller (e.g. the ~/.claude router) can override the label when the session
# is not running under one of the named account dirs, so the line never claims
# to be an account it is not. The colour is picked by account_color below.
LABEL_OVERRIDDEN=""
if [ -n "$ACCOUNT_LABEL_OVERRIDE" ]; then
  ACCOUNT_NAME="$ACCOUNT_LABEL_OVERRIDE"
  LABEL_OVERRIDDEN=1
fi

# -- Palette and glyph tier (environment, set per machine) --
# STATUSLINE_PALETTE=catppuccin|ansi, default catppuccin (24-bit). ansi keeps
# the 8-colour codes for a terminal without true colour. There is no automatic
# detection: whether Claude Code passes COLORTERM to this command is unverified
# and a wrong guess would silently drop the palette. Unknown values fall back
# to catppuccin, like an empty one.
# STATUSLINE_GLYPHS=nerd|unicode|ascii, default nerd. Unknown falls back to nerd.
case "$STATUSLINE_PALETTE" in
  ansi) PALETTE=ansi ;;
  *)    PALETTE=catppuccin ;;
esac
case "$STATUSLINE_GLYPHS" in
  unicode) GLYPHS=unicode ;;
  ascii)   GLYPHS=ascii ;;
  *)       GLYPHS=nerd ;;
esac

# Per-session and per-account state files (quota, cost ledger) live here so a
# test run can point them at a throwaway directory. Trailing slashes trimmed so
# "$STATE_DIR/name" never doubles one.
STATE_DIR="${CLAUDE_STATUSLINE_STATE_DIR:-/tmp}"
while [ "${#STATE_DIR}" -gt 1 ] && [ "${STATE_DIR%/}" != "$STATE_DIR" ]; do STATE_DIR="${STATE_DIR%/}"; done

# -- Colours --
# ANSI-C quoting ($'...') puts the real ESC byte in the variable at assignment
# time, so the final lines print with `printf '%s'`. With `%b` instead, printf
# expands backslash escapes in *every* interpolated value, including the cwd,
# the branch name and the git email: a directory named `bad\tdir` rendered a
# literal tab, and a `\n` or `\e` in a path broke the layout or injected
# arbitrary escape codes. Keep these as $'...' and never print them with %b.
#
# Catppuccin Mocha, from CCometixLine's catppuccin-mocha palette. Under ansi
# the category colours that had no colour before stay empty (plain text), and
# the ones that did keep today's code.
if [ "$PALETTE" = "ansi" ]; then
  C_OK=$'\033[32m';     C_WARN=$'\033[33m';  C_CRIT=$'\033[31m'
  C_ACCENT=$'\033[36m'; C_MUTED=$'\033[2m';  C_SEP=$'\033[2m'
  C_TEXT="";            C_IDENT="";          C_WORKSP=""
  C_VCS=$'\033[36m';    C_CTX="";             C_QUOTA=""
  C_COST=$'\033[33m';   C_CACHE="";           C_SESS=$'\033[35m'
  C_TIMING=""
else
  C_OK=$'\033[38;2;166;227;161m';    C_WARN=$'\033[38;2;249;226;175m'
  C_CRIT=$'\033[38;2;243;139;168m';  C_ACCENT=$'\033[38;2;137;180;250m'
  C_MUTED=$'\033[38;2;108;112;134m'; C_SEP=$'\033[38;2;127;132;156m'
  C_TEXT=$'\033[38;2;205;214;244m';  C_IDENT=$'\033[38;2;180;190;254m'
  C_WORKSP=$'\033[38;2;148;226;213m'; C_VCS=$'\033[38;2;116;199;236m'
  C_CTX=$'\033[38;2;203;166;247m';   C_QUOTA=$'\033[38;2;250;179;135m'
  C_COST=$'\033[38;2;249;226;175m';  C_CACHE=$'\033[38;2;137;220;235m'
  C_SESS=$'\033[38;2;245;194;231m';  C_TIMING=$'\033[38;2;242;205;205m'
fi
# The names the rest of the script already uses stay as aliases.
GREEN=$C_OK
YELLOW=$C_WARN
RED=$C_CRIT
CYAN=$C_VCS
MAGENTA=$C_SESS
DIM=$'\033[2m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# account_color <outvar> <LABEL>: the label colour under the active palette.
# Under catppuccin the current account uses ACCOUNT_COLOR (line 15) and the
# other named accounts their own colour, so a later "other accounts" line can
# colour each one; anything else (the router's CLAUDE) is plain text. Under
# ansi, line 15 is ignored and the 8-colour code comes from the label alone.
account_color() {
  local _c
  if [ "$PALETTE" = "ansi" ]; then
    case "$2" in
      WORK) _c=$'\033[33m' ;; PERSONAL) _c=$'\033[36m' ;; DEV) _c=$'\033[32m' ;;
      *)    _c=$'\033[37m' ;;
    esac
  elif [ -n "$LABEL_OVERRIDDEN" ] && [ "$2" = "$ACCOUNT_NAME" ]; then
    _c=$C_TEXT
  elif [ "$2" = "$ACCOUNT_NAME" ]; then
    _c=$ACCOUNT_COLOR
  else
    case "$2" in
      WORK) _c=$'\033[38;2;249;226;175m' ;; PERSONAL) _c=$'\033[38;2;137;220;235m' ;;
      DEV)  _c=$'\033[38;2;166;227;161m' ;; *) _c=$C_TEXT ;;
    esac
  fi
  printf -v "$1" '%s' "$_c"
}

# -- Icons and glyphs --
# Each I_* ends in one space, or is empty under ascii, so a segment can write
# "${I_GIT}${branch}" with no tier check. Nerd Font codepoints as CCometixLine
# uses them (Nerd Fonts 3.x), written as byte escapes so the file stays 7-bit
# and bash 3.2 (no \u escapes there) can still build them.
case "$GLYPHS" in
  nerd)
    I_MODEL=$'\xee\xbc\xa3 ';    I_NAME=$'\xef\x80\xab ';     I_DIR=$'\xf3\xb0\x89\x8b '
    I_GIT=$'\xf3\xb0\x8a\xa2 ';  I_WT=$'\xef\x86\xbb ';       I_PR=$'\xef\x90\x87 '
    I_STYLE=$'\xf3\xb1\x8b\xb5 '; I_VIM=$'\xee\x98\xab ';     I_AGENT=$'\xef\x80\x87 '
    I_COMPACT=$'\xef\x81\xa6 '; I_QUOTA=$'\xf3\xb0\x94\xa0 '; I_ETA=$'\xef\x89\x92 '
    I_COST=$'\xee\xbb\x81 ';    I_TODAY=$'\xef\x81\xb3 ';     I_RATE=$'\xef\x83\xa4 '
    I_CACHE=$'\xef\x87\x80 ';   I_TIME=$'\xf3\xb1\xa6\xbb ';  I_SWITCH=$'\xef\x83\xac '
    I_DEV="▶ " ;;
  unicode)
    I_MODEL="◆ "; I_NAME="# "; I_DIR="▣ "; I_GIT="⎇ "; I_WT="⑂ "; I_PR="⇄ "
    I_STYLE="◎ "; I_VIM="v "; I_AGENT="@ "; I_COMPACT="⇲ "; I_QUOTA="◷ "; I_ETA="⇥ "
    I_COST="$ "; I_TODAY="∑ "; I_RATE="∂ "; I_CACHE="≈ "; I_TIME="◷ "; I_SWITCH="⇆ "
    I_DEV="▶ " ;;
  *)
    I_MODEL=""; I_NAME=""; I_DIR=""; I_GIT=""; I_WT=""; I_PR=""
    I_STYLE=""; I_VIM=""; I_AGENT=""; I_COMPACT=""; I_QUOTA=""; I_ETA=""
    I_COST=""; I_TODAY=""; I_RATE=""; I_CACHE=""; I_TIME=""; I_SWITCH=""
    I_DEV="> " ;;
esac
if [ "$GLYPHS" = "ascii" ]; then
  G_FULL="="; G_EMPTY="-"; G_UP="^"; G_DOWN="v"; G_EVEN="+-"; G_DOT="-"; G_ELLIPSIS="..."
  SEP="${C_SEP} | ${RESET}"
else
  G_FULL="▰"; G_EMPTY="▱"; G_UP="⇡"; G_DOWN="⇣"; G_EVEN="±"; G_DOT="·"; G_ELLIPSIS="…"
  SEP="${C_SEP} │ ${RESET}"
fi

# -- Which config dir this session runs under, needed by the jq pass below --
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# -- Extract every field in one jq pass (one fork instead of ten) --
# Numeric fields that may be absent use -1 as the sentinel so a real 0
# stays distinguishable from "not sent".
#
# The Claude account email comes through --slurpfile rather than a second jq.
# .claude.json is ~178KB, but the cost was the extra process, not the parse:
# two jq calls 6.4ms, one with --slurpfile 4.9ms, one without the account file
# 3.0ms (min of 30 runs, three interleaved rounds). Caching the email instead
# would have been the wrong fix: with "refreshInterval": 60 against a 10s cache
# every scheduled render misses, so a cached value saves nothing on the path
# that actually dominates, while this saves ~1.5ms on every render.
#
# /dev/null stands in for a missing file: --slurpfile on a path that does not
# exist is a hard jq error, while on /dev/null it yields an empty array, so
# $acct[0] is null and the email falls back to "".
#
# One jq error aborts the whole pass and blanks every field on the line, so a
# single field arriving in an unexpected shape must not be able to raise one.
# Two kinds are guarded:
#   - indexing the wrong type: {"model":"x"} makes .model.display_name fail
#     with "Cannot index string". opt() turns any error in one field into null
#     and its `//` default takes over. A trailing `?` is not enough: it only
#     covers the last step, so .rate_limits.five_hour.used_percentage? still
#     fails when .rate_limits is an array, and so does any path on a payload
#     whose root is not an object.
#   - `floor` on a non-number: `numbers` drops a wrong-typed value first.
#
# Each value becomes one line, read back into F by position, so a real newline
# inside any value would shift every field after it (a model name with one in
# it pushed the cwd into the next slot). clean() flattens CR and LF to spaces.
#
# clean() also makes every value safe to print, after claude-hud's
# sanitizeDisplayText: it strips CSI and OSC escape sequences, other two-byte
# ESC sequences, the remaining C0/C1 controls and DEL, and the bidi marks,
# embeddings, overrides and isolates. Printing with %s (see ANSI colors) only
# stops printf from expanding backslashes; a raw ESC byte in the cwd, the model
# name or the free-text session name would still reach the terminal and could
# recolour, move the cursor or plant a hyperlink. Order matters: whole
# sequences go first so their parameter bytes do not survive as text.
# The control range starts at U+0000, not U+0001: a NUL that reaches
# `_fields=$(...)` makes bash 5 print "ignored null byte in input" on stderr
# (3.2 drops it silently), and jq 1.8 handles \u0000 in a regex class fine.
JQ_FIELDS='
  def opt(f): try f catch null;
  def clean:
    gsub("[\r\n]"; " ")
    | gsub("\u001b\\[[0-?]*[ -/]*[@-~]"; "")
    | gsub("\u001b\\][^\u0007\u001b]*(\u0007|\u001b\\\\)"; "")
    | gsub("\u001b[@-Z\\\\-_]"; "")
    | gsub("[\u0000-\u001f\u007f-\u009f؜‎‏‪-‮⁦-⁯]"; "");
  [ (opt(.model.display_name)                      // "?"),
    (opt(.workspace.current_dir) // opt(.cwd)      // ""),
    ((opt(.context_window.used_percentage) | numbers | floor) // 0),
    (opt(.cost.total_cost_usd)                     // 0),
    (opt(.cost.total_duration_ms)                  // 0),
    (opt(.cost.total_lines_added)                  // 0),
    (opt(.cost.total_lines_removed)                // 0),
    (opt(.version)                                 // ""),
    (opt(.context_window.context_window_size)      // 0),
    (opt(.effort.level)                            // ""),
    (opt(.thinking.enabled)                        // false),
    (opt(.fast_mode)                               // false),
    (opt(.pr.number)                               // ""),
    ((opt(.rate_limits.five_hour.used_percentage) | numbers | floor) // -1),
    (opt(.rate_limits.five_hour.resets_at)         // -1),
    ((opt(.rate_limits.seven_day.used_percentage) | numbers | floor) // -1),
    (opt(.rate_limits.seven_day.resets_at)         // -1),
    (opt(.session_id)                              // ""),
    (opt(.permission_mode)                         // ""),
    (opt($acct[0].oauthAccount.emailAddress)       // ""),
    (opt(.session_name | strings)                  // ""),
    (opt(.worktree.name | strings) // opt(.workspace.git_worktree | strings) // ""),
    (opt(.prompt_cache.warm)                       // false),
    (opt(.prompt_cache.caching_observed)           // false),
    ((opt(.prompt_cache.expires_at) | numbers | floor) // -1),
    (opt(.prompt_cache.ttl)                        // ""),
    ((opt(.prompt_cache.hit_ratio) | numbers | . * 100 | round) // -1),
    (opt(.workspace.repo.host | strings)           // ""),
    (opt(.workspace.repo.owner | strings)          // ""),
    (opt(.workspace.repo.name | strings)           // ""),
    (opt(.pr.url | strings)                        // ""),
    ((opt(.context_window.current_usage.input_tokens) | numbers | floor) // 0),
    ((opt(.context_window.current_usage
          | [.cache_creation_input_tokens, .cache_read_input_tokens]
          | map(numbers) | add | floor)) // 0),
    ((opt(.rate_limits.spend_limit.used_percentage) | numbers | floor) // -1),
    ((opt(.rate_limits.spend_limit.resets_at) | numbers | floor) // -1),
    (opt(.rate_limits.spend_limit.used_usd | numbers)  // ""),
    (opt(.rate_limits.spend_limit.limit_usd | numbers) // ""),
    (opt(.rate_limits.spend_limit.period | strings)    // ""),
    (opt(.pr.review_state | strings)               // ""),
    (opt(.workspace.project_dir | strings)         // "")
  ] | .[] | if type == "string" then clean else tostring end'
# Numbers and booleans cannot hold control characters, so only strings go
# through clean().

acct_file="$config_dir/.claude.json"
[ -f "$acct_file" ] || acct_file=/dev/null
_fields=$(printf '%s' "$input" | jq -r --slurpfile acct "$acct_file" "$JQ_FIELDS" 2>/dev/null)
# A half-written or corrupt .claude.json makes jq exit 2 with no output at all,
# which would blank every field on the line rather than just the email. Retry
# without it so a bad account file costs only the thing it describes.
if [ -z "$_fields" ]; then
  _fields=$(printf '%s' "$input" | jq -r --slurpfile acct /dev/null "$JQ_FIELDS" 2>/dev/null)
fi

# `mapfile` is bash 4+; macOS ships bash 3.2, so read the lines in a loop.
# The redirect keeps the loop in the current shell, so F survives it.
F=()
while IFS= read -r _f; do F+=("$_f"); done < <(printf '%s\n' "$_fields")

model="${F[0]}";        cwd="${F[1]}";           pct="${F[2]}"
cost="${F[3]}";         duration_ms="${F[4]}";   lines_added="${F[5]}"
lines_removed="${F[6]}"; version="${F[7]}";      cw_size="${F[8]}"
effort="${F[9]}";       thinking="${F[10]}";     fast_mode="${F[11]}"
pr_number="${F[12]}"
rl_5h="${F[13]}";       rl_5h_at="${F[14]}"
rl_7d="${F[15]}";       rl_7d_at="${F[16]}"
session_id="${F[17]}";  permission_mode="${F[18]}"
claude_email="${F[19]}"
session_name="${F[20]}"; worktree="${F[21]}"
cache_warm="${F[22]}";  cache_observed="${F[23]}"
cache_exp="${F[24]}";   cache_ttl="${F[25]}";    cache_hit="${F[26]}"
repo_host="${F[27]}";   repo_owner="${F[28]}";   repo_name="${F[29]}"
pr_url="${F[30]}"
cu_input="${F[31]}";    cu_cache="${F[32]}"
sl_pct="${F[33]}";      sl_at="${F[34]}"
sl_used="${F[35]}";     sl_limit="${F[36]}";     sl_period="${F[37]}"
pr_review="${F[38]}"
project_dir="${F[39]}"

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
_int cache_exp -1
_int cache_hit -1
_int cu_input 0
_int cu_cache 0
_int sl_pct -1
_int sl_at -1
# Dollar amounts are floats like the session cost; anything else is dropped.
[[ "$sl_used" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] || sl_used=""
[[ "$sl_limit" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] || sl_limit=""
# cost is the one float, so _int would reject a real value like 0.42. It still
# needs a guard: printf '%.2f' writes "invalid number" to stderr on anything
# else, and an empty field (non-JSON input, or any jq error) is exactly that.
# The exponent form is allowed because jq prints tiny costs as 1e-07.
[[ "$cost" =~ ^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] || cost=0
[[ "$model" ]] || model="?"

# -- Shorten directory (replace $HOME with ~) --
# Not ${cwd/#$HOME/\~}: bash 5 drops the backslash, but bash 3.2 (/bin/bash on
# macOS) keeps it and rendered `\~`. That form also matched a sibling such as
# /Users/me-old as `~-old`, and an unquoted $HOME is a glob pattern there.
# Inside double quotes `~` is never tilde-expanded, in any bash version.
case "$cwd" in
  "$HOME")   short_dir="~" ;;
  "$HOME"/*) short_dir="~${cwd#"$HOME"}" ;;
  *)         short_dir="$cwd" ;;
esac
# Show just folder name if too long (>30 chars)
if [ ${#short_dir} -gt 30 ]; then
  short_dir="${cwd##*/}"
fi

# The git email used to be read here on every render, uncached, while the
# branch state next to it was cached. It is now resolved inside the cache block
# below, which is the only place that still forks git. The Claude account email
# arrives with the payload, from the single jq pass above.

# No context fallback from current_usage: after /compact it is null too, and
# used_percentage is computed from those same token counts, so the two arrive
# together and a fallback between them never fires. claude-hud covers /compact
# by reading the session transcript, which would cost a file read per render.

# -- Wall clock and UTC offset, read once --
# Shared by the git cache check, the reset countdowns, the usage pace and the
# prompt-cache clock time. The offset comes from the same fork so the cache
# expiry can be shown as local HH:MM by arithmetic instead of a second `date`
# (BSD and GNU also disagree on how to format a given epoch). It is the offset
# now, which is also right at an expiry at most an hour away, barring a DST
# switch inside that hour.
read -r now tz_off < <(date '+%s %z')
[[ "$now" =~ ^[0-9]+$ ]] || now=0
tz_secs=0
if [[ "$tz_off" =~ ^([-+])([0-9]{2})([0-9]{2})$ ]]; then
  # 10# forces base ten: a bare 08 or 09 is an invalid octal literal.
  tz_secs=$(( 10#${BASH_REMATCH[2]} * 3600 + 10#${BASH_REMATCH[3]} * 60 ))
  [ "${BASH_REMATCH[1]}" = "-" ] && tz_secs=$(( -tz_secs ))
fi

# -- Git info (cached PER DIRECTORY) --
# The cache key includes the cwd and uid, so concurrent sessions in
# different repos can no longer overwrite each other's branch state.
safe_cwd="${cwd//\//_}"
safe_cwd="${safe_cwd//[^A-Za-z0-9_.-]/_}"
# Keep the tail (the distinctive part) if the path would overflow NAME_MAX.
# Guarded: a negative offset larger than the string yields "" in bash.
[ ${#safe_cwd} -gt 200 ] && safe_cwd="${safe_cwd: -200}"
# The mangling is lossy: /x/a/b and /x/a_b, or "my repo" and "my_repo", or two
# long paths sharing their last 200 chars, all map to one file. So the file
# name only picks a slot, and the exact cwd is stored as the entry's first line
# and checked on every read. An entry for a different directory counts as a
# miss, so a collision costs a recompute and never shows another repo's branch
# or git identity. Comparing a string costs no fork, unlike hashing the cwd.
#
# The -v5 is the cache *format* version. Each time the entry changes shape,
# reading it back from a file written by the previous format would silently
# shift every value after it, so the format gets a new name instead: v2 added
# conflicts, upstream and ahead/behind, v3 the git email, v4 the cwd key line,
# v5 the upstream ref itself (for the branch link), not just whether one exists.
CACHE_FILE="/tmp/claude-statusline-git-v5-${UID}-${safe_cwd}"
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

# True when the entry's key line is this exact cwd. A read failure leaves _key
# empty, which only matches an empty cwd, and that never reaches the cache.
cache_is_ours() {
  local _key=""
  IFS= read -r _key < "$CACHE_FILE" || return 1
  [ "$_key" = "$cwd" ]
}

cache_is_stale() {
  [ ! -f "$CACHE_FILE" ] || \
  [ $((now - $(_mtime "$CACHE_FILE"))) -gt $CACHE_MAX_AGE ] || \
  ! cache_is_ours
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
  #
  # --ignore-submodules=untracked keeps that equivalence for submodules. A
  # submodule holding nothing but untracked files is reported as `1 .M S..U`,
  # whose Y field would count as modified, while `git diff` ignored it because
  # diff.ignoreSubmodules defaults to untracked. Without the flag a submodule
  # with build output in it would pin a permanent `~1` on the line. A real
  # tracked change inside a submodule still reports (`S.M.`), as it did before.
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
  done < <(git --no-optional-locks -C "$cwd" status --porcelain=v2 --branch -uall \
    --ignore-submodules=untracked 2>/dev/null)

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

  # The git identity belongs here rather than on every render: it is read from
  # git config, so it respects an includeIf per directory, which makes it a
  # property of the cwd exactly like the branch state beside it. Together with
  # the jq merge above this takes a warm render from 14.4ms to 11.1ms and a
  # cold one from 16.9ms to 15.5ms (min of 30, three interleaved rounds); a
  # miss still pays this fork, because that is the render that fills the cache.
  gh_email=$(git --no-optional-locks -C "$cwd" config user.email 2>/dev/null || echo "")

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
  # The email goes last on purpose: `read` puts anything beyond the named
  # fields into the final variable, so a stray delimiter there cannot shift the
  # counts. (A `|` is legal in a git branch name and would still shift them;
  # a tab delimiter would fix that but IFS collapses runs of whitespace, which
  # would break the all-empty line written outside a work tree.)
  # The cwd sits on its own line ahead of the fields, so a `|` in a path can
  # never shift them. The upstream ref (e.g. origin/main) goes just before the
  # email, so the email keeps its place as the catch-all last field; a `|` in
  # the upstream name has the same caveat as one in the branch name.
  printf '%s\n%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$cwd" \
    "$branch" "$staged" "$modified" "$untracked" \
    "$conflicts" "$no_upstream" "${ahead}/${behind}" "$upstream" "$gh_email" > "$CACHE_FILE.$$"
  # Rename is atomic, so a concurrent reader never sees a half-written line.
  mv -f "$CACHE_FILE.$$" "$CACHE_FILE" 2>/dev/null || rm -f "$CACHE_FILE.$$"
fi

git_branch=""; git_staged=0; git_modified=0; git_untracked=0
git_conflicts=0; git_no_upstream=0; git_ab=""; git_upstream=""; gh_email=""
# The key is checked again here, not just in cache_is_stale: a colliding
# session can rename its own entry into the slot between our write and this
# read. If it does, this render shows no git info rather than the other repo's.
if [ -f "$CACHE_FILE" ]; then
  {
    IFS= read -r _key
    if [ "$_key" = "$cwd" ]; then
      IFS='|' read -r git_branch git_staged git_modified git_untracked \
        git_conflicts git_no_upstream git_ab git_upstream gh_email
    fi
  } < "$CACHE_FILE"
fi
git_ahead="${git_ab%%/*}"; git_behind="${git_ab##*/}"

# -- Build git status indicators --
# Order: branch, then sync state (how it sits against the remote), then dirty
# state (how it sits against the index). A branch with no upstream is called
# out because in a branch-and-PR-per-task workflow it means nothing is pushed
# and no PR can exist yet, which otherwise looks identical to being in sync.
# -- OSC 8 hyperlinks (Cmd+click in iTerm2) --
# ESC ] 8 ;; URL ST  TEXT  ESC ] 8 ;; ST, with ST as ESC \ like claude-hud's
# safeHyperlink. Only https URLs with no whitespace are linked; clean() already
# stripped ESC and BEL from every payload value, so a URL cannot close the
# sequence early and smuggle in its own. Terminals without OSC 8 support show
# the text alone. If links show but do not click, Claude Code (not this script)
# may have missed the terminal's support: launch it as `FORCE_HYPERLINK=1 claude`.
#
# A fourth argument `local` also admits exactly http://localhost:<port>, for
# the dev server links, whose URL is built here from a port number netstat
# reported. Payload URLs never pass it, so a pr.url of http://anything stays
# plain text.
OSC8_ST=$'\033\\'
osc8() {  # $1=outvar  $2=url  $3=text  [$4=local]
  if [[ "$2" =~ ^https://[^[:space:]]+$ ]] \
     || { [ "${4:-}" = "local" ] && [[ "$2" =~ ^http://localhost:[0-9]{1,5}$ ]]; }; then
    printf -v "$1" '%s' $'\033]8;;'"$2${OSC8_ST}$3"$'\033]8;;'"${OSC8_ST}"
  else
    printf -v "$1" '%s' "$3"
  fi
}

# Percent-encode a branch name for a URL path, keeping `/` so feature/x stays a
# path. LC_ALL=C makes ${s:i:1} walk bytes, so a multibyte character becomes
# its UTF-8 %XX sequence instead of one unencoded character.
urlenc_path() {  # $1=outvar  $2=string
  # The & 255: bash 3.2 reads a high byte through printf "'c" as a signed char,
  # so 0xC3 came out as -61 and printed %FFFFFFFFFFFFFFC3.
  local LC_ALL=C _s="$2" _o="" _ch _n _i
  for ((_i = 0; _i < ${#_s}; _i++)); do
    _ch="${_s:_i:1}"
    case "$_ch" in
      [A-Za-z0-9._~/-]) _o+="$_ch" ;;
      *) printf -v _n '%d' "'$_ch"; printf -v _ch '%%%02X' $(( _n & 255 )); _o+="$_ch" ;;
    esac
  done
  printf -v "$1" '%s' "$_o"
}

# Branch page on the forge, from workspace.repo (parsed by Claude Code from the
# origin remote, so no git fork). github.com and gitlab.com only, whose URL
# shapes are known; gitlab owners may be nested group/subgroup paths.
#
# Only for a branch whose upstream is on origin, and the page is the upstream
# branch, not the local name. workspace.repo always describes origin, so a
# branch tracking fork/feature would have linked origin's repo, where it may
# not exist, and a local branch tracking origin/main under another name would
# have linked a branch that is not on the remote at all. A local-only branch
# has no upstream, and neither has a detached HEAD, whose commit may never have
# been pushed: both show plain text rather than a link that can 404.
branch_url=""
_up_branch=""
case "$git_upstream" in origin/?*) _up_branch="${git_upstream#origin/}" ;; esac
if [ -n "$_up_branch" ] \
   && [[ "$repo_owner" =~ ^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$ ]] && [[ "$repo_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  urlenc_path _enc_branch "$_up_branch"
  case "$repo_host" in
    github.com) branch_url="https://github.com/${repo_owner}/${repo_name}/tree/${_enc_branch}" ;;
    gitlab.com) branch_url="https://gitlab.com/${repo_owner}/${repo_name}/-/tree/${_enc_branch}" ;;
  esac
fi

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
  osc8 _branch_txt "$branch_url" "${CYAN}${git_branch}${RESET}"
  git_info=" | ${_branch_txt}"
  [ ${#git_parts[@]} -gt 0 ] && git_info="${git_info} ${git_parts[*]}"
fi

# -- Open PR / merge request for the current branch --
pr_info=""
# pr.url comes straight from Claude Code (a GitLab merge request URL in a
# GitLab repo), so the PR links on any forge, not just the two above.
if [ -n "$pr_number" ]; then
  osc8 _pr_txt "$pr_url" "${MAGENTA}#${pr_number}${RESET}"
  pr_info="  ${_pr_txt}"
  # Review state, which the docs say can be absent even when pr is present.
  # Kept outside the link so only the number is the click target. For a GitLab
  # merge request Claude Code maps mergeable to approved and any other open
  # state to pending. Unknown values (a future enum member) are not shown.
  case "$pr_review" in
    approved)          pr_info+=" ${GREEN}approved${RESET}" ;;
    changes_requested) pr_info+=" ${RED}changes${RESET}" ;;
    pending)           pr_info+=" ${YELLOW}pending${RESET}" ;;
    draft)             pr_info+=" ${DIM}draft${RESET}" ;;
  esac
fi

# -- Dev servers running in this session's project --
# Footer badges (footerLinksRegexes) are text matches on the conversation: they
# show a localhost URL whenever one is printed, running or not, and a server
# started outside the session never gets one. This asks the OS instead.
#
# Listening sockets come from lsof on macOS and ss on Linux, filtered to dev
# runtimes: postgres, mysqld, nginx, mailpit and macOS services listen as well.
# Not netstat, although `netstat -anv` is 3ms against lsof's ~27ms: on the Mac
# this was built on, netstat printed nothing at all and still exited 0 whenever
# any ancestor process was Homebrew's bash (through env -i, /bin/sh -c and
# /bin/bash -c too), while lsof answered under both. The status line command is
# a bare `bash`, which can resolve to Homebrew's, so netstat would have failed
# silently. The listener list is cached for 10s in one file shared by every
# session, which absorbs the burst of renders in a turn the way the git cache
# does; CLAUDE_STATUSLINE_DEV_MAX_AGE overrides that (the tests set 0).
#
# A server belongs to the session when its working directory is the project
# (workspace.project_dir, else the cwd) or inside it, so apps/web in a monorepo
# counts and a sibling such as app-old does not. Paths are compared both as
# given and with symlinks resolved, since macOS reports /var/folders as
# /private/var/folders. Looking up a pid's cwd is the slow part on macOS (lsof,
# ~21ms), so it is cached per pid for 10 minutes: a running server does not
# change directory, and the expiry bounds the damage if a pid is reused. Linux
# reads /proc/PID/cwd, no lsof.
#
# A session in the home directory is not a project: every server under ~ would
# match, so it shows none. Up to three ports show, lowest first, each linked to
# http://localhost:<port>.
# Linux matches the executable's file name (/proc/PID/exe), not the process
# name ss reports: that name is /proc/PID/comm, which a process can change.
# The official Node 24 builds name their main thread MainThread, which is what
# comm shows (found by CI, whose runner uses them; Ubuntu's packaged node still
# says node), and Next.js retitles itself next-server. The executable stays
# node. A trailing " (deleted)" (the binary was upgraded underneath) is dropped.
# The macOS side is the -c list in _dev_scan, where p_comm is not retitled.
DEV_EXES='node|bun|deno|php[0-9.]*|python[0-9.]*|ruby[0-9.]*'

# Both dev caches store their own write time as the first word and compare it
# with $now, instead of asking stat for the mtime: that is a fork per file per
# render, and on a warm cache those forks were most of what this section cost.
_dev_cwd() {  # $1=outvar  $2=pid
  local _f="/tmp/claude-statusline-devcwd-${UID}-$2" _c="" _x _line="" _ts
  [ -f "$_f" ] && IFS= read -r _line < "$_f"
  _ts="${_line%% *}"
  if [[ "$_ts" =~ ^[0-9]+$ ]] && [ $((now - _ts)) -le 600 ]; then
    _c="${_line#* }"
  else
    case "$OSTYPE" in
      darwin*|*bsd*|FreeBSD*)
        while IFS= read -r _x; do
          case "$_x" in n*) _c="${_x#n}"; break ;; esac
        done < <(lsof -a -p "$2" -d cwd -Fn 2>/dev/null)
        ;;
      *) _c=$(readlink "/proc/$2/cwd" 2>/dev/null) ;;
    esac
    # Same atomic write as the git cache, so a concurrent render never reads a
    # half-written entry. The cwd follows the first space, so one containing
    # spaces survives the round trip. An empty answer is not cached: the
    # listener list can be up to 10s old, so the pid may have just exited, and
    # caching "no cwd" would hide a new server that reuses the pid for 10min.
    [ -n "$_c" ] && printf '%s %s\n' "$now" "$_c" > "$_f.$$" 2>/dev/null \
      && mv -f "$_f.$$" "$_f" 2>/dev/null
  fi
  printf -v "$1" '%s' "$_c"
}

dev_info=""
_dev_proj="${project_dir:-$cwd}"
_dev_proj="${_dev_proj%/}"
case "$_dev_proj" in ""|"$HOME") _dev_proj="" ;; esac
# Prints " port:pid" for every listening dev runtime, one entry per socket.
_dev_scan() {
  local _x _pid=""
  case "$OSTYPE" in
    darwin*|*bsd*|FreeBSD*)
      # -c is a prefix match on the program name (python3.12 matches python,
      # and the framework build on macOS is "Python"). -F output is one field
      # per line: p<pid>, f<fd>, n<address> such as *:3000 or [::1]:3000.
      while IFS= read -r _x; do
        case "$_x" in
          p*) _pid="${_x#p}" ;;
          n*) [[ "$_x" =~ :([0-9]+)$ ]] && printf ' %s:%s' "${BASH_REMATCH[1]}" "$_pid" ;;
        esac
      done < <(lsof -nP -a -iTCP -sTCP:LISTEN -c node -c bun -c deno -c php \
        -c python -c Python -c ruby -Fpn 2>/dev/null)
      ;;
    *)
      # LISTEN 0 511 127.0.0.1:3000 0.0.0.0:* users:(("MainThread",pid=4436,fd=21))
      # ss names a process only for the user's own sockets, so the readlink
      # below runs for a handful of pids, once each (_seen holds pid=verdict).
      local _re='^LISTEN +[0-9]+ +[0-9]+ +[^ ]*:([0-9]+) +[^ ]+ +users:\(\("[^"]*",pid=([0-9]+),'
      local _seen=" " _port _p _exe
      while IFS= read -r _x; do
        [[ "$_x" =~ $_re ]] || continue
        _port="${BASH_REMATCH[1]}"; _p="${BASH_REMATCH[2]}"
        case "$_seen" in
          *" $_p=1 "*) ;;
          *" $_p=0 "*) continue ;;
          *)
            _exe=$(readlink "/proc/$_p/exe" 2>/dev/null)
            _exe="${_exe% (deleted)}"; _exe="${_exe##*/}"
            if [[ "$_exe" =~ ^(${DEV_EXES})$ ]]; then _seen+="$_p=1 "; else _seen+="$_p=0 "; continue; fi
            ;;
        esac
        printf ' %s:%s' "$_port" "$_p"
      done < <(ss -ltnpH 2>/dev/null)
      ;;
  esac
}

# " port:pid" pairs. Only exact repeats collapse here (one process listening on
# both IPv4 and IPv6). Ports are deduplicated after the project check, not
# before: two processes can hold one port on different loopback addresses
# (127.0.0.1:3000 and [::1]:3000), and keeping whichever lsof listed first
# dropped the session's own server whenever the other project's came first.
_dev_list=""
if [ -n "$_dev_proj" ]; then
  _dev_cache="/tmp/claude-statusline-devlisten-${UID}"
  _dev_age="${CLAUDE_STATUSLINE_DEV_MAX_AGE:-10}"
  [[ "$_dev_age" =~ ^[0-9]+$ ]] || _dev_age=10
  _dev_raw=""; _dev_ts=""
  # A max age of 0 bypasses the shared cache entirely, reading and writing:
  # the tests run that way, and their fixture servers must never reach the
  # file the developer's real sessions read.
  [ "$_dev_age" -gt 0 ] && [ -f "$_dev_cache" ] && read -r _dev_ts _dev_raw < "$_dev_cache"
  if ! { [[ "$_dev_ts" =~ ^[0-9]+$ ]] && [ $((now - _dev_ts)) -lt "$_dev_age" ]; }; then
    _dev_raw=$(_dev_scan)
    [ "$_dev_age" -gt 0 ] && printf '%s %s\n' "$now" "$_dev_raw" > "$_dev_cache.$$" 2>/dev/null \
      && mv -f "$_dev_cache.$$" "$_dev_cache" 2>/dev/null
  fi
  for _e in $_dev_raw; do
    [[ "$_e" =~ ^[0-9]+:[0-9]+$ ]] || continue
    case "$_dev_list " in *" $_e "*) continue ;; esac
    _dev_list+=" $_e"
  done
fi
if [ -n "$_dev_list" ]; then
  # The symlink-resolved project path costs a subshell, so it is worked out
  # only the first time a server's cwd fails to match the path as given.
  _dev_real=""; _dev_resolved=0
  _dev_ports=()
  for _e in $_dev_list; do
    _dev_cwd _dc "${_e#*:}"
    case "$_dc" in
      "") continue ;;
      "$_dev_proj"|"$_dev_proj"/*) ;;
      *)
        if [ "$_dev_resolved" = 0 ]; then
          _dev_real=$(cd "$_dev_proj" 2>/dev/null && pwd -P); _dev_resolved=1
        fi
        [ -n "$_dev_real" ] && [ "$_dev_real" != "$_dev_proj" ] || continue
        case "$_dc" in "$_dev_real"|"$_dev_real"/*) ;; *) continue ;; esac
        ;;
    esac
    # Now one link per port: two of the project's own processes on one port
    # (both loopback addresses) still make a single localhost link.
    _p="${_e%%:*}"
    case " ${_dev_ports[*]} " in *" $_p "*) continue ;; esac
    # Insertion sort, lowest port first: bash 3.2 has no sort builtin, and a
    # `sort` fork for a list this short would cost more than it saves.
    _i=${#_dev_ports[@]}; _dev_ports+=("$_p")
    while [ "$_i" -gt 0 ] && [ "${_dev_ports[$((_i - 1))]}" -gt "$_p" ]; do
      _dev_ports[$_i]="${_dev_ports[$((_i - 1))]}"; _i=$((_i - 1))
    done
    _dev_ports[$_i]="$_p"
  done
  if [ ${#_dev_ports[@]} -gt 0 ]; then
    _dev_txt=""
    for _p in "${_dev_ports[@]:0:3}"; do
      osc8 _dl "http://localhost:${_p}" "${GREEN}localhost:${_p}${RESET}" local
      _dev_txt+="${_dev_txt:+ }${_dl}"
    done
    [ ${#_dev_ports[@]} -gt 3 ] && _dev_txt+=" ${DIM}+$(( ${#_dev_ports[@]} - 3 ))${RESET}"
    dev_info="${GREEN}▶${RESET} ${_dev_txt}"
  fi
fi

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

# -- Token breakdown once context is nearly full --
# ` (in: 12k, cache: 180k)` from 85%, claude-hud's critical threshold: that is
# when it matters whether the bulk is fresh input or cached history. Both
# numbers are from the last API call, the same input-only sum that
# used_percentage is computed from.
fmt_tok() {  # $1=outvar  $2=token count
  if   [ "$2" -ge 1000000 ]; then printf -v "$1" '%d.%dM' $(( $2 / 1000000 )) $(( ($2 % 1000000) / 100000 ))
  elif [ "$2" -ge 1000 ];    then printf -v "$1" '%dk' $(( $2 / 1000 ))
  else                            printf -v "$1" '%d' "$2"
  fi
}
tok_info=""
if [ "$pct" -ge 85 ] && [ $((cu_input + cu_cache)) -gt 0 ]; then
  fmt_tok _tin "$cu_input"; fmt_tok _tca "$cu_cache"
  tok_info=" ${DIM}(in: ${_tin}, cache: ${_tca})${RESET}"
fi

BAR_WIDTH=10
filled=$((pct * BAR_WIDTH / 100))
[ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
[ "$filled" -lt 0 ] && filled=0
empty=$((BAR_WIDTH - filled))
bar=""
for ((i=0; i<filled; i++)); do bar+="$G_FULL"; done
for ((i=0; i<empty; i++)); do bar+="$G_EMPTY"; done
[ "$GLYPHS" = "ascii" ] && bar="[${bar}]"

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

# Usage pace, after claude-hud's getUsagePace: project the used percentage
# linearly to the window's reset. 40% used one hour into a 5h window projects
# to 200%, which the raw percentage alone shows as a calm green. Projection
# above 100% (the limit runs out before the reset) is red, 90% or more is
# yellow, and the percent takes whichever of threshold or pace is worse. When
# pace raises an alert the projection is shown as `→200%`, which is the cue to
# switch accounts, but only when it is above the current percent: right before
# a reset almost no time is left to project over, so 95% projects to 95% and
# `5h 95% →95%` would say nothing. That case needs 90% or more used, where the
# threshold colour is already red, so hiding the marker loses no colour either.
# Below 10% used a projection is noise (3% five minutes in
# "projects" 180%), and a reset already past or a full window away has no
# elapsed time to project from, so neither grades pace.
fmt_rl() {  # $1=outvar  $2=label  $3=percent  $4=resets_at epoch (-1 if absent)  $5=window seconds
  local _sev=0 _psev=0 _c="$GREEN" _pc="" _rem _proj=0 left="" _pace=""
  if [ "$3" -ge 90 ]; then _sev=2; elif [ "$3" -ge 70 ]; then _sev=1; fi
  if [ "$4" -ge 0 ] && [ "$3" -ge 10 ]; then
    _rem=$(( $4 - now ))
    if [ "$_rem" -gt 0 ] && [ "$_rem" -lt "$5" ]; then
      _proj=$(( $3 * $5 / ($5 - _rem) ))
      if [ "$_proj" -gt 100 ]; then _psev=2; elif [ "$_proj" -ge 90 ]; then _psev=1; fi
    fi
  fi
  [ "$_psev" -gt "$_sev" ] && _sev=$_psev
  case "$_sev" in 2) _c="$RED" ;; 1) _c="$YELLOW" ;; esac
  if [ "$_psev" -gt 0 ] && [ "$_proj" -gt "$3" ]; then
    [ "$_psev" -eq 2 ] && _pc="$RED" || _pc="$YELLOW"
    [ "$_proj" -gt 999 ] && _proj=999
    _pace=" ${_pc}→${_proj}%${RESET}"
  fi
  [ "$4" -ge 0 ] && fmt_left left "$4"
  [ -n "$left" ] && left=" ${DIM}(${left})${RESET}"
  printf -v "$1" '%s%s%s %s%s%%%s%s%s' "$DIM" "$2" "$RESET" "$_c" "$3" "$RESET" "$_pace" "$left"
}

rl_parts=()
if [ "$rl_5h" -ge 0 ]; then fmt_rl _rl5 "5h" "$rl_5h" "$rl_5h_at" 18000; rl_parts+=("$_rl5"); fi
if [ "$rl_7d" -ge 0 ]; then fmt_rl _rl7 "7d" "$rl_7d" "$rl_7d_at" 604800; rl_parts+=("$_rl7"); fi

# Spend limit: only sent behind a Claude apps gateway that sets one, so on a
# plain Pro/Max login it never appears. used_percentage can pass 100 once the
# limit is exceeded, which fmt_rl already colours red. Pace needs a fixed
# window length, which daily and weekly have; a monthly period runs 28 to 31
# days, and guessing the wrong one skews the projection, so it gets window 0,
# which fmt_rl treats as "no pace". The dollar amounts arrive separately and
# up to five minutes later, so each is optional.
if [ "$sl_pct" -ge 0 ]; then
  case "$sl_period" in
    daily)  _sl_win=86400 ;;
    weekly) _sl_win=604800 ;;
    *)      _sl_win=0 ;;
  esac
  fmt_rl _rls "spend" "$sl_pct" "$sl_at" "$_sl_win"
  if [ -n "$sl_used" ] && [ -n "$sl_limit" ]; then
    _rls+=" ${DIM}$(printf '$%.0f/$%.0f' "$sl_used" "$sl_limit")${RESET}"
  fi
  rl_parts+=("$_rls")
fi
rl_info=""
[ ${#rl_parts[@]} -gt 0 ] && rl_info="${SEP}${rl_parts[*]}"

# -- Prompt cache: when it goes cold, and the session hit rate --
# A clock time, not a countdown, as claude-hud's promptCacheLine does: the line
# is not repainted between turns, exactly when the cache drains, so a countdown
# would freeze on a stale value. Green while warm, yellow in the last fifth of
# the TTL (at least a minute), dim `cold` once it has expired. Hidden until
# Claude Code has seen caching at all, so a fresh session shows nothing.
cache_info=""
if [ "$cache_observed" = "true" ]; then
  _cache_left=-1
  [ "$cache_warm" = "true" ] && [ "$cache_exp" -gt 0 ] && _cache_left=$((cache_exp - now))
  if [ "$_cache_left" -gt 0 ]; then
    case "$cache_ttl" in 1h) _ttl=3600 ;; *) _ttl=300 ;; esac
    _warn=$((_ttl / 5)); [ "$_warn" -lt 60 ] && _warn=60
    _local=$(( (cache_exp + tz_secs) % 86400 ))
    printf -v _hhmm '%02d:%02d' $((_local / 3600)) $(((_local % 3600) / 60))
    _cc="$GREEN"; [ "$_cache_left" -le "$_warn" ] && _cc="$YELLOW"
    cache_info="${DIM}cache${RESET} ${_cc}${_hhmm}${RESET}"
  else
    cache_info="${DIM}cache cold${RESET}"
  fi
fi
# Gated on caching_observed like the expiry above: with caching off, or a
# provider that does not report cache tokens, hit_ratio is a real 0, and
# `hit 0%` would read as a cache doing badly rather than one not in play.
if [ "$cache_observed" = "true" ] && [ "$cache_hit" -ge 0 ]; then
  [ "$cache_hit" -gt 100 ] && cache_hit=100
  _hit="${DIM}hit${RESET} ${cache_hit}%"
  cache_info="${cache_info:+${cache_info} }${_hit}"
fi
[ -n "$cache_info" ] && cache_info="${SEP}${cache_info}"

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
  lines_info="${SEP}${GREEN}+${lines_added}${RESET} ${RED}-${lines_removed}${RESET}"
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

# -- Session name (/rename, or the title Claude Code generated) --
# Easier to recognise than the id when picking a session up from another
# account. Already sanitised by clean(); capped so a long title cannot push the
# directory and branch off the line. Bash counts characters, not bytes, under a
# UTF-8 locale, so the cut does not split a multibyte character there.
name_info=""
if [ -n "$session_name" ]; then
  # 30 characters in all: 29 plus a one-character ellipsis, 27 plus "...".
  [ ${#session_name} -gt 30 ] && session_name="${session_name:0:$((30 - ${#G_ELLIPSIS}))}${G_ELLIPSIS}"
  name_info=" ${MAGENTA}${session_name}${RESET}"
fi

# -- Worktree (superpowers and EnterWorktree sessions) --
# workspace.git_worktree can be a path, so keep only its last segment.
wt_info=""
if [ -n "$worktree" ]; then
  wt_info=" ${DIM}wt:${RESET}${MAGENTA}${worktree##*/}${RESET}"
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
account_color _acct_col "$ACCOUNT_NAME"
account_label="${BOLD}${_acct_col}${ACCOUNT_NAME}${RESET}"

# -- LINE 1: Account | Git user (Claude account) | Model + flags + mode | Version | Session id | Dir | Git | PR --
# Dev servers get line 3: at the end of line 1 a narrow terminal cut them off.
# %s, never %b: the colours already hold real ESC bytes, and %b would expand
# backslash escapes inside the cwd, branch name and email too (see ANSI colors).
printf '%s\n' "${account_label}  ${gh_prefix}${claude_prefix}  ${C_IDENT}${I_MODEL}${RESET}${BOLD}[${model}]${RESET}${cw_label}${flags_info}${perm_info}${ver_info}${id_info}${name_info}  ${short_dir}${git_info}${wt_info}${pr_info}"

# -- LINE 2: Context bar | Rate limits + pace | Prompt cache | Cost | Duration | Lines --
printf '%s' "${bar_color}${bar}${RESET} ${pct}%${tok_info}${rl_info}${cache_info}${SEP}${YELLOW}${cost_fmt}${RESET}${SEP}${time_fmt}${lines_info}"

# -- LINE 3: Dev servers running in the project, only when there are any --
if [ -n "$dev_info" ]; then printf '\n%s' "$dev_info"; fi
