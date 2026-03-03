# Next.js Project Standards

App Router + TypeScript + Tailwind. Shared conventions (naming, git, security) in global CLAUDE.md.

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
├── hooks/                   # Custom React hooks
├── types/                   # Shared TypeScript types/interfaces
├── schemas/                 # Zod validation schemas
└── stores/                  # Zustand stores (if needed)
```

## Components
- Server Components by default. `'use client'` only when needed (hooks, events, browser APIs).
- Default export for `page.tsx`, `layout.tsx`, `error.tsx`, `loading.tsx`. Named exports elsewhere.
- Props interface: `{Component}Props`. Destructure in function params.
- Co-locate types in same file unless shared across multiple components.

## Data Fetching
- Fetch in Server Components — never `useEffect` for initial data.
- Next.js fetch caching: default `force-cache`, `{ next: { revalidate: N } }` for ISR, `{ cache: 'no-store' }` for dynamic.
- Server Actions (`'use server'`) for mutations. Validate with Zod before processing.
- `revalidateTag()` / `revalidatePath()` for granular cache invalidation.
- Parallel fetches with `Promise.all()` when data is independent.

## API Routes
- Route Handlers (`app/api/*/route.ts`) for webhooks, external integrations, non-form mutations.
- Return `NextResponse.json()` with proper status codes.
- Validate request body with Zod at the boundary.

## Styling
- Tailwind CSS only. `cn()` utility (clsx + twMerge) for conditional classes.
- Mobile-first responsive (`sm:`, `md:`, `lg:`). Dark mode via `dark:` variant if needed.

## Forms
- React Hook Form + Zod. Share schema between client validation and Server Action.
- Inline field errors. Handle submission loading + server error states.

## State
- URL state (`useSearchParams`, `nuqs`) for filterable/shareable UI.
- React state/context for local. Zustand for complex cross-component state.
- No client state for server-fetchable data.

## Database
- Prisma + PostgreSQL. Single `PrismaClient` instance via `lib/db.ts`.
- Migrations only (`pnpm prisma migrate dev`). Never edit prod DB manually.
- Validate external data with Zod at the boundary.

## Security
1. Validate all inputs with Zod (Server Actions, API routes, params)
2. Auth via `cookies()` / `headers()` from `next/headers` — never trust client-sent auth
3. Avoid `dangerouslySetInnerHTML` — sanitize if unavoidable
4. Server Actions have built-in CSRF. API routes need manual checks for non-GET.
5. Rate limit public API routes

## Performance
- Server Components to reduce client JS bundle
- `next/image` for images. `next/font` for fonts. `next/dynamic` for heavy client components.
- Targets: LCP < 2.5s, CLS < 0.1, INP < 200ms

## Environment
- `.env.local` for dev (gitignored). Vercel/Coolify env vars for staging/prod.
- Client-exposed vars: `NEXT_PUBLIC_` prefix.
- Validate env vars with Zod at build time via `lib/env.ts`.

## Deploy Checklist
- [ ] `pnpm lint` + `pnpm type-check` pass
- [ ] `pnpm build` succeeds
- [ ] Env vars set for target environment
- [ ] DB migrations applied
