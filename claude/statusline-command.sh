#!/usr/bin/env bash
# Router: delegates to the correct statusline based on CLAUDE_CONFIG_DIR
#
# Only reached when ~/.claude/settings.json is the active config, i.e. when
# CLAUDE_CONFIG_DIR is unset (bare `claude`, VS Code, or the desktop app).
# The claude-* shell functions set CLAUDE_CONFIG_DIR, so those sessions read
# their own account settings.json and never come through here.

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
account="${config_dir##*/.claude-}"

# An unset/plain ~/.claude leaves `account` as the whole path, which matches
# nothing below — fall through to the unlabelled default rather than
# mislabelling the session as another account.
case "$account" in
  personal|work|dev)
    script="$HOME/.claude-$account/statusline.sh"
    [ -f "$script" ] && exec bash "$script"
    ;;
esac

# No account dir resolved: render with a neutral label so the line never
# claims to be an account it is not.
exec env ACCOUNT_LABEL_OVERRIDE="CLAUDE" bash "$HOME/.claude-personal/statusline.sh"
