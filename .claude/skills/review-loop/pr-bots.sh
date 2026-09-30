#!/usr/bin/env bash
# PR review bot helpers for /review-loop. Needs an authenticated `gh`.
#
#   pr-bots.sh detect  <owner/repo> <pr> <head-sha> <default-branch>
#       Which bots can answer on this repo, and whether Codex already reviewed the head commit.
#   pr-bots.sh wait    <owner/repo> <pr> <head-sha> <codex-comment-id|-> <claude-comment-id|-> [timeout-min]
#       Polls every 30s until each triggered bot finishes, then prints
#       "<bot> done|failed|no-ack|timeout|skip" per bot and "since <iso>".
#   pr-bots.sh collect <owner/repo> <pr> <head-sha> <since-iso>
#       Prints every finding the bots posted since <since-iso>, with comment IDs for replies.
set -uo pipefail

CODEX='chatgpt-codex-connector[bot]'
CLAUDE='claude[bot]'
POLL_SECONDS=30
ACK_SECONDS=300

count() { awk '{ s += $1 } END { print s + 0 }'; }

cmd_detect() {
  local repo=$1 pr=$2 sha=$3 branch=$4 seen head_review wf="" paths path content
  seen=$(gh api "repos/$repo/issues/comments?sort=created&direction=desc&per_page=100" \
    --jq "[.[] | select(.user.login == \"$CODEX\")] | length")
  [ "${seen:-0}" -gt 0 ] && echo "codex seen" || echo "codex unknown"

  # Codex auto-reviews on PR open, so the head commit may already be reviewed.
  head_review=$(gh api "repos/$repo/pulls/$pr/reviews" --paginate \
    --jq ".[] | select(.user.login == \"$CODEX\" and .commit_id == \"$sha\") | (.submitted_at | fromdate - 1 | todate)" | tail -n 1)
  echo "codex-head-review ${head_review:-none}"

  # A missing workflows dir is an expected 404, and gh prints its error body to stdout.
  paths=$(gh api "repos/$repo/contents/.github/workflows?ref=$branch" --jq '.[].path' 2>/dev/null) || paths=""
  for path in $paths; do
    content=$(gh api -H 'Accept: application/vnd.github.raw' "repos/$repo/contents/$path?ref=$branch")
    if grep -q 'anthropics/claude-code-action' <<<"$content"; then
      wf=$path
      break
    fi
  done
  if [ -n "$wf" ]; then
    echo "claude action $wf"
    return
  fi
  seen=$( {
    gh api "repos/$repo/issues/comments?sort=created&direction=desc&per_page=100" --jq "[.[] | select(.user.login == \"$CLAUDE\")] | length"
    gh api "repos/$repo/pulls/comments?sort=created&direction=desc&per_page=100" --jq "[.[] | select(.user.login == \"$CLAUDE\")] | length"
  } | count)
  [ "$seen" -gt 0 ] && echo "claude app" || echo "claude none"
}

codex_status() {
  local n body row
  n=$(gh api "repos/$repo/pulls/$pr/reviews" --paginate \
    --jq "[.[] | select(.user.login == \"$CODEX\" and .submitted_at > \"$since\")] | length" | count)
  [ "$n" -gt 0 ] && { echo done; return; }

  # Codex keeps one summary comment per PR and updates its status row in place.
  body=$(gh api "repos/$repo/issues/$pr/comments" --paginate \
    --jq ".[] | select(.user.login == \"$CODEX\" and .updated_at > \"$since\" and (.body | contains(\"codex-pull-request-review-summary\"))) | .body")
  if [ -n "$body" ]; then
    row=$(grep -m 1 'Code Review\*\*' <<<"$body")
    if grep -q 'Completed' <<<"$row" && grep -q "${sha:0:7}" <<<"$row"; then echo done
    elif grep -qiE 'fail|error|cancel|timed out' <<<"$row"; then echo failed
    else echo acked; fi
    return
  fi
  case "$(gh api "repos/$repo/issues/comments/$codex_id/reactions" --jq ".[] | select(.user.login == \"$CODEX\") | .content")" in
    *+1*) echo done ;;
    ?*) echo acked ;;
    *) echo pending ;;
  esac
}

claude_status() {
  local check runs
  # Managed Code Review reports through a check run on the head commit.
  check=$(gh api "repos/$repo/commits/$sha/check-runs?check_name=Claude%20Code%20Review" \
    --jq ".check_runs[] | select((.started_at // \"9999\") > \"$since\") | \"\(.status)|\(.output.title // \"\")\"" | head -n 1)
  if [ -n "$check" ]; then
    case "$check" in
      completed*[Ff]ail*|completed*"timed out"*) echo failed ;;
      completed*) echo done ;;
      *) echo acked ;;
    esac
    return
  fi
  # The GitHub Action runs as an issue_comment workflow; runs for other comments are skipped.
  runs=$(gh api -X GET "repos/$repo/actions/runs" -f event=issue_comment -f "created=>=$since" -f per_page=30 \
    --jq '.workflow_runs[] | select((.name + " " + .path) | test("claude"; "i")) | select(.conclusion != "skipped") | "\(.status)|\(.conclusion)"')
  if [ -n "$runs" ]; then
    if grep -q '|success' <<<"$runs"; then echo done
    elif grep -qvE '^completed' <<<"$runs"; then echo acked
    else echo failed; fi
    return
  fi
  [ -n "$(gh api "repos/$repo/issues/comments/$claude_id/reactions" --jq ".[] | select(.user.login == \"$CLAUDE\") | .content")" ] \
    && echo acked || echo pending
}

# Moves one bot's state forward. Final states: done, failed, no-ack, timeout, skip.
next_state() {
  local bot=$1 state=$2 elapsed=$3 now
  case "$state" in done|failed|no-ack|timeout|skip) echo "$state"; return ;; esac
  now=$("${bot}_status")
  [ "$now" = pending ] && [ "$state" = acked ] && now=acked
  if [ "$now" = done ] || [ "$now" = failed ]; then echo "$now"
  elif [ "$elapsed" -ge "$timeout_s" ]; then echo timeout
  elif [ "$now" = pending ] && [ "$elapsed" -ge "$ACK_SECONDS" ]; then echo no-ack
  else echo "$now"; fi
}

cmd_wait() {
  repo=$1 pr=$2 sha=$3 codex_id=$4 claude_id=$5
  timeout_s=$(( ${6:-40} * 60 ))
  local first=$codex_id start elapsed codex_state=pending claude_state=pending
  [ "$first" = - ] && first=$claude_id
  # Use GitHub's clock, not ours: WSL clocks drift.
  since=$(gh api "repos/$repo/issues/comments/$first" --jq .created_at) || exit 1
  [ "$codex_id" = - ] && codex_state=skip
  [ "$claude_id" = - ] && claude_state=skip
  start=$(date +%s)
  while :; do
    elapsed=$(( $(date +%s) - start ))
    codex_state=$(next_state codex "$codex_state" "$elapsed")
    claude_state=$(next_state claude "$claude_state" "$elapsed")
    case "$codex_state $claude_state" in
      *pending*|*acked*) sleep "$POLL_SECONDS" ;;
      *) break ;;
    esac
  done
  # Codex can post the review a few seconds after flipping its status to Completed.
  sleep 10
  echo "codex $codex_state"
  echo "claude $claude_state"
  echo "since $since"
}

cmd_collect() {
  local repo=$1 pr=$2 sha=$3 since=$4 ids
  ids=$(gh api "repos/$repo/pulls/$pr/reviews" --paginate \
    --jq ".[] | select(.user.login == \"$CODEX\" and .submitted_at >= \"$since\") | .id" | paste -sd, -)
  echo "# Codex findings (reviews: ${ids:-none})"
  [ -n "$ids" ] && gh api "repos/$repo/pulls/$pr/comments" --paginate \
    --jq ".[] | select(.user.login == \"$CODEX\") | select(.pull_request_review_id as \$r | [$ids] | any(. == \$r)) | \"\n## comment \(.id) \(.path):\(.line // .original_line)\n\(.body)\""

  echo
  echo "# Claude inline findings"
  gh api "repos/$repo/pulls/$pr/comments" --paginate \
    --jq ".[] | select(.user.login == \"$CLAUDE\" and .created_at >= \"$since\") | \"\n## comment \(.id) \(.path):\(.line // .original_line)\n\(.body)\""
  echo
  echo "# Claude Code Review check run"
  gh api "repos/$repo/commits/$sha/check-runs?check_name=Claude%20Code%20Review" \
    --jq ".check_runs[] | select((.started_at // \"\") >= \"$since\") | \"\(.output.title // \"\")\n\(.output.text // \"\")\""
  echo
  echo "# Claude PR comments"
  gh api "repos/$repo/issues/$pr/comments" --paginate \
    --jq ".[] | select(.user.login == \"$CLAUDE\" and .updated_at >= \"$since\") | \"\n## comment \(.id)\n\(.body)\""
}

case "${1:-}" in
  detect) shift; cmd_detect "$@" ;;
  wait) shift; cmd_wait "$@" ;;
  collect) shift; cmd_collect "$@" ;;
  *) echo "usage: pr-bots.sh detect|wait|collect ..." >&2; exit 2 ;;
esac
