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

# Every render scans listening sockets afresh and leaves the shared dev
# listener cache alone (a max age of 0 neither reads nor writes it). Set for
# the whole suite: a render from an earlier section reading a listener list
# from a previous run looked up dead fixture pids.
export CLAUDE_STATUSLINE_DEV_MAX_AGE=0

# Existing colour assertions use the 8-colour codes; new sections set their own.
export STATUSLINE_PALETTE=ansi STATUSLINE_GLYPHS=unicode
STATE=$(mktemp -d) || exit 1
export CLAUDE_STATUSLINE_STATE_DIR="$STATE"

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
SERVER_PIDS=""
cleanup() {
  # Fixture dev servers first, then the per-pid cwd cache entries the script
  # wrote for them. Only this run's pids: the cache is shared with the
  # developer's real sessions.
  # The wait reaps each one, so bash does not print a "Terminated: 15" job
  # report for every fixture server on the way out.
  local p
  for p in $SERVER_PIDS; do
    kill "$p" 2>/dev/null
    wait "$p" 2>/dev/null
    rm -f /tmp/claude-statusline-devcwd-"${UID}"-"$p"
  done
  rm -rf "$FIX" "$CONFIG_DIR" "$STATE"
  # The variables stay quoted and only the * are bare, so the pattern expands
  # without word-splitting the path. With no match bash passes the pattern
  # through literally and `rm -f` ignores it.
  local k="${FIX//\//_}"
  rm -f /tmp/claude-statusline-git-*-"${UID}"-"${k//[^A-Za-z0-9_.-]/_}"*
}
trap cleanup EXIT

strip_ansi() { sed "s/${ESC}\\[[0-9;]*m//g"; }
# Also drops OSC 8 link wrappers (ESC ] 8 ;; URL ESC \), for asserting on the
# visible text alone: with them in place a linked port appears twice, once in
# the URL and once in the label.
strip_links() { strip_ansi | sed "s/${ESC}]8;;[^${ESC}]*${ESC}\\\\//g"; }

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

# devseg <dir> [extra-json] -- line 3 (the dev servers), colours stripped
devseg() {
  render "$1" "${2:-}" | sed -n '3p'
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
contains "tracking branch in sync names the branch" "⎇ main" "$got"
contains "branch after a divider" " │ ⎇ main" "$(render "$FIX/sync" | sed -n 1p)"
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
excludes "a non-repo shows no branch icon" "⎇" "$got"

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

# The label colour follows the palette: 24-bit Catppuccin by default, the
# 8-colour codes under ansi. Line 15 only decides the current account's colour
# under catppuccin; the override label is neutral text in both palettes.
for spec in "personal:PERSONAL:137;220;235:36" "work:WORK:249;226;175:33" "dev:DEV:166;227;161:32"; do
  IFS=: read -r acct label rgb ansi <<EOF_SPEC
$spec
EOF_SPEC
  copy="$REPO_ROOT/claude-$acct/statusline.sh"
  payload=$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"M"},cost:{},context_window:{used_percentage:1}}')
  out=$(printf '%s' "$payload" | STATUSLINE_PALETTE=catppuccin CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$copy" | sed -n '1p')
  contains "claude-$acct label is 24-bit under catppuccin" "${ESC}[38;2;${rgb}m${label}" "$out"
  out=$(printf '%s' "$payload" | STATUSLINE_PALETTE=ansi CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$copy" | sed -n '1p')
  contains "claude-$acct label is 8-colour under ansi" "${ESC}[${ansi}m${label}" "$out"
done
out=$(printf '%s' "$payload" \
  | STATUSLINE_PALETTE=catppuccin ACCOUNT_LABEL_OVERRIDE=CLAUDE CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | sed -n '1p')
contains "override label is neutral text under catppuccin" "${ESC}[38;2;205;214;244mCLAUDE" "$out"

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
# eta_want <epoch> -- the local HH:MM for an epoch under TZ=UTC0, as plain
# arithmetic. The script may read the clock a second after the suite, which
# moves a projected ETA by up to a minute, so callers accept epoch and epoch+60.
eta_want() {
  local e l
  for e in "$1" "$(($1 + 60))"; do
    l=$(( e % 86400 ))
    printf '%02d:%02d\n' $((l / 3600)) $(((l % 3600) / 60))
  done
}
# eta_has <name> <epoch> <output> -- passes when "out HH:MM" holds for either
eta_has() {
  local w1 w2
  { read -r w1; read -r w2; } < <(eta_want "$2")
  if [ "${3#*"out $w1"}" != "$3" ] || [ "${3#*"out $w2"}" != "$3" ]; then
    ok "$1"
  else
    bad "$1"
    printf '        want out %s or out %s\n        got: %s\n' "$w1" "$w2" "$3"
  fi
}
# 40% used one hour into a 5h window: 20% of the window elapsed, so 20 points
# ahead of the clock. The projection is 200%: red, and it runs out after 90
# more minutes (now + 5400).
got=$(raw "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":40,\"resets_at\":$((now + 14400))}}")
contains "5h on course to run out is red" "${RED}40%" "$got"
got=$(TZ=UTC0 line2 "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":40,\"resets_at\":$((now + 14400))}}")
contains "5h ahead of the clock" "5h 40% ⇡20%" "$got"
eta_has "5h run-out time is local" $((now + 5400)) "$got"
# 60% at day 4.5 of 7: 64% elapsed, 4 points behind; projects to 93%: amber
# from 90, but under 100 so no ETA.
got=$(raw "$FIX/plain" "\"rate_limits\":{\"seven_day\":{\"used_percentage\":60,\"resets_at\":$((now + 216000))}}")
contains "7d heading for 93% is yellow" "${YELLOW}60%" "$got"
plain_got=$(printf '%s' "$got" | strip_ansi)
contains "7d heading for 93% is behind the clock" "7d 60% ⇣4%" "$plain_got"
excludes "7d heading for 93% shows no ETA" "out " "$plain_got"
# 40% with 30 minutes left: 90% elapsed, 50 points behind.
got=$(raw "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":40,\"resets_at\":$((now + 1800))}}")
contains "5h on track stays green" "${GREEN}40%" "$got"
excludes "5h on track shows no ETA" "out " "$(printf '%s' "$got" | strip_ansi)"
# 24% with 3h12m left: 36% elapsed, 12 points behind, no ETA.
got=$(line2 "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":24,\"resets_at\":$((now + 11520))}}")
contains "behind the clock" "5h 24% ⇣12%" "$got"
excludes "behind the clock shows no ETA" "out " "$got"
# Below 10% a projection is noise (3% five minutes in "projects" 180%).
# The positive check first, so a payload that failed to parse cannot pass the
# exclusion by rendering no window at all.
got=$(line2 "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":5,\"resets_at\":$((now + 17700))}}")
contains "under 10% used still shows the window" "5h 5%" "$got"
excludes "under 10% used shows no pace marker" "⇡" "$got"
excludes "under 10% used shows no behind marker" "⇣" "$got"
excludes "under 10% used shows no ETA" "out " "$got"
# Pace never lowers the threshold colour: a minute before the reset, 95%
# projects to 95% (a yellow pace grade), and the percent stays red.
got=$(raw "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":95,\"resets_at\":$((now + 60))}}")
contains "pace never lowers a red threshold" "${RED}95%" "$got"
# The projection equals the percent, so there is no run-out to announce.
contains "a projection equal to the percent still shows the window" "5h 95%" "$(printf '%s' "$got" | strip_ansi)"
excludes "a projection equal to the percent shows no ETA" "out " "$(printf '%s' "$got" | strip_ansi)"
# 90% four hours into 5h: 80% elapsed, 10 ahead, projects to 112%, so it runs
# out 1600s from now.
got=$(TZ=UTC0 line2 "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":90,\"resets_at\":$((now + 3600))}}")
contains "a high percent still climbing is ahead" "5h 90% ⇡10%" "$got"
eta_has "a high percent still climbing shows its run-out" $((now + 1600)) "$got"
# 7d 70% with 3d left: 4d elapsed, runs out 148114s from now, more than 24h
# away, so the weekday comes first. 1970-01-01 was a Thursday.
got=$(TZ=UTC0 line2 "$FIX/plain" "\"rate_limits\":{\"seven_day\":{\"used_percentage\":70,\"resets_at\":$((now + 259200))}}")
contains "7d ahead of the clock" "7d 70% ⇡13%" "$got"
dnames=(Sun Mon Tue Wed Thu Fri Sat)
_e=$((now + 148114))
want_day=${dnames[$(( (_e / 86400 + 4) % 7 ))]}
_e1=$((now + 148114 + 60))
want_day1=${dnames[$(( (_e1 / 86400 + 4) % 7 ))]}
case "$got" in *"out $want_day "*|*"out $want_day1 "*) ok "an ETA over 24h away carries the weekday" ;; *) bad "an ETA over 24h away carries the weekday"; printf '        got: %s\n' "$got" ;; esac
# On pace exactly: no marker sign beyond +-0.
got=$(line2 "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":50,\"resets_at\":$((now + 9000))}}")
contains "on pace reads plus-minus zero" "5h 50% ±0%" "$got"

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
excludes "a monthly period shows no pace marker" "⇡" "$got"
excludes "a monthly period shows no ETA" "out " "$got"
got=$(raw "$FIX/plain" "\"rate_limits\":{\"spend_limit\":{\"used_percentage\":104,\"resets_at\":$((now + 1728000)),\"period\":\"monthly\"}}")
contains "spend over the limit is red" "${RED}104%" "$got"
# 50% three days into a week: 42% elapsed, 8 points ahead, projects to 116%.
got=$(line2 "$FIX/plain" "\"rate_limits\":{\"spend_limit\":{\"used_percentage\":50,\"resets_at\":$((now + 345600)),\"period\":\"weekly\"}}")
contains "a weekly period grades pace" "spend 50% ⇡8%" "$got"
contains "a weekly period shows its run-out" "out " "$got"
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
# workspace.repo always describes origin, so only a branch whose upstream is on
# origin can be linked, and the page is the upstream branch, not the local name.
newrepo "$FIX/forked" || exit 1
git init -q --bare "$FIX/bare-forked-origin"; git init -q --bare "$FIX/bare-forked-fork"
git -C "$FIX/forked" remote add origin "$FIX/bare-forked-origin"
git -C "$FIX/forked" remote add fork "$FIX/bare-forked-fork"
git -C "$FIX/forked" push -q -u origin main
git -C "$FIX/forked" switch -q -c feature
git -C "$FIX/forked" push -q -u fork feature
got=$(raw "$FIX/forked" "$gh_repo")
contains "a branch tracking a fork still shows its name" "feature" "$(printf '%s' "$got" | strip_ansi)"
excludes "a branch tracking a fork gets no origin link (it may 404)" "${ESC}]8;;" "$got"
# A local name that differs from the origin branch it tracks.
cp -R "$FIX/sync" "$FIX/renamed" || exit 1
git -C "$FIX/renamed" switch -q -c local-name
git -C "$FIX/renamed" branch -q --set-upstream-to=origin/main
got=$(raw "$FIX/renamed" "$gh_repo")
contains "a renamed branch links its upstream branch" \
  "${ESC}]8;;https://github.com/acme/widgets/tree/main${ESC}\\" "$got"
excludes "a renamed branch does not link its local name" "tree/local-name" "$got"
# Its commit may never have been pushed, so a detached HEAD is not linked.
got=$(raw "$FIX/detached" "$gh_repo")
oid=$(git -C "$FIX/detached" rev-parse HEAD)
contains "a detached HEAD still shows its short oid" "${oid%"${oid#???????}"}" "$(printf '%s' "$got" | strip_ansi)"
excludes "a detached HEAD gets no branch link" "${ESC}]8;;" "$got"
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
# A NUL that reached `_fields=$(...)` made bash 5 warn "ignored null byte in
# input" on stderr (3.2 dropped it silently). A shell variable cannot hold a
# NUL, so the evidence is the stderr and the text either side surviving.
nul_payload=$(jq -nc --arg d "$FIX/plain" '{workspace:{current_dir:$d},model:{display_name:"M"},session_name:"n\u0000ul"}')
err=$(printf '%s' "$nul_payload" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" 2>&1 > /dev/null)
equals "a NUL in a value causes nothing on stderr" "" "$err"
contains "the text around a NUL survives" "nul" \
  "$(printf '%s' "$nul_payload" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p')"

# ---------------------------------------------------------------------------
echo "-- home directory --"
# ${cwd/#$HOME/\~} kept the backslash under bash 3.2 and rendered \~, and it
# also matched a sibling such as /h/me-old as ~-old. The fake home sits under
# $FIX so the cache entries these renders write are cleaned up on exit.
home_line() {
  jq -nc --arg d "$1" '{workspace:{current_dir:$d},model:{display_name:"M"}}' \
    | HOME="$FIX/me" CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi | sed -n '1p' | sed 's/^.*\[M\] .*│ ▣ //'
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
echo "-- dev servers in the session's project --"
# Real listeners: node servers on OS-assigned ports, each started in a fixture
# directory so its cwd says which project it belongs to. The listener cache is
# off for the whole suite (see RUN_BASH), so every render sees current sockets.

# start_server <dir> [node|perl] [port] [host] -- sets SRV_PORT and SRV_PID, or
# returns 1. Port 0 (the default) lets the OS pick; a fixed port that is taken,
# or a host that cannot be bound (::1 with IPv6 off), makes the server exit,
# which shows up here as no port file. host applies to plain node servers and
# defaults to 127.0.0.1. perl stands for a listener that is not a dev runtime:
# a renamed copy of node did too, until CI's macOS node turned out to load
# libnode from a path relative to its binary.
start_server() {
  local dir="$1" kind="${2:-node}" port="${3:-0}" host="${4:-127.0.0.1}" pf waited=0
  pf="$FIX/port.$$.$RANDOM"
  # exec, so the listening process is the server itself, with $dir as its cwd.
  if [ "$kind" = perl ]; then
    ( cd "$dir" && exec perl -MIO::Socket::INET -e '
        my $s = IO::Socket::INET->new(Listen => 5, LocalAddr => "127.0.0.1",
          LocalPort => $ARGV[1]) or exit 1;
        open(my $f, ">", $ARGV[0]) or exit 1; print $f $s->sockport; close $f;
        sleep 120;' "$pf" "$port" ) &
  elif [ "$kind" = node-mainthread ]; then
    # Linux only: what the official Node 24 builds do, naming the main thread
    # (and so /proc/PID/comm, which ss reports) MainThread.
    ( cd "$dir" && exec node -e '
        require("fs").writeFileSync("/proc/self/comm", "MainThread");
        const s = require("net").createServer();
        s.on("error", () => process.exit(1));
        s.listen(Number(process.argv[2]), "127.0.0.1", () =>
          require("fs").writeFileSync(process.argv[1], String(s.address().port)));
        setTimeout(() => process.exit(0), 120000);' "$pf" "$port" ) &
  else
    ( cd "$dir" && exec node -e '
        const s = require("net").createServer();
        s.on("error", () => process.exit(1));
        s.listen(Number(process.argv[2]), process.argv[3], () =>
          require("fs").writeFileSync(process.argv[1], String(s.address().port)));
        setTimeout(() => process.exit(0), 120000);' "$pf" "$port" "$host" ) &
  fi
  SRV_PID=$!
  SERVER_PIDS="$SERVER_PIDS $SRV_PID"
  # Up to 5s (100 x 0.05s) for node to start and write its port.
  while [ "$waited" -lt 100 ]; do
    [ -s "$pf" ] && { SRV_PORT=$(cat "$pf"); return 0; }
    kill -0 "$SRV_PID" 2>/dev/null || return 1
    sleep 0.05
    waited=$((waited + 1))
  done
  return 1
}

# start_low_server <dir> -- a server on a free fixed port in 20000-20999, below
# the OS's ephemeral range, so a later process holds a lower port. Retries a
# few ports on a collision.
start_low_server() {
  local tries=0
  while [ "$tries" -lt 5 ]; do
    start_server "$1" node $((20000 + RANDOM % 1000)) && return 0
    tries=$((tries + 1))
  done
  return 1
}

if ! command -v node > /dev/null; then
  echo "SKIP  node is not installed, so no fixture server can listen"
else
  mkdir -p "$FIX/devproj/apps/web" "$FIX/otherproj" "$FIX/devproj-old"
  start_server "$FIX/devproj"          || bad "server in the project started"; P_ROOT=$SRV_PORT; PID_ROOT=$SRV_PID
  start_server "$FIX/devproj/apps/web" || bad "server in a subdirectory started"; P_SUB=$SRV_PORT
  start_server "$FIX/otherproj"        || bad "server in another project started"; P_OTHER=$SRV_PORT; PID_OTHER=$SRV_PID
  start_server "$FIX/devproj-old"      || bad "server in a sibling started"; P_SIB=$SRV_PORT
  if command -v perl > /dev/null; then
    start_server "$FIX/devproj" perl || bad "non-dev listener started"; P_NODEV=$SRV_PORT
  else
    echo "SKIP  perl is not installed, so no non-dev listener can be started"; P_NODEV=0
  fi

  dev_proj="\"workspace\":{\"project_dir\":\"$FIX/devproj\"}"
  got=$(raw "$FIX/devproj" "$dev_proj")
  line=$(printf '%s' "$got" | strip_links | sed -n '3p')
  excludes "dev servers are not on line 1" "localhost:" "$(printf '%s' "$got" | strip_links | sed -n '1p')"
  excludes "dev servers are not on line 2" "localhost:" "$(printf '%s' "$got" | strip_links | sed -n '2p')"
  contains "a server in the project is shown" "localhost:$P_ROOT" "$line"
  # When detection fails outright, say what the OS tools see for the fixture
  # server, so a CI log shows the cause rather than just the missing port.
  case "$line" in
    *"localhost:$P_ROOT"*) ;;
    *)
      echo "        diagnostics for pid $PID_ROOT (port $P_ROOT), OSTYPE=$OSTYPE:"
      {
        case "$OSTYPE" in
          darwin*|*bsd*|FreeBSD*)
            lsof -nP -a -iTCP -sTCP:LISTEN -p "$PID_ROOT" -Fpcn
            echo "comm (ps): $(ps -o comm= -p "$PID_ROOT")"
            lsof -a -p "$PID_ROOT" -d cwd -Fn ;;
          *)
            echo "ss: $(command -v ss || echo 'not found')"
            ss -ltnpH | grep -F ":$P_ROOT "
            echo "comm: $(cat "/proc/$PID_ROOT/comm")"
            echo "cwd:  $(readlink "/proc/$PID_ROOT/cwd")" ;;
        esac
        echo "project_dir: $FIX/devproj"
      } 2>&1 | sed 's/^/          /'
      ;;
  esac
  contains "a server in a project subdirectory is shown" "localhost:$P_SUB" "$line"
  excludes "a server in another project is not shown" "localhost:$P_OTHER" "$line"
  excludes "a server in a sibling such as devproj-old is not shown" "localhost:$P_SIB" "$line"
  excludes "a listener that is not a dev runtime is not shown" "localhost:$P_NODEV" "$line"
  contains "a dev server links to http://localhost" \
    "${ESC}]8;;http://localhost:${P_ROOT}${ESC}\\" "$got"
  # Lowest port first, whichever order the OS lists them in.
  lo=$P_ROOT; hi=$P_SUB; [ "$lo" -gt "$hi" ] && { lo=$P_SUB; hi=$P_ROOT; }
  contains "dev servers are listed lowest port first" "localhost:$lo localhost:$hi" "$line"

  # The same with project_dir already resolved. On macOS $FIX is under
  # /var/folders, which lsof reports as /private/var/folders, so the checks
  # above only reach the resolved-path comparison; these reach the plain one.
  real_proj=$(cd "$FIX/devproj" && pwd -P)
  got=$(raw "$real_proj" "\"workspace\":{\"project_dir\":\"$real_proj\"}" | strip_links | sed -n '3p')
  contains "a resolved project_dir shows its own server" "localhost:$P_ROOT" "$got"
  contains "a resolved project_dir shows a subdirectory server" "localhost:$P_SUB" "$got"
  excludes "a resolved project_dir does not show a sibling's server" "localhost:$P_SIB" "$got"

  dev_proj_slash="\"workspace\":{\"project_dir\":\"$FIX/devproj/\"}"
  got=$(devseg "$FIX/devproj" "$dev_proj_slash")
  contains "a trailing slash on project_dir still matches" "localhost:$P_ROOT" "$got"

  # Without project_dir the cwd is the project: from apps/ only apps/web counts.
  got=$(devseg "$FIX/devproj/apps" "")
  contains "without project_dir the cwd is used" "localhost:$P_SUB" "$got"
  excludes "without project_dir a server above the cwd is not shown" "localhost:$P_ROOT" "$got"

  got=$(devseg "$FIX/otherproj" "\"workspace\":{\"project_dir\":\"$FIX/otherproj\"}")
  contains "each session sees its own project's server" "localhost:$P_OTHER" "$got"
  excludes "and not the servers of another project" "localhost:$P_ROOT" "$got"

  # A home-directory session is not a project: everything under ~ would match.
  got=$(printf '%s' "$(jq -nc --arg d "$FIX/devproj" '{workspace:{current_dir:$d,project_dir:$d},model:{display_name:"M"}}')" \
    | HOME="$FIX/devproj" CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" | strip_ansi)
  contains "a home-directory session still renders" "[M]" "$got"
  excludes "a home-directory session shows no dev servers" "localhost:" "$got"

  # More than three: the lowest three by port, then a count. The extra two are
  # started last on fixed low ports, so they hold the lowest ports from the
  # newest pids and the listing order has to be sorted to come out right.
  start_low_server "$FIX/devproj" || bad "third project server started"; P_LO1=$SRV_PORT
  start_low_server "$FIX/devproj" || bad "fourth project server started"; P_LO2=$SRV_PORT
  got=$(raw "$FIX/devproj" "$dev_proj" | strip_links | sed -n '3p')
  contains "more than three servers show a +N count" "+1" "$got"
  n_links=$(printf '%s' "$got" | grep -o 'localhost:[0-9]*' | wc -l | tr -d ' ')
  equals "more than three servers show three links" "3" "$n_links"
  a=$P_LO1; b=$P_LO2; [ "$a" -gt "$b" ] && { a=$P_LO2; b=$P_LO1; }
  contains "the lowest ports come first, whatever order the processes started in" \
    "▶ localhost:$a localhost:$b localhost:$lo +1" "$got"

  # Two projects on one port, one on each loopback address: both can bind, and
  # each session must see its own. Ports used to be deduplicated before the
  # project check, keeping whichever socket the OS listed first, so one of the
  # two sessions always lost its server; checking both catches that whatever
  # order lsof or ss lists them in.
  mkdir -p "$FIX/samea" "$FIX/sameb"
  if start_server "$FIX/samea" node 0 127.0.0.1; then
    P_SAME=$SRV_PORT
    if start_server "$FIX/sameb" node "$P_SAME" ::1; then
      got=$(raw "$FIX/samea" "\"workspace\":{\"project_dir\":\"$FIX/samea\"}" | strip_links | sed -n '3p')
      contains "two projects on one port: the 127.0.0.1 one sees its server" "localhost:$P_SAME" "$got"
      got=$(raw "$FIX/sameb" "\"workspace\":{\"project_dir\":\"$FIX/sameb\"}" | strip_links | sed -n '3p')
      contains "two projects on one port: the ::1 one sees its server" "localhost:$P_SAME" "$got"
      n_links=$(printf '%s' "$got" | grep -o "localhost:$P_SAME" | wc -l | tr -d ' ')
      equals "two projects on one port: the port is listed once" "1" "$n_links"
    else
      echo "SKIP  ::1 cannot be bound here (IPv6 off), so two projects cannot share a port"
    fi
  else
    bad "a 127.0.0.1 server for the same-port case started"
  fi

  # Linux reads the runtime from /proc/PID/exe, because the process name ss
  # reports can be anything: CI's official Node 24 build says MainThread.
  case "$OSTYPE" in
    darwin*|*bsd*|FreeBSD*) ;;
    *)
      mkdir -p "$FIX/retitled"
      if start_server "$FIX/retitled" node-mainthread; then
        P_RT=$SRV_PORT
        equals "the fixture node really reports MainThread" "MainThread" "$(cat "/proc/$SRV_PID/comm")"
        got=$(devseg "$FIX/retitled" "\"workspace\":{\"project_dir\":\"$FIX/retitled\"}")
        contains "a node whose process name is MainThread is still shown" "localhost:$P_RT" "$(printf '%s' "$got" | strip_links)"
      else
        bad "a node server that retitles itself started"
      fi
      ;;
  esac

  # A stopped server disappears on the next scan.
  kill "$PID_OTHER" 2>/dev/null; wait "$PID_OTHER" 2>/dev/null
  got=$(devseg "$FIX/otherproj" "\"workspace\":{\"project_dir\":\"$FIX/otherproj\"}")
  excludes "a stopped server is no longer shown" "localhost:$P_OTHER" "$got"

  err=$(printf '%s' "$(jq -nc --arg d "$FIX/devproj" '{workspace:{current_dir:$d,project_dir:$d},model:{display_name:"M"}}')" \
    | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" 2>&1 > /dev/null)
  equals "no stderr: dev servers detected" "" "$err"
fi

# No dev servers, no third line: the status line stays two lines.
n_lines=$(printf '%s\n' "$(raw "$FIX/plain")" | wc -l | tr -d ' ')
equals "without dev servers the status line has two lines" "2" "$n_lines"

# The http://localhost exception is for the links the script builds itself; a
# payload URL never gets it.
got=$(raw "$FIX/plain" '"pr":{"number":5,"url":"http://localhost:1234"}')
excludes "a pr.url of http://localhost is not linked" "${ESC}]8;;" "$got"
contains "a session with no dev server shows no marker" "⇄ #5" "$(printf '%s' "$got" | strip_ansi)"
excludes "a session with no dev server shows no ▶" "▶" "$(printf '%s' "$got" | strip_ansi)"
got=$(seg "$FIX/plain" '"workspace":{"project_dir":{"a":1}}')
contains "a wrongly typed project_dir falls back to the cwd" "plain" "$got"

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

# ---------------------------------------------------------------------------
echo "-- palette and glyphs --"
got=$(STATUSLINE_PALETTE= STATUSLINE_GLYPHS= raw "$FIX/plain")
contains "default palette is catppuccin (ok green)" "${ESC}[38;2;166;227;161m" "$got"
contains "default glyphs are nerd (model icon)" $'\xee\xbc\xa3' "$got"
contains "unicode tier divider" " │ " "$(render "$FIX/plain" | sed -n 2p)"
contains "unicode bar glyphs" "▰▰▰▰▱▱▱▱▱▱ 40%" "$(line2 "$FIX/plain")"
got=$(STATUSLINE_GLYPHS=ascii render "$FIX/plain")
contains "ascii bar" "[====------] 40%" "$got"
excludes "ascii prints no box divider" "│" "$got"
equals "ascii output is 7-bit" "" "$(printf '%s' "$got" | LC_ALL=C tr -d '\000-\177')"
# A full payload: every optional segment, so a non-ASCII glyph in any of them
# fails here. The contains pairs keep a failed render from passing as empty.
got=$(STATUSLINE_GLYPHS=ascii TZ=UTC0 render "$FIX/sync" "\"output_style\":{\"name\":\"explanatory\"},\"vim\":{\"mode\":\"NORMAL\"},\"agent\":{\"name\":\"reviewer\"},\"session_name\":\"icons\",\"worktree\":{\"name\":\"feat-x\"},\"pr\":{\"number\":42,\"review_state\":\"approved\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":40,\"resets_at\":$((now + 14400))},\"seven_day\":{\"used_percentage\":24,\"resets_at\":$((now + 259200))}},\"prompt_cache\":{\"warm\":true,\"caching_observed\":true,\"ttl\":\"1h\",\"expires_at\":$((now + 1800)),\"hit_ratio\":0.88},\"cost\":{\"total_lines_added\":5,\"total_lines_removed\":2}")
contains "full ascii payload renders the pace marker" "5h 40% ^20%" "$got"
contains "full ascii payload renders the ETA" "out " "$got"
contains "full ascii payload renders the branch" "main" "$got"
contains "full ascii payload renders the cache" "cache " "$got"
contains "full ascii payload renders the style" "explanatory" "$got"
equals "full ascii output is 7-bit" "" "$(printf '%s' "$got" | LC_ALL=C tr -d '\000-\177')"
contains "unknown glyph tier falls back to nerd" $'\xee\xbc\xa3' "$(STATUSLINE_GLYPHS=bogus raw "$FIX/plain")"
contains "ansi palette keeps 8-colour green" "${ESC}[32m" "$(raw "$FIX/plain")"

# ---------------------------------------------------------------------------
echo "-- line 1 extras --"
got=$(render "$FIX/plain" '"output_style":{"name":"explanatory"},"vim":{"mode":"NORMAL"},"agent":{"name":"reviewer"}')
contains "output style shown" "◎ explanatory" "$got"
contains "vim mode shown" "v NORMAL" "$got"
contains "agent shown" "@ reviewer" "$got"
excludes "default output style hidden" "◎" "$(render "$FIX/plain" '"output_style":{"name":"default"}')"
contains "model icon" "◆ [M]" "$(render "$FIX/plain" | sed -n 1p)"
contains "folder after a divider" " │ ▣ " "$(render "$FIX/plain" | sed -n 1p)"
# Review Focus 5: wrong types hide their own segment, nothing on stderr
bad_types='"output_style":{"name":7},"vim":"NORMAL","agent":[1]'
# Payload assigned first: no \" inside a double-quoted $(...) (bash 3.2)
payload=$(jq -nc --arg d "$FIX/plain" --argjson x "{${bad_types}}" '{workspace:{current_dir:$d},model:{display_name:"M"}} * $x')
err=$(printf '%s' "$payload" | CLAUDE_CONFIG_DIR="$CONFIG_DIR" "$RUN_BASH" "$SCRIPT" 2>&1 >/dev/null)
equals "wrongly typed extras: no stderr" "" "$err"
got=$(render "$FIX/plain" "$bad_types")
contains "wrongly typed extras still render the model" "[M]" "$got"
excludes "wrongly typed extras show no vim" "NORMAL" "$got"
got=$(render "$FIX/plain" '"worktree":{"name":"feat-x"},"pr":{"number":42}')
contains "worktree after a divider" " │ ⑂ wt:feat-x" "$got"
contains "PR after a divider" " │ ⇄ #42" "$got"
got=$(STATUSLINE_GLYPHS=ascii raw "$FIX/plain")
excludes "ascii emits no empty colour pair before the model" "${ESC}[0m${ESC}[1m[M]" "$got"

echo
echo "$pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
