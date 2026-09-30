#!/usr/bin/env bash
# PR review bot helpers for /review-loop. Needs an authenticated `gh`.
#
#   pr-bots.sh detect  <owner/repo> <pr> <head-sha> <default-branch>
#       Prints "codex reviewed <iso>|unavailable|trigger" and "claude action <file>|app|none".
#   pr-bots.sh wait    <owner/repo> <pr> <head-sha> <codex-comment-id|-> <claude-comment-id|-> [timeout-min]
#       Prints "since <iso>", then "<bot> <state>" each time a bot's state changes, polling
#       every 30s. The last line per bot is its final state:
#       done, failed, unavailable, no-ack, timeout or skip.
#   pr-bots.sh collect <owner/repo> <pr> <head-sha> <since-iso>
#       Prints the findings the bots posted on <head-sha> since <since-iso>. Entries are
#       "review-comment <id>" (reply in its thread) or "issue-comment <id>" (no thread).
#
# Every command exits non-zero when a GitHub API call fails, instead of printing bad data.
set -uo pipefail

CODEX='chatgpt-codex-connector[bot]'
CLAUDE='claude[bot]'
NO_ENV='create an environment'
POLL_SECONDS=30
ACK_SECONDS=300

count() { awk '{ s += $1 } END { print s + 0 }'; }

# gh prints a failed call's error body to stdout, even with --jq, so never pass it on.
api() {
  local out
  out=$(gh api "$@") || return 1
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}

cmd_detect() {
  local repo=$1 pr=$2 sha=$3 branch=$4 reviewed latest paths path content wf="" seen
  reviewed=$(api "repos/$repo/pulls/$pr/reviews?per_page=100" --paginate \
    --jq ".[] | select(.user.login == \"$CODEX\" and .commit_id == \"$sha\") | (.submitted_at | fromdate - 1 | todate)" | tail -n 1) || return 1
  # Without a Codex cloud environment, the bot only answers with a setup link.
  latest=$(api "repos/$repo/issues/$pr/comments?per_page=100" --paginate \
    --jq ".[] | select(.user.login == \"$CODEX\") | \"\(.updated_at) \(.body | contains(\"$NO_ENV\"))\"" | sort | tail -n 1) || return 1
  if [ -n "$reviewed" ]; then echo "codex reviewed $reviewed"
  elif [ "${latest##* }" = true ]; then echo "codex unavailable"
  else echo "codex trigger"; fi

  # A missing workflows dir is an expected 404.
  paths=$(api "repos/$repo/contents/.github/workflows?ref=$branch" --jq '.[].path' 2>/dev/null) || paths=""
  for path in $paths; do
    content=$(api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$path?ref=$branch") || return 1
    # Only a workflow that runs on comments answers @claude.
    if grep -q 'anthropics/claude-code-action' <<<"$content" && grep -q 'issue_comment' <<<"$content"; then
      wf=$path
      break
    fi
  done
  if [ -n "$wf" ]; then
    echo "claude action $wf"
    return
  fi
  seen=$( {
    api "repos/$repo/issues/comments?sort=created&direction=desc&per_page=100" --jq "[.[] | select(.user.login == \"$CLAUDE\")] | length" || true
    api "repos/$repo/pulls/comments?sort=created&direction=desc&per_page=100" --jq "[.[] | select(.user.login == \"$CLAUDE\")] | length" || true
  } | count)
  [ "$seen" -gt 0 ] && echo "claude app" || echo "claude none"
}

# Status functions print pending, acked, done, failed, unavailable, or error on a failed call.
codex_status() {
  local n body row reactions
  n=$(api "repos/$repo/pulls/$pr/reviews?per_page=100" --paginate \
    --jq "[.[] | select(.user.login == \"$CODEX\" and .commit_id == \"$sha\" and .submitted_at > \"$since\")] | length" | count) || { echo error; return; }
  [ "$n" -gt 0 ] && { echo "done"; return; }

  body=$(api "repos/$repo/issues/$pr/comments?per_page=100" --paginate \
    --jq ".[] | select(.user.login == \"$CODEX\" and .updated_at > \"$since\") | .body") || { echo error; return; }
  grep -q "$NO_ENV" <<<"$body" && { echo unavailable; return; }
  # Codex keeps one summary comment per PR and updates its status row in place.
  row=$(grep -m 1 'Code Review\*\*' <<<"$body")
  if [ -n "$row" ]; then
    if grep -q 'Completed' <<<"$row" && grep -q "${sha:0:7}" <<<"$row"; then echo "done"
    elif grep -qiE 'fail|error|cancel|timed out' <<<"$row"; then echo failed
    else echo acked; fi
    return
  fi
  reactions=$(api "repos/$repo/issues/comments/$codex_id/reactions" \
    --jq ".[] | select(.user.login == \"$CODEX\") | .content") || { echo error; return; }
  case "$reactions" in
    *+1*) echo "done" ;;
    ?*) echo acked ;;
    *) echo pending ;;
  esac
}

claude_status() {
  local check runs reactions
  # Managed Code Review reports through a check run on the head commit. Its conclusion is
  # neutral even when the review itself failed, so the title decides that case.
  check=$(api "repos/$repo/commits/$sha/check-runs?check_name=Claude%20Code%20Review" \
    --jq "first(.check_runs[] | select((.started_at // \"9999\") > \"$since\") | \"\(.status)|\(.conclusion // \"\")|\(.output.title // \"\")\")") || { echo error; return; }
  if [ -n "$check" ]; then
    case "$check" in
      completed\|success\|*|completed\|neutral\|*)
        case "$check" in *[Ff]ail*|*"timed out"*|*[Ss]kip*) echo failed ;; *) echo "done" ;; esac ;;
      completed*) echo failed ;;
      *) echo acked ;;
    esac
    return
  fi
  # The GitHub Action runs as an issue_comment workflow; runs for other comments are skipped.
  # Known gap (PR #25): these runs are not tied to this PR, so another @claude run in the
  # same repo can end the wait early. Fix once a repo has the Action to test against.
  runs=$(api -X GET "repos/$repo/actions/runs" -f event=issue_comment -f "created=>=$since" -f per_page=100 \
    --jq '.workflow_runs[] | select((.name + " " + .path) | test("claude"; "i")) | select(.conclusion != "skipped") | "\(.status)|\(.conclusion)"') || { echo error; return; }
  if [ -n "$runs" ]; then
    if grep -q '|success' <<<"$runs"; then echo "done"
    elif grep -qvE '^completed' <<<"$runs"; then echo acked
    else echo failed; fi
    return
  fi
  reactions=$(api "repos/$repo/issues/comments/$claude_id/reactions" \
    --jq ".[] | select(.user.login == \"$CLAUDE\") | .content") || { echo error; return; }
  [ -n "$reactions" ] && echo acked || echo pending
}

# Moves one bot's state forward.
next_state() {
  local bot=$1 state=$2 elapsed=$3 now
  case "$state" in done|failed|unavailable|no-ack|timeout|skip) echo "$state"; return ;; esac
  now=$("${bot}_status")
  # A failed API call or a vanished reaction must not move a bot backwards.
  [ "$now" = error ] && now=$state
  [ "$now" = pending ] && [ "$state" = acked ] && now=acked
  case "$now" in done|failed|unavailable) echo "$now"; return ;; esac
  if [ "$elapsed" -ge "$timeout_s" ]; then echo timeout
  elif [ "$now" = pending ] && [ "$elapsed" -ge "$ACK_SECONDS" ]; then echo no-ack
  else echo "$now"; fi
}

cmd_wait() {
  repo=$1 pr=$2 sha=$3 codex_id=$4 claude_id=$5
  timeout_s=$(( ${6:-40} * 60 ))
  local first=$codex_id start elapsed codex_state=pending claude_state=pending prev_codex="" prev_claude=""
  [ "$first" = - ] && first=$claude_id
  if [ "$first" = - ]; then
    echo "codex skip"
    echo "claude skip"
    return 0
  fi
  # Use GitHub's clock, not ours: WSL clocks drift.
  since=$(api "repos/$repo/issues/comments/$first" --jq .created_at) || exit 1
  echo "since $since"
  [ "$codex_id" = - ] && codex_state=skip
  [ "$claude_id" = - ] && claude_state=skip
  start=$(date +%s)
  while :; do
    elapsed=$(( $(date +%s) - start ))
    codex_state=$(next_state codex "$codex_state" "$elapsed")
    claude_state=$(next_state claude "$claude_state" "$elapsed")
    # Codex can post its review a few seconds after flipping its status to Completed.
    case "$codex_state" in done) [ "$prev_codex" != "done" ] && sleep 10 ;; esac
    [ "$codex_state" != "$prev_codex" ] && echo "codex $codex_state"
    [ "$claude_state" != "$prev_claude" ] && echo "claude $claude_state"
    prev_codex=$codex_state prev_claude=$claude_state
    case "$codex_state $claude_state" in
      *pending*|*acked*) sleep "$POLL_SECONDS" ;;
      *) break ;;
    esac
  done
}

cmd_collect() {
  local repo=$1 pr=$2 sha=$3 since=$4 ids
  ids=$(api "repos/$repo/pulls/$pr/reviews?per_page=100" --paginate \
    --jq ".[] | select(.user.login == \"$CODEX\" and .commit_id == \"$sha\" and .submitted_at >= \"$since\") | .id" | paste -sd, -) || exit 1
  echo "# Codex findings (reviews: ${ids:-none})"
  if [ -n "$ids" ]; then
    api "repos/$repo/pulls/$pr/comments?per_page=100" --paginate \
      --jq ".[] | select(.user.login == \"$CODEX\") | select(.pull_request_review_id as \$r | [$ids] | any(. == \$r)) | \"\n## review-comment \(.id) \(.path):\(.line // .original_line)\n\(.body)\"" || exit 1
  fi

  echo
  echo "# Claude inline findings"
  api "repos/$repo/pulls/$pr/comments?per_page=100" --paginate \
    --jq ".[] | select(.user.login == \"$CLAUDE\" and .created_at >= \"$since\") | \"\n## review-comment \(.id) \(.path):\(.line // .original_line)\n\(.body)\"" || exit 1
  echo
  echo "# Claude Code Review check run"
  api "repos/$repo/commits/$sha/check-runs?check_name=Claude%20Code%20Review" \
    --jq ".check_runs[] | select((.started_at // \"\") >= \"$since\") | \"\(.output.title // \"\")\n\(.output.text // \"\")\"" || exit 1
  echo
  echo "# Claude PR comments (no thread: answer these in one PR comment)"
  api "repos/$repo/issues/$pr/comments?per_page=100" --paginate \
    --jq ".[] | select(.user.login == \"$CLAUDE\" and .updated_at >= \"$since\") | \"\n## issue-comment \(.id)\n\(.body)\"" || exit 1
}

case "${1:-}" in
  detect) shift; cmd_detect "$@" ;;
  wait) shift; cmd_wait "$@" ;;
  collect) shift; cmd_collect "$@" ;;
  *) echo "usage: pr-bots.sh detect|wait|collect ..." >&2; exit 2 ;;
esac
