# Claude Code — Global & Project Instructions

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration for my development workflow. Contains global preferences, project-specific standards, and reusable skill files for WordPress and Next.js development.

## Structure

```
.
├── CLAUDE.md                              # Global preferences (all projects)
├── .zshrc-claude                          # Multi-account shell setup (copy to ~/.zshrc)
├── statusline.sh                          # Status line template (copy to each account dir)
├── iterm-tab-status.sh                     # iTerm2 tab indicator (copy to ~/.local/bin/)
├── claude-personal/                       # Deployed copy of ~/.claude-personal
│   ├── statusline.sh                      #   PERSONAL variant (cyan label)
│   └── settings.json                      #   sanitized — see note below
├── claude-work/                           # Deployed copy of ~/.claude-work
│   ├── statusline.sh                      #   WORK variant (yellow label)
│   └── settings.json                      #   sanitized — see note below
├── claude-dev/                            # Deployed copy of ~/.claude-dev
│   ├── statusline.sh                      #   DEV variant (green label)
│   └── settings.json                      #   sanitized — see note below
├── .claude/skills/                        # Global skills (cross-project)
│   ├── pr-description/SKILL.md           # Generate PR descriptions from branch diff
│   ├── env-check/SKILL.md               # Audit env vars, secrets, and .env config
│   ├── security-audit/SKILL.md          # Scan for vulnerabilities (PHP + JS/TS)
│   ├── change-doc/SKILL.md              # File-by-file writeup of a completed change
│   ├── deep-dive/SKILL.md               # Research a system, output Markdown + PDF
│   ├── explain-code/SKILL.md            # Explain code with diagrams and analogies
│   ├── nextjs-conventions/SKILL.md      # Personal Next.js conventions (personal + dev only)
│   └── wp-backup/SKILL.md               # Export WordPress DB + zip files
├── wp-projects/
│   ├── CLAUDE.md                          # WordPress project standards
│   └── .claude/skills/wordpress/
│       ├── SKILL.md                       # Skill entry point
│       ├── scaffold.md                    # Boilerplate: classes, plugin bootstrap, build configs, SASS
│       └── patterns.md                    # Runtime: REST API, security, queries, WooCommerce, templates
└── nextjs-projects/
    ├── CLAUDE.md                          # Next.js project standards
    └── .claude/skills/nextjs/
        ├── SKILL.md                       # Skill entry point
        ├── scaffold.md                    # Boilerplate: layouts, configs, Prisma, middleware, env validation
        └── patterns.md                    # Runtime: data fetching, forms, Server Actions, Zustand, auth
```

## What's Inside

### Global `CLAUDE.md`
Shared conventions that apply to all projects:
- Communication style and response format
- Code style (TypeScript, naming conventions, quality rules)
- Tooling defaults (pnpm, Node 20+)
- Tech preferences (Lucide React, Framer Motion, Prisma/Drizzle)
- Deployment & hosting (Vercel, cPanel/VPS, Coolify, Docker)
- Git workflow (conventional commits, branch naming)
- Security guidelines and things to avoid

### Global Skills (`.claude/skills/`)
Cross-project skills that work everywhere — copy to `~/.claude/skills/` for global availability:

**Git & review**
- **`/pr-description`** — Reads branch diff and commits, generates a structured PR description with a ready-to-use `gh pr create` command
- **`/change-doc`** — File-by-file explanation of a completed change, with mermaid diagrams, so you can see what was built and why

**Auditing**
- **`/env-check`** — Audits environment variables: hardcoded secrets, `.gitignore` coverage, `.env.example` completeness, stack-specific misconfigurations
- **`/security-audit`** — Scans for common vulnerabilities (XSS, SQL injection, missing sanitization, exposed secrets) across PHP/WordPress and JS/TS/Next.js codebases

**Understanding & documenting**
- **`/explain-code`** — Explains how code works using diagrams and analogies, with depth scaled to complexity
- **`/deep-dive`** — Researches a system or integration thoroughly, then writes it up as both Markdown (mermaid) and a print-ready PDF (inline SVG)

**Stack-specific**
- **`/nextjs-conventions`** — Personal Next.js conventions: App Router, strict TypeScript, Prisma, Better Auth, server actions, file layout
- **`/wp-backup`** — Backs up a WordPress site: exports the database as SQL and zips the files, for migration or archiving

> `nextjs-conventions` is installed on the personal and dev accounts only. The other seven are on all three.

### WordPress (`wp-projects/`)
Standards for custom theme and plugin development:
- Project structure (themes + plugins)
- PHP conventions (strict types, Yoda conditions, early returns)
- SASS/CSS (7-1 pattern, BEM, CSS custom properties)
- Security checklist (sanitization, escaping, nonces, prepared SQL)
- Performance targets and optimization patterns
- Scaffold and runtime code patterns (CPTs, REST API, WooCommerce hooks, asset enqueue)

### Next.js (`nextjs-projects/`)
Standards for App Router projects with TypeScript, Tailwind, and Prisma:
- Project structure (`src/` with app, components, lib, hooks, types, schemas)
- Component conventions (Server Components by default, `'use client'` only when needed)
- Data fetching, caching, and revalidation patterns
- Forms (React Hook Form + Zod, Server Actions)
- Scaffold and runtime code patterns (layouts, Prisma CRUD, auth, Zustand, middleware)

## How It Works

### Multi-account setup

I use three separate Claude accounts (personal, work, and dev) with isolated config directories. Add the following to your `~/.zshrc` (or copy from `.zshrc-claude`):

```bash
# Claude CLI accounts
function claude-personal { CLAUDE_CONFIG_DIR="$HOME/.claude-personal" claude "$@"; }
function claude-work { CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude "$@"; }
function claude-dev { CLAUDE_CONFIG_DIR="$HOME/.claude-dev" claude "$@"; }

# Launch VS Code with specific Claude account
function code-personal { CLAUDE_CONFIG_DIR="$HOME/.claude-personal" code "$@"; }
function code-work { CLAUDE_CONFIG_DIR="$HOME/.claude-work" code "$@"; }
function code-dev { CLAUDE_CONFIG_DIR="$HOME/.claude-dev" code "$@"; }
```

Or append the file directly:

```bash
cat .zshrc-claude >> ~/.zshrc
source ~/.zshrc
```

**Usage:**

| Command | What it does |
|---------|-------------|
| `claude-work` | Opens Claude CLI with `~/.claude-work/` config |
| `claude-personal` | Opens Claude CLI with `~/.claude-personal/` config |
| `claude-dev` | Opens Claude CLI with `~/.claude-dev/` config |
| `code-work .` | Opens VS Code with work Claude account |
| `code-personal .` | Opens VS Code with personal Claude account |
| `code-dev .` | Opens VS Code with dev Claude account |

Each account has its own `CLAUDE.md` and `skills/` directory:
- `~/.claude-work/CLAUDE.md` + `~/.claude-work/skills/*`
- `~/.claude-personal/CLAUDE.md` + `~/.claude-personal/skills/*`
- `~/.claude-dev/CLAUDE.md` + `~/.claude-dev/skills/*`

> **Note:** `code-work` / `code-personal` / `code-dev` only works when launching VS Code from the terminal. Opening VS Code from Spotlight, Dock, or Finder won't pick up the account.

### Status line

A two-line status line covering account identity, model, git state, context usage, subscription rate limits, and session cost.

```
PERSONAL  chrisgen19 (chrisgen19)  [Opus 5] 1M hi think v2.1.235  ~/projects/my-app | main ~3 ?2  #42
█░░░░░░░░░░░░░░ 7% | 5h 19% (2h14m) 7d 3% (4d3h) | $1.64 | 26m 57s | +273 -3
```

**Line 1** — account label, git user with the Claude account in parens, model with context window size and session flags (`fast` / effort / `think`), Claude Code version, working directory, git branch with dirty counts (`+staged ~modified ?untracked`), open PR number.

**Line 2** — context usage bar, rate limit windows with reset countdowns, session cost, elapsed wall clock, lines added/removed.

Every segment hides itself when its data is absent, so the line stays short outside a git repo, on API billing, or early in a session.

| Colour | Meaning |
|--------|---------|
| Green | under 70% |
| Yellow | 70% or more |
| Red | 90% or more |

Applies to both the context bar and each rate limit window.

#### Setup

```bash
# Personal account
cp statusline.sh ~/.claude-personal/statusline.sh
# Edit ACCOUNT_NAME="PERSONAL" and ACCOUNT_COLOR='\033[36m' (cyan)

# Work account
cp statusline.sh ~/.claude-work/statusline.sh
# Edit ACCOUNT_NAME="WORK" and ACCOUNT_COLOR='\033[33m' (yellow)

# Dev account
cp statusline.sh ~/.claude-dev/statusline.sh
# Edit ACCOUNT_NAME="DEV" and ACCOUNT_COLOR='\033[32m' (green)
```

Then enable it in each account's `settings.json`:
```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude-work/statusline.sh",
    "refreshInterval": 60
  }
}
```

`refreshInterval` re-runs the script every 60 seconds so the rate limit countdowns stay honest while the session sits idle. Without it the status line only redraws when an assistant message arrives, and the countdown freezes. It runs locally and costs no tokens.

#### Keeping the three copies in sync

All three deployed scripts are identical except lines 14-15. Regenerate them from the root `statusline.sh` rather than hand-editing each, or they silently drift:

```bash
gen() {  # $1=account dir  $2=ACCOUNT_NAME line  $3=ACCOUNT_COLOR line
  { head -13 statusline.sh; printf '%s\n%s\n' "$2" "$3"; tail -n +16 statusline.sh; } > "$1/statusline.sh"
}

gen ~/.claude-personal 'ACCOUNT_NAME="PERSONAL"   # or "WORK" / "DEV"' \
  "ACCOUNT_COLOR='\033[36m'  # Cyan PERSONAL, '\033[33m' Yellow WORK, '\033[32m' Green DEV"
gen ~/.claude-work 'ACCOUNT_NAME="WORK"       # or "PERSONAL" / "DEV"' \
  "ACCOUNT_COLOR='\033[33m'  # Yellow WORK, '\033[36m' Cyan PERSONAL, '\033[32m' Green DEV"
gen ~/.claude-dev 'ACCOUNT_NAME="DEV"        # or "PERSONAL" / "WORK"' \
  "ACCOUNT_COLOR='\033[32m'  # Green DEV, '\033[36m' Cyan PERSONAL, '\033[33m' Yellow WORK"
```

The `head -13` / `tail -n +16` split assumes the config block sits on lines 14-15. Keep it there when editing the template header, or every regenerated copy loses its label.

Verify only the config block differs:
```bash
for a in personal work dev; do
  diff <(sed '14,15d' statusline.sh) <(sed '14,15d' ~/.claude-$a/statusline.sh) \
    && echo "$a: in sync"
done
```

#### Notes

- **Requires** bash 3.2+ (macOS stock `/bin/bash` works), `jq`, and `git`. Developed against Claude Code 2.1.235; the PR and rate limit fields need a recent version.
- Git state is cached for 5 seconds in `/tmp`, keyed per uid and per directory so concurrent sessions in different repos cannot overwrite each other's branch.
- All session data arrives as JSON on stdin from Claude Code. The script only formats it — see the [status line docs](https://code.claude.com/docs/en/statusline) for the full schema.

### iTerm2 tab status

Paints the iTerm2 tab of whichever session is running, so you can see at a glance which
of several tabs still needs you. Driven entirely by hooks — no polling, no daemon.

| State | Tab | Fired by |
|-------|-----|----------|
| Working | pulses orange (breathing, ~2s cycle) | `UserPromptSubmit`, `PostToolUse` |
| Needs input or permission | red, dock bounces until focused, `input?` badge | `Notification` |
| Finished | blinks green x4 then stays green, one dock bounce, `done` badge | `Stop` |
| Idle / cleared | tab colour removed | `SessionStart`, `SessionEnd` |

#### Setup

One shared copy serves every account — the hooks reference it by absolute path:

```bash
mkdir -p ~/.local/bin
cp iterm-tab-status.sh ~/.local/bin/claude-iterm-tab-status.sh
chmod +x ~/.local/bin/claude-iterm-tab-status.sh
```

Then wire it into each account's `settings.json` (already present in the tracked copies):

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash ~/.local/bin/claude-iterm-tab-status.sh busy",    "async": true }] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "bash ~/.local/bin/claude-iterm-tab-status.sh busy",    "async": true }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "bash ~/.local/bin/claude-iterm-tab-status.sh waiting" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "bash ~/.local/bin/claude-iterm-tab-status.sh done",    "async": true }] }],
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "bash ~/.local/bin/claude-iterm-tab-status.sh reset" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "bash ~/.local/bin/claude-iterm-tab-status.sh reset" }] }]
  }
}
```

`async: true` on `busy` and `done` keeps the ~2s blink animation off the critical path.

> Because `CLAUDE_CONFIG_DIR` replaces the config home outright, the accounts share
> nothing — hooks added to one do **not** apply to the others. Every account needs its
> own entry, which is why all three tracked `settings.json` files carry the block.

#### How it works

The tab is painted with iTerm2's proprietary escape sequences — `OSC 6;1;bg;...` for the
tab colour, `OSC 1337;SetBadgeFormat` and `RequestAttention` for the badge and dock bounce.

The awkward part is getting those bytes to the terminal at all. **Hooks are spawned
detached from the controlling terminal**, so `/dev/tty` fails with `device not configured`,
and `ps -o tty= -p $PPID` reports `??` because the immediate parent is an intermediate
shell with no tty either. The script therefore walks up the process tree until it finds the
`claude` CLI, which does own the pty, and writes straight to that device:

```bash
find_tty() {
  local p=$PPID t a i=0
  while [ "$i" -lt 8 ] && [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ]; do
    read -r t a <<< "$(ps -o tty=,ppid= -p "$p")"
    case "${t:-??}" in
      '?' | '??') ;;
      *) printf '%s' "$t"; return 0 ;;
    esac
    p="$a"; i=$((i + 1))
  done
  return 1
}
# -> /dev/ttys006
```

The orange pulse is a detached background loop, tracked by a pidfile keyed to the tty in
`$TMPDIR`. Consequences worth knowing:

- **`busy` is idempotent.** It has to be — it is wired to `PostToolUse`, which fires
  constantly. A repeat call finds the running animation and returns immediately rather
  than stacking a second one. That is also what restores orange after you approve a
  permission prompt, since there is no "permission granted" event to hook.
  Two hooks *can* still race past that check and both spawn a loop, so ownership of the
  pidfile is re-tested every frame using shell builtins only (no fork): the loser exits
  within one 0.15s tick rather than fighting for the tab.
- **Every transition claims the tab** by writing its pid to a generation file, and the
  `done` blink re-checks that claim before each write. Since `Stop` runs asynchronously,
  its ~1.8s animation would otherwise keep painting after a new prompt or a `SessionEnd`
  had already moved on, leaving a green tab over a session that is actually working.
  A superseded blink now aborts mid-animation.
- **A pid is never signalled without confirming what it is.** Pidfiles can outlive their
  animation (the `claude` process died, the tty vanished, the iteration cap hit) and the
  OS reuses pids, so `kill` is gated on the target's command line actually being one of
  these animation processes. A self-exiting loop also clears its own pidfile, but only
  while it still owns it.
- **The animation cannot outlive its session.** Every ~2s it re-checks that the tty still
  exists and the `claude` process is alive, plus a hard iteration cap as a backstop.
- **Accounts in different tabs never collide**, because state is keyed by tty name.
- A state file stops Claude Code's 60-second idle `Notification` from flipping a finished
  green tab to red — `waiting` is ignored when the state is already `done`.

#### Knobs

At the top of the script:

| Variable | Default | Effect |
|----------|---------|--------|
| `PULSE` | `1` | `0` = steady orange instead of the breathing animation |
| `BADGE` | `1` | `0` = no translucent in-pane badge |
| `BLINKS` | `4` | Green blink cycles on completion |
| `BLINK_DELAY` / `PULSE_DELAY` | `0.22` / `0.15` | Animation timing, seconds |

Colours are the `tabcolor r g b` calls in each branch of the `case`.

#### Notes

- **macOS + iTerm2 only.** The escape codes are iTerm2 extensions; Windows Terminal
  ignores them silently, and there is no writable pty device to target there anyway. The
  script exits cleanly when `$TERM_PROGRAM` is not `iTerm.app`, so it is harmless to
  install everywhere.
- For a cross-platform equivalent, Claude Code's built-in `"terminalProgressBarEnabled": true`
  emits `OSC 9;4`, which Windows Terminal renders as taskbar progress. It is emitted
  in-process, so it sidesteps the detached-terminal problem entirely.

### Account settings

`claude-personal/settings.json`, `claude-work/settings.json`, and `claude-dev/settings.json` are copies of the live files from each account directory.

> **Sanitized.** The `autoMode` block is stripped before committing. It holds auto-generated environment context about whichever client repo was last worked in (org name, CI secret names, protected branches, internal hostnames) and does not belong in a public repo. Re-add it locally by simply using Claude Code; it regenerates on its own.

Restore with:
```bash
cp claude-personal/settings.json ~/.claude-personal/settings.json
cp claude-work/settings.json     ~/.claude-work/settings.json
cp claude-dev/settings.json      ~/.claude-dev/settings.json
```

### Global config
The root `CLAUDE.md` contains shared preferences. Copy it to every account directory:
```bash
cp CLAUDE.md ~/.claude-personal/CLAUDE.md
cp CLAUDE.md ~/.claude-work/CLAUDE.md
cp CLAUDE.md ~/.claude-dev/CLAUDE.md
```

### Global skills
Copy skills to every account directory:
```bash
cp -r .claude/skills/* ~/.claude-personal/skills/
cp -r .claude/skills/* ~/.claude-dev/skills/

# Work gets everything except nextjs-conventions, which is personal-stack only
for s in .claude/skills/*/; do
  [ "$(basename "$s")" = "nextjs-conventions" ] && continue
  cp -r "$s" ~/.claude-work/skills/
done
```

### Project-level config
Each project directory (`wp-projects/`, `nextjs-projects/`) has its own `CLAUDE.md` and `.claude/skills/`. When running Claude Code from within a project directory, it automatically loads:
1. `~/.claude-{account}/CLAUDE.md` (global preferences)
2. The project's own `CLAUDE.md` (project-specific standards)
3. Skills from `.claude/skills/` (auto-discovered)

## Using Skills

Skills provide scaffold and runtime code patterns that Claude loads on-demand.

### Automatic
Claude reads each skill's `description` field and auto-triggers when your prompt matches. For example, asking "add a contact form" in a Next.js project will automatically load the `nextjs` skill — no action needed.

### Manual
Type `/nextjs` or `/wordpress` in the chat to invoke a skill directly.

### What loads when
| Layer | When loaded |
|-------|-------------|
| Skill descriptions (YAML frontmatter) | Always in context — used for matching |
| Skill body (SKILL.md content) | When triggered (auto or manual) |
| Supporting files (scaffold.md, patterns.md) | On-demand — only when Claude reads them per the SKILL.md instruction |

## Tech Stack

- **WordPress:** Custom themes, custom plugins, WooCommerce, ACF Pro, Contact Form 7
- **Next.js:** App Router, TypeScript, Tailwind CSS, Prisma, Zod, React Hook Form
- **Deployment:** Vercel, cPanel/VPS, Coolify, Docker
