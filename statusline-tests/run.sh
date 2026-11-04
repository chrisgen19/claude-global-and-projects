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
#   - no \" inside a $(...) that is itself in double quotes: bash 3.2 parses
#     that nesting differently and the payload reaches jq mangled. Assign
#     got=$(...) first, unquoted, then pass "$got"
#
# Every git state gets its own directory, so each render is a cache miss and
# the suite never has to clear the cache. That matters: the cache lives in
# /tmp keyed by uid, so globbing it away would delete the entries belonging to
# the developer's real sessions.

set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd) || exit 1
SCRIPT="$REPO_ROOT/statusline.sh"
ESC=$(printf '\033')

# The script runs under the same bash as this suite. A bare `bash "$SCRIPT"`
# resolved through PATH, so `/bin/bash ./statusline-tests/run.sh` ran the suite
# under 3.2 but the script under whatever bash came first on PATH (Homebrew's
# 5.x on a Mac that has it), and a 3.2-only bug such as the signed byte in
# urlenc_path passed. $BASH is the binary running this file.
RUN_BASH="$BASH"

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
  printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi
}

# seg <dir> [extra-json] -- line 1 from the model tag onwards
seg() {
  render "$1" "${2:-}" | sed -n '1p' | sed 's/^.*\[M\] *//'
}

# raw <dir> [extra-json] -- full output with every escape kept, for asserting on
# colours and OSC 8 links. Extra environment (TZ, HOME) passes through.
raw() {
  local dir="$1" extra="${2:-}" payload
  payload=$(jq -nc --arg d "$dir" --argjson x "{${extra}}" \
    '{workspace:{current_dir:$d},model:{display_name:"M"},cost:{},context_window:{used_percentage:40}} * $x')
  printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT"
}

# line2 <dir> [extra-json] -- line 2, colours stripped
line2() {
  render "$1" "${2:-}" | sed -n '2p'
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
echo "  bash:   $BASH_VERSION ($RUN_BASH, for the suite and the script)"
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
    | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$copy" | strip_ansi | sed -n '1p')
  contains "claude-$acct renders the $expected label" "$expected" "$out"
done

# The router passes this when a session is not under a named account dir, so
# the line never claims to be an account it is not.
out=$(printf '%s' \
  "$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"M"},cost:{},context_window:{used_percentage:1}}')" \
  | ACCOUNT_LABEL_OVERRIDE=CLAUDE CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p')
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
  | CLAUDE_CONFIG_DIR="$acct_dir" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p')
contains "the account username is shown in parens" "(someone)" "$out"
excludes "the domain is stripped" "example.com" "$out"

# Truncated mid-write: jq exits 2 with no output at all on a bad --slurpfile,
# so without the fallback this blanks the model, the directory and everything
# else, not just the email.
printf '{"oauthAccount":{"emailAddress":"someone@example.' > "$acct_dir/.claude.json"
out=$(printf '%s' \
  "$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"MODELNAME"},cost:{},context_window:{used_percentage:1}}')" \
  | CLAUDE_CONFIG_DIR="$acct_dir" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p')
contains "a corrupt .claude.json still renders the rest of the line" "MODELNAME" "$out"
excludes "a corrupt .claude.json shows no account" "(" "$out"

# No .claude.json at all: --slurpfile on a missing path is a hard jq error, so
# the script has to substitute /dev/null rather than pass the path through.
rm -f "$acct_dir/.claude.json"
out=$(printf '%s' \
  "$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"MODELNAME"},cost:{},context_window:{used_percentage:1}}')" \
  | CLAUDE_CONFIG_DIR="$acct_dir" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p')
contains "an absent .claude.json still renders the line" "MODELNAME" "$out"
rm -rf "$acct_dir"

echo "-- the git identity --"
# Read from git config so an includeIf per directory is respected, which is why
# it is resolved per cwd rather than once per session.
contains "the git email username is shown" "t@e.com" \
  "$(git -C "$FIX/sync" config user.email)"
contains "the git email username appears on the line" "t" \
  "$(render "$FIX/sync" | sed -n '1p')"

echo "-- cache key collisions --"
# The cache file name mangles / to _, so a/b and a_b share one slot. Rendered
# back to back (well inside the 10s window), the second must not be served the
# first one's branch or git identity. The branches and emails differ so either
# kind of leak shows up.
newrepo "$FIX/col/a/b" col-slash-branch || exit 1
git -C "$FIX/col/a/b" config user.email slashuser@e.com
newrepo "$FIX/col/a_b" col-under-branch || exit 1
git -C "$FIX/col/a_b" config user.email underuser@e.com
first=$(render "$FIX/col/a/b" | sed -n '1p')
second=$(render "$FIX/col/a_b" | sed -n '1p')
contains "a/b shows its own branch" "col-slash-branch" "$first"
contains "a_b, rendered next, shows its own branch" "col-under-branch" "$second"
excludes "a_b is not served the a/b branch from the cache" "col-slash-branch" "$second"
contains "a_b shows its own git identity" "underuser" "$second"
excludes "a_b is not served the a/b git identity from the cache" "slashuser" "$second"
# And back again: the slot now holds a_b's entry, which a/b must not take.
again=$(render "$FIX/col/a/b" | sed -n '1p')
contains "a/b after a_b still shows its own branch" "col-slash-branch" "$again"
excludes "a/b after a_b is not served the a_b identity" "underuser" "$again"

echo "-- malformed and absent payload fields --"
# The script is fed whatever Claude Code sends; a missing field must not make
# it print an error or die mid-line.
equals "empty object payload still renders two lines" \
  "1" "$(printf '{}' | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | wc -l | tr -d ' ')"
contains "absent model falls back to ?" "[?]" \
  "$(printf '{}' | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p')"
equals "non-numeric context percentage does not break the bar" \
  "1" "$(printf '{"context_window":{"used_percentage":"oops"}}' \
    | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | wc -l | tr -d ' ')"
equals "non-JSON input still renders two lines" \
  "1" "$(printf 'not json at all' | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | wc -l | tr -d ' ')"

# A wrong-typed number used to abort the whole jq pass, so one bad field cost
# the model, the directory and everything else on the line.
contains "a non-numeric context percentage keeps the rest of the line" "[MODELNAME]" \
  "$(printf '{"model":{"display_name":"MODELNAME"},"context_window":{"used_percentage":"oops"}}' \
    | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p')"
contains "a non-numeric rate limit keeps the rest of the line" "[MODELNAME]" \
  "$(printf '{"model":{"display_name":"MODELNAME"},"rate_limits":{"five_hour":{"used_percentage":"x"}}}' \
    | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p')"
contains "a tiny cost in exponent form still formats" '$0.00' \
  "$(printf '{"cost":{"total_cost_usd":1e-7}}' \
    | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi)"

echo "-- nothing on stderr --"
# Claude Code shows only stdout, so stderr noise is invisible in normal use and
# easy to regress. Every assertion above discards it, which is how the
# `printf: : invalid number` on an empty cost went unnoticed. Each payload here
# must render with stderr completely empty, good input and bad alike.
# stderr_of <label> <payload>
stderr_of() {
  local err
  err=$(printf '%s' "$2" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" 2>&1 > /dev/null)
  equals "no stderr: $1" "" "$err"
}
stderr_of "an ordinary render in a repo" \
  "$(jq -nc --arg d "$FIX/sync" '{workspace:{current_dir:$d},model:{display_name:"M"},cost:{total_cost_usd:0.42},context_window:{used_percentage:40}}')"
stderr_of "an ordinary render outside a repo" \
  "$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"M"},cost:{},context_window:{used_percentage:40}}')"
stderr_of "an empty object payload"                '{}'
stderr_of "non-JSON input"                         'not json at all'
stderr_of "a non-numeric context percentage"       '{"context_window":{"used_percentage":"oops"}}'
stderr_of "a non-numeric cost"                     '{"cost":{"total_cost_usd":"x"}}'
stderr_of "a non-numeric rate limit"               '{"rate_limits":{"five_hour":{"used_percentage":"x"}}}'
stderr_of "a model given as a string"              '{"model":"x"}'
stderr_of "a tiny cost in exponent form"           '{"cost":{"total_cost_usd":1e-7}}'

# ---------------------------------------------------------------------------
echo "-- wrongly shaped payload fields --"
# One jq error used to abort the whole field pass, so a single field arriving
# in an unexpected shape (an object that became a string, a number, an array)
# blanked the model, the directory, git and everything else. Each shape below
# is merged over a good payload, so the assertion is that the fields it does
# NOT touch still render, and that nothing reaches stderr.
#
# shape_ok <label> <shape-json> <needle-that-must-survive>
shape_ok() {
  local payload out err
  payload=$(jq -nc --arg d "$FIX/plain" --argjson x "$2" \
    '{workspace:{current_dir:$d},model:{display_name:"MODELNAME"},cost:{total_cost_usd:0.42},context_window:{used_percentage:40}} * $x')
  out=$(printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi)
  err=$(printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" 2>&1 > /dev/null)
  contains "$1: the rest of the line survives" "$3" "$out"
  equals "$1: nothing on stderr" "" "$err"
}
# The untouched model name is the canary, except where the shape replaces the
# model itself; there the directory is.
shape_ok "model as a string"            '{"model":"x"}'                          "plain"
shape_ok "model name as an object"      '{"model":{"display_name":{"a":1}}}'     "plain"
shape_ok "workspace as a string"        '{"workspace":"x"}'                      "[MODELNAME]"
shape_ok "cost as a string"             '{"cost":"free"}'                        "[MODELNAME]"
shape_ok "cost as a number"             '{"cost":5}'                             "[MODELNAME]"
shape_ok "cost total as an array"       '{"cost":{"total_cost_usd":[1]}}'        "[MODELNAME]"
shape_ok "context_window as a string"   '{"context_window":"big"}'               "[MODELNAME]"
shape_ok "effort as a string"           '{"effort":"high"}'                      "[MODELNAME]"
shape_ok "thinking as a boolean"        '{"thinking":true}'                      "[MODELNAME]"
shape_ok "pr as a number"               '{"pr":42}'                              "[MODELNAME]"
shape_ok "a rate limit window as a string" '{"rate_limits":{"five_hour":"x"}}'   "[MODELNAME]"
shape_ok "rate_limits as an array"      '{"rate_limits":[1]}'                    "[MODELNAME]"

# A root that is not an object at all used to fail before any field was read.
# There is nothing to keep, so the line must just render cleanly with defaults.
for root in '[]' '"str"' 'null'; do
  equals "root $root still renders two lines" \
    "1" "$(printf '%s' "$root" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | wc -l | tr -d ' ')"
  contains "root $root falls back to the ? model" "[?]" \
    "$(printf '%s' "$root" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p')"
  stderr_of "root $root" "$root"
done

# A wrongly shaped account file is a payload of its own: oauthAccount as a
# string used to fail the pass and fall back to the second jq run. Now it
# costs only the email, on the first pass.
acct_dir=$(mktemp -d) || exit 1
printf '{"oauthAccount":"x"}' > "$acct_dir/.claude.json"
out=$(printf '{"model":{"display_name":"MODELNAME"}}' | CLAUDE_CONFIG_DIR="$acct_dir" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p')
contains "oauthAccount as a string keeps the line" "[MODELNAME]" "$out"
excludes "oauthAccount as a string shows no account" "(" "$out"
rm -rf "$acct_dir"

# ---------------------------------------------------------------------------
echo "-- newlines inside values --"
# Fields are passed one per line and read back by position, so a real newline
# in any value shifted every field after it: a model name holding one pushed
# its second half into the cwd slot. jq builds the payload, so "\n" here is a
# real LF on the wire, which is the case that matters (the #81 tests cover a
# literal backslash-n).
nl_payload=$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"top\nbottom"},cost:{},context_window:{used_percentage:40}}')
out=$(printf '%s' "$nl_payload" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi)
contains "a newline in the model name is flattened to a space" "[top bottom]" "$out"
contains "a newline in the model name does not shift the cwd" "plain" "$(printf '%s\n' "$out" | sed -n '1p')"
equals "a newline in the model name cannot add a third line" \
  "1" "$(printf '%s' "$nl_payload" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | wc -l | tr -d ' ')"
cr_payload=$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"top\r\nbottom"},cost:{},context_window:{used_percentage:40}}')
contains "a CRLF in the model name is flattened too" "plain" \
  "$(printf '%s' "$cr_payload" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p')"

# ---------------------------------------------------------------------------
# The segments below were added in #88. Times are relative to `now`, and every
# expected value is chosen so that the script reading the clock a second later
# than this suite does not change it: a projection that lands on a boundary
# would make the suite flaky.
now=$(date +%s)
RED="${ESC}[31m"; YELLOW="${ESC}[33m"; GREEN="${ESC}[32m"; DIM="${ESC}[2m"; RST="${ESC}[0m"

# ---------------------------------------------------------------------------
echo "-- usage pace --"
# 40% used one hour into a 5h window projects to 200%: red, with the
# projection shown. Over 100 means the limit runs out before the reset.
got=$(raw "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":40,\"resets_at\":$((now + 14400))}}")
contains "5h on course to run out is red" "${RED}40%" "$got"
contains "5h on course to run out shows the projection" "→" "$(printf '%s' "$got" | strip_ansi)"
# 60% at day 4.5 of 7 projects to 93%: amber, from 90.
got=$(raw "$FIX/plain" "\"rate_limits\":{\"seven_day\":{\"used_percentage\":60,\"resets_at\":$((now + 216000))}}")
contains "7d heading for 93% is yellow" "${YELLOW}60%" "$got"
contains "7d heading for 93% shows it" "→93%" "$(printf '%s' "$got" | strip_ansi)"
# 40% with 30 minutes left projects to 44%: on track, no marker.
got=$(raw "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":40,\"resets_at\":$((now + 1800))}}")
contains "5h on track stays green" "${GREEN}40%" "$got"
excludes "5h on track shows no projection" "→" "$(printf '%s' "$got" | strip_ansi)"
# Below 10% a projection is noise (3% five minutes in "projects" 180%).
# The positive check first, so a payload that failed to parse cannot pass the
# exclusion by rendering no window at all.
got=$(line2 "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$((now + 17700))}}")
contains "under 10% used still shows the window" "5h 5%" "$got"
excludes "under 10% used grades no pace" "→" "$got"
# Pace never lowers the threshold colour: a minute before the reset, 95%
# projects to 95% (a yellow pace grade), and the percent stays red.
got=$(raw "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":95,\"resets_at\":$((now + 60))}}")
contains "pace never lowers a red threshold" "${RED}95%" "$got"

# ---------------------------------------------------------------------------
echo "-- prompt cache --"
# caching_observed false means caching is off or unreported. hit_ratio is a
# real 0 then, and `hit 0%` would read as a cache doing badly.
got=$(line2 "$FIX/plain" '"prompt_cache":{"warm":false,"caching_observed":false,"hit_ratio":0}')
excludes "unobserved caching shows no cache segment" "cache" "$got"
excludes "unobserved caching shows no hit rate" "hit" "$got"
got=$(line2 "$FIX/plain" '"prompt_cache":{"warm":false,"caching_observed":true,"hit_ratio":0.937}')
contains "observed but not warm reads cold" "cache cold" "$got"
contains "hit ratio is rounded to a percent" "hit 94%" "$got"
# The expiry is a local clock time. POSIX TZ strings need no tzdata, so the
# expected HH:MM is plain arithmetic on any machine. ABC-8 is UTC+8 and ABC+5
# is UTC-5: both signs of the %z parse.
exp=$((now + 1800))
for tzcase in "UTC0 0" "ABC-8 28800" "ABC+5 -18000"; do
  tz="${tzcase% *}"; off="${tzcase#* }"
  l=$(( ((exp + off) % 86400 + 86400) % 86400 ))
  want=$(printf '%02d:%02d' $((l / 3600)) $(((l % 3600) / 60)))
  got=$(TZ="$tz" raw "$FIX/plain" "\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"ttl\":\"1h\",\"expires_at\":$exp}" | strip_ansi | sed -n '2p')
  contains "expiry as local time under TZ=$tz" "cache $want" "$got"
done
got=$(raw "$FIX/plain" "\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"ttl\":\"1h\",\"expires_at\":$((now + 1800))}")
contains "warm cache well before expiry is green" "${DIM}cache${RST} ${GREEN}" "$got"
# Last fifth of a 5m TTL, floored at a minute: 30s left is inside it.
got=$(raw "$FIX/plain" "\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"ttl\":\"5m\",\"expires_at\":$((now + 30))}")
contains "cache about to expire is yellow" "${DIM}cache${RST} ${YELLOW}" "$got"
got=$(line2 "$FIX/plain" "\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"ttl\":\"5m\",\"expires_at\":$((now - 10))}")
contains "an expiry already passed reads cold" "cache cold" "$got"

# ---------------------------------------------------------------------------
echo "-- spend limit --"
got=$(line2 "$FIX/plain" "\"rate_limits\":{\"spend_limit\":{\"used_percentage\":104,\"resets_at\":$((now + 1728000)),\"used_usd\":520.4,\"limit_usd\":500,\"period\":\"monthly\"}}")
contains "spend over the limit shows its percent" "spend 104%" "$got"
contains "spend shows used over limit in whole dollars" '$520/$500' "$got"
# Months run 28 to 31 days, so a monthly period grades no pace.
excludes "a monthly period grades no pace" "→" "$got"
got=$(raw "$FIX/plain" "\"rate_limits\":{\"spend_limit\":{\"used_percentage\":104,\"resets_at\":$((now + 1728000)),\"period\":\"monthly\"}}")
contains "spend over the limit is red" "${RED}104%" "$got"
# 50% three days into a week projects to 116%.
got=$(line2 "$FIX/plain" "\"rate_limits\":{\"spend_limit\":{\"used_percentage\":50,\"resets_at\":$((now + 345600)),\"period\":\"weekly\"}}")
contains "a weekly period grades pace" "→116%" "$got"
# The dollar amounts arrive up to five minutes after the percentage.
got=$(line2 "$FIX/plain" "\"rate_limits\":{\"spend_limit\":{\"used_percentage\":50,\"resets_at\":$((now + 345600))}}")
contains "spend without dollars still shows its percent" "spend 50%" "$got"
excludes "spend without dollars shows no amounts" '/$' "$got"
excludes "a wrongly typed spend limit is dropped" "spend" \
  "$(line2 "$FIX/plain" '"rate_limits":{"spend_limit":{"used_percentage":"x","used_usd":"lots","limit_usd":[1]}}')"

# ---------------------------------------------------------------------------
echo "-- token breakdown --"
contains "breakdown shows from 85%" "91% (in: 12k, cache: 170k)" \
  "$(line2 "$FIX/plain" '"context_window":{"context_window_size":200000,"used_percentage":91,"current_usage":{"input_tokens":12345,"cache_creation_input_tokens":3000,"cache_read_input_tokens":167000}}')"
excludes "no breakdown below 85%" "(in:" \
  "$(line2 "$FIX/plain" '"context_window":{"context_window_size":200000,"used_percentage":84,"current_usage":{"input_tokens":5000,"cache_read_input_tokens":160000}}')"
contains "a million or more reads as M" "(in: 150k, cache: 1.6M)" \
  "$(line2 "$FIX/plain" '"context_window":{"context_window_size":2000000,"used_percentage":90,"current_usage":{"input_tokens":150000,"cache_read_input_tokens":1650000}}')"
# After /compact current_usage is null: nothing to break down.
excludes "no breakdown without current_usage" "(in:" \
  "$(line2 "$FIX/plain" '"context_window":{"context_window_size":200000,"used_percentage":91,"current_usage":null}')"

# ---------------------------------------------------------------------------
echo "-- OSC 8 links --"
# $FIX/sync tracks origin/main, $FIX/unpushed has a remote but no upstream.
gh_repo='"workspace":{"repo":{"host":"github.com","owner":"acme","name":"widgets"}}'
contains "a tracking branch links to its github page" \
  "${ESC}]8;;https://github.com/acme/widgets/tree/main${ESC}\\" "$(raw "$FIX/sync" "$gh_repo")"
contains "a nested gitlab owner keeps its path" \
  "${ESC}]8;;https://gitlab.com/grp/sub/proj/-/tree/main${ESC}\\" \
  "$(raw "$FIX/sync" '"workspace":{"repo":{"host":"gitlab.com","owner":"grp/sub","name":"proj"}}')"
excludes "an unknown host gets no branch link" "${ESC}]8;;" \
  "$(raw "$FIX/sync" '"workspace":{"repo":{"host":"bitbucket.org","owner":"acme","name":"widgets"}}')"
excludes "an owner with a space gets no branch link" "${ESC}]8;;" \
  "$(raw "$FIX/sync" '"workspace":{"repo":{"host":"github.com","owner":"a b","name":"widgets"}}')"
excludes "a branch with no upstream gets no link (it would 404)" "${ESC}]8;;" \
  "$(raw "$FIX/unpushed" "$gh_repo")"
# A non-ASCII byte and a # in the name: percent-encoded byte by byte, with the
# & 255 mask that keeps bash 3.2 from printing %FFFFFFFFFFFFFFC3.
enc_branch=$(printf 'feat/\303\274#x')
newrepo "$FIX/enc" "$enc_branch" || exit 1
git init -q --bare "$FIX/bare-enc"
git -C "$FIX/enc" remote add origin "$FIX/bare-enc"
git -C "$FIX/enc" push -q -u origin "$enc_branch"
contains "a branch name is percent-encoded byte by byte" \
  "tree/feat/%C3%BC%23x${ESC}\\" "$(raw "$FIX/enc" "$gh_repo")"
pr_link='"pr":{"number":42,"url":"https://github.com/acme/widgets/pull/42"}'
contains "the PR number links to pr.url" \
  "${ESC}]8;;https://github.com/acme/widgets/pull/42${ESC}\\" "$(raw "$FIX/plain" "$pr_link")"
got=$(raw "$FIX/plain" '"pr":{"number":42,"url":"javascript:alert(1)"}')
excludes "a non-https pr.url is not linked" "${ESC}]8;;" "$got"
contains "a non-https pr.url still shows the number" "#42" "$(printf '%s' "$got" | strip_ansi)"
# An ST and a second OSC 8 smuggled into the URL: clean() strips the ESC and
# BEL bytes, so the link cannot be closed early or retargeted.
got=$(raw "$FIX/plain" '"pr":{"number":8,"url":"https://x.io/\u001b\\\u001b]8;;https://evil\u0007"}')
excludes "a smuggled link target is stripped" "evil" "$got"
contains "the PR link keeps only the clean prefix" "${ESC}]8;;https://x.io/${ESC}\\" "$got"

# ---------------------------------------------------------------------------
echo "-- PR review state --"
for rs in "approved approved" "changes_requested changes" "pending pending" "draft draft"; do
  got=$(seg "$FIX/plain" "\"pr\":{\"number\":42,\"review_state\":\"${rs% *}\"}")
  contains "review state ${rs% *}" "#42 ${rs#* }" "$got"
done
got=$(seg "$FIX/plain" '"pr":{"number":42}')
excludes "an absent review state adds nothing" "#42 " "$got"
excludes "an unknown review state is not printed" "merged" \
  "$(seg "$FIX/plain" '"pr":{"number":42,"review_state":"merged"}')"
excludes "a wrongly typed review state is dropped" "{" \
  "$(seg "$FIX/plain" '"pr":{"number":42,"review_state":{"a":1}}')"

# ---------------------------------------------------------------------------
echo "-- session name and worktree --"
contains "the session name is shown" "fix login flow" "$(seg "$FIX/plain" '"session_name":"fix login flow"')"
got=$(seg "$FIX/plain" '"session_name":"abcdefghijklmnopqrstuvwxyz0123456789"')
contains "a long session name is cut to 29 characters and an ellipsis" "abcdefghijklmnopqrstuvwxyz012…" "$got"
excludes "a long session name does not run on" "3456789" "$got"
excludes "a wrongly typed session name is dropped" "{" "$(seg "$FIX/plain" '"session_name":{"a":1}')"
contains "worktree.name is shown" "wt:feat-x" "$(seg "$FIX/plain" '"worktree":{"name":"feat-x"}')"
contains "a git_worktree path shows its last segment" "wt:fix-y" \
  "$(seg "$FIX/plain" '"workspace":{"git_worktree":"/a/b/.worktrees/fix-y"}')"
excludes "a wrongly typed worktree is dropped" "wt:" "$(seg "$FIX/plain" '"worktree":[1]')"

# ---------------------------------------------------------------------------
echo "-- sanitising payload strings --"
# clean() in the jq pass: a raw ESC printed with %s still reaches the terminal,
# so sequences, controls and bidi marks are stripped before anything renders.
got=$(raw "$FIX/plain" '"session_name":"a\u001b[31mred"')
excludes "a CSI sequence in a value is stripped" "${ESC}[31mred" "$got"
contains "the text around a CSI sequence survives" "ared" "$(printf '%s' "$got" | strip_ansi)"
got=$(raw "$FIX/plain" '"session_name":"a\u001b]8;;https://evil\u0007b"')
excludes "an OSC 8 link in a value is stripped" "evil" "$got"
contains "the text around an OSC sequence survives" "ab" "$(printf '%s' "$got" | strip_ansi)"
rlo=$(printf '\342\200\256')
got=$(raw "$FIX/plain" '"session_name":"x‮y"')
excludes "a right-to-left override is stripped" "$rlo" "$got"
contains "the text around a bidi mark survives" "xy" "$(printf '%s' "$got" | strip_ansi)"
bel=$(printf '\007')
got=$(raw "$FIX/plain" '"session_name":"p\u0007q\tr"')
excludes "a BEL in a value is stripped" "$bel" "$got"
contains "a BEL and a tab are removed, not spaced" "pqr" "$(printf '%s' "$got" | strip_ansi)"
got=$(raw "$FIX/plain" '"model":{"display_name":"M\u001b[2J"}')
excludes "a sequence in the model name is stripped too" "${ESC}[2J" "$got"

# ---------------------------------------------------------------------------
echo "-- home directory --"
# ${cwd/#$HOME/\~} kept the backslash under bash 3.2 and rendered \~, and it
# also matched a sibling such as /h/me-old as ~-old. The fake home sits under
# $FIX so the cache entries these renders write are cleaned up on exit.
home_line() {
  jq -nc --arg d "$1" '{workspace:{current_dir:$d},model:{display_name:"M"}}' \
    | HOME="$FIX/me" CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p' | sed 's/^.*\[M\] *//'
}
equals "the home directory is ~" "~" "$(home_line "$FIX/me")"
# The literal ~/p is the expected text, not a path to expand, so SC2088's
# "tilde does not expand in quotes" is exactly the behaviour wanted here.
# shellcheck disable=SC2088
equals "a path under home starts with ~/" "~/p" "$(home_line "$FIX/me/p")"
# How an unshortened sibling renders depends on the fixture path's length:
# the full path when it fits in 30 characters (/tmp/tmp.X on Linux), its last
# segment when it does not (/var/folders on macOS). Either way it must end in
# me-old and carry no tilde; the old bug rendered ~-old.
got=$(home_line "$FIX/me-old")
contains "a sibling of home keeps its own name" "me-old" "$got"
excludes "a sibling of home is not shortened to ~-old" "~" "$got"

# ---------------------------------------------------------------------------
echo "-- new segments: nothing on stderr --"
full=$(jq -nc --arg d "$FIX/sync" --argjson n "$now" '{
  workspace:{current_dir:$d,repo:{host:"github.com",owner:"acme",name:"widgets"}},
  model:{display_name:"M"}, session_name:"s", worktree:{name:"w"},
  pr:{number:1,url:"https://github.com/acme/widgets/pull/1",review_state:"approved"},
  context_window:{context_window_size:200000,used_percentage:91,current_usage:{input_tokens:1,cache_read_input_tokens:2}},
  rate_limits:{five_hour:{used_percentage:40,resets_at:($n+14400)},spend_limit:{used_percentage:50,resets_at:($n+345600),used_usd:1,limit_usd:2,period:"weekly"}},
  prompt_cache:{warm:true,caching_observed:true,ttl:"5m",expires_at:($n+30),hit_ratio:0.5}}')
err=$(printf '%s' "$full" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" 2>&1 > /dev/null)
equals "no stderr: every new segment at once" "" "$err"
equals "every new segment at once is still two lines" \
  "1" "$(printf '%s' "$full" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | wc -l | tr -d ' ')"

echo
echo "$pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
