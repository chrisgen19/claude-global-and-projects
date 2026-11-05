# Statusline Catppuccin, Icons and Cross-Account Usage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle `statusline.sh` with Catppuccin Mocha colours, Nerd Font icons (Unicode/ASCII fallbacks) and `│` dividers, and add quota run-out ETA, pace vs clock, tokens to auto-compact, cost today across all accounts with $/h, output style/vim/agent, and an other-accounts line.

**Architecture:** Everything stays in the single bash script `statusline.sh` (project convention), extended in place. New per-account quota files and per-session state files live under a state dir (`CLAUDE_STATUSLINE_STATE_DIR`, default `/tmp`) so the suite can isolate them. All new payload fields join the existing single `jq` pass; new state is read with builtins and written with at most one `mv` per changed render.

**Tech Stack:** bash 3.2+, jq, git, BSD/GNU userland. Tests: `statusline-tests/run.sh` (plain bash asserts).

**Spec:** `docs/superpowers/specs/2026-11-05-statusline-catppuccin-icons-design.md`

## Global Constraints

- bash 3.2: no `mapfile`, `declare -A`, `${var^^}`, `\u`/`\U` escapes. Nerd glyphs are stored as `$'\x..'` UTF-8 byte escapes (table in Task 1).
- One `jq` fork per render. A render where nothing changed adds no fork; a changed render adds at most one `mv` (plus `mkdir` and old-folder cleanup on the first render of a day).
- Output printed with `printf '%s'` only, never `%b`. Colours hold real ESC bytes.
- Every payload string goes through `opt()` and `clean()` in the jq pass.
- `ACCOUNT_NAME`/`ACCOUNT_COLOR` stay on lines 14-15 of `statusline.sh`, ANSI-C quoted (`$'\033[...m'`).
- Every `/tmp` file name carries `${UID}`; every write is temp file plus `mv`.
- `STATUSLINE_GLYPHS=nerd|unicode|ascii` (default `nerd`, unknown value means `nerd`); `STATUSLINE_PALETTE=catppuccin|ansi` (default `catppuccin`).
- Catppuccin Mocha hex values exactly as in the spec's colour table.
- After every task: regenerate `claude-{personal,work,dev}/statusline.sh` with the README `gen` block (updated in Task 1), then run `./statusline-tests/run.sh` and `shellcheck --severity=warning --exclude=SC2154 statusline.sh claude*/statusline.sh statusline-tests/run.sh`. Both must pass before the commit.
- Never use em or en dashes in comments, docs or commit messages.
- Commits: Conventional Commits, scope `statusline`, on branch `feature/statusline-catppuccin-icons`.

## Review Focus

1. **A `session_id` containing `/`, `..` or nothing** must never write outside the ledger folder: it is sanitised to `[A-Za-z0-9-]`, and an empty result skips the ledger. Test in Task 5.
2. **Cost going down after `/clear`** must never make "today" go down: the drop is banked. Test in Task 5.
3. **A session that started before midnight** counts only what it spends after midnight. Test in Task 5.
4. **Another account's quota file that is corrupt, stale (over 5h) or past its reset** shows nothing, nothing, and `reset` respectively, with nothing on stderr. Test in Task 7.
5. **Wrongly typed new fields** (`vim` a string, `output_style` a number, `agent` an array, a corrupt `settings.json`) hide only their own segment, with nothing on stderr. Tests in Tasks 2 and 4.

---

### Task 1: Palette, glyph tiers, dividers and state dir

**Files:**
- Modify: `statusline.sh:13-43` (config block, colours), `statusline.sh:761-768` (bar), `statusline.sh:945-955` (printing)
- Modify: `README.md:250-275` (`gen` block)
- Modify: `statusline-tests/run.sh` (top of file, new section)
- Regenerate: `claude-personal/statusline.sh`, `claude-work/statusline.sh`, `claude-dev/statusline.sh`

**Interfaces:**
- Produces (globals every later task uses):
  - Colours: `C_OK C_WARN C_CRIT C_ACCENT C_MUTED C_SEP C_TEXT C_IDENT C_WORKSP C_VCS C_CTX C_QUOTA C_COST C_CACHE C_SESS C_TIMING`, plus `BOLD DIM RESET`. Existing names `GREEN YELLOW RED CYAN MAGENTA` stay as aliases (`GREEN=$C_OK`, `YELLOW=$C_WARN`, `RED=$C_CRIT`, `CYAN=$C_VCS`, `MAGENTA=$C_SESS`) so untouched code keeps working.
  - `account_color <outvar> <LABEL>`: colour for PERSONAL/WORK/DEV/other under the active palette.
  - Icons: `I_MODEL I_NAME I_DIR I_GIT I_WT I_PR I_STYLE I_VIM I_AGENT I_COMPACT I_QUOTA I_ETA I_COST I_TODAY I_RATE I_CACHE I_TIME I_SWITCH I_DEV`, each ending in one space, or empty under `ascii`.
  - Glyphs: `G_FULL G_EMPTY G_UP G_DOWN G_EVEN G_DOT G_ELLIPSIS`, divider `SEP` (already coloured, e.g. `"${C_SEP} │ ${RESET}"`).
  - `STATE_DIR` (from `CLAUDE_STATUSLINE_STATE_DIR`, default `/tmp`, trailing `/` trimmed).

- [ ] **Step 1: Write the failing tests** in a new section `-- palette and glyphs --` in `statusline-tests/run.sh`, and at the top of the suite (after `export CLAUDE_STATUSLINE_DEV_MAX_AGE=0`) add:

```bash
# Existing colour assertions use the 8-colour codes; new sections set their own.
export STATUSLINE_PALETTE=ansi STATUSLINE_GLYPHS=unicode
STATE=$(mktemp -d) || exit 1
export CLAUDE_STATUSLINE_STATE_DIR="$STATE"
```

Add `"$STATE"` to the `rm -rf` in `cleanup()`. Tests:

```bash
got=$(STATUSLINE_PALETTE= STATUSLINE_GLYPHS= raw "$FIX/plain")
contains "default palette is catppuccin (ok green)" "${ESC}[38;2;166;227;161m" "$got"
contains "default glyphs are nerd (model icon)" $'\xee\xbc\xa3' "$got"
contains "unicode tier divider" " │ " "$(render "$FIX/plain" | sed -n 2p)"
contains "unicode bar glyphs" "▰▰▰▰▱▱▱▱▱▱ 40%" "$(line2 "$FIX/plain")"
got=$(STATUSLINE_GLYPHS=ascii render "$FIX/plain")
contains "ascii bar" "[====------] 40%" "$got"
excludes "ascii prints no box divider" "│" "$got"
equals "ascii output is 7-bit" "" "$(printf '%s' "$got" | LC_ALL=C tr -d '\000-\177')"
contains "unknown glyph tier falls back to nerd" $'\xee\xbc\xa3' "$(STATUSLINE_GLYPHS=bogus raw "$FIX/plain")"
contains "ansi palette keeps 8-colour green" "${ESC}[32m" "$(raw "$FIX/plain")"
```

Also in `-- account copies --`: assert `claude-work` line 1 under `STATUSLINE_PALETTE=catppuccin` contains `${ESC}[38;2;249;226;175mWORK`, and under `ansi` contains `${ESC}[33mWORK` (PERSONAL `137;220;235` / `36`, DEV `166;227;161` / `32`). The `ACCOUNT_LABEL_OVERRIDE=CLAUDE` render under catppuccin contains `${ESC}[38;2;205;214;244mCLAUDE`.

- [ ] **Step 2: Run** `./statusline-tests/run.sh`. Expected: the new assertions FAIL (no `38;2`, no icons, `█` bar).

- [ ] **Step 3: Implement.**
  - Lines 14-15 of the template (PERSONAL) become:
    `ACCOUNT_NAME="PERSONAL"     # or "WORK" / "DEV"` and
    `ACCOUNT_COLOR=$'\033[38;2;137;220;235m'   # Catppuccin: PERSONAL 137;220;235, WORK 249;226;175, DEV 166;227;161`.
    Keep the two-line comment below them about lines 14-15.
  - Under `ansi`, `account_color` ignores line 15 and maps WORK `33`, PERSONAL `36`, DEV `32`, anything else `37`. Under `catppuccin`, the current account uses `ACCOUNT_COLOR`, the others the RGB triples above, anything else `text` (`205;214;244`). `ACCOUNT_LABEL_OVERRIDE` uses `text` / `37`.
  - Catppuccin escapes are `$'\033[38;2;R;G;Bm'` from the spec's hex values. The `ansi` set is today's codes (`C_OK=32 C_WARN=33 C_CRIT=31 C_ACCENT=36 C_MUTED=DIM C_SEP=DIM C_TEXT=""`, category colours fall back to today's colour for that segment).
  - Nerd icon bytes (each followed by a space in the `I_*` value):

    | var | cp | bytes | var | cp | bytes |
    |---|---|---|---|---|---|
    | I_MODEL | EF23 | `\xee\xbc\xa3` | I_COMPACT | F066 | `\xef\x81\xa6` |
    | I_NAME | F02B | `\xef\x80\xab` | I_QUOTA | F0520 | `\xf3\xb0\x94\xa0` |
    | I_DIR | F024B | `\xf3\xb0\x89\x8b` | I_ETA | F252 | `\xef\x89\x92` |
    | I_GIT | F02A2 | `\xf3\xb0\x8a\xa2` | I_COST | EEC1 | `\xee\xbb\x81` |
    | I_WT | F1BB | `\xef\x86\xbb` | I_TODAY | F073 | `\xef\x81\xb3` |
    | I_PR | F407 | `\xef\x90\x87` | I_RATE | F0E4 | `\xef\x83\xa4` |
    | I_STYLE | F12F5 | `\xf3\xb1\x8b\xb5` | I_CACHE | F1C0 | `\xef\x87\x80` |
    | I_VIM | E62B | `\xee\x98\xab` | I_TIME | F19BB | `\xf3\xb1\xa6\xbb` |
    | I_AGENT | F007 | `\xef\x80\x87` | I_SWITCH | F0EC | `\xef\x83\xac` |

    Unicode tier: the spec's Unicode column; `I_DEV` is `▶ ` for nerd/unicode, `> ` for ascii.
  - Glyphs: nerd/unicode `G_FULL=▰ G_EMPTY=▱ G_UP=⇡ G_DOWN=⇣ G_EVEN=± G_DOT=· G_ELLIPSIS=…`, divider ` │ `; ascii `= - ^ v +- - ...`, divider ` | `, bar wrapped in `[` `]`.
  - `BAR_WIDTH=10`; the session-name cut uses `G_ELLIPSIS` (cut to 29 chars for `…`, 27 for `...`).
  - Line 2's ` | ` separators become `$SEP`. Line 1's group gaps change in Task 2.
  - `README.md` `gen` block: the three calls pass the new line-15 strings (`\$'\\033[38;2;137;220;235m'` etc.), comments updated.

- [ ] **Step 4: Regenerate the copies** by running the README `gen` block from the repo root, then run the suite and shellcheck (see Global Constraints). Expected: all PASS, including the existing `→` pace tests (unchanged until Task 3).

- [ ] **Step 5: Commit**

```bash
git add statusline.sh claude-*/statusline.sh statusline-tests/run.sh README.md
git commit -m "feat(statusline): add Catppuccin palette, glyph tiers and dividers"
```

---

### Task 2: Line 1 icons, dividers, output style, vim mode and agent

**Files:**
- Modify: `statusline.sh:90-177` (jq pass and field reads), `statusline.sh:698-728` (flags/perm), `statusline.sh:900-949` (line 1 assembly)
- Modify: `statusline-tests/run.sh` (new section `-- line 1 extras --`)

**Interfaces:**
- Consumes: Task 1 icons, colours, `SEP`.
- Produces: fields `F[40]=output_style` (`opt(.output_style.name | strings) // ""`), `F[41]=vim_mode` (`opt(.vim.mode | strings) // ""`), `F[42]=agent_name` (`opt(.agent.name | strings) // ""`). New fields are always appended at the end of the jq array so earlier indices never move.

- [ ] **Step 1: Write the failing tests** (`STATUSLINE_GLYPHS=unicode` from the suite default):

```bash
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
```

In the existing git sections, the branch assertion gains its icon (`⎇ main`), and the PR test gains `⇄ #5`. Pin one: `contains "branch after a divider" " │ ⎇ main" ...` on the `sync` fixture.

- [ ] **Step 2: Run the suite.** Expected: the new assertions FAIL.

- [ ] **Step 3: Implement.** Line 1 order, per the spec's target layout:
  `account  gitUser(claude)  I_MODEL[model] cw flags style vim agent perm ver id I_NAME name` `SEP` `I_DIR dir` `SEP` `I_GIT branch counts` `SEP` `I_WT wt:name` `SEP` `I_PR #n state`.
  A divider appears only between segments that are present (worktree and PR are optional). Colours: model `C_IDENT`, dir `C_WORKSP`, branch `C_VCS`, session name and worktree `C_SESS`, PR `C_ACCENT`, output style `C_MUTED`, vim `C_QUOTA`, agent `C_ACCENT`. The OSC 8 branch and PR links wrap the text only, not the icon.

- [ ] **Step 4: Regenerate copies, run suite and shellcheck.** Expected: all PASS.

- [ ] **Step 5: Commit** `feat(statusline): add line 1 icons, dividers, output style, vim and agent`

---

### Task 3: Line 2 restyle, pace vs clock and run-out ETA

**Files:**
- Modify: `statusline.sh:231-245` (date read), `statusline.sh:770-899` (`fmt_rl`, cache, cost, duration, lines)
- Modify: `statusline-tests/run.sh:549-630` (`-- usage pace --`, `-- spend limit --`)

**Interfaces:**
- Produces:
  - `today` (local `YYYY-MM-DD`) and `midnight` (local midnight epoch), from the existing single `date` call extended to `date '+%s %z %Y-%m-%d'`; `midnight=$(( now - ((now + tz_secs) % 86400) ))`.
  - `fmt_clock <outvar> <epoch>`: local `HH:MM`, prefixed with the weekday (`Sun`..`Sat`, index `((epoch + tz_secs) / 86400 + 4) % 7`) when `epoch - now > 86400`.
  - `fmt_rl` keeps its signature and also sets the global `RL_LAST_SEV` (0 ok, 1 warn, 2 crit) for the window it just formatted.

- [ ] **Step 1: Rewrite the pace tests.** Replace every `→` assertion in `-- usage pace --` and `-- spend limit --` with the new markers. Add helper `eta_want <epoch>` that prints the expected `HH:MM` (with `TZ=UTC0`, plain arithmetic like the cache test) for both `epoch` and `epoch+60`, and assert one of them is in the output. New and changed cases (all `TZ=UTC0`):

```bash
# 40% with 4h left of 5h: 20% elapsed, ahead by 20, runs out at now+5400
got=$(TZ=UTC0 line2 "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":40,\"resets_at\":$((now + 14400))}}")
contains "ahead of the clock" "5h 40% ⇡20%" "$got"
# assert "out $(eta_want $((now + 5400)))" via the helper
# 24% with 3h12m left: 36% elapsed, behind by 12, no ETA
got=$(line2 "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":24,\"resets_at\":$((now + 11520))}}")
contains "behind the clock" "5h 24% ⇣12%" "$got"
excludes "on track shows no ETA" "out " "$got"
# 90% with 1h left: ahead by 10, projection 112%, ETA now+1600
# 7d 70% with 3d left: elapsed 4d, ETA now+148114, more than 24h away
got=$(TZ=UTC0 line2 "$FIX/plain" "\"rate_limits\":{\"seven_day\":{\"used_percentage\":70,\"resets_at\":$((now + 259200))}}")
# assert "out <Day> HH:MM" where Day is computed with the same formula
# under 10% used: no ⇡/⇣ and no ETA (replaces the old → exclusion)
# monthly spend: no pace marker, no ETA; weekly spend 50% with 4d left: ⇡8%, ETA shown
```

The colour tests stay: pace severity rules are unchanged (`${RED}40%` etc.).

- [ ] **Step 2: Run the suite.** Expected: the rewritten pace assertions FAIL (old `→` output).

- [ ] **Step 3: Implement in `fmt_rl`.** When pace is graded (same guard as today: used `>= 10`, `0 < rem < window`): `elapsed = window - rem`, `delta = used - elapsed * 100 / window`. Marker: `⇡delta%` in the pace severity colour (`C_OK` when 0), `⇣|delta|%` in `C_OK`, `±0%` muted. ETA when the projection is over 100: `eta = now - elapsed + elapsed * 100 / used`, shown as `I_ETA out <fmt_clock>` in the pace severity colour. The `→N%` marker is removed. Line 2 segment order and icons follow the spec's target layout: bar, `SEP I_QUOTA 5h … 7d … spend …`, `SEP I_CACHE cache …`, `SEP I_COST $x` (today and $/h join here in Task 5), `SEP I_TIME duration`, `SEP +a -r`.

- [ ] **Step 4: Regenerate copies, run suite and shellcheck.** Expected: all PASS.

- [ ] **Step 5: Commit** `feat(statusline): show pace against the clock and quota run-out time`

---

### Task 4: Tokens to auto-compact

**Files:**
- Modify: `statusline.sh:90-152` (jq pass, settings slurp, retry), `statusline.sh:744-759` (token breakdown)
- Modify: `statusline-tests/run.sh` (new section `-- auto-compact --`)

**Interfaces:**
- Consumes: `fmt_tok` (existing), `cu_input`, `cu_cache`, `cw_size`, `pct`.
- Produces: `F[43]=ac_enabled` and `F[44]=ac_window` from the jq pass; `compact_left` (tokens, or `-1` when no segment) for Task 6.

- [ ] **Step 1: Write the failing tests.** Each uses a 200k window unless stated; `ctx(pct, input, cache)` builds the `context_window` JSON.

```bash
# 141k used: point 167k, 26k left
contains "tokens left before compact" "⇲ 26k to compact" "$(line2 "$FIX/plain" "$(ctx 88 1000 140000)")"
contains "20k or less left is yellow" "${YELLOW}" "$(raw "$FIX/plain" "$(ctx 90 1000 149000)" | sed -n 2p)"
contains "past the point reads compact due" "compact due" "$(line2 "$FIX/plain" "$(ctx 95 4000 170000)")"
excludes "below 85% shows no compact" "compact" "$(line2 "$FIX/plain" "$(ctx 84 1000 140000)")"
contains "pct override moves the point earlier" "⇲ 9k to compact" \
  "$(CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50 line2 "$FIX/plain" "$(ctx 86 1000 80000)")"   # point 90k, 9k left
# CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000 on a 1M window: point 117k
contains "window cap" "⇲ 16k to compact" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000 line2 "$FIX/plain" "$(ctx1m 90 1000 100000)")"
excludes "DISABLE_AUTO_COMPACT hides it" "compact" "$(DISABLE_AUTO_COMPACT=1 line2 "$FIX/plain" "$(ctx 88 1000 140000)")"
# settings.json in a separate config dir: autoCompactEnabled false hides it
# Review Focus 5: a corrupt settings.json hides only the compact segment and keeps the email
```

The corrupt-settings test writes `{` to `$cfg/settings.json`, writes a valid `.claude.json` with an email, and asserts: no stderr, the email suffix still renders, `compact` absent.

- [ ] **Step 2: Run the suite.** Expected: the new assertions FAIL.

- [ ] **Step 3: Implement.**
  - Slurp `$config_dir/settings.json` as `$set` (`/dev/null` when missing). If the pass yields nothing, retry with both `$acct` and `$set` on `/dev/null`.
  - Fields (keeps `false` from vanishing under `//`):
    `(opt($set[0].autoCompactEnabled | booleans | tostring) // opt($acct[0].autoCompactEnabled | booleans | tostring) // "")` and the same shape for `autoCompactWindow` with `numbers | floor`.
  - `compact_point`: disabled when `DISABLE_COMPACT` or `DISABLE_AUTO_COMPACT` is `1|true|yes|on` (case-insensitive) or `ac_enabled` is `false`. `window = cw_size`, capped by `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (integer, clamped 100000..1000000) else `ac_window`. `usable = window - 20000`, `point = usable - 13000`; with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` in (0,100]: `point = min(usable * pct / 100, point)` (integer).
  - Shown from `pct >= 85` beside the breakdown: `I_COMPACT <fmt_tok left> to compact` in `C_CTX`, `C_WARN` when `left <= 20000`, `compact due` in `C_CRIT` at `left <= 0`.

- [ ] **Step 4: Regenerate copies, run suite and shellcheck.** Expected: all PASS.

- [ ] **Step 5: Commit** `feat(statusline): show tokens left before auto-compact`

---

### Task 5: Per-session state file, cost today and $/h

**Files:**
- Modify: `statusline.sh` (new block after the cost formatting, `statusline.sh:877-878`)
- Modify: `statusline-tests/run.sh` (new section `-- cost today --`)

**Interfaces:**
- Consumes: `STATE_DIR`, `today`, `midnight`, `now`, `session_id`, `cost`, `duration_ms`, `cu_input + cu_cache`.
- Produces:
  - `usd_to_micros <outvar> <usd-string>`: integer micro-dollars, pure bash (integer part times 1000000 plus the first six fraction digits, right-padded); any exponent form gives 0.
  - `fmt_usd <outvar> <micros>`: `$D.CC`, rounded half up on cents.
  - State file `$STATE_DIR/claude-statusline-cost-${UID}/$today/<sid>`, where `sid` is `session_id` with everything outside `[A-Za-z0-9-]` removed (empty: no state file, no today/rate). Format: line 1 `base total banked` (micros); then `c <epoch> <micros>` lines (last hour); then `x <tokens>` lines (last 10 changes, written from Task 6 on but reserved here).
  - `today_micros`, `rate_micros_per_hour` (or `-1`).

- [ ] **Step 1: Write the failing tests.** Each test uses its own `session_id` and a fresh `CLAUDE_STATUSLINE_STATE_DIR=$(mktemp -d)`. `rnd <sid> <cost> <duration_ms>` renders line 2 with those fields.

```bash
# started today: counts from zero
contains "a new session counts its whole cost" "today \$1.50" "$(rnd s1 1.5 60000)"
# two sessions sum
rnd s2 2.25 60000 >/dev/null
contains "sessions sum" "today \$3.75" "$(rnd s1 1.5 60000)"
# Review Focus 2: /clear drops the cost, today keeps it
rnd s3 4 60000 >/dev/null
contains "a cost drop is banked" "today \$4.50" "$(rnd s3 0.5 60000)"   # in a dir with only s3
# Review Focus 3: started before midnight (duration longer than time since midnight)
rnd s4 10 $(( (now - midnight + 3600) * 1000 )) >/dev/null
contains "pre-midnight spend is not today's" "today \$2.00" "$(rnd s4 12 $(( (now - midnight + 3700) * 1000 )))"
# Review Focus 1: a hostile session id stays inside the folder
rnd '../../evil/x' 1 60000 >/dev/null
equals "no file escapes the ledger folder" "" "$(find "$CLAUDE_STATUSLINE_STATE_DIR" -path '*evil*')"
got=$(rnd '///' 1 60000)
contains "an empty sanitised id still shows the session cost" "\$1.00" "$got"
excludes "an empty sanitised id shows no today" "today" "$got"
# old date folders are removed on the first render of a new day (pre-create a dated folder)
# $/h: hidden under 2 minutes of samples; shown once a pre-seeded sample 30 min old exists
#   (seed the state file with "c $((now-1800)) 1000000", current cost 2.0 -> "$2.00/h")
# unchanged render does not rewrite the file (mtime unchanged after a second identical render)
```

Midnight-dependent tests need `midnight`; compute it in the suite the same way as the script (from `date '+%s %z'`). The $/h seed file is `0 1000000 0` then `c $((now-1800)) 1000000`, rendered with cost `2.0`.

- [ ] **Step 2: Run the suite.** Expected: the new assertions FAIL.

- [ ] **Step 3: Implement** the ledger as the spec's "Cost today and $/h" pins it: first sight today sets `base = 0` when `now - duration_ms/1000 >= midnight`, else `base = total`; a lower cost banks `total - base` and resets `base`; session today `= banked + max(0, total - base)`; today `= sum` over the folder's files (glob plus builtin `read`). Rewrite (temp file plus `mv`) only when `total` changed. `mkdir -p` the day folder and `rm -rf` sibling date folders only when the day folder does not exist yet. $/h: per file, the increase from its oldest `c` sample within the last hour (restarting after any drop) to its `total`; sum the increases; `span = now - oldest sample epoch` across files; shown when `span >= 120`, `rate = sum * 3600 / span`. Display on the cost segment: `I_COST $session G_DOT I_TODAY today $X G_DOT I_RATE $Y/h`, rate muted, `C_WARN` above `$10/h` (my call for the threshold the spec leaves open).

- [ ] **Step 4: Regenerate copies, run suite and shellcheck.** Expected: all PASS.

- [ ] **Step 5: Commit** `feat(statusline): add cost today across sessions and spend per hour`

---

### Task 6: Turns until compact

**Files:**
- Modify: `statusline.sh` (state file write from Task 5, compact segment from Task 4)
- Modify: `statusline-tests/run.sh` (`-- auto-compact --`)

**Interfaces:**
- Consumes: Task 5 state file and its write path; Task 4 `compact_left`.
- Produces: `x <tokens>` lines in the state file; `~N turns` on the compact segment.

- [ ] **Step 1: Write the failing tests.** Seed a state file with `x 100000`, `x 110000`, `x 120000`, `x 130000` and render at 141000 tokens (26k left, growth 10k per step): expect `⇲ 26k to compact ~3 turns`. With only two growth samples: no `turns`. With a drop in the samples (`x 150000`, `x 60000`, `x 70000`): only samples after the drop count (two, so no `turns`).

- [ ] **Step 2: Run the suite.** Expected: FAIL.

- [ ] **Step 3: Implement.** Append `x <tokens>` when tokens differ from the last `x` line, keep the last 10, in the same single rewrite as Task 5 (a token change alone also triggers it). Turns: samples after the last decrease, at least 3, `per = (last - first) / (n - 1)`, `turns = ceil(left / per)`, shown as ` ~N turns` only when `per > 0`.

- [ ] **Step 4: Regenerate copies, run suite and shellcheck.** Expected: all PASS.

- [ ] **Step 5: Commit** `feat(statusline): estimate turns until auto-compact`

---

### Task 7: Quota files and the other-accounts line

**Files:**
- Modify: `statusline.sh` (after the rate limit block, and the final printing)
- Modify: `statusline-tests/run.sh` (new section `-- other accounts --`; `devseg` reads the last line instead of line 3)

**Interfaces:**
- Consumes: `RL_LAST_SEV` from the 5h `fmt_rl` call, `claude_email`, `account_color`, `STATE_DIR`.
- Produces: quota file `$STATE_DIR/claude-statusline-quota-${UID}-<LABEL>`, one line: `label email p5 at5 p7 at7 seen` (missing values `-1`, empty email `-`).

- [ ] **Step 1: Write the failing tests** (each with its own state dir; `qfile <LABEL> <email> <p5> <at5> <seen>` writes a fixture file):

```bash
# own file is written
render "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":20,\"resets_at\":$((now+9000))}}" >/dev/null
contains "own quota file written" "PERSONAL" "$(cat "$CLAUDE_STATUSLINE_STATE_DIR"/claude-statusline-quota-"$UID"-PERSONAL)"
# line 3 appears only when the current 5h is warn or crit
qfile WORK w@x 12 $((now+9000)) $((now-480)); qfile DEV d@x 3 $((now+9000)) $((now-7200))
got=$(render "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":72,\"resets_at\":$((now+7500))}}" | sed -n 3p)
contains "other accounts listed" "⇆ other accounts: WORK 12% (8m ago)  DEV 3% (2h ago)" "$got"
excludes "current account not listed" "PERSONAL" "$got"
equals "calm session has no line 3" "1" "$(render "$FIX/plain" "\"rate_limits\":{\"five_hour\":{\"used_percentage\":20,\"resets_at\":$((now+9000))}}" | wc -l | tr -d ' ')"
# Review Focus 4
qfile WORK w@x 50 $((now-60)) $((now-600))      # past reset -> "WORK reset"
qfile DEV d@x 40 $((now+9000)) $((now-20000))   # older than 5h -> omitted
printf 'garbage\n' > "$CLAUDE_STATUSLINE_STATE_DIR/claude-statusline-quota-$UID-DEV"  # corrupt -> omitted, no stderr
# CLAUDE router session: email matches WORK's file -> writes WORK's file, lists PERSONAL and DEV only
# CLAUDE session with no matching email -> writes nothing, lists every account whose email differs
# dev servers move to line 4 when line 3 is present (devseg now reads the last line)
```

- [ ] **Step 2: Run the suite.** Expected: FAIL.

- [ ] **Step 3: Implement.** Write the own file only when a value changed or `seen` is 60s or older (read the current file with builtin `read` first). Under `ACCOUNT_NAME=CLAUDE` (the override), find the label whose file's email equals `claude_email` (non-empty) among PERSONAL, WORK, DEV; write to that label, or write nothing. Line 3, when `RL_LAST_SEV >= 1` for 5h: `I_SWITCH other accounts:` then, per label in order PERSONAL, WORK, DEV, skip the current account (or the CLAUDE session's matched one; with no match, skip any file whose email equals `claude_email`), and skip files that are missing, unparsable (non-integer fields) or with `now - seen > 18000`; `reset` in `C_OK` when `at5 <= now`; else `p5%` coloured by threshold (70 warn, 90 crit) and `(Nm ago)` / `(Nh ago)` muted. Labels bold in `account_color`. Print order: line 1, line 2, other accounts, dev servers.

- [ ] **Step 4: Regenerate copies, run suite and shellcheck.** Expected: all PASS.

- [ ] **Step 5: Commit** `feat(statusline): show other accounts' 5h usage when nearing the limit`

---

### Task 8: Performance guard and README

**Files:**
- Modify: `statusline-tests/run.sh` (new section `-- performance --`), `statusline-tests/README.md`
- Modify: `README.md:186-212` (status line docs)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the performance test.** Runs only when `$EPOCHREALTIME` is set (bash 5); otherwise prints `SKIP`. Render the same warm payload (git cache hot, unchanged cost) 20 times and assert the minimum wall time is under `${STATUSLINE_PERF_BUDGET_MS:-15}` ms. Also assert an unchanged second render does not change the state file's or quota file's mtime (no rewrite, no `mv`).

- [ ] **Step 2: Run the suite.** Expected: PASS. If the minimum exceeds 15ms locally, profile before raising the budget; record the measured minimum in the commit body.

- [ ] **Step 3: Update the docs.**
  - `README.md`: new sample block (the spec's target layout in the Unicode tier), the env vars `STATUSLINE_GLYPHS`, `STATUSLINE_PALETTE`, `CLAUDE_STATUSLINE_STATE_DIR`; how to set them in `statusLine.command`; what `today` means (API-equivalent cost on Pro/Max, not a bill); pace `⇡/⇣` and `out HH:MM`; the other-accounts line and its ages; the compact point (167k on 200k, 967k on 1M), its sources, and that project-level settings are not read; the colour table with Catppuccin hex values; credit to CCometixLine, Catppuccin and Nerd Fonts.
  - `statusline-tests/README.md`: the suite defaults (`ansi`, `unicode`, temp state dir) and the mutations checked for the new sections.

- [ ] **Step 4: Run the suite and shellcheck; then manually** compare `⇲ N to compact` with one real auto-compact in a session and note the result in the README.

- [ ] **Step 5: Commit** `docs(statusline): document the new segments, env vars and colours`
