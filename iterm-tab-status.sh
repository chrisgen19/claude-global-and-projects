#!/usr/bin/env bash
# iTerm2 tab status indicator for Claude Code.
#
#   busy     -> tab pulses orange while Claude is working
#   waiting  -> tab goes red, dock bounces (Claude needs input / permission)
#   done     -> tab blinks green x4, then stays green + one dock bounce
#   reset    -> clears tab color, badge and any running animation
#
# Wired up from the hooks block in each account's settings.json.
set -u

# Only meaningful inside iTerm2.
[ "${TERM_PROGRAM:-}" = "iTerm.app" ] || exit 0

BADGE=1              # 0 = no translucent in-pane badge
PULSE=1              # 0 = steady orange instead of the breathing animation
BLINKS=4             # blink cycles for "done"
BLINK_DELAY=0.22
PULSE_DELAY=0.15
MAX_PULSE_ITERS=100000   # backstop so an orphaned animation can't run forever

# Hooks are spawned detached from the controlling terminal, so /dev/tty is
# unusable and $PPID (an intermediate shell) reports no tty either. Walk up the
# process tree until we hit the claude CLI, which does own the iTerm2 pty.
find_tty() {
  local p=$PPID t a i=0
  while [ "$i" -lt 8 ] && [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
    read -r t a <<< "$(ps -o tty=,ppid= -p "$p")"
    case "${t:-??}" in
      '?' | '??') ;;
      *) printf '%s' "$t"; return 0 ;;
    esac
    p="$a"
    i=$((i + 1))
  done
  return 1
}
# The detached animation child is handed the tty directly: by the time it
# starts, its own parent has exited and the ancestry walk would find nothing.
tty_name="${CLAUDE_TAB_TTY:-}"
[ -n "$tty_name" ] || tty_name=$(find_tty)
[ -n "$tty_name" ] || exit 0
DEV="/dev/$tty_name"
[ -w "$DEV" ] || exit 0

RUN="${TMPDIR:-/tmp}"
PIDFILE="$RUN/claude-tab-$tty_name.pid"
STATEFILE="$RUN/claude-tab-$tty_name.state"
GENFILE="$RUN/claude-tab-$tty_name.gen"

# ps prints nothing (and no stderr) for a dead pid.
alive()     { [ -n "$(ps -p "$1" -o pid=)" ]; }
tabcolor()  { printf '\033]6;1;bg;red;brightness;%s\007\033]6;1;bg;green;brightness;%s\007\033]6;1;bg;blue;brightness;%s\007' \
                "$1" "$2" "$3" > "$DEV"; }
tabreset()  { printf '\033]6;1;bg;*;default\007' > "$DEV"; }
attention() { printf '\033]1337;RequestAttention=%s\007' "$1" > "$DEV"; }
badge()     { [ "$BADGE" = 1 ] || return 0
              printf '\033]1337;SetBadgeFormat=%s\007' "$(printf '%s' "$1" | base64)" > "$DEV"; }
set_state() { printf '%s' "$1" > "$STATEFILE"; }
get_state() { local s=none; [ -f "$STATEFILE" ] && read -r s < "$STATEFILE"; printf '%s' "${s:-none}"; }

# Every state transition claims the tab by writing its own pid. A long-running
# animation re-checks the claim before each write and bails the moment a newer
# transition has taken over, so a slow "done" blink can never repaint over a
# "busy" or "reset" that landed while it was still running.
claim()     { printf '%s' "$$" > "$GENFILE"; }
current()   { local g=''; [ -f "$GENFILE" ] && read -r g < "$GENFILE"; [ "$g" = "$$" ]; }

pulse_pid() { local p=''; [ -f "$PIDFILE" ] && read -r p < "$PIDFILE"; printf '%s' "$p"; }

# A stale pidfile can outlive its animation (claude died, tty vanished, cap hit),
# and the OS reuses pids. Never signal a pid without confirming it is one of our
# own animation processes.
is_pulse() {
  case "$(ps -p "$1" -o command=)" in
    *iterm-tab-status*__pulse*) return 0 ;;
  esac
  return 1
}

# Kill one specific animation. Taking the pid as an argument matters: a caller
# that captured it before claiming the tab must not kill whatever newer pulse
# has started since. The pidfile is only cleared while it still names that pid.
kill_pulse() {
  local p="$1"
  [ -n "$p" ] || return 0
  alive "$p" && is_pulse "$p" && kill "$p"
  [ "$(pulse_pid)" = "$p" ] && rm -f "$PIDFILE"
  return 0
}

stop_pulse() { kill_pulse "$(pulse_pid)"; }

case "${1:-reset}" in

  # Internal: the breathing-orange animation. Dark orange <-> bright orange.
  __pulse)
    watch_pid="${2:-0}"
    levels=(0 12 25 40 55 70 85 100 85 70 55 40 25 12)
    n=${#levels[@]}
    i=0
    while [ "$i" -lt "$MAX_PULSE_ITERS" ]; do
      L=${levels[$((i % n))]}
      tabcolor $((120 + 135 * L / 100)) $((55 + 95 * L / 100)) $((20 * L / 100))
      sleep "$PULSE_DELAY"
      i=$((i + 1))
      # Ownership is a builtin-only check (no fork), so it runs every tick: two
      # hooks racing to start an animation resolve within one frame.
      [ "$(pulse_pid)" = "$$" ] || break
      # The checks that cost a fork run every ~2s instead.
      if [ $((i % 14)) -eq 0 ]; then
        [ -w "$DEV" ] || break
        if [ "$watch_pid" != 0 ] && ! alive "$watch_pid"; then break; fi
      fi
    done
    # Only clear the pidfile if it is still ours, so we never delete the record
    # of the animation that replaced us.
    [ "$(pulse_pid)" = "$$" ] && rm -f "$PIDFILE"
    exit 0
    ;;

  busy)
    claim
    p=$(pulse_pid)
    if [ -n "$p" ] && alive "$p" && is_pulse "$p"; then
      set_state busy       # already animating - nothing to do
      exit 0
    fi
    set_state busy
    attention no
    badge ''
    if [ "$PULSE" = 1 ]; then
      claude_pid=$(ps -t "$tty_name" -o pid=,comm= | awk '$2 ~ /claude/ {print $1; exit}')
      CLAUDE_TAB_TTY="$tty_name" "$0" __pulse "${claude_pid:-0}" > /dev/null &
      printf '%s' "$!" > "$PIDFILE"
    else
      tabcolor 255 140 0
    fi
    ;;

  waiting)
    # Don't stomp on the green "done" tab when an idle notification fires.
    [ "$(get_state)" = "done" ] && exit 0
    claim
    stop_pulse
    set_state waiting
    tabcolor 225 60 60
    attention yes
    badge 'input?'
    ;;

  done)
    # Note what is running before claiming, so the teardown below can only ever
    # target the animation that was live when this hook started.
    was_pulsing=$(pulse_pid)
    claim
    # Stop runs async, so a busy/reset can claim between the lines below. Both
    # of the next steps are destructive - killing the pulse and forcing the
    # state to "done" would strand an active session with no animation and
    # suppress its red "needs input" tab - so both are gated on still owning
    # the claim, not just the repaints further down.
    current || exit 0
    kill_pulse "$was_pulsing"
    current || exit 0
    set_state "done"
    i=0
    while [ "$i" -lt "$BLINKS" ] && current; do
      tabcolor 40 200 120; sleep "$BLINK_DELAY"
      current || break
      tabreset;            sleep "$BLINK_DELAY"
      i=$((i + 1))
    done
    if current; then
      tabcolor 40 200 120
      attention once
      badge 'done'
    fi
    ;;

  *)
    claim
    stop_pulse
    set_state none
    tabreset
    attention no
    badge ''
    ;;
esac
exit 0
