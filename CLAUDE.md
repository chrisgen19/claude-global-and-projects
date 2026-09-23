# Global Preferences: Christian

Full-stack dev (WordPress + Next.js/TypeScript), Philippines. Multiple client projects, confirm project/environment if unclear.

## Compaction
Preserve: project/client, files being edited, decisions made, active errors, git branch, environment context.

## Communication
- Code/commands first, explain after
- Warn before production-affecting changes
- Show file path + surrounding context for code changes
- On failure: show error + fix, never silently retry

## Response Format
1. **Plan** (1-3 bullets)
2. **Code / Commands**
3. **Notes / Risks** (+ revert steps)
4. **Verification**

## Code Style (JS/TS)
- TypeScript over JS unless project is JS-only
- Named exports except framework defaults (Next.js pages/layouts)
- `function` for components, arrows for utilities. Match existing project style.
- `const` default, `let` when needed, never `var`. `unknown` over `any`.
- Files: `kebab-case` | Components: `PascalCase` | Vars/functions: `camelCase` | Constants: `UPPER_SNAKE` | DB columns: `snake_case`
- Functions ≤ 50 lines, components ≤ 150 lines
- No `console.log` in commits. Handle loading/error/empty states.
- JSDoc for non-self-explanatory functions. Prefer backward-compatible, non-breaking changes.

For PHP naming and conventions, see project-level CLAUDE.md.

## Tooling
- `pnpm` unless project uses something else. Node 20+.
- Follow existing lint/format/test configs. Don't add tooling without asking.

## Tech Preferences
- Framework: Next.js App Router (primary), React + Vite when appropriate
- Styling: Tailwind CSS utility classes directly, avoid `@apply` unless necessary
- Forms: React Hook Form + Zod validation
- State: React state/context for simple cases, Zustand for complex state
- Icons: Lucide React. Animation: Framer Motion when needed.
- DB: MySQL (WordPress), PostgreSQL (Next.js). ORM: Prisma (primary), Drizzle as alternative.

## Deployment
- **Production:** Vercel (Next.js), cPanel/VPS (WordPress)
- **Staging:** Coolify (self-hosted) or Vercel preview deployments
- **CI/CD:** GitHub Actions or Coolify auto-deploy via webhooks
- **Containers:** Docker when using Coolify/Dokploy

## Git
- Follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):
  ```
  <type>[optional scope][optional !]: <description>

  [optional body]

  [optional footer(s)]
  ```
- **Allowed types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
- **Scope:** optional, in parentheses, e.g. `feat(cart): add discount validation`
- **Breaking changes:** add `!` before colon and/or `BREAKING CHANGE:` footer, e.g. `feat(api)!: change response format`
- **Body:** optional, separated by blank line, use for non-obvious "why" behind the change
- **Footers:** optional, separated by blank line, e.g. `Reviewed-by: name`, `Refs: #123`
- Branches: `feature/*`, `bugfix/*`, `hotfix/*`
- Never commit to `main`/`master`. Lint + type-check first.
- After code changes → end with ready-to-use commit command.

## After Code Changes
- Verify responsive/mobile behavior
- Suggest tests if logic is complex or critical
- For TS/React/Next.js: run lint + type-check before done (use project's package manager)
- Summarize changes + remaining follow-ups

## Things I Don't Want
- Don't add new packages without asking first: prefer native APIs or existing dependencies; if a new one is truly needed, verify it exists and link to its npm/packagist page
- Don't over-engineer simple features with complex design patterns
- Don't create separate CSS/SCSS files when Tailwind can handle it
- Don't use `index.ts` barrel files unless the project already uses them
- Don't introduce new linting rules, formatters, or tooling without asking first
- Don't assume the project structure: check first, then follow existing conventions
- Don't make changes across multiple unrelated files in one go without explaining the scope
- Never use em dashes or en dashes anywhere: chat replies, code, comments, commit messages, PR titles/descriptions/comments, or Jira. Use hyphens, colons, commas, or parentheses instead.
- NEVER add `2>&1`, `2>/dev/null` or any other stderr redirection to Bash commands. The Bash tool already captures stderr, and the `&` in `2>&1` can make the permission checker split one command into two (`cmd 2>` and `1`), which triggers a prompt or a denial. To cut noise, pipe into `grep` or `head` instead.
