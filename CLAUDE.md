# Global Preferences — Christian

Full-stack dev (WordPress + Next.js/TypeScript), Philippines. Multiple client projects — confirm project/environment if unclear.

## Compaction
Preserve: project/client, files being edited, decisions made, active errors, git branch, environment context.

## Communication
- Code/commands first, explain after
- Ambiguous → ask to clarify, or propose 1–2 options with tradeoffs
- Warn before production-affecting changes
- Show file path + surrounding context for code changes
- On failure: show error + fix — never silently retry

## Response Format
1. **Plan** (1–3 bullets)
2. **Code / Commands**
3. **Notes / Risks** (+ revert steps)
4. **Verification**

## Code Style
- TypeScript over JS unless project is JS-only
- Named exports except framework defaults (Next.js pages/layouts)
- `function` for components, arrows for utilities. Match existing project style.
- `const` default, `let` when needed, never `var`. `unknown` over `any`.
- Files: `kebab-case` | Components: `PascalCase` | Vars/functions: `camelCase` | Constants: `UPPER_SNAKE` | DB columns: `snake_case`
- Functions ≤ 50 lines, components ≤ 150 lines
- No `console.log` in commits. Handle loading/error/empty states.
- JSDoc for non-self-explanatory functions. Prefer backward-compatible, non-breaking changes.

## Tooling
- `pnpm` unless project uses something else. Node 20+.
- Follow existing lint/format/test configs. Don't add tooling without asking.

## Tech Preferences
- Framework: Next.js App Router (primary), React + Vite when appropriate
- Icons: Lucide React. Animation: Framer Motion when needed.
- DB: MySQL (WordPress), PostgreSQL (Next.js). ORM: Prisma (primary), Drizzle as alternative.

## Deployment
- **Production:** Vercel (Next.js), cPanel/VPS (WordPress)
- **Staging:** Coolify (self-hosted) or Vercel preview deployments
- **CI/CD:** GitHub Actions or Coolify auto-deploy via webhooks
- **Containers:** Docker when using Coolify/Dokploy
- Always double-check target environment (staging vs production) before deploying

## Git
- Conventional commits: `type(scope): description`
- Branches: `feature/*`, `bugfix/*`, `hotfix/*`
- Always check current branch before making changes
- Never commit to `main`/`master`. Lint + type-check first.
- Run tests before pushing (if project has them)
- For significant changes, suggest a PR description
- After code changes → end with ready-to-use commit command.

## Workflow
- **Before:** Understand requirements, check existing patterns, plan complex features
- **While:** Follow project patterns, write incrementally, handle edge cases, type as you go

## After Code Changes
- Check for hardcoded values that should be env vars
- Check for security issues (XSS, SQL injection, exposed secrets)
- Verify responsive/mobile behavior
- Suggest tests if logic is complex or critical
- For TS/React/Next.js: run `pnpm lint` + `pnpm type-check` before done
- Summarize changes + remaining follow-ups

## Security
- No hardcoded secrets — `.env` locally, env vars in prod
- Validate/sanitize all input. HTTPS everywhere. Flag issues immediately.
- CSRF protection: nonces (WordPress), CSRF tokens (Next.js)
- File uploads: validate types and sizes

## Don't
- Add dependencies without asking (verify they exist + link to npm/packagist page)
- Over-engineer — minimum complexity for the task
- Create CSS/SCSS when Tailwind handles it
- Use barrel files unless project does
- Add tooling/linting without asking
- Assume project structure — check first
- Change unrelated files without explaining scope
- Use `2>/dev/null` or `2>&1` in Bash commands
