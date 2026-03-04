---
name: env-check
description: Audit environment variables for security issues, missing entries, and misconfigurations. Use when the user asks to check environment, audit env vars, or types `/env-check`.
---

You are auditing environment variable usage and configuration in the current project.

## Steps

1. **Detect the project type** — check for `next.config.*` (Next.js), `wp-config.php` (WordPress), `package.json`, or `composer.json` to determine the stack.

2. **Scan for hardcoded secrets** in source files:
   - Search for patterns: API keys, passwords, tokens, connection strings, private keys.
   - Common patterns: `sk_live_`, `sk_test_`, `AKIA`, `ghp_`, `Bearer `, `password`, `secret`, `-----BEGIN`.
   - Exclude `.env*` files, lock files, and `node_modules`/`vendor` from this scan.

3. **Check `.gitignore` coverage:**
   - Verify `.env` and `.env.local` are in `.gitignore`.
   - Check if any `.env*` files are tracked by git (`git ls-files '*.env*'`).

4. **Audit `.env.example`:**
   - If missing, flag it.
   - If present, compare against actual env var usage in code:
     - Find env vars used in code (`process.env.`, `getenv(`, `$_ENV[`, `$_SERVER[`).
     - Flag vars used in code but missing from `.env.example`.
     - Flag vars in `.env.example` but not used in code (stale entries).

5. **Stack-specific checks:**

   **Next.js:**
   - Vars used in client components or `'use client'` files without `NEXT_PUBLIC_` prefix — these will be `undefined` at runtime.
   - `NEXT_PUBLIC_` vars that look like secrets (contain `SECRET`, `KEY`, `PASSWORD`, `TOKEN` in the name).

   **WordPress:**
   - Secrets hardcoded directly in `wp-config.php` (DB credentials, auth keys/salts) that should use `getenv()` or a `.env` loader.
   - Check if `wp-config.php` is in `.gitignore` or if it contains hardcoded values.

6. **Output a report:**

   ```
   ## Environment Audit Report

   ### Critical
   - [file:line] Hardcoded secret found: `API_KEY = "sk_live_..."`

   ### Warnings
   - `.env.example` is missing
   - `DATABASE_URL` used in code but not in `.env.example`
   - `NEXT_PUBLIC_OLD_VAR` in `.env.example` but not used in code

   ### Info
   - `.env` and `.env.local` are properly gitignored
   - 12 env vars used, 12 documented in `.env.example`

   ### Suggested Fixes
   1. Add `.env.example` with placeholder values for: ...
   2. Move hardcoded secret in `lib/api.ts:15` to an env var
   ```

## Rules

- Never read or output the contents of `.env` or `.env.local` — only check for their existence and gitignore coverage.
- When reporting hardcoded secrets, truncate the value (show first 8 chars + `...`).
- Group findings by severity: Critical → Warning → Info.
- Include file paths and line numbers for all findings.
- If the project is clean, say so — don't manufacture issues.
