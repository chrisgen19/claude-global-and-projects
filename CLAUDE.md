# Global Preferences: Christian

Full-stack dev (WordPress + Next.js/TypeScript), Philippines. Multiple client projects, confirm project/environment if unclear.

## Compaction
Preserve: project/client, files being edited, decisions made, active errors, git branch, environment (local, staging or production).

## Communication
- Keep prose short: code and commands before long explanation
- Before production-affecting changes: warn and wait for a go-ahead
- On failure: show error + fix, never silently retry

## Accuracy
- Before stating how existing code works, read it and cite `path/to/file.ts:42`. If you haven't checked, say so instead of guessing.
- For library APIs, props and config options, go by the installed version rather than memory: its types or bundled docs in `node_modules`, or the docs for the version in the lockfile. Especially for fast-moving libraries (Next.js, Prisma, Zod).

## Response Format
For code changes, in this order (skip a section with nothing to say):
1. **Summary**: 1-3 bullets on what changed, or the plan if nothing is applied yet
2. **Code / Commands**: file paths with the key code in context, and commands run or to run
3. **Notes / Risks**: what could break, revert steps, remaining follow-ups
4. **Verification**: checks run and their results, then what to check by hand
5. **Commit**: ready-to-use commit command

For questions, research and reviews: answer first, then the evidence. No fixed sections.

## Code Style (JS/TS)
Defaults for new code. In an existing project, its style wins.
- TypeScript over JS unless project is JS-only
- Named exports except framework defaults (Next.js pages/layouts)
- `function` for components, arrows for utilities
- `unknown` over `any`
- Files: `kebab-case` | Components: `PascalCase` | Vars/functions: `camelCase` | Constants: `UPPER_SNAKE` | DB columns: `snake_case`
- Functions ≤ 50 lines, components ≤ 150 lines
- No `console.log` in commits. Handle loading/error/empty states.
- JSDoc for non-self-explanatory functions. Prefer backward-compatible changes.

## Tooling
- `pnpm` unless project uses something else. Node 24 LTS.
- Follow existing lint/format/test configs. Don't add tooling or change lint rules without asking.

## Tech Preferences
- Framework: Next.js App Router (primary), React + Vite when appropriate
- Styling (Next.js/React): Tailwind CSS utility classes directly, avoid `@apply` unless necessary
- Forms: Zod validation. React Hook Form for complex client-side forms.
- State: React state/context for simple cases, Zustand for complex state
- Icons: Lucide React. Animation: Motion (`motion` package) when needed.
- DB: MySQL (WordPress), PostgreSQL (Next.js). ORM: Prisma (primary), Drizzle as alternative.

## Deployment
- **Production:** Vercel or Coolify (Next.js), cPanel/VPS (WordPress)
- **Staging:** Vercel preview deployments or Coolify previews
- **CI/CD:** GitHub Actions or Coolify auto-deploy via webhooks
- **Containers:** Docker when using Coolify/Dokploy

## Git
- Commits follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/), e.g. `feat(cart): add discount validation`, or `feat(api)!: change response format` for a breaking change
- Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
- Body only for the non-obvious "why". Footers when needed, e.g. `Refs: #123`
- Branches: `feature/*`, `bugfix/*`, `hotfix/*`. Never commit to `main`/`master`: work on a branch.

## After Code Changes
- TS/React/Next.js: run the project's lint + type-check before committing or calling it done
- UI changes: check the layout at mobile width, or say it was not checked
- Suggest tests if logic is complex or critical

## Superpowers Plugin
- For small fixes, skip the superpowers `brainstorming` and `using-git-worktrees` skills: go straight to the fix on the current branch. A small fix is a bug fix, typo, copy/style tweak, config change or one-file change with a clear expected result.
- Still use brainstorming and worktrees for new features, multi-file changes, or when the requirements are unclear. If unsure which this is, ask in one line.

## Things I Don't Want
- Don't add new packages without asking first: prefer native APIs or existing dependencies. When suggesting a new package, verify it exists and link to its npm/packagist page
- Don't over-engineer simple features with complex design patterns
- Don't create separate CSS/SCSS files when Tailwind can handle it
- Don't use `index.ts` barrel files unless the project already uses them
- Don't assume the project structure: check first, then follow existing conventions
- Don't make changes across multiple unrelated files in one go without explaining the scope
- Never use em dashes or en dashes in text you write: chat replies, code comments, docs, commit messages, PR titles/descriptions/comments, or Jira. Use hyphens, colons, commas, or parentheses instead. Leave existing dashes in code, content and strings alone (translation strings and tests may depend on them).
- NEVER add `2>&1`, `2>/dev/null` or any other stderr redirection to commands you run with the Bash tool. It already captures stderr, so redirection is unnecessary, and `2>/dev/null` hides errors from Claude. Scripts you write may redirect stderr where the script needs it.
- Run builds, tests, installs and migrations without piping their output into anything (`head`, `tail`, `grep`, `sed`, `wc`...): the pipe hides the exit code, and `head` or `grep -q` can end the command early. Don't silence them with `--silent` either, since that also hides the error. The Bash tool saves long output to a file, so read that instead. Piping is fine for read-only commands like `git log` or `ls`.
