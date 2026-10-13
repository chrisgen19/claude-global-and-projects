#!/usr/bin/env bash
# Windows Terminal (WSL) tab status indicator for Claude Code.
# Port of iterm-tab-status.sh - same hooks, same states.
#
#   busy     -> tab turns orange, spinner on the tab + taskbar while Claude works
#   waiting  -> tab goes red, taskbar goes red (Claude needs input / permission)
#   done     -> tab blinks green x4, then stays green with a full progress ring
#   reset    -> clears tab colour and progress indicator
#
# An interrupted turn (Esc / Ctrl+C) runs no hook at all, so busy also starts a
# watcher that resets the tab when the interrupt lands in the transcript.
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
# process tree until we hit the claude CLI, which does own the WT pty. Prints
# the tty name and that process's pid.
find_tty() {
  local p=$PPID t a i=0
  while [ "$i" -lt 8 ] && [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
    read -r t a <<< "$(ps -o tty=,ppid= -p "$p")"
    case "${t:-?}" in
      '?' | '??') ;;
      *) printf '%s %s' "$t" "$p"; return 0 ;;
    esac
    p="$a"
    i=$((i + 1))
  done
  return 1
}
found=$(find_tty) || exit 0
read -r tty_name tty_pid <<< "$found"
DEV="/dev/$tty_name"
[ -w "$DEV" ] || exit 0

# Linux tty names contain a slash (pts/6), so flatten them for the state files.
key="${tty_name//\//-}"
RUN="${TMPDIR:-/tmp}"
STATEFILE="$RUN/claude-tab-$key.state"
GENFILE="$RUN/claude-tab-$key.gen"
WATCHFILE="$RUN/claude-tab-$key.watch"
WATCHLOCK="$RUN/claude-tab-$key.watch.lock"

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

# Claude Code runs no hook when a turn is interrupted: Stop is documented not to
# fire on a user interrupt, so the tab would stay orange (or red, from a
# permission prompt) until a later turn finishes. The interrupt is still written
# to the session transcript as a user message, so busy starts one watcher per
# turn that tails the transcript and resets the tab when that message shows up.
# done/reset kill it, and tail --pid ends it if claude itself exits.
INTERRUPT_MARK='"text":"[Request interrupted by user'   # also "... for tool use]"
SETTLE_DELAY=0.3     # lets async busy hooks fired just before the interrupt land first

# Prints the live watcher's pid. The args check stops a recycled pid from being
# mistaken for (and killed as) the watcher.
watch_pid() {
  local w=''
  [ -f "$WATCHFILE" ] && read -r w < "$WATCHFILE"
  [ -n "$w" ] || return 1
  case "$(ps -o args= -p "$w")" in
    *tab-status*) printf '%s' "$w" ;;
    *) return 1 ;;
  esac
}

# Kill one specific watcher. It leads its own process group, so this takes its
# tail and grep too. Taking the pid as an argument matters: done captures it
# before claiming, so it can never stop a watcher started since. The watch file
# is only cleared while it still names that pid.
stop_watch() {
  local w=$1 f=''
  [ -n "$w" ] && kill -- "-$w" 2>/dev/null
  [ -f "$WATCHFILE" ] && read -r f < "$WATCHFILE"
  [ "$f" = "$w" ] && rm -f "$WATCHFILE"
  return 0
}

# Several busy hooks can fire at once (parallel tool calls each send
# PostToolUse). mkdir is atomic, so only one of them starts a watcher and the
# rest skip it, instead of leaving an untracked one behind. A lock left by a
# hook that died mid-start is cleared once it is a minute old.
ensure_watch() {
  watch_pid > /dev/null && return 0
  [ -n "$(find "$WATCHLOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rmdir "$WATCHLOCK" 2>/dev/null
  mkdir "$WATCHLOCK" 2>/dev/null || return 0
  watch_pid > /dev/null || start_watch
  rmdir "$WATCHLOCK"
}

# Reads the hook's JSON input on stdin for the transcript path. No jq or no
# transcript_path means no watcher: the old behaviour. Codex sends one too, but
# its transcript never carries Claude Code's marker, so there the watcher just
# idles until done/reset or Codex exits.
start_watch() {
  local transcript
  transcript=$(jq -r '.transcript_path // empty' 2>/dev/null) || return 0
  [ -n "$transcript" ] || return 0
  set -m   # job control gives the background watcher its own process group
  (
    exec 3< <(tail -n 0 -F --pid="$tty_pid" "$transcript" 2>/dev/null)
    tail_pid=$!
    grep -m 1 -qF "$INTERRUPT_MARK" <&3 || exit 0
    kill "$tail_pid" 2>/dev/null
    sleep "$SETTLE_DELAY"
    case "$(get_state)" in
      busy | waiting) claim; set_state none; tabreset; progress 0 ;;
    esac
    [ "$(watch_pid)" = "$BASHPID" ] && rm -f "$WATCHFILE"
  ) < /dev/null > /dev/null 2>&1 &
  printf '%s' "$!" > "$WATCHFILE"
  set +m
}

case "${1:-reset}" in

  busy)
    claim
    # Before the busy guard, so a missing watcher (say, a state file left
    # behind by an older version of this script) is started on the next hook.
    ensure_watch
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
    # Note the watcher before claiming, so the teardown below can only ever
    # stop the one that was live when this hook started.
    was_watching=$(watch_pid)
    claim
    # A busy/reset may have claimed in between - don't stop the watcher a newer
    # transition relies on, or force the state back to "done" over it (the next
    # red "needs input" tab would be suppressed).
    current || exit 0
    stop_watch "$was_watching"
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
    stop_watch "$(watch_pid)"
    set_state none
    tabreset
    progress 0
    ;;
esac
exit 0
