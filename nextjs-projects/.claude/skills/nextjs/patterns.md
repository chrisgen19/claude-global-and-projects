# Runtime Patterns

## Server Component with Data Fetching

Components read through the data access layer, never `db`. `getServices()` is a cached read (see Cached Queries in `scaffold.md`), so this component can prerender. A component that awaits an uncached DAL read, such as one that calls `requireUser()`, renders inside `<Suspense>` or below a `loading.tsx`.

```tsx
// src/components/services/service-list.tsx
import { getServices } from "@/lib/dal";
import { ServiceCard } from "./service-card";

export async function ServiceList() {
  const services = await getServices();

  if (services.length === 0) {
    return <p className="py-8 text-center text-gray-500">No services yet.</p>;
  }

  return (
    <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
      {services.map((service) => (
        <ServiceCard key={service.id} service={service} />
      ))}
    </div>
  );
}
```

## Client Component

```tsx
// src/components/ui/counter.tsx
"use client";

import { useState } from "react";
import { cn } from "@/lib/utils";

type CounterProps = {
  initialCount?: number;
  className?: string;
};

export function Counter({ initialCount = 0, className }: CounterProps) {
  const [count, setCount] = useState(initialCount);

  return (
    <div className={cn("flex items-center gap-3", className)}>
      <button
        onClick={() => setCount((c) => c - 1)}
        className="rounded-md bg-gray-100 px-3 py-1 hover:bg-gray-200"
      >
        -
      </button>
      <span className="min-w-[2ch] text-center font-medium">{count}</span>
      <button
        onClick={() => setCount((c) => c + 1)}
        className="rounded-md bg-gray-100 px-3 py-1 hover:bg-gray-200"
      >
        +
      </button>
    </div>
  );
}
```

## Shared Zod Schema

Forms, Server Actions and Route Handlers import the same schema, so client and server rules can't drift. Keep it out of the `"use server"` file: that file can only export async functions.

```ts
// src/schemas/contact.ts
import { z } from "zod";

export const contactSchema = z.object({
  name: z.string().min(1, "Name is required").max(100),
  email: z.email("Invalid email"),
  message: z.string().min(10, "Message must be at least 10 characters").max(2000),
});
```

## Server Action with Zod Validation

```ts
// src/actions/contact.ts
"use server";

import { z } from "zod";
import { contactSchema } from "@/schemas/contact";

type ContactState = {
  success: boolean;
  errors?: Record<string, string[]>;
  message?: string;
};

export async function submitContact(
  _prevState: ContactState,
  formData: FormData
): Promise<ContactState> {
  // A public form, so no requireUser(). Actions that touch user data call it first.
  const result = contactSchema.safeParse({
    name: formData.get("name"),
    email: formData.get("email"),
    message: formData.get("message"),
  });

  if (!result.success) {
    return { success: false, errors: z.flattenError(result.error).fieldErrors };
  }

  try {
    // Process validated data (send email, save to DB, etc.)
    return { success: true, message: "Message sent!" };
  } catch {
    return { success: false, message: "Failed to send. Try again." };
  }
}
```

## Form with useActionState (default)

```tsx
// src/components/forms/contact-form-action.tsx
"use client";

import { useActionState } from "react";
import { submitContact } from "@/actions/contact";

export function ContactFormAction() {
  const [state, formAction, isPending] = useActionState(submitContact, {
    success: false,
  });

  return (
    <form action={formAction} className="space-y-4">
      <div>
        <input
          name="name"
          placeholder="Name"
          className="w-full rounded-md border border-gray-300 px-3 py-2"
        />
        {state.errors?.name && (
          <p className="mt-1 text-sm text-red-600">{state.errors.name[0]}</p>
        )}
      </div>

      <div>
        <input
          name="email"
          type="email"
          placeholder="Email"
          className="w-full rounded-md border border-gray-300 px-3 py-2"
        />
        {state.errors?.email && (
          <p className="mt-1 text-sm text-red-600">{state.errors.email[0]}</p>
        )}
      </div>

      <div>
        <textarea
          name="message"
          rows={4}
          placeholder="Message"
          className="w-full rounded-md border border-gray-300 px-3 py-2"
        />
        {state.errors?.message && (
          <p className="mt-1 text-sm text-red-600">{state.errors.message[0]}</p>
        )}
      </div>

      <button
        type="submit"
        disabled={isPending}
        className="rounded-md bg-gray-900 px-4 py-2 text-sm text-white hover:bg-gray-800 disabled:opacity-50"
      >
        {isPending ? "Sending..." : "Send"}
      </button>

      {state.message && (
        <p className={state.success ? "text-green-600" : "text-red-600"}>
          {state.message}
        </p>
      )}
    </form>
  );
}
```

## Form with React Hook Form + Zod (complex client-side forms only)

```tsx
// src/components/forms/contact-form.tsx
"use client";

import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { cn } from "@/lib/utils";
import { contactSchema } from "@/schemas/contact";

type ContactFormData = z.infer<typeof contactSchema>;

export function ContactForm() {
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<ContactFormData>({
    resolver: zodResolver(contactSchema),
  });

  const onSubmit = async (data: ContactFormData) => {
    const res = await fetch("/api/contact", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data),
    });

    if (res.ok) reset();
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
      <div>
        <label htmlFor="name" className="mb-1 block text-sm font-medium">
          Name
        </label>
        <input
          id="name"
          {...register("name")}
          className={cn(
            "w-full rounded-md border px-3 py-2",
            errors.name ? "border-red-500" : "border-gray-300"
          )}
        />
        {errors.name && (
          <p className="mt-1 text-sm text-red-600">{errors.name.message}</p>
        )}
      </div>

      <div>
        <label htmlFor="email" className="mb-1 block text-sm font-medium">
          Email
        </label>
        <input
          id="email"
          type="email"
          {...register("email")}
          className={cn(
            "w-full rounded-md border px-3 py-2",
            errors.email ? "border-red-500" : "border-gray-300"
          )}
        />
        {errors.email && (
          <p className="mt-1 text-sm text-red-600">{errors.email.message}</p>
        )}
      </div>

      <div>
        <label htmlFor="message" className="mb-1 block text-sm font-medium">
          Message
        </label>
        <textarea
          id="message"
          rows={4}
          {...register("message")}
          className={cn(
            "w-full rounded-md border px-3 py-2",
            errors.message ? "border-red-500" : "border-gray-300"
          )}
        />
        {errors.message && (
          <p className="mt-1 text-sm text-red-600">{errors.message.message}</p>
        )}
      </div>

      <button
        type="submit"
        disabled={isSubmitting}
        className="rounded-md bg-gray-900 px-4 py-2 text-sm text-white hover:bg-gray-800 disabled:opacity-50"
      >
        {isSubmitting ? "Sending..." : "Send Message"}
      </button>
    </form>
  );
}
```

## Zustand Store

```ts
// src/stores/cart-store.ts
import { create } from "zustand";

type CartItem = {
  id: string;
  name: string;
  price: number;
  quantity: number;
};

type CartStore = {
  items: CartItem[];
  addItem: (item: Omit<CartItem, "quantity">) => void;
  removeItem: (id: string) => void;
  updateQuantity: (id: string, quantity: number) => void;
  clearCart: () => void;
  total: () => number;
};

export const useCartStore = create<CartStore>((set, get) => ({
  items: [],
  addItem: (item) =>
    set((state) => {
      const existing = state.items.find((i) => i.id === item.id);
      if (existing) {
        return {
          items: state.items.map((i) =>
            i.id === item.id ? { ...i, quantity: i.quantity + 1 } : i
          ),
        };
      }
      return { items: [...state.items, { ...item, quantity: 1 }] };
    }),
  removeItem: (id) =>
    set((state) => ({ items: state.items.filter((i) => i.id !== id) })),
  updateQuantity: (id, quantity) =>
    set((state) => ({
      items: quantity <= 0
        ? state.items.filter((i) => i.id !== id)
        : state.items.map((i) => (i.id === id ? { ...i, quantity } : i)),
    })),
  clearCart: () => set({ items: [] }),
  total: () => get().items.reduce((sum, i) => sum + i.price * i.quantity, 0),
}));
```

## Data Access Layer

Every Prisma call lives in `src/lib/dal.ts`, which becomes `lib/dal/<domain>.ts` as it grows. Pages, components, Route Handlers and Server Actions call DAL functions, never `db`. The DAL authorizes: it gets the user from the session with `requireUser()` (Better Auth setup is in `scaffold.md`), never from client input, and scopes owned data by that user. It returns minimal DTOs through `select`, not raw rows. Public reads skip `requireUser()`.

```ts
// src/lib/dal.ts
import "server-only";
import { cacheLife, cacheTag } from "next/cache";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { cache } from "react";
import { Prisma } from "@/generated/prisma/client";
import { auth } from "@/lib/auth";
import { db } from "@/lib/db";
import type { CreatePostInput } from "@/schemas/posts";

/** The signed-in user for this request; redirects to sign-in when there is none. */
export const requireUser = cache(async () => {
  const session = await auth.api.getSession({ headers: await headers() });
  if (!session) redirect("/sign-in");
  return session.user;
});

// React cache() deduplicates within a single render pass
export const getPublishedPosts = cache(async (page = 1, perPage = 10) => {
  const [posts, total] = await Promise.all([
    db.post.findMany({
      where: { published: true },
      orderBy: { publishedAt: "desc" },
      skip: (page - 1) * perPage,
      take: perPage,
      select: { id: true, title: true, slug: true, excerpt: true, publishedAt: true },
    }),
    db.post.count({ where: { published: true } }),
  ]);

  return { posts, total, totalPages: Math.ceil(total / perPage) };
});

export const getPostBySlug = cache(async (slug: string) => {
  return db.post.findUnique({
    where: { slug, published: true },
    select: {
      title: true,
      content: true,
      publishedAt: true,
      author: { select: { name: true } },
    },
  });
});
```

### Writes

DAL writes take an ID plus the change and check ownership in the query. Server Actions authenticate, validate with the shared schema, call the DAL, then update the cache.

```ts
// src/lib/dal.ts (continued)
/** Creates a post owned by the user. Returns null when the slug is already taken. */
export async function createPost(input: CreatePostInput) {
  const user = await requireUser();
  try {
    return await db.post.create({
      data: { ...input, authorId: user.id },
      select: { id: true, slug: true },
    });
  } catch (error) {
    // P2002: unique constraint (the slug). Anything else is unexpected.
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
      return null;
    }
    throw error;
  }
}

/** Publishes or unpublishes a post the user owns. Returns null when it is missing or not theirs. */
export async function togglePublish(postId: string) {
  const user = await requireUser();
  const post = await db.post.findFirst({
    where: { id: postId, authorId: user.id },
    select: { published: true },
  });
  if (!post) return null;

  return db.post.update({
    where: { id: postId },
    data: {
      published: !post.published,
      publishedAt: post.published ? null : new Date(),
    },
    select: { slug: true },
  });
}
```

```ts
// src/schemas/posts.ts
import { z } from "zod";

export const createPostSchema = z.object({
  title: z.string().min(1).max(200),
  slug: z.string().min(1).max(200).regex(/^[a-z0-9-]+$/),
  content: z.string().optional(),
});

export type CreatePostInput = z.infer<typeof createPostSchema>;

export type ActionResult =
  | { ok: true }
  | { ok: false; error: string; fieldErrors?: Partial<Record<string, string[]>> };
```

```ts
// src/actions/posts.ts
"use server";

import { revalidatePath, updateTag } from "next/cache";
import { z } from "zod";
import { createPost, requireUser, setFeatured, togglePublish } from "@/lib/dal";
import { type ActionResult, createPostSchema } from "@/schemas/posts";

export async function createPostAction(
  _prev: ActionResult | null,
  formData: FormData
): Promise<ActionResult> {
  await requireUser(); // cached: the DAL's own check reuses it

  const parsed = createPostSchema.safeParse({
    title: formData.get("title"),
    slug: formData.get("slug"),
    content: formData.get("content") ?? undefined,
  });
  if (!parsed.success) {
    return {
      ok: false,
      error: "Check the highlighted fields.",
      fieldErrors: z.flattenError(parsed.error).fieldErrors,
    };
  }

  const post = await createPost(parsed.data);
  if (!post) {
    return {
      ok: false,
      error: "Check the highlighted fields.",
      fieldErrors: { slug: ["That slug is already taken."] },
    };
  }

  revalidatePath("/posts");
  return { ok: true };
}

export async function togglePublishAction(postId: string): Promise<ActionResult> {
  await requireUser();

  const parsed = z.cuid().safeParse(postId);
  if (!parsed.success) return { ok: false, error: "Invalid post." };

  const post = await togglePublish(parsed.data);
  if (!post) return { ok: false, error: "Post not found." };

  updateTag("posts"); // getFeaturedPosts is tagged "posts"
  revalidatePath("/posts");
  revalidatePath(`/posts/${post.slug}`);
  return { ok: true };
}
```

## Revalidation Patterns

`"use cache"` needs `cacheComponents: true`, which the scaffold `next.config.ts` sets. With the flag on, request data (`cookies()`, `params`, `searchParams`) must be read under `<Suspense>` or below a `loading.tsx`, and uncached reads need the same or `"use cache"`. In a project without the flag, keep `unstable_cache` for database reads.

```ts
// src/lib/dal.ts (continued)
// Public cached read, tagged so a write can invalidate it
export async function getFeaturedPosts() {
  "use cache";
  cacheLife("hours");
  cacheTag("posts");

  return db.post.findMany({
    where: { published: true, featured: true },
    select: { id: true, title: true, slug: true, excerpt: true },
    take: 6,
  });
}

/** Features or unfeatures a post the user owns. Returns false when it is missing or not theirs. */
export async function setFeatured(postId: string, featured: boolean) {
  const user = await requireUser();
  const { count } = await db.post.updateMany({
    where: { id: postId, authorId: user.id },
    data: { featured },
  });
  return count === 1;
}
```

```ts
// src/actions/posts.ts (continued)
export async function setFeaturedAction(
  postId: string,
  featured: boolean
): Promise<ActionResult> {
  await requireUser();

  const parsed = z
    .object({ postId: z.cuid(), featured: z.boolean() })
    .safeParse({ postId, featured });
  if (!parsed.success) return { ok: false, error: "Invalid input." };

  const updated = await setFeatured(parsed.data.postId, parsed.data.featured);
  if (!updated) return { ok: false, error: "Post not found." };

  // updateTag(): the user sees their own write on the next render.
  // revalidateTag("posts", "max") instead serves stale data while it refreshes
  // (Next.js 16 requires the profile argument).
  updateTag("posts");
  return { ok: true };
}
```

## Protected Page Pattern

```tsx
// src/app/dashboard/page.tsx
import { Suspense } from "react";
import { requireUser } from "@/lib/dal";

// The page stays static. The session read happens in a child under <Suspense>
// and streams in at request time.
export default function DashboardPage() {
  return (
    <main className="mx-auto max-w-7xl px-4 py-12">
      <Suspense fallback={<p className="text-gray-500">Loading...</p>}>
        <Welcome />
      </Suspense>
    </main>
  );
}

async function Welcome() {
  const user = await requireUser();

  return <h1 className="text-2xl font-bold">Welcome, {user.name}</h1>;
}
```

## Search Params Pattern

```tsx
// src/app/posts/page.tsx
import { Suspense } from "react";
import { getPublishedPosts } from "@/lib/dal";
import { Pagination } from "@/components/ui/pagination";

type Props = {
  searchParams: Promise<{ page?: string; q?: string }>;
};

// searchParams is only known at request time. Pass the promise to a child
// under <Suspense> instead of awaiting it here.
export default function PostsPage({ searchParams }: Props) {
  return (
    <main className="mx-auto max-w-7xl px-4 py-12">
      <Suspense fallback={<p className="text-gray-500">Loading posts...</p>}>
        <PostResults searchParams={searchParams} />
      </Suspense>
    </main>
  );
}

async function PostResults({ searchParams }: Props) {
  const { page } = await searchParams;
  const currentPage = Math.max(1, Number(page) || 1);
  const { posts, totalPages } = await getPublishedPosts(currentPage, 10);

  return (
    <>
      <div className="grid gap-6">
        {posts.map((post) => (
          <article key={post.id}>
            <h2 className="text-xl font-semibold">{post.title}</h2>
          </article>
        ))}
      </div>
      <Pagination currentPage={currentPage} totalPages={totalPages} />
    </>
  );
}
```

## Custom Hook

```ts
// src/hooks/use-debounce.ts
import { useEffect, useState } from "react";

export function useDebounce<T>(value: T, delay = 300): T {
  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debounced;
}
```
