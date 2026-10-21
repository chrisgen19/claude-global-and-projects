# Next.js Project Standards

App Router + TypeScript + Tailwind. Targets Next.js 16, Tailwind 4, Prisma 7, Zod 4; on older majors follow the project's code and don't upgrade unasked. Shared conventions (naming, git) in global CLAUDE.md.

## Structure
```
src/
├── app/                     # App Router (layouts, pages, routes)
│   ├── (auth)/              # Route groups for layout variants
│   ├── api/                 # Route Handlers
│   ├── layout.tsx           # Root layout (default export)
│   ├── page.tsx             # Home page (default export)
│   ├── error.tsx            # Error boundary
│   ├── loading.tsx          # Loading UI
│   └── not-found.tsx        # 404
├── components/
│   ├── ui/                  # Reusable primitives (button, input, card)
│   └── [feature]/           # Feature-specific components
├── lib/                     # DB client, auth config, shared utilities
├── generated/prisma/        # Prisma 7 client output (gitignored)
├── hooks/                   # Custom React hooks
├── types/                   # Shared TypeScript types/interfaces
├── schemas/                 # Zod validation schemas
├── stores/                  # Zustand stores (if needed)
└── proxy.ts                 # Next.js 16 rename of middleware.ts (see Security)
```

## Components
- Server Components by default. `'use client'` only when needed (hooks, events, browser APIs).
- Props interface: `{Component}Props`. Destructure in function params.
- Co-locate types in same file unless shared across multiple components.

## Data Fetching
- Fetch in Server Components, never `useEffect` for initial data.
- With `cacheComponents: true` (the scaffold default on Next.js 16): cache shared reads with `"use cache"` plus `cacheLife` and `cacheTag`, and read `cookies()`, `params` and `searchParams` inside `<Suspense>`.
- Without the flag: `fetch` is not cached by default (15+). Use `{ cache: 'force-cache' }` to cache, `{ next: { revalidate: N } }` for ISR, `unstable_cache` for DB reads.
- Server Actions (`'use server'`) for mutations. Validate with Zod before processing.
- After a mutation: `updateTag(tag)` in a Server Action when the user must see their own write, else `revalidateTag(tag, 'max')` (profile arg required in 16) or `revalidatePath()`.
- Parallel fetches with `Promise.all()` when data is independent.

## API Routes
- Route Handlers (`app/api/*/route.ts`) for webhooks, external integrations, non-form mutations.
- Return `NextResponse.json()` with proper status codes.

## Styling
- Tailwind CSS only. `cn()` utility (clsx + twMerge) for conditional classes.
- Mobile-first responsive (`sm:`, `md:`, `lg:`). Dark mode via `dark:` variant if needed.

## Forms
- `<form action>` + `useActionState` by default; React Hook Form only for complex client-side forms. Share one Zod schema (in `schemas/`) between client validation and the Server Action.
- Inline field errors. Handle submission loading + server error states.

## State
- URL state (`searchParams` / `useSearchParams`, or `nuqs` if already installed) for filterable/shareable UI.
- No client state for server-fetchable data.

## Database
- Prisma 7 + PostgreSQL. Single `PrismaClient` instance via `lib/db.ts`. Import from `@/generated/prisma/client`, not `@prisma/client`; run `prisma generate` after schema changes.
- Migrations only: `prisma migrate dev` locally, `prisma migrate deploy` for staging/prod. Never edit prod DB manually.

## Security
1. Validate all inputs with Zod (Server Actions, API routes, params)
2. Auth via `cookies()` / `headers()` from `next/headers`, never trust client-sent auth
3. Authenticate and authorize inside every Server Action. Each one is reachable by a direct POST, so a page-level check does not protect it.
4. Avoid `dangerouslySetInnerHTML`: sanitize if unavoidable
5. Server Actions have built-in CSRF. API routes need manual checks for non-GET.
6. Rate limit public API routes
7. `proxy.ts` (keep `middleware.ts` on Next.js 15) does optimistic cookie checks only, no DB calls. Real authorization lives in pages, Server Actions and the data layer.

## Performance
- `next/image` for images. `next/font` for fonts. `next/dynamic` for heavy client components.
- Targets: LCP < 2.5s, CLS < 0.1, INP < 200ms

## Environment
- `.env.local` for dev (gitignored). Vercel/Coolify env vars for staging/prod.
- Client-exposed vars: `NEXT_PUBLIC_` prefix.
- Validate env vars with Zod via `lib/env.ts`.

## Deploy Checklist
- [ ] Lint + type-check pass
- [ ] Build succeeds
- [ ] Env vars set for target environment
- [ ] DB migrations applied (`prisma migrate deploy`)
