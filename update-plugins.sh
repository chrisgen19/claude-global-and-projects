#!/usr/bin/env bash
# Refresh every plugin marketplace, then update every user-scope plugin, in each
# Claude Code profile. Plugin versions live only in the profile, never in this
# repo, so this changes nothing tracked here and needs no commit afterwards.
#
# install.sh deploys it as ~/.local/bin/claude-update-plugins.
#
# Usage: claude-update-plugins                # claude-dev, claude-personal, claude-work, claude-yosh
#        claude-update-plugins claude-work    # only these profiles (dir names under $HOME)
#
# Project-scope installs are left alone: update those with /plugin inside the project.
# A plugin whose marketplace declares an install command asks before running it;
# answer at the prompt, or run `claude plugin update` by hand for that one.
# Restart running Claude sessions afterwards to load the new versions.
#
# Requires claude, jq and bash 3.2+ (macOS stock bash is fine).
set -uo pipefail

# A profile named on the command line must exist: asking to update it and
# silently doing nothing would be worse than an error. The default list is the
# full set of accounts, and not every machine has all of them, so an absent one
# there is skipped without failing the run.
if [[ $# -gt 0 ]]; then
  profiles="$*"
  named=1
else
  profiles="claude-dev claude-personal claude-work claude-yosh"
  named=0
fi

failed=""
for profile in $profiles; do
  dir="$HOME/.$profile"
  if [[ ! -d $dir ]]; then
    echo "skip $profile: $dir does not exist" >&2
    if [[ $named = 1 ]]; then failed+=" $profile"; fi
    continue
  fi
  echo "===== $profile"

  # No name updates every configured marketplace.
  if ! CLAUDE_CONFIG_DIR=$dir claude plugin marketplace update; then
    failed+=" $profile:marketplaces"
    continue
  fi

  # name@skills-dir entries are plugins living in the profile's skills/ folder,
  # not marketplace installs, so `plugin update` cannot update them.
  if ! ids=$(CLAUDE_CONFIG_DIR=$dir claude plugin list --json \
    | jq -r '[.[] | select(.scope == "user" and (.id | endswith("@skills-dir") | not)) | .id] | unique | .[]'); then
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
