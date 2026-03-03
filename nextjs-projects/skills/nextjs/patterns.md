# Runtime Patterns

## Server Component with Data Fetching

```tsx
// src/components/services/service-list.tsx
import { db } from "@/lib/db";
import { ServiceCard } from "./service-card";

export async function ServiceList() {
  const services = await db.service.findMany({
    where: { published: true },
    orderBy: { createdAt: "desc" },
    take: 12,
  });

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

## Server Action with Zod Validation

```ts
// src/app/actions/contact.ts
"use server";

import { z } from "zod";

const contactSchema = z.object({
  name: z.string().min(1, "Name is required").max(100),
  email: z.string().email("Invalid email"),
  message: z.string().min(10, "Message must be at least 10 characters").max(2000),
});

type ContactState = {
  success: boolean;
  errors?: Record<string, string[]>;
  message?: string;
};

export async function submitContact(
  _prevState: ContactState,
  formData: FormData
): Promise<ContactState> {
  const result = contactSchema.safeParse({
    name: formData.get("name"),
    email: formData.get("email"),
    message: formData.get("message"),
  });

  if (!result.success) {
    return { success: false, errors: result.error.flatten().fieldErrors };
  }

  try {
    // Process validated data (send email, save to DB, etc.)
    return { success: true, message: "Message sent!" };
  } catch {
    return { success: false, message: "Failed to send. Try again." };
  }
}
```

## Form with React Hook Form + Zod

```tsx
// src/components/forms/contact-form.tsx
"use client";

import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { cn } from "@/lib/utils";

const contactSchema = z.object({
  name: z.string().min(1, "Name is required"),
  email: z.string().email("Invalid email"),
  message: z.string().min(10, "Message must be at least 10 characters"),
});

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

## Form with useActionState (Server Action)

```tsx
// src/components/forms/contact-form-action.tsx
"use client";

import { useActionState } from "react";
import { submitContact } from "@/app/actions/contact";

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

## Prisma CRUD Queries

```ts
// src/lib/queries/posts.ts
import { db } from "@/lib/db";
import { cache } from "react";

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
    where: { slug },
    include: { author: { select: { name: true } } },
  });
});
```

### Mutations

```ts
// src/lib/mutations/posts.ts
import { db } from "@/lib/db";
import { revalidatePath } from "next/cache";
import { z } from "zod";

const createPostSchema = z.object({
  title: z.string().min(1).max(200),
  slug: z.string().min(1).max(200).regex(/^[a-z0-9-]+$/),
  content: z.string().optional(),
  authorId: z.string().cuid(),
});

export async function createPost(data: z.infer<typeof createPostSchema>) {
  const post = await db.post.create({ data });
  revalidatePath("/posts");
  return post;
}

export async function togglePublish(id: string) {
  const post = await db.post.findUniqueOrThrow({ where: { id } });
  const updated = await db.post.update({
    where: { id },
    data: {
      published: !post.published,
      publishedAt: post.published ? null : new Date(),
    },
  });
  revalidatePath("/posts");
  revalidatePath(`/posts/${updated.slug}`);
  return updated;
}
```

## Revalidation Patterns

```ts
// Tag-based revalidation
import { unstable_cache } from "next/cache";
import { revalidateTag } from "next/cache";
import { db } from "@/lib/db";

// Cached query with tags
export const getFeaturedPosts = unstable_cache(
  async () => {
    return db.post.findMany({
      where: { published: true, featured: true },
      take: 6,
    });
  },
  ["featured-posts"],
  { tags: ["posts"], revalidate: 3600 }
);

// Invalidate after mutation
export async function updatePost(id: string, data: Record<string, unknown>) {
  await db.post.update({ where: { id }, data });
  revalidateTag("posts");
}
```

## Auth Session Helper

```ts
// src/lib/auth.ts
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { db } from "@/lib/db";

export async function getSession() {
  const cookieStore = await cookies();
  const token = cookieStore.get("session")?.value;
  if (!token) return null;

  const session = await db.session.findUnique({
    where: { token },
    include: { user: { select: { id: true, email: true, name: true, role: true } } },
  });

  if (!session || session.expiresAt < new Date()) return null;
  return session.user;
}

export async function requireAuth() {
  const user = await getSession();
  if (!user) redirect("/login");
  return user;
}

export async function requireAdmin() {
  const user = await requireAuth();
  if (user.role !== "ADMIN") redirect("/unauthorized");
  return user;
}
```

## Protected Page Pattern

```tsx
// src/app/dashboard/page.tsx
import { requireAuth } from "@/lib/auth";

export default async function DashboardPage() {
  const user = await requireAuth();

  return (
    <main className="mx-auto max-w-7xl px-4 py-12">
      <h1 className="text-2xl font-bold">Welcome, {user.name}</h1>
    </main>
  );
}
```

## Search Params Pattern

```tsx
// src/app/posts/page.tsx
import { getPublishedPosts } from "@/lib/queries/posts";
import { Pagination } from "@/components/ui/pagination";

type Props = {
  searchParams: Promise<{ page?: string; q?: string }>;
};

export default async function PostsPage({ searchParams }: Props) {
  const { page, q } = await searchParams;
  const currentPage = Math.max(1, Number(page) || 1);
  const { posts, totalPages } = await getPublishedPosts(currentPage, 10);

  return (
    <main className="mx-auto max-w-7xl px-4 py-12">
      <div className="grid gap-6">
        {posts.map((post) => (
          <article key={post.id}>
            <h2 className="text-xl font-semibold">{post.title}</h2>
          </article>
        ))}
      </div>
      <Pagination currentPage={currentPage} totalPages={totalPages} />
    </main>
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
