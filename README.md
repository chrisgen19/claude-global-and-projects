# Claude Code — Global & Project Instructions

Personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration for my development workflow. Contains global preferences, project-specific standards, and reusable skill files for WordPress and Next.js development.

## Structure

```
.
├── CLAUDE.md                              # Global preferences (all projects)
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

### Global config
The root `CLAUDE.md` contains shared preferences. Copy it to `~/.claude/CLAUDE.md` once finalized:
```bash
cp CLAUDE.md ~/.claude/CLAUDE.md
```

### Project-level config
Each project directory (`wp-projects/`, `nextjs-projects/`) has its own `CLAUDE.md` and `.claude/skills/`. When running Claude Code from within a project directory, it automatically loads:
1. `~/.claude/CLAUDE.md` (global preferences)
2. The project's own `CLAUDE.md` (project-specific standards)
3. Skills from `.claude/skills/` (auto-discovered)

## Tech Stack

- **WordPress:** Custom themes, custom plugins, WooCommerce, ACF Pro, Contact Form 7
- **Next.js:** App Router, TypeScript, Tailwind CSS, Prisma, Zod, React Hook Form
- **Deployment:** Vercel, cPanel/VPS, Coolify, Docker
