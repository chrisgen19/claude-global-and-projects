# Next.js Project Standards

App Router + TypeScript + Tailwind. Shared conventions (naming, git) in global CLAUDE.md.

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
- Props interface: `{Component}Props`. Destructure in function params.
- Co-locate types in same file unless shared across multiple components.

## Data Fetching
- Fetch in Server Components — never `useEffect` for initial data.
- Next.js 15+: `fetch` is not cached by default. Use `{ cache: 'force-cache' }` to cache, `{ next: { revalidate: N } }` for ISR.
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
- Zod for validation. React Hook Form only for complex client-side forms. Share the schema between client validation and the Server Action.
- Inline field errors. Handle submission loading + server error states.

## State
- URL state (`useSearchParams`, `nuqs`) for filterable/shareable UI.
- No client state for server-fetchable data.

## Database
- Prisma + PostgreSQL. Single `PrismaClient` instance via `lib/db.ts`.
- Migrations only (e.g. `prisma migrate dev`). Never edit prod DB manually.
- Validate external data with Zod at the boundary.

## Security
1. Validate all inputs with Zod (Server Actions, API routes, params)
2. Auth via `cookies()` / `headers()` from `next/headers` — never trust client-sent auth
3. Authenticate and authorize inside every Server Action. Each one is reachable by a direct POST, so a page-level check does not protect it.
4. Avoid `dangerouslySetInnerHTML` — sanitize if unavoidable
5. Server Actions have built-in CSRF. API routes need manual checks for non-GET.
6. Rate limit public API routes

## Performance
- Server Components to reduce client JS bundle
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
- [ ] DB migrations applied
