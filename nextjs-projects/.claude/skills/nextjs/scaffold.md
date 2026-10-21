# Scaffold Patterns

## Root Layout

```tsx
// src/app/layout.tsx
import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "@/app/globals.css";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });

export const metadata: Metadata = {
  title: { default: "Site Name", template: "%s | Site Name" },
  description: "Site description",
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000"),
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={inter.variable}>
      <body className="min-h-screen bg-white text-gray-900 antialiased">
        {children}
      </body>
    </html>
  );
}
```

## Page with Metadata

```tsx
// src/app/services/page.tsx
import type { Metadata } from "next";
import { getServices } from "@/lib/dal";
import { ServiceList } from "@/components/services/service-list";

export const metadata: Metadata = {
  title: "Services",
  description: "Our services",
};

export default async function ServicesPage() {
  const services = await getServices();

  if (services.length === 0) {
    return <p className="py-12 text-center text-gray-500">No services found.</p>;
  }

  return (
    <main className="mx-auto max-w-7xl px-4 py-12">
      <h1 className="mb-8 text-3xl font-bold">Services</h1>
      <ServiceList services={services} />
    </main>
  );
}
```

## Dynamic Route with generateMetadata

```tsx
// src/app/services/[slug]/page.tsx
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { getServiceBySlug, getServiceSlugs } from "@/lib/dal";

type Props = { params: Promise<{ slug: string }> };

// Cache Components needs at least one param here, or the build fails. With no
// published service yet, return a placeholder: no service has this slug, so the
// page below answers it with notFound().
const PLACEHOLDER_SLUG = "__placeholder__";

export async function generateStaticParams() {
  const slugs = await getServiceSlugs();
  if (slugs.length === 0) return [{ slug: PLACEHOLDER_SLUG }];
  return slugs.map((slug) => ({ slug }));
}

// The database read is a cached query, so the metadata can prerender.
export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const service = await getServiceBySlug(slug);
  if (!service) return {};
  return { title: service.title, description: service.excerpt };
}

// The page does not await params. It passes the promise to a child under
// <Suspense>, so the shell also prerenders for slugs not known at build time.
export default function ServicePage({ params }: Props) {
  return (
    <main className="mx-auto max-w-3xl px-4 py-12">
      <Suspense fallback={<p className="text-gray-500">Loading...</p>}>
        <ServiceContent params={params} />
      </Suspense>
    </main>
  );
}

async function ServiceContent({ params }: Props) {
  const { slug } = await params;
  const service = await getServiceBySlug(slug);
  if (!service) notFound();

  return (
    <>
      <h1 className="mb-4 text-3xl font-bold">{service.title}</h1>
      <div className="prose max-w-none">{service.content}</div>
    </>
  );
}
```

## Cached Queries

Reads that many requests share go through `"use cache"` functions in the data access layer. A page can then await them at the top and still prerender. Public reads like these skip `requireUser()` (see Data Access Layer in `patterns.md`): a `"use cache"` function can't read cookies or headers.

```ts
// src/lib/dal.ts
import "server-only";
import { cacheLife, cacheTag } from "next/cache";
import { db } from "@/lib/db";

export async function getServices() {
  "use cache";
  cacheLife("hours");
  cacheTag("services");

  return db.service.findMany({
    where: { published: true },
    orderBy: { createdAt: "desc" },
    select: { id: true, title: true, slug: true, excerpt: true },
  });
}

export async function getServiceSlugs() {
  "use cache";
  cacheLife("hours");
  cacheTag("services");

  const services = await db.service.findMany({
    where: { published: true },
    select: { slug: true },
  });
  return services.map((service) => service.slug);
}

export async function getServiceBySlug(slug: string) {
  "use cache";
  cacheLife("hours");
  cacheTag("services");

  return db.service.findUnique({
    where: { slug, published: true },
    select: { title: true, excerpt: true, content: true },
  });
}
```

## API Route Handler

```ts
// src/app/api/contact/route.ts
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { contactSchema } from "@/schemas/contact";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const result = contactSchema.safeParse(body);

  if (!result.success) {
    return NextResponse.json(
      { error: "Validation failed", issues: z.flattenError(result.error).fieldErrors },
      { status: 400 }
    );
  }

  try {
    // Process validated data
    return NextResponse.json({ success: true }, { status: 200 });
  } catch {
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
```

## Proxy

Next.js 16 renamed `middleware.ts` to `proxy.ts` (Node.js runtime only). On Next.js 15, keep `src/middleware.ts` exporting `middleware`. Use it for optimistic checks: is there a session cookie, no database calls. Real authorization happens in the data access layer and Server Actions.

```ts
// src/proxy.ts
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

## Prisma Setup

### Client singleton

Prisma 7 generates the client into the project and connects through a driver adapter (`@prisma/adapter-pg`). Run `prisma generate` after changing the schema. Only the data access layer (`lib/dal.ts`) and the Better Auth adapter (`lib/auth.ts`) import `db`. It has no `import "server-only"`: the Better Auth CLI loads `auth.ts` and `db.ts` and exits when it meets that import. `dal.ts` keeps the guard.

```ts
// src/lib/db.ts
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "@/generated/prisma/client";
import { env } from "@/lib/env";

const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const db =
  globalForPrisma.prisma ??
  new PrismaClient({
    adapter: new PrismaPg({ connectionString: env.DATABASE_URL }),
  });

if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = db;
```

### prisma.config.ts

```ts
// prisma.config.ts
import "dotenv/config";
import { defineConfig } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: { path: "prisma/migrations", seed: "tsx prisma/seed.ts" },
  // process.env, not Prisma's env(): env() throws when the variable is unset,
  // which breaks `prisma generate` on CI and Docker installs.
  datasource: { url: process.env.DATABASE_URL },
});
```

### Schema example

```prisma
// prisma/schema.prisma
generator client {
  provider = "prisma-client"
  output   = "../src/generated/prisma"
}

datasource db {
  provider = "postgresql"
}

// User, Session, Account and Verification come from the Better Auth CLI (see
// Better Auth below). Add `posts Post[]` to the generated User model.

model Post {
  id          String   @id @default(cuid())
  title       String
  slug        String   @unique
  excerpt     String?
  content     String?
  published   Boolean  @default(false)
  featured    Boolean  @default(false)
  author      User     @relation(fields: [authorId], references: [id])
  authorId    String   @map("author_id")
  publishedAt DateTime? @map("published_at")
  createdAt   DateTime  @default(now()) @map("created_at")
  updatedAt   DateTime  @updatedAt @map("updated_at")

  @@index([authorId])
  @@index([slug])
  @@map("posts")
}

model Service {
  id        String   @id @default(cuid())
  title     String
  slug      String   @unique
  excerpt   String?
  content   String?
  published Boolean  @default(false)
  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")

  @@map("services")
}
```

## Better Auth

Generate the auth models with `pnpm dlx auth@<installed better-auth version> generate`, then run a Prisma migration. The env needs `BETTER_AUTH_SECRET` (32+ chars) and `BETTER_AUTH_URL`.

Sign-up is off (`disableSignUp: true`), which also blocks `auth.api.signUpEmail` on the server. Create accounts in a seed script (see First Account below) or an admin-only action: with Better Auth's admin plugin, `auth.api.createUser` works server-side without a session. Remove the flag only on sites where anyone may register.

```ts
// src/lib/auth.ts
import { betterAuth } from "better-auth";
import { prismaAdapter } from "better-auth/adapters/prisma";
import { nextCookies } from "better-auth/next-js";
import { db } from "@/lib/db";

// Reads BETTER_AUTH_SECRET and BETTER_AUTH_URL from the environment. The schema
// CLI looks for this `auth` export.
export const auth = betterAuth({
  database: prismaAdapter(db, { provider: "postgresql" }),
  emailAndPassword: { enabled: true, disableSignUp: true }, // invite-only
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

If `next build` must run without auth secrets, wrap `betterAuth()` in a lazy `getAuth()` that builds the instance on first call and reads `authEnv()` (see Env Validation).

### First Account

`prisma db seed` runs `prisma/seed.ts` (wired in `prisma.config.ts`). It does what the admin plugin's `createUser` does, through Better Auth's adapter rather than Prisma: a user plus a `credential` account with a hashed password. Set `SEED_EMAIL` and `SEED_PASSWORD` in `.env`, then run `pnpm prisma db seed`. Re-running skips an account that already has a password and finishes one whose password link failed.

```ts
// prisma/seed.ts
import "dotenv/config";
import { z } from "zod";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";

const { SEED_EMAIL, SEED_PASSWORD, SEED_NAME } = z
  .object({
    SEED_EMAIL: z.email(),
    // Better Auth's default limits; this path skips its own checks
    SEED_PASSWORD: z.string().min(8).max(128),
    SEED_NAME: z.string().min(1).default("Owner"),
  })
  .parse(process.env);

async function main() {
  const ctx = await auth.$context;
  const email = SEED_EMAIL.toLowerCase();
  // Hash first, so a failure here leaves no half-created user behind
  const password = await ctx.password.hash(SEED_PASSWORD);

  const existing = await ctx.internalAdapter.findUserByEmail(email, {
    includeAccounts: true,
  });
  if (existing?.accounts.some((account) => account.providerId === "credential")) {
    console.info(`${email} already exists, skipped`);
    return;
  }

  // A user without a credential account comes from a run that failed midway
  const user =
    existing?.user ??
    (await ctx.internalAdapter.createUser({
      email,
      name: SEED_NAME,
      emailVerified: true,
    }));
  await ctx.internalAdapter.linkAccount({
    userId: user.id,
    providerId: "credential",
    accountId: user.id,
    password,
  });
  console.info(existing ? `Linked a password to ${email}` : `Created ${email}`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  // The pg pool would otherwise keep the process alive until its idle timeout
  .finally(() => db.$disconnect());
```

## Env Validation

```ts
// src/lib/env.ts
import { z } from "zod";

// Needed by the build and every request: checked when the module loads.
const envSchema = z.object({
  DATABASE_URL: z.url(),
  NEXT_PUBLIC_SITE_URL: z.url(),
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
});

export const env = envSchema.parse(process.env);

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

## cn() Utility

```ts
// src/lib/utils.ts
import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export const cn = (...inputs: ClassValue[]) => twMerge(clsx(inputs));
```

## Error Boundary

```tsx
// src/app/error.tsx
"use client";

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center gap-4">
      <h2 className="text-xl font-semibold">Something went wrong</h2>
      <button
        onClick={reset}
        className="rounded-md bg-gray-900 px-4 py-2 text-sm text-white hover:bg-gray-800"
      >
        Try again
      </button>
    </div>
  );
}
```

## Loading Component

```tsx
// src/app/loading.tsx
export default function Loading() {
  return (
    <div className="flex min-h-[50vh] items-center justify-center">
      <div className="h-8 w-8 animate-spin rounded-full border-4 border-gray-200 border-t-gray-900" />
    </div>
  );
}
```

## Configs

### next.config.ts

```ts
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  cacheComponents: true,
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "**.example.com" },
    ],
  },
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
        ],
      },
    ];
  },
};

export default nextConfig;
```

### globals.css (Tailwind CSS 4)

Tailwind CSS 4 is configured in CSS. There is no `tailwind.config.ts` and no `content` list: sources are detected automatically.

```css
/* src/app/globals.css */
@import "tailwindcss";

/* inline: --font-inter is set at runtime by next/font in the root layout */
@theme inline {
  --font-sans: var(--font-inter), system-ui, sans-serif;
}

@theme {
  --color-brand-50: #f0f7ff;
  --color-brand-500: #3b82f6;
  --color-brand-600: #2563eb;
  --color-brand-700: #1d4ed8;
  --color-brand-900: #1e3a5f;
}
```

### postcss.config.mjs

```js
const config = {
  plugins: {
    "@tailwindcss/postcss": {},
  },
};

export default config;
```

### tsconfig.json

```json
{
  "compilerOptions": {
    "target": "ES2017",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
```

### .gitignore

```gitignore
node_modules/
.next/
out/
.env
.env.local
.env.*.local
!.env.example
*.tsbuildinfo
next-env.d.ts
src/generated/
```

### .env.example

```env
DATABASE_URL="postgresql://user:password@localhost:5432/dbname"
NEXT_PUBLIC_SITE_URL="http://localhost:3000"
BETTER_AUTH_SECRET="change-me-to-a-random-32-char-string"
BETTER_AUTH_URL="http://localhost:3000"
```
