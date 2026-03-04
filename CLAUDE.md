# Global Preferences — Christian

Full-stack dev (WordPress + Next.js/TypeScript), Philippines. Multiple client projects — confirm project/environment if unclear.

## Compaction
Preserve: project/client, files being edited, decisions made, active errors, git branch, environment context.

## Communication
- Code/commands first, explain after
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
- Styling: Tailwind CSS utility classes directly — avoid `@apply` unless necessary
- Forms: React Hook Form + Zod validation
- State: React state/context for simple cases, Zustand for complex state
- Icons: Lucide React. Animation: Framer Motion when needed.
- DB: MySQL (WordPress), PostgreSQL (Next.js). ORM: Prisma (primary), Drizzle as alternative.

## WordPress / PHP
- Follow WordPress Coding Standards. Modern PHP (8.2+: typed properties, readonly, arrow functions, enums, union types).
- Always sanitize/escape: `sanitize_text_field()`, `esc_html()`, `wp_nonce_field()`. Use `$wpdb->prepare()` — never raw SQL.
- Enqueue scripts/styles properly. Prefer hooks over template overrides (especially WooCommerce).
- ACF Pro for custom fields (register in code when possible). CF7 + `wpcf7_before_send_mail` for form processing.
- Plugin dev: OOP with namespacing, unique prefix per client (e.g., `ag_`, `mmg_`). Register activation/deactivation/uninstall hooks.
- Never modify core or third-party plugin files — use hooks and filters only.

## Deployment
- **Production:** Vercel (Next.js), cPanel/VPS (WordPress)
- **Staging:** Coolify (self-hosted) or Vercel preview deployments
- **CI/CD:** GitHub Actions or Coolify auto-deploy via webhooks
- **Containers:** Docker when using Coolify/Dokploy

## Git
- Conventional commits: `type(scope): description` — e.g. `feat(cart): add discount validation`
- Branches: `feature/*`, `bugfix/*`, `hotfix/*`
- Never commit to `main`/`master`. Lint + type-check first.
- After code changes → end with ready-to-use commit command.

## After Code Changes
- Verify responsive/mobile behavior
- Suggest tests if logic is complex or critical
- For TS/React/Next.js: run lint + type-check before done (use project's package manager)
- Summarize changes + remaining follow-ups

## Don't
- Add dependencies without asking (verify they exist + link to npm/packagist page)
- Create CSS/SCSS when Tailwind handles it
- Use barrel files unless project does
- Add tooling/linting without asking
- Change unrelated files without explaining scope
- Use `2>/dev/null` or `2>&1` in Bash commands
