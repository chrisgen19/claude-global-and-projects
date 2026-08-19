# Claude Code — Global & Project Instructions

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration for my development workflow. Contains global preferences, project-specific standards, and reusable skill files for WordPress and Next.js development.

## Structure

```
.
├── CLAUDE.md                              # Global preferences (all projects)
├── .zshrc-claude                          # Multi-account shell setup (copy to ~/.zshrc)
├── statusline.sh                          # Status line template (copy to each account dir)
├── claude-personal/                       # Deployed copy of ~/.claude-personal
│   ├── statusline.sh                      #   PERSONAL variant (cyan label)
│   └── settings.json                      #   sanitized — see note below
├── claude-work/                           # Deployed copy of ~/.claude-work
│   ├── statusline.sh                      #   WORK variant (yellow label)
│   └── settings.json                      #   sanitized — see note below
├── .claude/skills/                        # Global skills (cross-project)
│   ├── pr-description/SKILL.md           # Generate PR descriptions from branch diff
│   ├── env-check/SKILL.md               # Audit env vars, secrets, and .env config
│   └── security-audit/SKILL.md          # Scan for vulnerabilities (PHP + JS/TS)
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
- **`/pr-description`** — Reads branch diff and commits, generates a structured PR description with a ready-to-use `gh pr create` command
- **`/env-check`** — Audits environment variables: hardcoded secrets, `.gitignore` coverage, `.env.example` completeness, stack-specific misconfigurations
- **`/security-audit`** — Scans for common vulnerabilities (XSS, SQL injection, missing sanitization, exposed secrets) across PHP/WordPress and JS/TS/Next.js codebases

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

I use two separate Claude accounts (personal and work) with isolated config directories. Add the following to your `~/.zshrc` (or copy from `.zshrc-claude`):

```bash
# Claude CLI accounts
function claude-personal { CLAUDE_CONFIG_DIR="$HOME/.claude-personal" claude "$@"; }
function claude-work { CLAUDE_CONFIG_DIR="$HOME/.claude-work" claude "$@"; }

# Launch VS Code with specific Claude account
function code-personal { CLAUDE_CONFIG_DIR="$HOME/.claude-personal" code "$@"; }
function code-work { CLAUDE_CONFIG_DIR="$HOME/.claude-work" code "$@"; }
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
| `code-work .` | Opens VS Code with work Claude account |
| `code-personal .` | Opens VS Code with personal Claude account |

Each account has its own `CLAUDE.md` and `skills/` directory:
- `~/.claude-work/CLAUDE.md` + `~/.claude-work/skills/*`
- `~/.claude-personal/CLAUDE.md` + `~/.claude-personal/skills/*`

> **Note:** `code-work` / `code-personal` only works when launching VS Code from the terminal. Opening VS Code from Spotlight, Dock, or Finder won't pick up the account.

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

#### Keeping the two copies in sync

The two deployed scripts are identical except lines 14-15. Regenerate the work copy from the personal one rather than hand-editing both, or they silently drift:

```bash
{ head -13 statusline.sh
  printf '%s\n' 'ACCOUNT_NAME="WORK"       # Change to "PERSONAL" for personal account'
  printf '%s\n' "ACCOUNT_COLOR='\033[33m'  # Yellow for WORK, use '\033[36m' (Cyan) for PERSONAL"
  tail -n +16 statusline.sh
} > ~/.claude-work/statusline.sh
```

Verify only the config block differs:
```bash
diff <(sed '14,15d' ~/.claude-personal/statusline.sh) \
     <(sed '14,15d' ~/.claude-work/statusline.sh) && echo "in sync"
```

#### Notes

- **Requires** bash 4+, `jq`, and `git`. Developed against Claude Code 2.1.235; the PR and rate limit fields need a recent version.
- Git state is cached for 5 seconds in `/tmp`, keyed per uid and per directory so concurrent sessions in different repos cannot overwrite each other's branch.
- All session data arrives as JSON on stdin from Claude Code. The script only formats it — see the [status line docs](https://code.claude.com/docs/en/statusline) for the full schema.

### Account settings

`claude-personal/settings.json` and `claude-work/settings.json` are copies of the live files from each account directory.

> **Sanitized.** The `autoMode` block is stripped before committing. It holds auto-generated environment context about whichever client repo was last worked in (org name, CI secret names, protected branches, internal hostnames) and does not belong in a public repo. Re-add it locally by simply using Claude Code; it regenerates on its own.

Restore with:
```bash
cp claude-personal/settings.json ~/.claude-personal/settings.json
cp claude-work/settings.json     ~/.claude-work/settings.json
```

### Global config
The root `CLAUDE.md` contains shared preferences. Copy it to both account directories:
```bash
cp CLAUDE.md ~/.claude-personal/CLAUDE.md
cp CLAUDE.md ~/.claude-work/CLAUDE.md
```

### Global skills
Copy skills to both account directories:
```bash
cp -r .claude/skills/* ~/.claude-personal/skills/
cp -r .claude/skills/* ~/.claude-work/skills/
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
