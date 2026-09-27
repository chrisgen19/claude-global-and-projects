#!/bin/bash
#
# Claude Code PreToolUse (Bash) hook: asks for confirmation before destructive
# Prisma commands when the project's database URL points at a production host.
#
#   prisma migrate dev | migrate reset | migrate resolve | db push | db execute
#
# Also catches them behind package scripts (pnpm db:push, npm start, bun run
# db:migrate, ...) by reading the script body from package.json.
#
# It never blocks: it returns permissionDecision "ask", so the command still runs
# once the user approves it. Safe commands (generate, migrate deploy, studio)
# and anything pointing elsewhere pass through with no prompt.
#
# Production hosts are machine-local and never committed. List them, one
# extended-regex fragment per line (# comments allowed), in:
#
#   ~/.config/prisma-prod-guard/hosts      e.g.  203\.0\.113\.10
#                                                example\.dev
#
# With no hosts file the hook does nothing, so a fresh machine is unaffected.
# Requires bash 3.2+ and jq. Reads the hook payload (JSON) on stdin.

HOSTS_FILE="${PRISMA_GUARD_HOSTS:-$HOME/.config/prisma-prod-guard/hosts}"
DANGEROUS='prisma[[:space:]]+(migrate[[:space:]]+(dev|reset|resolve)|db[[:space:]]+(push|execute))'
RUNNER='(npm|pnpm|yarn|bun)[[:space:]]+((run|run-script)[[:space:]]+)?[A-Za-z0-9:_.-]+'
URL_LINE='^[[:space:]]*(export[[:space:]]+)?[A-Z_]*(DATABASE|DIRECT|SHADOW|DB|POSTGRES)[A-Z_]*URL[[:space:]]*='
WARN="'prisma migrate dev/reset/resolve' and 'db push/execute' can drop or rewrite live data. Approve only if you meant to change the live database."

[ -f "$HOSTS_FILE" ] || exit 0
PROD_HOSTS=$(grep -vE '^[[:space:]]*(#|$)' "$HOSTS_FILE" | paste -sd '|' -)
[ -n "$PROD_HOSTS" ] || exit 0

input=$(cat)
# Cheap pre-filter on the raw payload, so most commands never spawn jq.
printf '%s' "$input" | grep -Eq 'prisma|(npm|pnpm|yarn|bun)[[:space:]]' || exit 0

# A missing jq must not silently switch the guard off. Exit 1 is a non-blocking
# hook error: the command still runs, but the failure is shown.
if ! command -v jq > /dev/null; then
  echo "prisma-prod-guard: jq not found, production database check skipped" >&2
  exit 1
fi

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -z "$cwd" ] && cwd=$PWD

ask() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}

# Directories the command runs in: the session cwd, then each cd target resolved
# against the one before it (cd services && cd api -> services/api). Quoted
# targets keep their spaces.
dirs="$cwd"
cur="$cwd"
while IFS= read -r d; do
  [ -n "$d" ] || continue
  case "$d" in
    \"*\") d=${d#\"}; d=${d%\"} ;;
    \'*\') d=${d#\'}; d=${d%\'} ;;
  esac
  case "$d" in
    \~) d=$HOME ;;
    \~/*) d="$HOME/${d#??}" ;;
  esac
  case "$d" in /*) cur=$d ;; *) cur="$cur/$d" ;; esac
  dirs="$dirs
$cur"
done <<EOF
$(printf '%s' "$cmd" | grep -oE "(^|[;&|[:space:]])cd[[:space:]]+(\"[^\"]*\"|'[^']*'|[^;&|[:space:]]+)" | sed -E 's/^[;&|[:space:]]*cd[[:space:]]+//')
EOF

# Directory and script names below never contain newlines, so split on those only.
IFS='
'

# Is anything destructive actually going to run? Either the command itself, or
# the body of a package.json script it invokes.
via=""
if ! printf '%s' "$cmd" | grep -Eq "$DANGEROUS"; then
  for name in $(printf '%s' "$cmd" | grep -oE "$RUNNER" | awk '{print $NF}'); do
    for d in $dirs; do
      [ -f "$d/package.json" ] || continue
      body=$(jq -r --arg n "$name" '.scripts[$n] // empty' "$d/package.json")
      if printf '%s' "$body" | grep -Eq "$DANGEROUS"; then
        via=" (via package.json script \"$name\": $body)"
        break 2
      fi
    done
  done
  [ -n "$via" ] || exit 0
fi

# 1. Inline URL in the command itself, or DATABASE_URL already in the environment
if printf '%s' "$cmd" | grep -Eq "(postgres(ql)?://|_URL=)[^[:space:]]*($PROD_HOSTS)"; then
  ask "PRODUCTION DB: this command sets a database URL pointing at a production host$via. $WARN"
fi
if printf '%s' "${DATABASE_URL:-}" | grep -Eq "$PROD_HOSTS"; then
  ask "PRODUCTION DB: DATABASE_URL in the environment points at a production host$via. $WARN"
fi

# 2. .env files in each directory the command runs in
for d in $dirs; do
  for f in .env .env.local .env.development .env.development.local prisma/.env; do
    p="$d/$f"
    [ -f "$p" ] || continue
    if grep -E "$URL_LINE" "$p" | grep -Eq "$PROD_HOSTS"; then
      ask "PRODUCTION DB: $p points at a production host$via. $WARN"
    fi
  done
done
exit 0
