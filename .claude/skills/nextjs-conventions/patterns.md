# Next.js Patterns

Reference code for the conventions in [SKILL.md](SKILL.md). Adapt names to the
feature; match the repo when it already has its own version of a file.

## Env: `src/lib/env.ts` and `src/lib/public-env.ts`
```ts
// src/lib/env.ts
import "server-only";
import { z } from "zod";

// Needed by the build and every request: checked when the module loads.
const coreSchema = z.object({
  DATABASE_URL: z.url(),
});

export const env = coreSchema.parse(process.env);

// Request-time only: checked on first use, so `next build` runs without them.
const authSchema = z.object({
  BETTER_AUTH_SECRET: z.string().min(32),
  BETTER_AUTH_URL: z.url(),
});

let authEnvCache: z.infer<typeof authSchema> | undefined;

export function authEnv() {
  authEnvCache ??= authSchema.parse(process.env);
  return authEnvCache;
}
```

```ts
// src/lib/public-env.ts
import { z } from "zod";

// Each value is written out literally so Next.js can inline it at build time.
export const publicEnv = z
  .object({ NEXT_PUBLIC_SITE_URL: z.url() })
  .parse({ NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL });
```

## Prisma 7: schema, config and client
```prisma
// prisma/schema.prisma
generator client {
  provider = "prisma-client"
  output   = "../src/generated/prisma"
}

datasource db {
  provider = "postgresql"
}
```

```ts
// prisma.config.ts
import "dotenv/config";
import { defineConfig } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: { path: "prisma/migrations", seed: "tsx prisma/seed.ts" },
  // process.env, not Prisma's env(): env() throws when the variable is unset,
  // which breaks `prisma generate` in postinstall on CI and Docker installs.
  datasource: { url: process.env.DATABASE_URL },
});
```

```ts
// src/lib/db.ts
import "server-only";
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "@/generated/prisma/client";
import { env } from "@/lib/env";

// One client per process; dev hot reloads would otherwise open a new pool each time.
const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const db =
  globalForPrisma.prisma ??
  new PrismaClient({
    adapter: new PrismaPg({ connectionString: env.DATABASE_URL }),
  });

if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = db;
```

## Better Auth
```ts
// src/lib/auth.ts
import { betterAuth } from "better-auth";
import { prismaAdapter } from "better-auth/adapters/prisma";
import { nextCookies } from "better-auth/next-js";
import { db } from "@/lib/db";

// Reads BETTER_AUTH_SECRET and BETTER_AUTH_URL from the environment. The schema
// CLI (`pnpm dlx auth@<version> generate`) looks for this `auth` export.
export const auth = betterAuth({
  database: prismaAdapter(db, { provider: "postgresql" }),
  emailAndPassword: { enabled: true },
  plugins: [nextCookies()], // must stay last
});
```

```ts
// src/app/api/auth/[...all]/route.ts
import { toNextJsHandler } from "better-auth/next-js";
import { auth } from "@/lib/auth";

export const { GET, POST } = toNextJsHandler(auth);
```

```ts
// src/lib/auth-client.ts
import { createAuthClient } from "better-auth/react";

export const authClient = createAuthClient();
```

If `next build` must run without auth secrets, wrap `betterAuth()` in a lazy
`getAuth()` that builds the instance on first call and reads `authEnv()`.

## Data access layer: `src/lib/dal.ts`
```ts
import "server-only";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { cache } from "react";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";

/** The signed-in user for this request; redirects to sign-in when there is none. */
export const requireUser = cache(async () => {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session) redirect("/sign-in");
  return session.user;
});

export type PostSummary = { id: string; title: string; updatedAt: Date };

export async function listMyPosts(): Promise<PostSummary[]> {
  const user = await requireUser();
  return db.post.findMany({
    where: { authorId: user.id },
    select: { id: true, title: true, updatedAt: true },
    orderBy: { updatedAt: "desc" },
  });
}

/** Renames a post the user owns. Returns false when it is missing or not theirs. */
export async function renamePost(postId: string, title: string) {
  const user = await requireUser();
  const { count } = await db.post.updateMany({
    where: { id: postId, authorId: user.id },
    data: { title },
  });
  return count === 1;
}
```

## Server Action with a shared schema
```ts
// src/schemas/posts.ts
import { z } from "zod";

export const renamePostSchema = z.object({
  postId: z.string().min(1),
  title: z.string().trim().min(1, { error: "Title is required." }).max(120),
});

export type ActionResult =
  | { ok: true }
  | {
      ok: false;
      error: string;
      fieldErrors?: Partial<Record<string, string[]>>;
    };
```

```ts
// src/actions/posts.ts
"use server";

import { updateTag } from "next/cache";
import { z } from "zod";
import { renamePost, requireUser } from "@/lib/dal";
import { type ActionResult, renamePostSchema } from "@/schemas/posts";

export async function renamePostAction(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  await requireUser(); // cached: the DAL's own check reuses it

  const parsed = renamePostSchema.safeParse({
    postId: formData.get("postId"),
    title: formData.get("title"),
  });
  if (!parsed.success) {
    return {
      ok: false,
      error: "Check the highlighted fields.",
      fieldErrors: z.flattenError(parsed.error).fieldErrors,
    };
  }

  const renamed = await renamePost(parsed.data.postId, parsed.data.title);
  if (!renamed) return { ok: false, error: "Post not found." };

  // Tag set by cacheTag() in the cached read. Without Cache Components,
  // use revalidatePath("/posts") instead.
  updateTag("posts");
  return { ok: true };
}
```

```tsx
// src/components/posts/rename-post-form.tsx
"use client";

import { useActionState } from "react";
import { renamePostAction } from "@/actions/posts";

interface RenamePostFormProps {
  postId: string;
  title: string;
}

export function RenamePostForm({ postId, title }: RenamePostFormProps) {
  const [state, formAction, pending] = useActionState(renamePostAction, null);
  const titleError =
    state?.ok === false ? state.fieldErrors?.title?.[0] : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-2 sm:flex-row">
      <input type="hidden" name="postId" value={postId} />
      <input
        name="title"
        defaultValue={title}
        aria-invalid={Boolean(titleError)}
      />
      {titleError && <p className="text-sm text-red-600">{titleError}</p>}
      {state?.ok === false && !titleError && (
        <p className="text-sm text-red-600">{state.error}</p>
      )}
      <button type="submit" disabled={pending}>
        {pending ? "Saving..." : "Save"}
      </button>
    </form>
  );
}
```

## Proxy: `src/proxy.ts`
```ts
import { getSessionCookie } from "better-auth/cookies";
import { type NextRequest, NextResponse } from "next/server";

// Optimistic only: checks that a session cookie exists. The DAL validates the
// session on every read and action.
export function proxy(request: NextRequest) {
  if (!getSessionCookie(request)) {
    return NextResponse.redirect(new URL("/sign-in", request.url));
  }
  return NextResponse.next();
}

export const config = { matcher: ["/dashboard/:path*", "/settings/:path*"] };
```

## Tooling config
`biome.json`. Keep the `$schema` version in step with `@biomejs/biome`. Biome
indents with tabs unless `formatter` says otherwise.
```json
{
  "$schema": "https://biomejs.dev/schemas/2.5.15/schema.json",
  "vcs": { "enabled": true, "clientKind": "git", "useIgnoreFile": true },
  "files": { "includes": ["**", "!src/generated"] },
  "formatter": { "enabled": true, "indentStyle": "space", "indentWidth": 2 },
  "css": { "parser": { "tailwindDirectives": true } },
  "linter": {
    "enabled": true,
    "rules": { "preset": "recommended" },
    "domains": { "next": "recommended", "react": "recommended" }
  },
  "assist": { "actions": { "source": { "organizeImports": "on" } } }
}
```

```yaml
# pnpm-workspace.yaml: every dependency with a build script needs true or false
allowBuilds:
  '@prisma/engines': true
  prisma: true
  sharp: false
```

```json
// package.json scripts
{
  "postinstall": "prisma generate",
  "typecheck": "next typegen && tsc --noEmit",
  "lint": "biome check .",
  "format": "biome format --write .",
  "db:migrate": "prisma migrate dev",
  "db:deploy": "prisma migrate deploy",
  "db:seed": "prisma db seed"
}
```
