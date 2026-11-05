# Statusline: Catppuccin, icons and cross-account usage

Date: 2026-11-05
Status: draft, awaiting approval
Scope: `statusline.sh` (template), the three account copies, `statusline-tests/`, `README.md`

## Why

The status line is mostly read to answer two questions:

1. **Should I switch accounts before the 5h limit runs out?** Today the line
   shows `5h 40% →200% (3h12m)`: it says the limit will be exceeded, not
   *when*, and it says nothing about the other two accounts, which are the
   ones being switched *to*.
2. **How much have I used today across WORK, PERSONAL and DEV?** Today only the
   current session's cost is shown.

The visual refresh (icons, Catppuccin colours, `│` dividers) is borrowed from
[CCometixLine](https://github.com/Haleclipse/CCometixLine) after comparing it
with our script. A mockup was reviewed and approved:
`statusline-mockup.sh` (throwaway, not in the repo; its layout is reproduced
below).

## Goals

- Show when the current account's 5h (and 7d) limit runs out at the current
  pace, as a local clock time.
- Show the other accounts' last-known 5h usage when the current account is
  heading for its limit.
- Show today's usage across all sessions in all three accounts, and the
  current spend rate per hour.
- Show tokens left before auto-compact once context is nearly full.
- Show output style, vim mode and agent name when they apply.
- Nerd Font icons with Unicode and ASCII fallbacks, Catppuccin Mocha colours,
  dim `│` dividers.

## Non-goals

- No configurator, presets, config file, TUI, or Rust binary. Everything stays
  in the one bash script with a few env vars.
- No `subagentStatusLine`, companion mod (TTFT, tokens/s), model registry,
  sparkline/trend chart, or cache rewarm cost.
- No width-aware reflow of line 1 in this round (see "Left open").

## Anti-goals (would make this a failure even if it works)

- A slower warm render. Today: ~11ms warm, one jq fork, no git fork on a
  cache hit. A render where nothing changed must stay fork-free apart from
  today's jq (my call). A render where cost or context changed may pay at
  most one extra fork in total: the single `mv` of its per-session state file
  (see "Cost today and $/h"). The first render of a day may also pay a
  `mkdir` and the old-folder cleanup. The tests assert the warm render stays
  within ~15ms of wall time on CI's Linux runner, not a fork count.
- Breaking bash 3.2 / BSD userland on macOS, or the CI drift check.
- Any payload text reaching the terminal unsanitised, or printing with `%b`.
- Another account's numbers shown as if current: every cross-account value
  carries its age.
- One session's ledger write corrupting or losing another session's numbers.

## Decided by the user

| Topic | Decision |
|---|---|
| Icons | Switchable: `STATUSLINE_GLYPHS=nerd\|unicode\|ascii`, default `nerd` |
| Divider | ` │ ` in a dim colour (`ascii` tier: ` \| `) |
| Colours | Catppuccin Mocha, 24-bit |
| Features | Quota run-out ETA; cost today across all sessions plus $/h; tokens to auto-compact; output style, vim mode, agent name; pace shown as points ahead/behind the clock (`⇡34%` / `⇣6%`) |
| Other accounts line | Keep |
| Layout | As in the approved mockup (below) |

## Target layout

```
Line 1  WORK  chris (christian.diomampo)  ◆ [Opus 5.5] 1M hi think ◎ explanatory v NORMAL @ reviewer v2.1.330 id:4f7b85aa # statusline upgrade │ ▣ ~/claude-global │ ⎇ feature/statusline ^2 +1 ~3 ?2 │ ⑂ wt:icons │ ⇄ #42 approved
Line 2  ▰▰▰▰▰▰▰▰▱▱ 87% (in: 12k, cache: 180k) ⇲ 26k to compact ~3 turns │ ◷ 5h 72% ⇡34% ⇥ out 14:20 (2h05m)  7d 71% (1d6h) │ ≈ cache 14:02 hit 88% │ $ $9.84 · ∑ today $46.10 · ∂ $7.90/h │ ◷ 1h 14m │ +880 -212
Line 3  ⇆ other accounts: PERSONAL 12% (8m ago)  DEV 3% (2h ago)
Line 4  ▶ localhost:3000 localhost:5173
```

(Shown with the Unicode tier; Nerd Font icons replace the symbols.) Lines 3
and 4 appear only when they have content. Line 3 sits above the dev servers
because it is the one read under pressure (my call).

Line 1 keeps today's order. Changes: icon before model, session name, folder,
branch, worktree, PR; `│` between the identity/model group, folder, git,
worktree and PR; new segments for output style (hidden when `default`), vim
mode, agent name.

Line 2 changes: bar glyphs `▰▱` at 10 cells (was `█░` at 15); compact segment;
pace and ETA on the quota segment; today and $/h on the cost segment; `│`
dividers; icons per segment.

## Colours (Catppuccin Mocha)

Values from CCometixLine's `catppuccin-mocha` palette, which match the
published Catppuccin palette (MIT).

| Role | Hex | Used for |
|---|---|---|
| ok | `#a6e3a1` | below thresholds, staged, lines added, DEV label, dev servers |
| warn | `#f9e2af` | 70%+ thresholds, modified, ahead, WORK label |
| crit | `#f38ba8` | 90%+, projected over limit, untracked, conflicts, lines removed, BYPASS |
| accent | `#89b4fa` | PR number, plan mode |
| muted | `#6c7086` | labels, dim text, ages |
| separator | `#7f849c` | ` │ ` and ` · ` |
| text | `#cdd6f4` | plain values |
| identity | `#b4befe` | model |
| workspace | `#94e2d5` | folder |
| vcs | `#74c7ec` | branch |
| context | `#cba6f7` | compact segment |
| quota | `#fab387` | quota icon, vim mode |
| cost | `#f9e2af` | cost, today |
| cache | `#89dceb` | cache icon, PERSONAL label |
| session | `#f5c2e7` | session name, worktree |
| timing | `#f2cdcd` | duration |

Account colours on lines 14-15 become 24-bit escapes in the same ANSI-C quoted
form, e.g. `ACCOUNT_COLOR=$'\033[38;2;249;226;175m'` for WORK. The router's
neutral `CLAUDE` label uses `text`.

My call: `STATUSLINE_PALETTE=ansi` keeps today's 8-colour output for a terminal
without 24-bit colour. Default is `catppuccin`. No automatic detection: whether
Claude Code passes `COLORTERM` to the status line command is unverified, and a
wrong guess would silently drop the palette.

## Icons

Nerd Font codepoints as CCometixLine uses them (Nerd Fonts 3.x); Unicode
fallbacks from the same table. ASCII tier: no icons.

| Segment | Nerd | Unicode |
|---|---|---|
| model | `U+EF23` | ◆ |
| session name | `U+F02B` | # |
| folder | `U+F024B` | ▣ |
| branch | `U+F02A2` | ⎇ |
| worktree | `U+F1BB` | ⑂ |
| PR | `U+F407` | ⇄ |
| output style | `U+F12F5` | ◎ |
| vim | `U+E62B` | v |
| agent | `U+F007` | @ |
| context/compact | `U+F066` | ⇲ |
| quota | `U+F0520` | ◷ |
| ETA | `U+F252` | ⇥ |
| cost | `U+EEC1` | $ |
| today | `U+F073` | ∑ |
| rate | `U+F0E4` | ∂ |
| cache | `U+F1C0` | ≈ |
| duration | `U+F19BB` | ◷ |
| other accounts | `U+F0EC` | ⇆ |
| dev servers | ▶ | ▶ |

Bar: `▰▱` for nerd and unicode, `[==--]` for ascii.

The `ascii` tier is pure 7-bit for everything the script itself prints (my
call: it exists for terminals that cannot render more): `│` becomes `|`, `·`
becomes `-`, `⇡`/`⇣`/`±` become `^`/`v`/`+-`, `…` becomes `...`, `▶` becomes
`>`. Payload text (folder, branch, session name) is printed as it arrives.

`STATUSLINE_GLYPHS` is read from the environment. Set it per machine in the
`statusLine.command` string (`STATUSLINE_GLYPHS=unicode bash ~/...`) or the
shell profile; the README documents both. An unknown value falls back to
`nerd`.

## Feature behaviour

### Pace and run-out ETA

- Pace is shown as points ahead of or behind the clock: `used% - elapsed%` of
  the window, `⇡N%` when ahead, `⇣N%` when behind, `±0%` on pace. This
  replaces today's `→200%` projection marker.
- Severity rules stay as today's `fmt_rl` (threshold or projection, whichever
  is worse; no pace grading below 10% used or with no elapsed time).
- ETA: when the linear projection exceeds 100% before the reset, show
  `out HH:MM` (local), the time used reaches 100% at the current average rate:
  `window_start + elapsed * 100 / used`, where `window_start = resets_at -
  window_len` and `elapsed = now - window_start`. Coloured with the pace
  severity. Hidden when the projection stays at or below 100%.
- ETA more than 24h away (7d, weekly spend): prefix the weekday, `out Thu
  14:20` (my call). Worked out by arithmetic on the local epoch (1970-01-01
  was a Thursday), with no `date` fork.
- Applies to 5h, 7d, and the spend limit when it has a fixed window (daily,
  weekly), same as pace today.

### Other accounts line

- Every render writes the current account's `{label, Claude email, 5h %, 5h
  resets_at, 7d %, 7d resets_at, seen}` to a per-account file:
  `/tmp/claude-statusline-quota-${UID}-<ACCOUNT_NAME>`. Write atomically
  (temp file and `mv`), and only when a value changed or the entry is older
  than 60s, so most warm renders skip the `mv` fork.
- Line 3 shows the other accounts (not the current one) from those files.
- Router sessions labelled `CLAUDE` (bare `claude`, VS Code, desktop app) are
  logged into one of the three accounts. My call: such a session matches its
  Claude email (already in the jq pass) against the emails in the quota files.
  On a match it writes to that account's file and leaves it out of line 3. With
  no match it writes nothing and line 3 lists every account whose email differs
  from its own, so the current account is never offered as one to switch to.
- My call: line 3 appears only when the current account's 5h segment is warn
  or crit. A permanently visible line was not asked for, and the mockup showed
  it only in the switch moment.
- Per account: label in its colour, 5h % in its own severity colour, age
  `(8m ago)` in muted. If its `resets_at` is in the past, show `reset` in ok
  instead of a stale percentage. Accounts with no file are omitted. Entries
  older than 5h are omitted.

### Cost today and $/h

- `cost.total_cost_usd` is API-equivalent cost, not a bill, on Pro/Max. The
  label stays `today`; the README states what it means.
- State: one file per session, so concurrent sessions never read-modify-write
  the same file: `/tmp/claude-statusline-cost-${UID}/<YYYY-MM-DD>/<session_id>`.
  It holds everything this feature and the compact estimate need for that
  session (my call, so a changed render costs one `mv`, not three):
  `base total banked` on the first line, then the session's cost samples
  (`epoch cost`, last hour) and context samples (`tokens`, last ~10 changes).
  - First sight today: `base` is 0 if the session started today
    (`now - duration_ms/1000` is after local midnight), else the current cost.
  - Each render sets `total` to the current cost. If cost goes down (after
    `/clear`), add `total - base` to `banked` and reset `base` to the new cost.
  - Session's today = `banked + max(0, total - base)`.
  - Today = sum over all files in today's folder. Written only when `total`
    changed, atomically.
  - Folders for earlier dates are deleted on the first render of a new day.
- $/h: the sum over today's session files of each session's cost increase
  across its last-hour samples, scaled to an hour by the longest span covered.
  Shown only once the samples cover at least 2 minutes (CCometixLine's
  `RATE_MIN_SPAN`). Coloured muted, warn above a threshold left to the
  builder. Just after midnight it counts only today's folder, so it starts low
  again: accepted.
- Reading the ledger folder is a glob plus `read` per file, no fork; the
  folder holds one file per session today.

### Tokens to auto-compact

- Compact point, following CCometixLine's reading of Claude Code (not verified
  against Claude Code itself; see "Risks"): `window - 20000 (output reserve) -
  13000 (buffer)`, so 167k for 200k and 967k for 1M.
  - `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (clamped 100k..1M) or the
    `autoCompactWindow` setting caps the window.
  - `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` moves the point earlier, never later.
  - `DISABLE_COMPACT`, `DISABLE_AUTO_COMPACT`, or `autoCompactEnabled: false`:
    no segment.
  - Sources (my call): the env vars above from the status line's own
    environment, plus `autoCompactEnabled`/`autoCompactWindow` from
    `$CLAUDE_CONFIG_DIR/settings.json` and the `.claude.json` already slurped,
    read in the existing jq pass (one more `--slurpfile` at most, no new
    fork). Project-level `.claude/settings*.json` is not read; the README says
    so. Checked 2026-11-05: none of the four accounts' `settings.json` or
    `.claude.json` sets either key, and no shell profile sets the env vars, so
    the default point applies on this machine today.
- Tokens used: `input_tokens + cache tokens` from `current_usage`, as today's
  breakdown.
- Shown from 85% context, beside the existing `(in: …, cache: …)` breakdown:
  `⇲ 26k to compact`, warn when 20k or less is left, `compact due` in crit at
  0.
- `~N turns`: needs per-turn context history. Per-session samples file
  `/tmp/claude-statusline-ctx-${UID}-<session_id>`, appending the token count
  when it changes, last ~10 entries. Turns = `left / average growth` over the
  recent turns since context last shrank (min 3 samples, else omit `~N turns`).

### Output style, vim mode, agent

- `.output_style.name`: shown unless `default`.
- `.vim.mode`: e.g. `NORMAL`, `INSERT`.
- `.agent.name`: when the session runs as a named agent.
- All three through `opt()` and `clean()` like every other string.
- Field names are from CCometixLine's `input.rs`; confirm them in a real
  payload before relying on them.

## Constraints

- One jq pass per render, extended with the new fields and the settings file.
- Bash 3.2: no `mapfile`, `declare -A`, `${var^^}`; `\U` escapes in `$'...'`
  are not supported by bash 3.2, so Nerd Font glyphs above `U+FFFF` and all
  icons are stored as literal UTF-8 or byte escapes (`$'\xf3\xb0\x89\x8b'`).
- `ACCOUNT_NAME`/`ACCOUNT_COLOR` stay on lines 14-15 (CI drift check).
- Output printed with `printf '%s'` only; colours as real ESC bytes.
- New `/tmp` files follow the existing pattern: `${UID}` in the name, atomic
  write, never read another user's file.
- Tests: extend `statusline-tests/run.sh` with a test for each feature and each
  glyph tier, and check each can fail (mutation, as the tests README does).
  Tests must not touch the developer's real `/tmp` ledger, quota or samples
  files: add env overrides for their locations, as `CLAUDE_STATUSLINE_DEV_MAX_AGE`
  does for the dev cache.
- Copy the template to the three account copies and keep CI green
  (shellcheck, tests, drift, ACCOUNT_COLOR quoting).
- README: document the env vars, the new segments, and what "today" means.

## Risks

- **Compact point** comes from CCometixLine's reading of Claude Code. If it is
  wrong the segment misleads. Mitigation: compare against a real auto-compact
  once, note the result in the README.
- **Nerd Font** missing in a terminal shows boxes. Mitigation: the env var.
- **Line 1 length** (~190 chars with everything on): narrow terminals cut off
  worktree and PR first.
- **Truecolor**: a terminal without it shows wrong colours. Mitigation:
  `STATUSLINE_PALETTE=ansi`.
- **Cross-account staleness**: other accounts' numbers are only as fresh as
  their last render; the age is always shown.

## Also left to the builder

Settled by the builder check as sensible defaults: the colour mapping under
`STATUSLINE_PALETTE=ansi` (today's colours), account colours there and on
line 3 from a fixed name-to-colour table, dev servers moving up to line 3 when
there is no other-accounts line, and confirming the `output_style`, `vim` and
`agent` field names against a captured real payload before writing their
tests.

## Left open (builder's call)

- Exact $/h warn threshold.
- Whether `⇣N%` (behind the clock) is shown or hidden when calm.
- Trimming line 1 when `COLUMNS` (set by Claude Code since 2.1.153, per
  CCometixLine) is narrower than the line: a follow-up, not this round.
- Internal structure of the script (helpers, ordering) within the constraints.
