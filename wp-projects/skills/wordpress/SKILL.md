---
name: wordpress
description: WordPress theme and plugin development skill. Use when building or modifying custom WordPress themes, plugins, CPTs, REST API endpoints, WooCommerce customizations, ACF fields, SASS/JS assets, or deployment configs. Auto-triggers when the user asks to build, add, fix, or scaffold anything in a WordPress/PHP project.
---

You are working on a custom WordPress theme or plugin using modern PHP (8.1+), @wordpress/scripts, and SASS 7-1.

Before writing any code, read the relevant pattern file:
- For boilerplate and project setup (PHP classes, plugin bootstrap, CPTs, asset enqueue, build configs, deploy, SASS architecture) → read `scaffold.md`
- For runtime patterns (REST API, security/nonces/sanitization, optimized queries, WooCommerce hooks, template parts) → read `patterns.md`

Always follow the conventions in CLAUDE.md. Use the client-specific prefix defined per project. Use patterns from those files as the baseline — adapt to the specific task, don't copy blindly.
