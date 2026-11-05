# statusline tests

Behaviour tests for `statusline.sh`. Run them from anywhere:

```sh
./statusline-tests/run.sh
```

## Why these exist

CI already ran shellcheck, a `bash -n` parse under macOS bash 3.2, and a diff
of each account copy against the template. All three passed throughout the
life of the `printf '%b'` bug in #81, which expanded backslash escapes in the
cwd, the branch name and the git email: a directory holding a literal
backslash-t rendered as a tab, and a backslash-n emitted a third line and broke
the two-line contract the status line is configured for.

None of those checks look at what the script prints. These do.

## How they work

Each test feeds the script a statusline JSON payload on stdin, strips the ANSI
colours from the result and asserts on the text. Fixture git repos are built in
a `mktemp -d` and removed on exit.

Two things worth knowing before editing:

- **Every git state gets its own directory.** That makes each render a cache
  miss, so the suite never clears the cache. It must not: the cache lives in
  `/tmp` keyed by uid, so globbing it away would delete the entries belonging
  to the developer's real sessions.
- **Payloads are built with `jq`, not `printf`.** To test a literal backslash
  it has to reach the script as `\\` on the wire. Writing `\t` by hand makes it
  a JSON tab escape, which `jq` decodes before the script sees it, and the test
  proves nothing.

`CLAUDE_CONFIG_DIR` is pointed at an empty directory so the `(account)` suffix
does not vary with whatever is installed on the machine running the tests.

The suite exports its own defaults for the whole run, so the developer's shell
cannot change what is asserted:

- `STATUSLINE_PALETTE=ansi` and `STATUSLINE_GLYPHS=unicode`: the older tests
  assert on 8-colour codes and plain symbols. Sections that test the other
  palette or tiers set them for that one render.
- `CLAUDE_STATUSLINE_STATE_DIR` is a `mktemp -d` directory, removed on exit, so
  cost files, quota files and context samples never touch the real `/tmp` ones.
  Sections that need an empty or special state dir (`qdir`, `newledger`) point
  it at their own and restore it afterwards.
- `DISABLE_COMPACT`, `DISABLE_AUTO_COMPACT`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
  and `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` are unset.

The `-- performance --` section renders one warm payload (git cache hot, cost
and quota unchanged) 20 times, alternating with a baseline (a bash, one `jq`
and one `date` on the same payload), and asserts the fastest render is under
`STATUSLINE_PERF_FACTOR` (default 5) times the fastest baseline. It is relative
because the GitHub runner measured 15.9ms one run and 22.6ms the next, so a
fixed budget in ms flaked. A WSL2 dev box measures about 3.8. The factor
catches a heavy regression on the warm path (a second `jq`, a `git` call,
several forks), not one extra fork, which adds about 0.3. The render uses `HOME` as the
session directory, which skips the dev server scan: the suite runs that scan on
every render (see below), which is a cold cost and not what the guard is for.
It needs `EPOCHREALTIME` (bash 5) and prints `SKIP` under bash 3.2. The same
section checks that an unchanged render rewrites neither the cost file nor the
quota file. That compares inodes after every render with `ls -i`, not mtime
(which can tie within a second) and not once at the end (a freed inode number
is handed straight to the next temp file, so two rewrites can swap between two
numbers and look unchanged). The budget is a wall-time guard measured on a
shared runner: if CI is flaky on it, look at what the script forks before
raising the number.

The dev server tests start real listeners: `node` servers on OS-assigned (and
two fixed, 20000-20999) ports, each in a fixture directory, plus one `perl`
socket server to stand for a listener that is not a dev runtime. (A renamed
copy of `node` did that first, until CI's macOS `node` failed to start from
another directory: it loads `libnode` by a path relative to its own binary.)
They need `node` and `perl` on `PATH` and print `SKIP` without them; both CI
runners have both. If the first detection check fails, the suite prints what
`lsof` or `ss` sees for that server, with its `comm` and cwd.
The exit trap stops them and removes only their own `devcwd` cache entries.
`CLAUDE_STATUSLINE_DEV_MAX_AGE=0` is exported for the whole suite, which makes
the script neither read nor write the shared listener cache: an earlier render
reading a previous run's list looked up dead fixture pids. Assertions on the
visible text of linked output use `strip_links`, since with the OSC 8 wrapper in
place a linked port appears twice.

## Portability

CI runs this on Ubuntu and on macOS with the stock `/bin/bash` 3.2 and BSD
`sed`, so the suite avoids `mapfile`, `declare -A`, `${var^^}`, `grep -P`,
`date +%N`, and `sed 's/\x1b//'` (BSD `sed` has no `\x` escapes, so the ESC
byte is built with `printf` and interpolated into the pattern).

The script under test runs under the same bash as the suite (`$BASH`, printed
in the header). It used to be invoked as a bare `bash`, which resolved through
`PATH`: `/bin/bash ./statusline-tests/run.sh` ran the suite under 3.2 but the
script under Homebrew's 5.x wherever that came first, so a 3.2-only bug (the
signed byte in `urlenc_path`) passed.

Never put `\"` inside a `$(...)` that is itself in double quotes: bash 3.2
parses that nesting differently, the payload reaches `jq` mangled, and an
`excludes` check then passes on an empty render. Assign `got=$(...)` first,
then pass `"$got"`. Where a test only asserts an absence, pair it with a
`contains` on the same output so a render that failed outright cannot pass.

## Checking the tests can still fail

A suite that cannot fail guards nothing. Reintroduce a bug and confirm the
matching test goes red, for example:

```sh
sed -i "s|^printf '%s\\\\n'|printf '%b\\\\n'|" statusline.sh   # restores the #81 bug
./statusline-tests/run.sh                                      # 3 failures expected
git checkout statusline.sh
```

The mutations checked when these tests were written, each caught by exactly the
test named for it: restoring `printf '%b'`, dropping `-uall` from `git status`,
not counting `u` (conflict) lines, dropping the detached-HEAD guard on the
no-upstream marker, and swapping the staged and unstaged halves of the
porcelain XY pair.

For the #88 segments, each of these was caught under both bash 5 and 3.2
unless noted: removing the `caching_observed` gate on the hit rate, making
`clean()` a no-op, disabling pace alerts, dropping the `& 255` byte mask (3.2
only, as the bug is), restoring `${cwd/#$HOME/\~}`, ignoring the `%z` sign,
linking branches without an upstream, dropping a review state, raising the
token breakdown threshold, uncapping the session name, and pacing a monthly
spend limit.

For the dev server links, each caught under both: dropping the runtime filter,
matching the project as a bare prefix (so `devproj-old` counts), skipping
symlink resolution, not excluding the home directory, dropping the three-port
limit, skipping the sort, letting `osc8` link `http://` for any caller, not
linking the ports, and deduplicating ports before the project check (two
projects on one port, on `127.0.0.1` and `::1`: one session lost its server).
That case prints `SKIP` where `::1` cannot be bound, as in a Docker container
with IPv6 off. On Linux (an `ubuntu:26.04` container, as root and as a
normal user), matching the runtime by `/proc/PID/comm` instead of
`/proc/PID/exe` is caught by the `MainThread` case: that is what CI's official
Node 24 build reports as its process name, which the first version matched on
and missed. Not trimming a trailing slash from `project_dir` survives,
and should: the resolved-path comparison strips it anyway, so the trim only
saves a subshell.

For the performance section: making the quota file rewrite on every render
(`if true ||` in front of the changed-or-old test) is caught by the inode
check, and passes the single before/after comparison it
replaced, which is why the check runs after every render. The sections for the
palette, glyph tiers, line 1 extras, cost today, tokens to compact and other
accounts were each written test first (red, then green); no per-mutation list
was recorded for them, so rerun the mutation check above on any of them before
trusting a change there.
