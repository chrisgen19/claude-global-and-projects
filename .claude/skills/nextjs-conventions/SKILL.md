---
name: nextjs-conventions
description: "Personal Next.js 16 full-stack conventions: App Router, strict TypeScript, Prisma 7 + PostgreSQL, Better Auth, Zod 4, Server Actions, data access layer, Biome, pnpm. Use when scaffolding, implementing, or reviewing features in a personal Next.js project."
---

# Next.js Project Conventions

Standing conventions for my personal Next.js apps. The repo's existing code wins:
if it already does something differently (layout, linter, package manager), match
it and don't migrate unless asked. Code for the patterns below is in
[patterns.md](patterns.md).

## Read the installed docs first
- Next.js ships version-matched docs in `node_modules/next/dist/docs/`. Read the
  relevant guide before using caching, proxy, routing or Server Action APIs, and
  trust it over memory. Its examples still use Zod 3 syntax: translate to Zod 4.
- `AGENTS.md` holds a managed block that `next dev` writes and re-adds. Keep it
  and commit it. `CLAUDE.md` pulls it in with `@AGENTS.md`.
- For any other library, check the installed major in `package.json` first.

## Stack
- Next.js 16 (App Router, Turbopack), React 19.2+, TypeScript strict.
- Node 24 LTS. Node 20 is EOL (Next 16 needs 20.9+, Prisma 7 needs 20.19+).
- pnpm for new projects. In an existing repo, use the manager its lockfile shows.
- Tailwind CSS v4, CSS-first (`@import "tailwindcss"` and `@theme` in
  `globals.css`, no `tailwind.config.*`). shadcn/ui on top.
- Better Auth 1.x. Prisma ORM 7 + PostgreSQL through `@prisma/adapter-pg`.
- Zod 4. Zustand 5 for client state. TanStack Query 5 only where the client
  must fetch. React Hook Form only for complex client-side forms.
- Biome 2 for lint and format (not ESLint/Prettier).

## File layout (defaults for new projects)
```
src/
  app/                     routes; Better Auth handler at app/api/auth/[...all]/route.ts
  actions/                 "use server" files, one per domain (posts.ts)
  schemas/                 Zod schemas shared by forms and actions
  components/ui/           shadcn primitives (CLI-generated)
  lib/env.ts               Zod-validated server env
  lib/public-env.ts        NEXT_PUBLIC_* values, client-safe
  lib/db.ts                PrismaClient singleton, imported only by the DAL
  lib/dal.ts               data access layer; becomes lib/dal/<domain>.ts as it grows
  lib/auth.ts              betterAuth() instance (server)
  lib/auth-client.ts       createAuthClient() (client)
  generated/prisma/        Prisma client output (gitignored, excluded from Biome)
  proxy.ts                 optional optimistic redirects; must sit in src/ next to app/
```

## Data access layer
- Every Prisma call lives in the DAL. Pages, components, route handlers and
  actions call DAL functions, never `db`.
- DAL files start with `import "server-only"`.
- The DAL authorizes: it gets the user from the session (`requireUser()`),
  never from client input, and scopes every query by owner.
- Return minimal DTOs (only what the UI renders), not raw Prisma rows.
- Wrap per-request reads such as the session in React `cache()`.

## Server Actions
- Every exported action is a public POST endpoint. A page-level auth check does
  not protect the actions on that page.
- Order inside an action: authenticate, `safeParse` with Zod, call the DAL,
  update the cache, return a small typed result.
- Accept an ID plus the change, never a whole record. Ownership comes from the
  session.
- Expected failures return `{ ok: false, error, fieldErrors? }`; throw only for
  the unexpected.
- `redirect()` throws: call it outside `try/catch` and after cache updates.
- A `"use server"` file can only export async functions (type exports are fine).
  Keep schemas and constants in `src/schemas/` or a plain module.
- Actions are for mutations. The client runs them one at a time, so never use
  one as a fetcher (for example a TanStack `queryFn`).
- Cache updates: `updateTag(tag)` when the user must see their own write,
  `revalidateTag(tag, "max")` (the profile is required in 16),
  `revalidatePath(path)`, or `refresh()`.

## Next.js 16 rules
- `params`, `searchParams`, `cookies()` and `headers()` are async: await them.
  Type pages with the global `PageProps<"/posts/[id]">` and `LayoutProps` helpers.
- `middleware.ts` is deprecated. Use `proxy.ts` exporting `proxy()` (Node runtime).
- Proxy does optimistic checks only: cookie presence (`getSessionCookie`) and
  redirects, no database calls. Real checks live in the DAL and actions.
- Server Components by default; `"use client"` at the leaves, with DTO props.
- With `cacheComponents: true`, shared reads use `"use cache"` + `cacheTag` +
  `cacheLife`. Never call `cookies()` or `headers()` inside a `"use cache"`
  function (pass the value in, or use `"use cache: private"`). Keep secrets and
  personal data out of cache keys and tags.
- Parallel route slots need a `default.tsx`.
- `next lint` is gone and `next build` no longer lints: run the linter yourself.

## Better Auth
- `lib/auth.ts`: `betterAuth({ database: prismaAdapter(db, { provider: "postgresql" }) })`,
  with `nextCookies()` as the last plugin so actions can set cookies.
- Server session: `auth.api.getSession({ headers: await headers() })`.
- Schema: `pnpm dlx auth@<installed better-auth version> generate`, then a Prisma
  migration. Env: `BETTER_AUTH_SECRET` (32+ chars) and `BETTER_AUTH_URL`.

## Prisma 7
- Pin the major: `prisma@7`, `@prisma/client@7`, `@prisma/adapter-pg@7`. The npm
  `latest` tag is a Prisma 8 release candidate with breaking schema and API
  changes. Don't move to 8 unless asked.
- Generator `provider = "prisma-client"` with a required `output`. Import from
  `@/generated/prisma/client`, not `@prisma/client`.
- `prisma.config.ts` holds the datasource URL and does not load `.env` itself.
- `migrate dev` no longer runs `generate` or the seed. Run `prisma generate`
  (keep a `postinstall`) and `prisma db seed` yourself.
- `$use` middleware is gone: use Client Extensions.
- Schema changes go through migrations (`migrate dev` locally, `migrate deploy`
  in production). No `db push` against a shared database.

## Zod 4
- Formats are top level: `z.email()`, `z.url()`, `z.uuid()`.
- Messages use `{ error: "..." }`, not `message`, `invalid_type_error` or
  `required_error`.
- `z.flattenError(err).fieldErrors` and `z.treeifyError(err)` replace
  `.flatten()` and `.format()`.
- `z.strictObject()` / `z.looseObject()` replace `.strict()` / `.passthrough()`.
  `z.record()` takes a key and a value schema.

## Environment variables
- Feature code reads env only through `lib/env.ts` (`import "server-only"`,
  Zod-validated). Exceptions: `next.config.ts`, `prisma.config.ts` and
  `process.env.NODE_ENV`.
- Validate secrets the build doesn't need lazily (a function, not top-level
  parse) so `next build` runs without them.
- `NEXT_PUBLIC_*` values are inlined at build time only when written literally as
  `process.env.NEXT_PUBLIC_X`. Parsing or destructuring `process.env` breaks that,
  so list them one by one in `lib/public-env.ts`.

## Fetching, state and forms
- Initial data: fetch in Server Components through the DAL. No `useEffect` fetching.
- TanStack Query only for client-driven needs (polling, infinite lists, heavy
  optimistic updates). Its `queryFn` calls a GET Route Handler. Prefetch on the
  server and pass `HydrationBoundary`, with `staleTime` above 0.
- Zustand holds client UI state only. Create stores per request with
  `createStore` + a context provider. Server Components never touch a store.
- Filters, tabs and pagination go in search params.
- Forms: `<form action>` + `useActionState` + `useFormStatus` by default. For React
  Hook Form, use `zodResolver` (`@hookform/resolvers` 5.1+ for Zod 4) with the
  shared schema, and validate again in the action.

## Tooling
- `biome.json`: `linter.domains` `next` and `react` set to `"recommended"`,
  `css.parser.tailwindDirectives: true`, generated code excluded. Fix with
  `pnpm biome check --write .`, and use `pnpm biome ci` in CI.
- pnpm 11+: every dependency build script needs an explicit `true`/`false` under
  `allowBuilds` in `pnpm-workspace.yaml`, or scripts abort with
  `ERR_PNPM_IGNORED_BUILDS` (Prisma needs `prisma` and `@prisma/engines` set to
  `true`). Settings other than auth and registry live there, not in `.npmrc`.
- Pin `packageManager` (`pnpm@<version>`) in `package.json` so CI and Coolify run
  the same pnpm major.
- shadcn: `pnpm dlx shadcn@latest add <name>`. Don't hand-write files in
  `components/ui/`. Follow the repo's `components.json` (Radix or Base UI).
- New project: `pnpm create next-app@latest <name> --ts --tailwind --biome --app
  --src-dir --import-alias "@/*" --use-pnpm` (it adds `AGENTS.md` by default).

## Before calling it done
Use the repo's scripts when they exist (`pnpm typecheck`, `pnpm lint`,
`pnpm check`). Otherwise run, and fix what they report:
1. `pnpm next typegen && pnpm tsc --noEmit` (route types such as `PageProps` come
   from typegen; plain `tsc` misses them).
2. `pnpm biome check .`
3. `pnpm build` when the change touches routing, caching, proxy or config.

## Don't
- Add ESLint or Prettier to a Biome repo, or swap an existing repo's linter.
- Call Prisma outside the DAL or read `process.env` outside `env.ts`.
- Add a state, data-fetching or form library the stack already covers.
- Create `middleware.ts`, call `revalidateTag` without a profile, or upgrade a
  major version (Next, Prisma, Zod, Tailwind) unasked.
