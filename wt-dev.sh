#!/usr/bin/env bash
# wt-dev: run a dev server for the worktrees of the current repo inside one tmux session.
# One window per worktree, named "<branch> :<port>". The port is derived from the branch
# name, so the same branch always gets the same URL.
#
# Usage: wt-dev              # every worktree
#        wt-dev main feat/x  # only these branches
#
# Dev command, first match wins ({port} is replaced with the worktree's port):
#   1. WT_DEV_CMD env var      WT_DEV_CMD='pnpm dev --port {port}' wt-dev
#   2. per-repo git config     git config wt.devcmd 'pnpm --filter web dev --port {port}'
#   3. default                 PORT={port} pnpm dev
#
# Requires tmux and bash 3.2+ (macOS stock bash is fine).
set -euo pipefail

cmd=${WT_DEV_CMD:-$(git config --get wt.devcmd || echo 'PORT={port} pnpm dev')}
main=$(git worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')
session=$(basename "$main" | tr '.:' '__')

if tmux has-session -t "=$session" 2>/dev/null; then
  exec tmux attach -t "=$session"
fi

while IFS=$'\t' read -r path branch; do
  if [[ $# -gt 0 && " $* " != *" $branch "* ]]; then continue; fi
  if [[ ! -d $path ]]; then
    echo "skip $branch: $path no longer exists (git worktree prune cleans it up)" >&2
    continue
  fi
  port=$(( 3100 + $(printf '%s' "$branch" | cksum | cut -d' ' -f1) % 900 ))
  if tmux has-session -t "=$session" 2>/dev/null; then
    win=$(tmux new-window -d -P -F '#{window_id}' -t "$session:" -n "$branch :$port" -c "$path")
  else
    win=$(tmux new-session -d -P -F '#{window_id}' -s "$session" -n "$branch :$port" -c "$path")
  fi
  tmux send-keys -t "$win" "${cmd//\{port\}/$port}" Enter
  printf '%-40s http://localhost:%s\n' "$branch" "$port"
done < <(git worktree list --porcelain | awk '
  /^worktree / { path = substr($0, 10) }
  /^branch /   { sub("refs/heads/", "", $2); print path "\t" $2 }
  /^detached/  { n = split(path, p, "/"); print path "\t" p[n] }
')

if ! tmux has-session -t "=$session" 2>/dev/null; then
  echo "no matching worktrees, nothing started" >&2
  exit 1
fi
exec tmux attach -t "=$session"
