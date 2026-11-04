#!/usr/bin/env bash
# Behaviour tests for statusline.sh.
#
# Linting proves the script parses and avoids known footguns. It cannot tell
# whether the rendered line is correct, which is what actually breaks: the %b
# escape bug (#81) was shellcheck-clean for as long as it existed.
#
# (This comment must not begin with the word shellcheck: a comment whose first
# token is that word is parsed as a shellcheck directive and fails the lint.)
#
# Each test feeds the script a statusline JSON payload on stdin and asserts on
# what it prints. Run from anywhere:  ./statusline-tests/run.sh
#
# Portability, because CI runs this on macOS with the stock /bin/bash 3.2 and
# BSD sed as well as on Ubuntu:
#   - no mapfile, no declare -A, no ${var^^} (all bash 4+)
#   - no `sed 's/\x1b//'`: BSD sed has no \x escapes, so the ESC byte is built
#     with printf and interpolated into the pattern
#   - no `grep -P`, no `date +%N`
#
# Every git state gets its own directory, so each render is a cache miss and
# the suite never has to clear the cache. That matters: the cache lives in
# /tmp keyed by uid, so globbing it away would delete the entries belonging to
# the developer's real sessions.

set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd) || exit 1
SCRIPT="$REPO_ROOT/statusline.sh"
ESC=$(printf '\033')

pass=0
fail=0

# A config dir with no .claude.json, so the "(account)" suffix never varies
# with whatever is installed on the machine running the tests.
CONFIG_DIR=$(mktemp -d) || exit 1
FIX=$(mktemp -d) || exit 1

# Removing the fixtures is not enough: the script writes a cache entry per
# directory it renders, so every run used to leave ~11 orphans behind in /tmp.
# They are keyed by the mangled cwd, so matching on this run's own $FIX leaves
# every other session's entries untouched. The mangling has to agree with the
# script's: / becomes _, then anything outside [A-Za-z0-9_.-] becomes _ too.
#
# The cache format version is globbed rather than named, so this keeps working
# when the script bumps it. Naming v3 here would have quietly started leaking
# again at v4, which is the same way the leak arrived in the first place.
cleanup() {
  rm -rf "$FIX" "$CONFIG_DIR"
  # The variables stay quoted and only the * are bare, so the pattern expands
  # without word-splitting the path. With no match bash passes the pattern
  # through literally and `rm -f` ignores it.
  local k="${FIX//\//_}"
  rm -f /tmp/claude-statusline-git-*-"${UID}"-"${k//[^A-Za-z0-9_.-]/_}"*
}
trap cleanup EXIT

strip_ansi() { sed "s/${ESC}\\[[0-9;]*m//g"; }

# render <dir> [extra-json] -- full output of the script, colours stripped
render() {
  local dir="$1" extra="${2:-}" payload
  payload=$(jq -nc --arg d "$dir" --argjson x "{${extra}}" \
    '{workspace:{current_dir:$d},model:{display_name:"M"},cost:{},context_window:{used_percentage:40}} * $x')
  printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" bash "$SCRIPT" | strip_ansi
}

# seg <dir> [extra-json] -- line 1 from the model tag onwards
seg() {
  render "$1" "${2:-}" | sed -n '1p' | sed 's/^.*\[M\] *//'
}

ok()   { pass=$((pass + 1)); printf 'ok    %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'FAIL  %s\n' "$1"; }

# contains <label> <needle> <haystack>
contains() {
  if [ "${3#*"$2"}" != "$3" ]; then
    ok "$1"
  else
    bad "$1"
    printf '        want substring: %s\n        got:            %s\n' "$2" "$3"
  fi
}

# excludes <label> <needle> <haystack>
excludes() {
  if [ "${3#*"$2"}" = "$3" ]; then
    ok "$1"
  else
    bad "$1"
    printf '        must NOT contain: %s\n        got:              %s\n' "$2" "$3"
  fi
}

equals() {
  if [ "$3" = "$2" ]; then
    ok "$1"
  else
    bad "$1"
    printf '        want: %s\n        got:  %s\n' "$2" "$3"
  fi
}

# newrepo <path> [branch] -- an initialised repo with a committed file
newrepo() {
  local p="$1" b="${2:-main}"
  mkdir -p "$p" || return 1
  git init -q -b "$b" "$p" || return 1
  git -C "$p" config user.email t@e.com
  git -C "$p" config user.name T
  echo seed > "$p/seed.txt"
  git -C "$p" add -A
  git -C "$p" commit -qm seed
}

echo "statusline.sh behaviour tests"
echo "  script: $SCRIPT"
echo "  bash:   $BASH_VERSION"
echo

# ---------------------------------------------------------------------------
echo "-- dirty state counts --"
# The counts must stay stable: they are the part of the line read most often,
# and the porcelain parse that produces them replaced five separate git calls.
newrepo "$FIX/mixed" || exit 1
(
  cd "$FIX/mixed" || exit 1
  echo keep > k.txt && git add k.txt && git commit -qm k
  echo n > staged.txt && git add staged.txt          # staged only
  echo c >> k.txt                                     # modified only
  echo b > both.txt && git add both.txt && echo m >> both.txt  # staged AND modified
  mkdir -p un && echo 1 > un/a.txt && echo 2 > un/b.txt        # untracked, in a dir
  git mv seed.txt renamed.txt                         # staged rename
) || exit 1
got=$(seg "$FIX/mixed")
contains "staged/modified/untracked counted as +3 ~2 ?2" "+3 ~2 ?2" "$got"
# Untracked files are counted individually, not collapsed to their directory.
# This is what -uall buys; without it `un/` would count as 1 instead of 2.
contains "untracked counted per file, not per directory" "?2" "$got"

# ---------------------------------------------------------------------------
echo "-- branch sync state --"
# A repo with no remote at all: the marker would be permanent and unactionable.
excludes "local-only repo shows no sync marker" "no-upstream" "$(seg "$FIX/mixed")"

git init -q --bare "$FIX/bare" || exit 1
newrepo "$FIX/sync" || exit 1
git -C "$FIX/sync" remote add origin "$FIX/bare"
git -C "$FIX/sync" push -q -u origin main

got=$(seg "$FIX/sync")
contains "tracking branch in sync names the branch" "| main" "$got"
excludes "tracking branch in sync: no ahead marker" "^" "$got"
excludes "tracking branch in sync: no no-upstream" "no-upstream" "$got"

cp -R "$FIX/sync" "$FIX/ahead" || exit 1
(
  cd "$FIX/ahead" || exit 1
  echo a > a.txt && git add a.txt && git commit -qm a
  echo b > b.txt && git add b.txt && git commit -qm b
) || exit 1
contains "two unpushed commits show ^2" "main ^2" "$(seg "$FIX/ahead")"

# Its own bare repo, so moving this remote cannot change what the others see.
git init -q --bare "$FIX/bare-behind" || exit 1
newrepo "$FIX/behind" || exit 1
git -C "$FIX/behind" remote add origin "$FIX/bare-behind"
git -C "$FIX/behind" push -q -u origin main
(
  cd "$FIX/behind" || exit 1
  echo a > a.txt && git add a.txt && git commit -qm a
  echo b > b.txt && git add b.txt && git commit -qm b
  git push -q
  git reset -q --hard HEAD~2
) || exit 1
contains "two commits behind show v2" "main v2" "$(seg "$FIX/behind")"

cp -R "$FIX/sync" "$FIX/unpushed" || exit 1
git -C "$FIX/unpushed" checkout -q -b feature/phase-9
contains "new branch in a repo with a remote shows no-upstream" \
  "feature/phase-9 no-upstream" "$(seg "$FIX/unpushed")"

# ---------------------------------------------------------------------------
echo "-- submodules --"
# A submodule holding nothing but untracked files is reported by porcelain v2
# as `1 .M S..U`, whose Y field reads as modified, while the `git diff` this
# parser replaced ignored it (diff.ignoreSubmodules defaults to untracked).
# Without --ignore-submodules=untracked a submodule with build output in it
# would pin a permanent ~1 on the line. A real tracked change must still show.
#
# -c protocol.file.allow=always: git refuses file:// submodules by default
# (CVE-2022-39253), and the fixtures here are local paths.
newrepo "$FIX/inner" || exit 1
newrepo "$FIX/super" || exit 1
if git -C "$FIX/super" -c protocol.file.allow=always submodule add -q "$FIX/inner" sub > /dev/null; then
  git -C "$FIX/super" commit -qm "add submodule"

  cp -R "$FIX/super" "$FIX/sub-untracked" || exit 1
  echo scratch > "$FIX/sub-untracked/sub/untracked.txt"
  excludes "a submodule with only untracked content is not counted as modified" \
    "~1" "$(seg "$FIX/sub-untracked")"

  cp -R "$FIX/super" "$FIX/sub-modified" || exit 1
  echo changed >> "$FIX/sub-modified/sub/seed.txt"
  contains "a real tracked change inside a submodule still counts as modified" \
    "~1" "$(seg "$FIX/sub-modified")"
else
  # Never silently skip: a skipped assertion looks like a passing one.
  bad "submodule fixture could not be created (git submodule add failed)"
fi

echo "-- conflicts --"
# Before the porcelain parse, a single conflicted file was reported as a bogus
# "+1 ~2" by the two diff calls. It must not swing the other way and vanish.
cp -R "$FIX/sync" "$FIX/conflict" || exit 1
(
  cd "$FIX/conflict" || exit 1
  git checkout -q -b side
  echo side > seed.txt && git commit -qam side
  git checkout -q main
  echo main > seed.txt && git commit -qam main
  git merge side -q
) > /dev/null
got=$(seg "$FIX/conflict")
contains "a conflicted file is shown once as !1" "!1" "$got"
excludes "a conflicted file is not double counted as modified" "~2" "$got"

# ---------------------------------------------------------------------------
echo "-- detached HEAD --"
cp -R "$FIX/sync" "$FIX/detached" || exit 1
git -C "$FIX/detached" checkout -q --detach HEAD
got=$(seg "$FIX/detached")
oid=$(git -C "$FIX/detached" rev-parse HEAD)
contains "detached HEAD shows the short oid" "${oid%"${oid#???????}"}" "$got"
# A detached HEAD has no upstream by definition, so saying so adds nothing.
excludes "detached HEAD does not claim no-upstream" "no-upstream" "$got"

# ---------------------------------------------------------------------------
echo "-- outside a repo --"
mkdir -p "$FIX/plain" || exit 1
got=$(seg "$FIX/plain")
excludes "a non-repo shows no branch separator" "|" "$got"

# ---------------------------------------------------------------------------
echo "-- permission mode --"
# default is the ordinary case: the line should only speak up when the session
# is not asking before it acts.
contains "plan"              "plan"      "$(seg "$FIX/plain" '"permission_mode":"plan"')"
contains "acceptEdits"       "auto-edit" "$(seg "$FIX/plain" '"permission_mode":"acceptEdits"')"
contains "auto"              "auto"      "$(seg "$FIX/plain" '"permission_mode":"auto"')"
contains "dontAsk"           "dont-ask"  "$(seg "$FIX/plain" '"permission_mode":"dontAsk"')"
contains "bypassPermissions" "BYPASS"    "$(seg "$FIX/plain" '"permission_mode":"bypassPermissions"')"
excludes "default is silent" "default"   "$(seg "$FIX/plain" '"permission_mode":"default"')"
excludes "an unknown mode is ignored rather than printed" \
  "someFutureMode" "$(seg "$FIX/plain" '"permission_mode":"someFutureMode"')"

# ---------------------------------------------------------------------------
echo "-- escape sequences in untrusted values (#81) --"
# The cwd, branch name and git email are interpolated into the output. With
# printf '%b' they were expanded as format strings: a directory holding a
# literal backslash-t rendered as a tab, and a backslash-n emitted a third
# line, breaking the two-line contract the status line is configured for.
#
# jq builds the payload so the backslash is escaped as \\ on the wire. Writing
# \t by hand would make it a JSON tab escape, which jq decodes before the
# script ever sees it, and the test would prove nothing.
bad_dir="$FIX/bad"$'\\'"tdir"
mkdir -p "$bad_dir" || exit 1
got=$(render "$bad_dir")
contains "a literal backslash in the cwd stays literal" 'bad\tdir' "$got"
tab=$(printf '\t')
excludes "a literal backslash in the cwd is not expanded to a tab" \
  "bad${tab}dir" "$got"

nl_dir="$FIX/two"$'\\'"nlines"
mkdir -p "$nl_dir" || exit 1
equals "a backslash-n in the cwd cannot add a third line" \
  "1" "$(render "$nl_dir" | wc -l | tr -d ' ')"

# The contract is two lines: one newline, because line 2 has no trailing one.
equals "ordinary render is exactly two lines" \
  "1" "$(render "$FIX/sync" | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
echo "-- account copies --"
# The three copies differ from the template only on lines 14 and 15, which CI
# diff-checks. That proves they are in sync, not that the config block in each
# one is valid shell: a broken quote there would still pass the diff.
for acct in personal work dev; do
  copy="$REPO_ROOT/claude-$acct/statusline.sh"
  if [ ! -f "$copy" ]; then
    bad "claude-$acct/statusline.sh exists"
    continue
  fi
  expected=$(echo "$acct" | tr '[:lower:]' '[:upper:]')
  out=$(printf '%s' \
    "$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"M"},cost:{},context_window:{used_percentage:1}}')" \
    | CLAUDE_CONFIG_DIR="$CONFIG_DIR" bash "$copy" | strip_ansi | sed -n '1p')
  contains "claude-$acct renders the $expected label" "$expected" "$out"
done

# The router passes this when a session is not under a named account dir, so
# the line never claims to be an account it is not.
out=$(printf '%s' \
  "$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"M"},cost:{},context_window:{used_percentage:1}}')" \
  | ACCOUNT_LABEL_OVERRIDE=CLAUDE CLAUDE_CONFIG_DIR="$CONFIG_DIR" bash "$SCRIPT" | strip_ansi | sed -n '1p')
contains "ACCOUNT_LABEL_OVERRIDE wins over the built-in label" "CLAUDE" "$out"

# ---------------------------------------------------------------------------
echo "-- the Claude account email --"
# It arrives through --slurpfile on the same jq pass as the payload, so the
# things worth pinning are that it is read at all, and that a bad account file
# costs only the email rather than blanking the whole line.
acct_dir=$(mktemp -d) || exit 1
printf '{"oauthAccount":{"emailAddress":"someone@example.com"}}' > "$acct_dir/.claude.json"
out=$(printf '%s' \
  "$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"M"},cost:{},context_window:{used_percentage:1}}')" \
  | CLAUDE_CONFIG_DIR="$acct_dir" bash "$SCRIPT" | strip_ansi | sed -n '1p')
contains "the account username is shown in parens" "(someone)" "$out"
excludes "the domain is stripped" "example.com" "$out"

# Truncated mid-write: jq exits 2 with no output at all on a bad --slurpfile,
# so without the fallback this blanks the model, the directory and everything
# else, not just the email.
printf '{"oauthAccount":{"emailAddress":"someone@example.' > "$acct_dir/.claude.json"
out=$(printf '%s' \
  "$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"MODELNAME"},cost:{},context_window:{used_percentage:1}}')" \
  | CLAUDE_CONFIG_DIR="$acct_dir" bash "$SCRIPT" | strip_ansi | sed -n '1p')
contains "a corrupt .claude.json still renders the rest of the line" "MODELNAME" "$out"
excludes "a corrupt .claude.json shows no account" "(" "$out"

# No .claude.json at all: --slurpfile on a missing path is a hard jq error, so
# the script has to substitute /dev/null rather than pass the path through.
rm -f "$acct_dir/.claude.json"
out=$(printf '%s' \
  "$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"MODELNAME"},cost:{},context_window:{used_percentage:1}}')" \
  | CLAUDE_CONFIG_DIR="$acct_dir" bash "$SCRIPT" | strip_ansi | sed -n '1p')
contains "an absent .claude.json still renders the line" "MODELNAME" "$out"
rm -rf "$acct_dir"

echo "-- the git identity --"
# Read from git config so an includeIf per directory is respected, which is why
# it is resolved per cwd rather than once per session.
contains "the git email username is shown" "t@e.com" \
  "$(git -C "$FIX/sync" config user.email)"
contains "the git email username appears on the line" "t" \
  "$(render "$FIX/sync" | sed -n '1p')"

echo "-- malformed and absent payload fields --"
# The script is fed whatever Claude Code sends; a missing field must not make
# it print an error or die mid-line.
equals "empty object payload still renders two lines" \
  "1" "$(printf '{}' | CLAUDE_CONFIG_DIR="$CONFIG_DIR" bash "$SCRIPT" | wc -l | tr -d ' ')"
contains "absent model falls back to ?" "[?]" \
  "$(printf '{}' | CLAUDE_CONFIG_DIR="$CONFIG_DIR" bash "$SCRIPT" | strip_ansi | sed -n '1p')"
equals "non-numeric context percentage does not break the bar" \
  "1" "$(printf '{"context_window":{"used_percentage":"oops"}}' \
    | CLAUDE_CONFIG_DIR="$CONFIG_DIR" bash "$SCRIPT" | wc -l | tr -d ' ')"
equals "non-JSON input still renders two lines" \
  "1" "$(printf 'not json at all' | CLAUDE_CONFIG_DIR="$CONFIG_DIR" bash "$SCRIPT" | wc -l | tr -d ' ')"

echo
echo "$pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
