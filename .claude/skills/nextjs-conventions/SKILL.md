---
name: nextjs-conventions
description: Personal Next.js full-stack conventions — App Router, TypeScript strict, Prisma, Better Auth, server actions, and file-layout rules. Use when implementing or reviewing features in a personal Next.js project.
---

# Next.js Project Conventions

These are the standing conventions for my personal Next.js apps. Follow them
unless the repo's existing code clearly does otherwise — match the repo first.

## Stack
- Next.js 15, App Router, TypeScript (strict).
- Package manager: pnpm (never npm/yarn). Use `pnpm` for all installs/scripts.
- Tailwind CSS v4, shadcn/ui for components.
- Auth: Better Auth.
- Data: Prisma + PostgreSQL.
- Server state: TanStack Query v5. Client state: Zustand. Validation: Zod.
- Lint/format: Biome (not ESLint/Prettier).

## File layout (hard rules)
- Server Actions live in `src/actions/`. Do not inline mutations in components.
- ALL database queries go through the data access layer in `src/lib/dal.ts`.
  Never call Prisma directly from a component, route, or action — go via the DAL.
- Environment variables are accessed through `src/lib/env.ts` (validated with
  Zod), never `process.env` directly in feature code.
- Auth setup/config lives in `src/lib/auth.ts`.

## Conventions
- Validate all external input (form data, request bodies, params) with Zod
  before use.
- Prefer Server Components; mark Client Components with "use client" only when
  interactivity requires it.
- Keep components typed; no `any`. Respect strict mode.
- Use TanStack Query for client-side server-state fetching; don't hand-roll
  fetch + useEffect for that.
- Run `pnpm biome check` (or the repo's lint script) and `pnpm tsc --noEmit`
  before considering work done; fix what they surface.

## What NOT to do
- Don't add ESLint/Prettier configs.
- Don't scatter Prisma calls outside the DAL.
- Don't read process.env outside env.ts.
- Don't introduce a new state/data library when Zustand/TanStack already cover it.