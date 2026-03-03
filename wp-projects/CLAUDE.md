# WordPress Project Standards

Custom themes + plugins. Shared conventions (naming, git, security philosophy) in global CLAUDE.md.

## Conventions
- Unique prefix per client (e.g., `ag_` for Access Group, `mmg_` for Magnetite)
- Never modify core or third-party plugin files — use hooks and filters only
- Follow WordPress template hierarchy (`single.php`, `archive.php`, `page-{slug}.php`, etc.)
- Use a clean starter theme or build from scratch depending on project needs
- **ACF Pro** for custom fields — register field groups in code when possible
- **Contact Form 7** for forms — use `wpcf7_before_send_mail` hook for custom processing
- Test with common plugins (Elementor, WooCommerce, ACF) to avoid conflicts

## Structure
```
theme-name/
├── assets/src/{scss,js}/    # SASS 7-1 + ES6+ modules
├── assets/dist/             # Compiled (gitignored)
├── inc/classes/             # One class per file (class-*.php)
├── inc/helpers/             # Utility functions
├── template-parts/          # Reusable partials
├── acf-json/                # ACF local JSON sync
├── functions.php            # require_once only
└── style.css                # Header metadata only
```
Plugins: `includes/{admin,public,api,models}/`

## Naming
- Functions/hooks: `snake_case`, prefixed — `theme_slug_get_hero()`
- Classes: `Title_Case` in `class-*.php` — `Theme_Setup`
- Constants: `UPPER_SNAKE`, prefixed — `THEME_SLUG_VERSION`
- CSS: BEM — `.card__title--featured`
- Templates: `kebab-case` — `content-single-product.php`

## PHP
- `declare(strict_types=1);` + `defined('ABSPATH') || exit;` in class files
- Return types on methods. Yoda conditions (`'value' === $var`). Strict comparison.
- Early returns over nesting. One class per file. No logic in templates.

## JS
- ES6+ modules. No jQuery in new code.
- `wp_enqueue_script()` with `strategy => 'defer'`. `wp_localize_script()` for server data.
- Conditional loading: `is_page()`, `is_singular()`, etc.

## SASS/CSS
- 7-1 pattern. `@use`/`@forward` only (not `@import`).
- CSS custom properties for theming. BEM. Mobile-first (`min-width`).
- Max 3 nesting levels. No `!important`. `clamp()` for fluid type.

## Security
1. **Input**: `sanitize_text_field()`, `absint()`, `sanitize_email()`, `wp_kses_post()`
2. **Output**: `esc_html()`, `esc_attr()`, `esc_url()`
3. **Auth**: nonces on mutations, `current_user_can()` before privileged actions
4. **SQL**: `$wpdb->prepare()` always
5. **Prod**: `DISALLOW_FILE_EDIT` + `DISALLOW_FILE_MODS` = true, `WP_DEBUG_DISPLAY` = false

## Performance
- Transients for expensive queries (invalidate on `save_post`)
- `no_found_rows => true` / `fields => 'ids'` when applicable
- Lazy load below-fold, defer non-critical JS, remove unused block styles
- Targets: LCP < 2.5s, CLS < 0.1, DB queries < 50/page

## Build
- `@wordpress/scripts` for standard WP. `npm run dev` / `npm run build`.
- Never commit `assets/dist/` or `node_modules/`.

## i18n
All strings translatable: `__()`, `_e()`, `esc_html__()`. Use `sprintf()` — never concatenate.

## Accessibility
Semantic HTML. Alt text on images. Visible focus states. Label all inputs. 4.5:1 contrast.

## Deploy Checklist
- [ ] Linters pass, `npm run build` succeeds
- [ ] Debug off, file edit disabled, secrets in env vars
- [ ] DB backup taken, cache purged
