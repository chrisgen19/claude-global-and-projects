---
name: security-audit
description: Scan for common security vulnerabilities across PHP/WordPress and JS/TS/Next.js projects. Use when the user asks to audit security, check for vulnerabilities, or types `/security-audit`.
---

You are performing a security audit on the current project's source code.

## Steps

1. **Detect the project type** — check for `next.config.*`, `wp-config.php`, `package.json`, `composer.json`, or both (mixed stack). Run relevant checks based on what's found.

2. **Scan PHP/WordPress code** (if applicable):
   - **Input sanitization** — `$_GET`, `$_POST`, `$_REQUEST`, `$_SERVER` used without `sanitize_text_field()`, `absint()`, `sanitize_email()`, `wp_kses_post()`, or similar.
   - **Output escaping** — variables echoed/printed without `esc_html()`, `esc_attr()`, `esc_url()`, `wp_kses_post()`.
   - **Nonce verification** — form handlers and AJAX callbacks missing `wp_verify_nonce()` or `check_ajax_referer()`.
   - **SQL injection** — `$wpdb->query()`, `$wpdb->get_results()`, etc. without `$wpdb->prepare()`. String concatenation in queries.
   - **Dangerous functions** — `eval()`, `extract()`, `unserialize()` on untrusted data, `shell_exec()`, `exec()`, `system()`.
   - **File operations** — `file_get_contents()`, `include`/`require` with user-controlled paths without validation.
   - **Capability checks** — admin actions missing `current_user_can()`.

3. **Scan JS/TS/Next.js code** (if applicable):
   - **XSS** — `dangerouslySetInnerHTML` without DOMPurify or equivalent sanitization. Direct `innerHTML` assignment.
   - **Input validation** — API routes and Server Actions missing Zod (or equivalent) validation on request body/params.
   - **Secret exposure** — non-`NEXT_PUBLIC_` env vars accessed in client components. API keys in client-side code.
   - **CSRF** — non-GET API routes without CSRF protection (Server Actions have built-in CSRF, Route Handlers don't).
   - **Dangerous functions** — `eval()`, `new Function()`, `document.write()`.
   - **Unvalidated redirects** — `redirect()` or `router.push()` with user-supplied URLs without allowlist validation.
   - **Auth checks** — protected API routes or Server Actions missing authentication/authorization verification.

4. **Scan both stacks for:**
   - **Hardcoded credentials** — API keys, passwords, tokens, connection strings in source files.
   - **CORS** — overly permissive `Access-Control-Allow-Origin: *` on authenticated endpoints.
   - **File uploads** — missing file type validation, missing size limits, storing in publicly accessible directories without checks.
   - **Rate limiting** — public-facing API endpoints without rate limiting.
   - **Dependency vulnerabilities** — run `pnpm audit` or `npm audit` (JS) / `composer audit` (PHP) if available.

5. **Output a report grouped by severity:**

   ```
   ## Security Audit Report

   ### Critical
   - `inc/api.php:45` — Raw SQL query without `$wpdb->prepare()`:
     `$wpdb->get_results("SELECT * FROM {$table} WHERE id = {$id}")`
     **Fix:** Use `$wpdb->prepare("SELECT * FROM %i WHERE id = %d", $table, $id)`

   ### Warning
   - `src/app/api/users/route.ts:12` — Missing Zod validation on request body
     **Fix:** Add `const body = schema.parse(await req.json())` before processing

   ### Info
   - `src/components/comment.tsx:8` — `dangerouslySetInnerHTML` used but input is sanitized with DOMPurify (OK)

   ### Summary
   - 2 Critical, 3 Warning, 1 Info
   - Areas checked: input validation, output escaping, SQL injection, XSS, auth, CORS, secrets
   ```

## Rules

- Include file paths and line numbers for every finding.
- Show the problematic code snippet (1–2 lines) and a concrete fix for Critical and Warning items.
- Don't flag sanitized/escaped code as vulnerable — check for proper handling before reporting.
- Don't report issues in `node_modules/`, `vendor/`, lock files, or `.env` files.
- If the project is clean, say so with a summary of what was checked.
- Keep the report actionable — every finding should have a clear fix.
