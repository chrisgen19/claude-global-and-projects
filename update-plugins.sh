#!/usr/bin/env bash
# Refresh every plugin marketplace, then update every user-scope plugin, in each
# Claude Code profile. Plugin versions live only in the profile, never in this
# repo, so this changes nothing tracked here and needs no commit afterwards.
#
# install.sh deploys it as ~/.local/bin/claude-update-plugins.
#
# Usage: claude-update-plugins                # claude-dev, claude-personal, claude-work
#        claude-update-plugins claude-work    # only these profiles (dir names under $HOME)
#
# Project-scope installs are left alone: update those with /plugin inside the project.
# A plugin whose marketplace declares an install command asks before running it;
# answer at the prompt, or run `claude plugin update` by hand for that one.
# Restart running Claude sessions afterwards to load the new versions.
#
# Requires claude, jq and bash 3.2+ (macOS stock bash is fine).
set -uo pipefail

if [[ $# -gt 0 ]]; then
  profiles="$*"
else
  profiles="claude-dev claude-personal claude-work"
fi

failed=""
for profile in $profiles; do
  dir="$HOME/.$profile"
  if [[ ! -d $dir ]]; then
    echo "skip $profile: $dir does not exist" >&2
    failed+=" $profile"
    continue
  fi
  echo "===== $profile"

  # No name updates every configured marketplace.
  if ! CLAUDE_CONFIG_DIR=$dir claude plugin marketplace update; then
    failed+=" $profile:marketplaces"
    continue
  fi

  if ! ids=$(CLAUDE_CONFIG_DIR=$dir claude plugin list --json \
    | jq -r '[.[] | select(.scope == "user") | .id] | unique | .[]'); then
    failed+=" $profile:list"
    continue
  fi
  for id in $ids; do
    if ! CLAUDE_CONFIG_DIR=$dir claude plugin update --scope user "$id"; then
      failed+=" $profile:$id"
    fi
  done
done

if [[ -n $failed ]]; then
  echo "failed:$failed" >&2
  exit 1
fi
echo "done. Restart running Claude sessions to load the updates."
