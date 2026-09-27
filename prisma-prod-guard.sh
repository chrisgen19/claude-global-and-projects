#!/bin/bash
#
# Claude Code PreToolUse (Bash) hook: asks for confirmation before destructive
# Prisma commands when the project's database URL points at a production host.
#
#   prisma migrate dev | migrate reset | migrate resolve | db push | db execute
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
URL_LINE='^[[:space:]]*(export[[:space:]]+)?[A-Z_]*(DATABASE|DIRECT|SHADOW|DB|POSTGRES)[A-Z_]*URL[[:space:]]*='
WARN="'prisma migrate dev/reset/resolve' and 'db push/execute' can drop or rewrite live data. Approve only if you meant to change the live database."

[ -f "$HOSTS_FILE" ] || exit 0
PROD_HOSTS=$(grep -vE '^[[:space:]]*(#|$)' "$HOSTS_FILE" | paste -sd '|' -)
[ -n "$PROD_HOSTS" ] || exit 0

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -z "$cwd" ] && cwd=$PWD

printf '%s' "$cmd" | grep -Eq "$DANGEROUS" || exit 0

ask() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}

# 1. Inline URL in the command itself, or DATABASE_URL already in the environment
if printf '%s' "$cmd" | grep -Eq "(postgres(ql)?://|_URL=)[^[:space:]]*($PROD_HOSTS)"; then
  ask "PRODUCTION DB: this Prisma command sets a database URL pointing at a production host. $WARN"
fi
if printf '%s' "${DATABASE_URL:-}" | grep -Eq "$PROD_HOSTS"; then
  ask "PRODUCTION DB: DATABASE_URL in the environment points at a production host. $WARN"
fi

# 2. .env files in the session cwd and in any directory the command cd's into
dirs="$cwd"
for d in $(printf '%s' "$cmd" | grep -oE '(^|[;&|[:space:]])cd[[:space:]]+[^;&|[:space:]]+' | sed -E 's/^[;&|[:space:]]*cd[[:space:]]+//'); do
  d=$(printf '%s' "$d" | sed -e "s#^~#$HOME#" -e "s/^[\"']//" -e "s/[\"']\$//")
  case "$d" in /*) ;; *) d="$cwd/$d" ;; esac
  dirs="$dirs
$d"
done

old_ifs=$IFS
IFS='
'
for d in $dirs; do
  for f in .env .env.local .env.development .env.development.local prisma/.env; do
    p="$d/$f"
    [ -f "$p" ] || continue
    if grep -E "$URL_LINE" "$p" | grep -Eq "$PROD_HOSTS"; then
      IFS=$old_ifs
      ask "PRODUCTION DB: $p points at a production host. $WARN"
    fi
  done
done
IFS=$old_ifs
exit 0
