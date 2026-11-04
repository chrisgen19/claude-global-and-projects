#!/usr/bin/env bash
#
# Hand a Claude Code session over to another account (e.g. when one account
# hits its 5h limit mid-task).
#
#   claude-handoff list [--all] [--dir DIR]       sessions for this project, every account, newest first
#   claude-handoff brief <id> [-n N] [--from ACCOUNT]
#                                                 Markdown handoff: last N messages + current git state
#   claude-handoff copy <id> --to ACCOUNT [--from ACCOUNT] [--force]
#                                                 copy the transcript so `claude-<account> --resume <id>` opens it
#
# <id> is a session id or any unique prefix of one (the status line shows the
# first 8 characters as id:xxxxxxxx). ACCOUNT is dev, work, personal or default
# (~/.claude). A copied session exists in two accounts: the newest copy is used
# unless --from names the account to read.
#
# brief is the cheap option: a fresh session reads a page of text. copy gives
# the other account the full context, but resuming reloads the whole transcript
# (often 5 to 30MB), which uses a lot of that account's limit.
#
# Requires bash 3.2+ and jq. Reads ~/.claude*/projects only; copy writes into
# the target account's projects dir and never touches the original.
set -uo pipefail

ACCOUNTS="default dev work personal"

die() { printf 'claude-handoff: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; }

account_dir() { # account -> config dir
  case "$1" in
    default) printf '%s\n' "$HOME/.claude" ;;
    dev|work|personal) printf '%s\n' "$HOME/.claude-$1" ;;
    *) return 1 ;;
  esac
}

# Claude names a project folder after its cwd with every non-alphanumeric
# character replaced by "-" (/tmp/claude-1000/-home -> -tmp-claude-1000--home).
slug_for() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

case "$OSTYPE" in
  darwin*|*bsd*|FreeBSD*)
    _mtime() { stat -f %m "$1"; }
    _size() { stat -f %z "$1"; }
    _date() { date -r "$1" '+%Y-%m-%d %H:%M'; }
    ;;
  *)
    _mtime() { stat -c %Y "$1"; }
    _size() { stat -c %s "$1"; }
    _date() { date -d "@$1" '+%Y-%m-%d %H:%M'; }
    ;;
esac

human_size() {
  awk -v b="$1" 'BEGIN { if (b >= 1048576) printf "%.1fM", b / 1048576; else printf "%dK", b / 1024 }'
}

# Text of the user and assistant turns, skipping tool results and the harness's
# <system-reminder>/<command-*> wrappers. One JSON string per message.
MESSAGES_JQ='
  select(.type == "user" or .type == "assistant") | select(.isMeta != true)
  | .type as $t
  | (.message.content
     | if type == "string" then . else (map(select(.type == "text") | .text) | join("\n")) end) as $c
  | select($c != "" and ($c | startswith("<") | not))
  | {role: $t, text: $c}'

# Every transcript for the project (or all projects), newest first, as
# "mtime<TAB>account<TAB>path" lines.
transcripts() { # all(0|1) slug
  local a dir f
  for a in $ACCOUNTS; do
    dir=$(account_dir "$a")
    [ -d "$dir/projects" ] || continue
    if [ "$1" = 1 ]; then
      for f in "$dir"/projects/*/*.jsonl; do
        [ -f "$f" ] && printf '%s\t%s\t%s\n' "$(_mtime "$f")" "$a" "$f"
      done
    else
      for f in "$dir/projects/$2"/*.jsonl; do
        [ -f "$f" ] && printf '%s\t%s\t%s\n' "$(_mtime "$f")" "$a" "$f"
      done
    fi
  done | sort -rn
}

# Resolve an id prefix to exactly one "mtime<TAB>account<TAB>path" line. Searches
# every project, so a session started in another worktree is still found. After
# a copy the same id lives in two accounts: those count as one session and the
# newest copy wins. $2 limits the search to one account (--from), $3 skips one
# (the copy target).
resolve() { # prefix from skip
  local matches count
  matches=$(transcripts 1 "" | awk -F'\t' -v p="$1" -v from="$2" -v skip="$3" '
    from != "" && $2 != from { next }
    skip != "" && $2 == skip { next }
    { n = split($3, a, "/"); id = a[n]; if (index(id, p) == 1 && !(id in seen)) { seen[id] = 1; print } }')
  count=$(printf '%s' "$matches" | grep -c . || true)
  [ "$count" = 0 ] && die "no session id starts with '$1'${2:+ in the $2 account}"
  if [ "$count" -gt 1 ]; then
    printf 'claude-handoff: %s sessions start with %s:\n' "$count" "$1" >&2
    printf '%s\n' "$matches" | awk -F'\t' '{ print "  " $2 "  " $3 }' >&2
    exit 1
  fi
  printf '%s\n' "$matches"
}

cmd_list() { # all slug
  local rows mtime acct path id prompt
  rows=$(transcripts "$1" "$2")
  if [ -z "$rows" ]; then
    printf 'No sessions for %s in any account. Try --all, or --dir <project dir>.\n' "$2"
    return 0
  fi
  printf '%-8s  %-8s  %-16s  %6s  %s\n' ACCOUNT ID 'LAST ACTIVE' SIZE 'LAST PROMPT'
  printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r mtime acct path; do
    id=$(basename "$path" .jsonl)
    # The tail is enough to find the last prompt and keeps list fast on 30MB files.
    prompt=$(tail -n 400 "$path" | jq -rs "[.[] | $MESSAGES_JQ | select(.role == \"user\")] | last | .text // \"\"" 2> /dev/null \
      | tr '\n' ' ' | cut -c1-80)
    printf '%-8s  %-8s  %-16s  %6s  %s\n' "$acct" "${id:0:8}" "$(_date "$mtime")" "$(human_size "$(_size "$path")")" "$prompt"
  done
}

cmd_brief() { # prefix count from
  local line mtime acct path id cwd branch
  line=$(resolve "$1" "$3" "") || exit 1
  IFS="$(printf '\t')" read -r mtime acct path <<EOF
$line
EOF
  id=$(basename "$path" .jsonl)
  cwd=$(jq -r 'select(.cwd != null) | .cwd' "$path" | tail -n 1)
  branch=$(jq -r 'select(.gitBranch != null) | .gitBranch' "$path" | tail -n 1)

  printf '# Handoff from session %s\n\n' "${id:0:8}"
  printf -- '- **Account:** %s (`%s`)\n' "$acct" "$(account_dir "$acct")"
  printf -- '- **Session id:** `%s`\n' "$id"
  printf -- '- **Last active:** %s\n' "$(_date "$mtime")"
  printf -- '- **Directory:** `%s`\n' "${cwd:-unknown}"
  printf -- '- **Branch at the time:** `%s`\n' "${branch:-unknown}"
  printf -- '- **Transcript:** `%s` (%s)\n\n' "$path" "$(human_size "$(_size "$path")")"

  printf '## Last %s messages\n\n' "$2"
  jq -c "$MESSAGES_JQ" "$path" | tail -n "$2" | jq -r '
    "### " + (if .role == "user" then "User" else "Claude" end) + "\n\n"
    + (if (.text | length) > 2500 then .text[0:2500] + "\n\n[...truncated]" else .text end) + "\n"'

  # The last todo list, if the session kept one.
  jq -c 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "TodoWrite") | .input.todos' "$path" \
    | tail -n 1 | jq -r '"## Last todo list\n\n" + (map("- [" + (if .status == "completed" then "x" else " " end) + "] " + .content + (if .status == "in_progress" then " (in progress)" else "" end)) | join("\n")) + "\n"'

  if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    printf '## Git state now (%s)\n\n```text\n' "$cwd"
    git -C "$cwd" status -sb
    printf -- '---\n'
    git -C "$cwd" log --oneline -5
    printf '```\n\n'
  fi
  printf 'Check this against the live state (git, PRs, CI) before acting: the transcript can be stale.\n'
}

cmd_copy() { # prefix target force from
  local line mtime acct path id src_dir target_dir dest age
  target_dir=$(account_dir "$2") || die "unknown account '$2' (use: $ACCOUNTS)"
  [ "$4" = "$2" ] && die "--from and --to are the same account"
  line=$(resolve "$1" "$4" "$2") || exit 1
  IFS="$(printf '\t')" read -r mtime acct path <<EOF
$line
EOF
  [ -d "$target_dir" ] || die "$target_dir does not exist"
  id=$(basename "$path" .jsonl)
  src_dir=$(dirname "$path")
  dest="$target_dir/projects/$(basename "$src_dir")"

  if [ -e "$dest/$id.jsonl" ] && [ "$3" != 1 ]; then
    die "$dest/$id.jsonl already exists (use --force to overwrite)"
  fi
  age=$(( $(date +%s) - mtime ))
  if [ "$age" -lt 120 ]; then
    printf 'Warning: the source session was written %ss ago and may still be running.\n' "$age" >&2
  fi

  mkdir -p "$dest" || die "cannot create $dest"
  cp -p "$path" "$dest/$id.jsonl" || die "cannot copy the transcript"
  if [ -d "$src_dir/$id" ]; then
    rm -rf "${dest:?}/$id"
    cp -pR "$src_dir/$id" "$dest/$id" || die "cannot copy $src_dir/$id"
  fi

  printf 'Copied %s (%s) from %s to %s.\n' "${id:0:8}" "$(human_size "$(_size "$path")")" "$acct" "$2"
  printf 'Resume it from the session'"'"'s directory with:\n\n'
  if [ "$2" = default ]; then printf '  claude --resume %s\n' "$id"; else printf '  claude-%s --resume %s\n' "$2" "$id"; fi
  printf '\nResuming reloads the whole transcript into the %s account.\n' "$2"
}

main() {
  command -v jq > /dev/null || die "jq is required"
  local cmd="${1:-}" all=0 count=12 to="" from="" force=0 dir="$PWD" id=""
  [ $# -gt 0 ] && shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) all=1 ;;
      -n) [ $# -ge 2 ] || die "-n needs a number"; count="$2"; shift ;;
      --to) [ $# -ge 2 ] || die "--to needs an account"; to="$2"; shift ;;
      --from)
        [ $# -ge 2 ] || die "--from needs an account"; from="$2"; shift
        account_dir "$from" > /dev/null || die "unknown account '$from' (use: $ACCOUNTS)"
        ;;
      --force) force=1 ;;
      --dir) [ $# -ge 2 ] || die "--dir needs a path"; dir="$2"; shift ;;
      -h|--help) usage; exit 0 ;;
      -*) die "unknown option $1" ;;
      *) [ -z "$id" ] || die "unexpected argument $1"; id="$1" ;;
    esac
    shift
  done
  case "$count" in ''|*[!0-9]*) die "-n needs a number" ;; esac

  case "$cmd" in
    list) cmd_list "$all" "$(slug_for "$dir")" ;;
    brief) [ -n "$id" ] || die "brief needs a session id"; cmd_brief "$id" "$count" "$from" ;;
    copy)
      [ -n "$id" ] || die "copy needs a session id"
      [ -n "$to" ] || die "copy needs --to dev|work|personal|default"
      cmd_copy "$id" "$to" "$force" "$from"
      ;;
    ''|-h|--help|help) usage ;;
    *) die "unknown command '$cmd' (list, brief, copy)" ;;
  esac
}

main "$@"
