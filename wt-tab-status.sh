#!/usr/bin/env bash
# Windows Terminal (WSL) tab status indicator for Claude Code.
# Port of iterm-tab-status.sh - same hooks, same states.
#
#   busy     -> tab turns orange, spinner on the tab + taskbar while Claude works
#   waiting  -> tab goes red, taskbar goes red (Claude needs input / permission)
#   done     -> tab blinks green x4, then stays green with a full progress ring
#   reset    -> clears tab colour and progress indicator
#
# Wired up from the hooks block in each account's settings.json.
set -u

# Only meaningful inside Windows Terminal. Hooks inherit claude's environment.
[ -n "${WT_SESSION:-}" ] || exit 0

PROGRESS=1           # 0 = leave the tab progress ring / taskbar alone
BELL=0               # 1 = also ring the bell on "waiting" (sound or flash, per WT bellStyle)
BLINKS=4             # blink cycles for "done"
BLINK_DELAY=0.22

# DECAC only takes a palette index, not RGB, so these are the xterm 256-colour
# cube entries closest to the iTerm version's colours. WT picks a contrasting
# label colour on its own.
COLOR_BUSY=130       # #af5f00
COLOR_WAITING=160    # #d70000
COLOR_DONE=29        # #00875f

# Hooks are spawned detached from the controlling terminal, so /dev/tty is
# unusable and $PPID (an intermediate shell) reports no tty either. Walk up the
# process tree until we hit the claude CLI, which does own the WT pty.
find_tty() {
  local p=$PPID t a i=0
  while [ "$i" -lt 8 ] && [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
    read -r t a <<< "$(ps -o tty=,ppid= -p "$p")"
    case "${t:-?}" in
      '?' | '??') ;;
      *) printf '%s' "$t"; return 0 ;;
    esac
    p="$a"
    i=$((i + 1))
  done
  return 1
}
tty_name=$(find_tty) || exit 0
DEV="/dev/$tty_name"
[ -w "$DEV" ] || exit 0

# Linux tty names contain a slash (pts/6), so flatten them for the state files.
key="${tty_name//\//-}"
RUN="${TMPDIR:-/tmp}"
STATEFILE="$RUN/claude-tab-$key.state"
GENFILE="$RUN/claude-tab-$key.gen"

# DECAC item 2 (window frame) is the WT tab colour. 263/264 are WT's own frame
# fg/bg table slots, so pointing the alias back at them restores the profile
# default (no colour, or the profile's tabColor).
tabcolor()  { printf '\033[2;15;%s,|' "$1" > "$DEV"; }
tabreset()  { printf '\033[2;263;264,|' > "$DEV"; }
# OSC 9;4 states: 0 clear, 1 normal, 2 error, 3 indeterminate, 4 warning.
progress()  { [ "$PROGRESS" = 1 ] || return 0
              printf '\033]9;4;%s;%s\007' "$1" "${2:-0}" > "$DEV"; }
bell()      { [ "$BELL" = 1 ] || return 0; printf '\007' > "$DEV"; }
set_state() { printf '%s' "$1" > "$STATEFILE"; }
get_state() { local s=none; [ -f "$STATEFILE" ] && read -r s < "$STATEFILE"; printf '%s' "${s:-none}"; }

# Every state transition claims the tab by writing its own pid. The "done" blink
# re-checks the claim before each write and bails the moment a newer transition
# has taken over, so it can never repaint over a "busy" or "reset".
claim()     { printf '%s' "$$" > "$GENFILE"; }
current()   { local g=''; [ -f "$GENFILE" ] && read -r g < "$GENFILE"; [ "$g" = "$$" ]; }

case "${1:-reset}" in

  busy)
    claim
    # busy fires on every PostToolUse, so without this guard the tab would be
    # repainted at every tool call - straight into the pty Claude Code is
    # rendering to. Only repaint on a real state transition.
    [ "$(get_state)" = busy ] && exit 0
    set_state busy
    tabcolor "$COLOR_BUSY"
    progress 3
    ;;

  waiting)
    # Don't stomp on the green "done" tab when an idle notification fires.
    [ "$(get_state)" = "done" ] && exit 0
    claim
    set_state waiting
    tabcolor "$COLOR_WAITING"
    progress 2 100
    bell
    ;;

  done)
    claim
    # A busy/reset may have claimed in between - don't force the state back to
    # "done" over it, or the next red "needs input" tab would be suppressed.
    current || exit 0
    set_state "done"
    i=0
    while [ "$i" -lt "$BLINKS" ] && current; do
      tabcolor "$COLOR_DONE"; sleep "$BLINK_DELAY"
      current || break
      tabreset;               sleep "$BLINK_DELAY"
      i=$((i + 1))
    done
    if current; then
      tabcolor "$COLOR_DONE"
      progress 1 100
    fi
    ;;

  *)
    claim
    set_state none
    tabreset
    progress 0
    ;;
esac
exit 0
