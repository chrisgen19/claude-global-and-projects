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

## Portability

CI runs this on Ubuntu and on macOS with the stock `/bin/bash` 3.2 and BSD
`sed`, so the suite avoids `mapfile`, `declare -A`, `${var^^}`, `grep -P`,
`date +%N`, and `sed 's/\x1b//'` (BSD `sed` has no `\x` escapes, so the ESC
byte is built with `printf` and interpolated into the pattern).

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
