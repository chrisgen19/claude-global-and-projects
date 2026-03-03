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
import { getServices } from "@/lib/queries/services";
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
import { getServiceBySlug, getServiceSlugs } from "@/lib/queries/services";

type Props = { params: Promise<{ slug: string }> };

export async function generateStaticParams() {
  const slugs = await getServiceSlugs();
  return slugs.map((slug) => ({ slug }));
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const service = await getServiceBySlug(slug);
  if (!service) return {};
  return { title: service.title, description: service.excerpt };
}

export default async function ServicePage({ params }: Props) {
  const { slug } = await params;
  const service = await getServiceBySlug(slug);
  if (!service) notFound();

  return (
    <main className="mx-auto max-w-3xl px-4 py-12">
      <h1 className="mb-4 text-3xl font-bold">{service.title}</h1>
      <div className="prose max-w-none">{service.content}</div>
    </main>
  );
}
```

## API Route Handler

```ts
// src/app/api/contact/route.ts
import { NextRequest, NextResponse } from "next/server";
import { contactSchema } from "@/schemas/contact";

export async function POST(request: NextRequest) {
  const body = await request.json();
  const result = contactSchema.safeParse(body);

  if (!result.success) {
    return NextResponse.json(
      { error: "Validation failed", issues: result.error.flatten().fieldErrors },
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

## Middleware

```ts
// src/middleware.ts
import { NextRequest, NextResponse } from "next/server";

const protectedPaths = ["/dashboard", "/settings", "/admin"];

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const isProtected = protectedPaths.some((p) => pathname.startsWith(p));

  if (isProtected) {
    const token = request.cookies.get("session")?.value;
    if (!token) {
      const loginUrl = new URL("/login", request.url);
      loginUrl.searchParams.set("callbackUrl", pathname);
      return NextResponse.redirect(loginUrl);
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico).*)"],
};
```

## Prisma Setup

### Client singleton

```ts
// src/lib/db.ts
import { PrismaClient } from "@prisma/client";

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };

export const db = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== "production") globalForPrisma.prisma = db;
```

### Schema example

```prisma
// prisma/schema.prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        String   @id @default(cuid())
  email     String   @unique
  name      String?
  role      Role     @default(USER)
  posts     Post[]
  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")

  @@map("users")
}

model Post {
  id          String   @id @default(cuid())
  title       String
  slug        String   @unique
  content     String?
  published   Boolean  @default(false)
  author      User     @relation(fields: [authorId], references: [id])
  authorId    String   @map("author_id")
  publishedAt DateTime? @map("published_at")
  createdAt   DateTime  @default(now()) @map("created_at")
  updatedAt   DateTime  @updatedAt @map("updated_at")

  @@index([authorId])
  @@index([slug])
  @@map("posts")
}

enum Role {
  USER
  ADMIN
}
```

## Env Validation

```ts
// src/lib/env.ts
import { z } from "zod";

const envSchema = z.object({
  DATABASE_URL: z.string().url(),
  NEXT_PUBLIC_SITE_URL: z.string().url(),
  SESSION_SECRET: z.string().min(32),
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
});

export const env = envSchema.parse(process.env);
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

### tailwind.config.ts

```ts
import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["var(--font-inter)", "system-ui", "sans-serif"],
      },
      colors: {
        brand: {
          50: "#f0f7ff",
          500: "#3b82f6",
          600: "#2563eb",
          700: "#1d4ed8",
          900: "#1e3a5f",
        },
      },
    },
  },
  plugins: [],
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
```

### .env.example

```env
DATABASE_URL="postgresql://user:password@localhost:5432/dbname"
NEXT_PUBLIC_SITE_URL="http://localhost:3000"
SESSION_SECRET="change-me-to-a-random-32-char-string"
```
