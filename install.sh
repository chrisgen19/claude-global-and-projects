#!/usr/bin/env bash
#
# Install this repo's configuration into the live Claude Code profiles, check
# the live profiles against it, or pull live changes back into the repo.
#
#   ./install.sh            deploy repo -> ~/.claude*, ~/.local/bin
#   ./install.sh --check    report where the live profiles differ (exit 1 on drift)
#   ./install.sh --pull     copy live settings back into the repo (autoMode stripped)
#   ./install.sh --help
#
# Direction matters. Deploying a stale repo silently reverts real live state -
# plugins enabled since the last commit, an effort level raised in /config, a
# pinned model. Run --check first: if a difference is something you changed
# live, --pull it into the repo rather than deploying over it. Deploys back up
# the previous settings.json either way.
#
# The README's copy commands are the manual equivalent. They are easy to run
# partially - which is how the default ~/.claude profile ended up untracked,
# with an empty CLAUDE.md and one of eight skills - so prefer this.
#
# Requires bash 3.2 (macOS stock), jq and diff. macOS/Linux only: the Windows
# profile in windows/ is copied by hand, see the README.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$REPO_ROOT" || exit 1

# repo dir : live dir : status line filename : skill set
PROFILES="claude:$HOME/.claude:statusline-command.sh:all
claude-dev:$HOME/.claude-dev:statusline.sh:all
claude-personal:$HOME/.claude-personal:statusline.sh:all
claude-work:$HOME/.claude-work:statusline.sh:no-nextjs"

TAB_SCRIPT_SRC="iterm-tab-status.sh"
TAB_SCRIPT_DST="$HOME/.local/bin/claude-iterm-tab-status.sh"

MODE="install"
case "${1:-}" in
  --check) MODE="check" ;;
  --pull) MODE="pull" ;;
  --help | -h) sed -n '2,22p' "$0" | sed 's/^#//;s/^ //'; exit 0 ;;
  "") ;;
  *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

drift=0
STAMP=$(date +%Y%m%d-%H%M%S)
note()   { printf '  %s\n' "$1"; }
differ() { drift=$((drift + 1)); printf '  DRIFT  %s\n' "$1"; }
backup() { [ -f "$1" ] && cp "$1" "$1.bak-$STAMP"; return 0; }

# Compare tracked vs live settings, ignoring the deliberately stripped autoMode
# block. Keys are sorted so formatting differences never read as drift.
settings_differ() { # repo_file live_file
  [ -f "$2" ] || return 0
  ! diff -q <(jq -S 'del(.autoMode)' "$2") <(jq -S . "$1") > /dev/null
}

skills_for() { # skill set -> prints source skill dirs
  for s in .claude/skills/*/; do
    [ "$1" = "no-nextjs" ] && [ "$(basename "$s")" = "nextjs-conventions" ] && continue
    printf '%s\n' "$s"
  done
}

echo "Claude Code config — ${MODE}"
echo

while IFS=: read -r repo_dir live_dir sl_name skillset; do
  [ -n "$repo_dir" ] || continue
  echo "$repo_dir  ->  ${live_dir/#$HOME/\~}"

  if [ "$MODE" != "install" ] && [ ! -d "$live_dir" ]; then
    differ "profile directory missing"
    echo; continue
  fi

  # --- settings.json: the only artefact that flows in both directions ---
  case "$MODE" in
    install)
      mkdir -p "$live_dir"
      backup "$live_dir/settings.json"
      cp "$repo_dir/settings.json" "$live_dir/settings.json"
      note "settings.json  (previous saved as settings.json.bak-$STAMP)"
      ;;
    pull)
      if [ -f "$live_dir/settings.json" ]; then
        jq 'del(.autoMode)' "$live_dir/settings.json" > "$repo_dir/settings.json"
        note "settings.json  <- live (autoMode stripped)"
      else
        note "settings.json  live file missing, skipped"
      fi
      ;;
    check)
      if settings_differ "$repo_dir/settings.json" "$live_dir/settings.json"; then
        differ "settings.json"
        diff <(jq -S . "$repo_dir/settings.json") <(jq -S 'del(.autoMode)' "$live_dir/settings.json") \
          | grep -E '^[<>]' | head -6 | sed 's/^/           /'
      else
        note "settings.json  ok"
      fi
      ;;
  esac

  # Everything below flows repo -> live only, so --pull leaves it alone.
  if [ "$MODE" != "pull" ]; then

    # --- status line ---
    if [ "$MODE" = "install" ]; then
      cp "$repo_dir/$sl_name" "$live_dir/$sl_name"
      chmod +x "$live_dir/$sl_name"
      note "$sl_name"
    elif ! diff -q "$repo_dir/$sl_name" "$live_dir/$sl_name" > /dev/null; then
      differ "$sl_name"
    else
      note "$sl_name  ok"
    fi

    # --- CLAUDE.md ---
    if [ "$MODE" = "install" ]; then
      cp CLAUDE.md "$live_dir/CLAUDE.md"
      note "CLAUDE.md"
    elif ! diff -q CLAUDE.md "$live_dir/CLAUDE.md" > /dev/null; then
      differ "CLAUDE.md"
    else
      note "CLAUDE.md  ok"
    fi

    # --- skills ---
    missing=""
    for s in $(skills_for "$skillset"); do
      name=$(basename "$s")
      if [ "$MODE" = "install" ]; then
        mkdir -p "$live_dir/skills"
        cp -R "$s" "$live_dir/skills/"
      elif ! diff -rq "$s" "$live_dir/skills/$name" > /dev/null; then
        missing="$missing $name"
      fi
    done
    if [ "$MODE" = "install" ]; then
      note "skills ($skillset)"
    elif [ -n "$missing" ]; then
      differ "skills:$missing"
    else
      note "skills  ok"
    fi

  fi

  echo
done <<< "$PROFILES"

# --- shared tab-status script: repo -> live only ---
if [ "$MODE" != "pull" ]; then
  echo "shared"
  if [ "$MODE" = "install" ]; then
    mkdir -p "$(dirname "$TAB_SCRIPT_DST")"
    cp "$TAB_SCRIPT_SRC" "$TAB_SCRIPT_DST"
    chmod +x "$TAB_SCRIPT_DST"
    note "${TAB_SCRIPT_DST/#$HOME/\~}"
  elif [ ! -f "$TAB_SCRIPT_DST" ]; then
    differ "${TAB_SCRIPT_DST/#$HOME/\~} missing"
  elif ! diff -q "$TAB_SCRIPT_SRC" "$TAB_SCRIPT_DST" > /dev/null; then
    differ "${TAB_SCRIPT_DST/#$HOME/\~}"
  else
    note "${TAB_SCRIPT_DST/#$HOME/\~}  ok"
  fi
  echo
fi

if [ "$MODE" = "check" ]; then
  if [ "$drift" -gt 0 ]; then
    echo "$drift item(s) differ. Deploy with ./install.sh, or --pull if live is the newer side."
    exit 1
  fi
  echo "live profiles match the repo."
fi
exit 0
