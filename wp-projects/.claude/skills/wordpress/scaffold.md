# Scaffold Patterns

## Theme Setup Class

```php
<?php
declare( strict_types=1 );
namespace Theme_Slug\Inc;
defined( 'ABSPATH' ) || exit;

class Theme_Setup {
    public function init(): void {
        add_action( 'after_setup_theme', [ $this, 'setup_theme' ] );
        add_action( 'init', [ $this, 'register_menus' ] );
    }

    public function setup_theme(): void {
        add_theme_support( 'title-tag' );
        add_theme_support( 'post-thumbnails' );
        add_theme_support( 'html5', [ 'search-form', 'comment-form', 'comment-list', 'gallery', 'caption', 'style', 'script' ] );
        add_image_size( 'theme-slug-hero', 1920, 800, true );
        add_image_size( 'theme-slug-card', 640, 420, true );
    }

    public function register_menus(): void {
        register_nav_menus( [
            'primary' => esc_html__( 'Primary Menu', 'theme-slug' ),
            'footer'  => esc_html__( 'Footer Menu', 'theme-slug' ),
        ] );
    }
}
```

## Asset Enqueue Class

```php
<?php
declare( strict_types=1 );
namespace Theme_Slug\Inc;
defined( 'ABSPATH' ) || exit;

class Assets {
    public function init(): void {
        add_action( 'wp_enqueue_scripts', [ $this, 'enqueue_frontend' ] );
    }

    public function enqueue_frontend(): void {
        $asset_file = get_theme_file_path( 'assets/dist/js/main.asset.php' );
        $asset = file_exists( $asset_file )
            ? require $asset_file
            : [ 'dependencies' => [], 'version' => THEME_SLUG_VERSION ];

        wp_enqueue_style( 'theme-slug-style', get_theme_file_uri( 'assets/dist/css/main.css' ), [], $asset['version'] );
        wp_enqueue_script( 'theme-slug-main', get_theme_file_uri( 'assets/dist/js/main.js' ),
            $asset['dependencies'], $asset['version'], [ 'strategy' => 'defer', 'in_footer' => true ] );
        wp_localize_script( 'theme-slug-main', 'themeSlugData', [
            'ajaxUrl' => admin_url( 'admin-ajax.php' ),
            'restUrl' => rest_url( 'theme-slug/v1/' ),
            'nonce'   => wp_create_nonce( 'wp_rest' ),
        ] );
    }
}
```

## Custom Post Type Class

```php
<?php
declare( strict_types=1 );
namespace Theme_Slug\Inc;
defined( 'ABSPATH' ) || exit;

class Custom_Post_Types {
    public function init(): void {
        add_action( 'init', [ $this, 'register' ] );
    }

    public function register(): void {
        register_post_type( 'theme_slug_service', [
            'labels'       => $this->labels( 'Service', 'Services' ),
            'public'       => true,
            'show_in_rest' => true,
            'has_archive'  => 'services',
            'rewrite'      => [ 'slug' => 'services', 'with_front' => false ],
            'menu_icon'    => 'dashicons-hammer',
            'supports'     => [ 'title', 'editor', 'thumbnail', 'excerpt', 'revisions', 'custom-fields' ],
        ] );
    }

    private function labels( string $s, string $p ): array {
        return [
            'name'          => esc_html_x( $p, 'Post type general name', 'theme-slug' ),
            'singular_name' => esc_html_x( $s, 'Post type singular name', 'theme-slug' ),
            'add_new_item'  => sprintf( esc_html__( 'Add New %s', 'theme-slug' ), $s ),
            'edit_item'     => sprintf( esc_html__( 'Edit %s', 'theme-slug' ), $s ),
        ];
    }
}
```

## Plugin Bootstrap

```php
<?php
/**
 * Plugin Name: Plugin Name
 * Version: 1.0.0
 * Requires PHP: 8.2
 * Text Domain: plugin-name
 */
declare( strict_types=1 );
defined( 'ABSPATH' ) || exit;

define( 'PLUGIN_NAME_VERSION', '1.0.0' );
define( 'PLUGIN_NAME_FILE', __FILE__ );
define( 'PLUGIN_NAME_PATH', plugin_dir_path( __FILE__ ) );
define( 'PLUGIN_NAME_URL', plugin_dir_url( __FILE__ ) );
define( 'PLUGIN_NAME_BASENAME', plugin_basename( __FILE__ ) );

require_once PLUGIN_NAME_PATH . 'vendor/autoload.php';
register_activation_hook( __FILE__, [ 'Plugin_Name\\Activator', 'activate' ] );
register_deactivation_hook( __FILE__, [ 'Plugin_Name\\Deactivator', 'deactivate' ] );
add_action( 'plugins_loaded', fn() => Plugin_Name\Plugin::instance()->init() );
```

### Singleton

```php
<?php
declare( strict_types=1 );
namespace Plugin_Name;
defined( 'ABSPATH' ) || exit;

final class Plugin {
    private static ?self $instance = null;
    public static function instance(): self { return self::$instance ??= new self(); }
    private function __construct() {}
    private function __clone() {}

    public function init(): void {
        load_plugin_textdomain( 'plugin-name', false, dirname( PLUGIN_NAME_BASENAME ) . '/languages' );
        ( new Admin\Settings() )->init();
        ( new Api\Rest_Controller() )->init();
    }
}
```

### Activator with Custom Tables

```php
<?php
declare( strict_types=1 );
namespace Plugin_Name;

class Activator {
    public static function activate(): void {
        if ( version_compare( PHP_VERSION, '8.2', '<' ) ) {
            deactivate_plugins( PLUGIN_NAME_BASENAME );
            wp_die( 'Requires PHP 8.2+.' );
        }
        self::create_tables();
        add_option( 'plugin_name_version', PLUGIN_NAME_VERSION );
        flush_rewrite_rules();
    }

    private static function create_tables(): void {
        global $wpdb;
        $sql = "CREATE TABLE IF NOT EXISTS {$wpdb->prefix}plugin_name_data (
            id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
            user_id bigint(20) unsigned NOT NULL DEFAULT 0,
            title varchar(255) NOT NULL DEFAULT '',
            status varchar(20) NOT NULL DEFAULT 'draft',
            created_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id), KEY user_id (user_id), KEY status (status)
        ) {$wpdb->get_charset_collate()};";
        require_once ABSPATH . 'wp-admin/includes/upgrade.php';
        dbDelta( $sql );
    }
}
```

## Build Configs

### package.json

```json
{
    "scripts": {
        "dev": "wp-scripts start --webpack-src-dir=assets/src --output-path=assets/dist",
        "build": "wp-scripts build --webpack-src-dir=assets/src --output-path=assets/dist",
        "lint:js": "wp-scripts lint-js assets/src/js",
        "lint:css": "wp-scripts lint-style assets/src/scss"
    },
    "devDependencies": {
        "@wordpress/scripts": "^28.0.0",
        "autoprefixer": "^10.4.0",
        "css-minimizer-webpack-plugin": "^7.0.0",
        "mini-css-extract-plugin": "^2.9.0",
        "postcss": "^8.4.0",
        "sass": "^1.70.0",
        "sass-loader": "^14.0.0"
    }
}
```

### webpack.config.js

```js
const defaultConfig = require('@wordpress/scripts/config/webpack.config');
const MiniCssExtractPlugin = require('mini-css-extract-plugin');
const CssMinimizerPlugin = require('css-minimizer-webpack-plugin');
const path = require('path');

module.exports = {
    ...defaultConfig,
    entry: {
        main: path.resolve(__dirname, 'assets/src/js/main.js'),
        style: path.resolve(__dirname, 'assets/src/scss/main.scss'),
    },
    output: { path: path.resolve(__dirname, 'assets/dist'), filename: 'js/[name].js', clean: true },
    module: { ...defaultConfig.module, rules: [ ...defaultConfig.module.rules,
        { test: /\.scss$/, use: [ MiniCssExtractPlugin.loader, 'css-loader',
            { loader: 'postcss-loader', options: { postcssOptions: { plugins: ['postcss-preset-env', 'autoprefixer'] } } },
            'sass-loader' ] } ] },
    plugins: [ ...defaultConfig.plugins.filter(p => p.constructor.name !== 'MiniCssExtractPlugin'),
        new MiniCssExtractPlugin({ filename: 'css/[name].css' }) ],
    optimization: { ...defaultConfig.optimization, minimizer: ['...', new CssMinimizerPlugin()] },
};
```

### composer.json

```json
{
    "require-dev": {
        "squizlabs/php_codesniffer": "^3.7",
        "wp-coding-standards/wpcs": "^3.0",
        "dealerdirect/phpcodesniffer-composer-installer": "^1.0",
        "phpstan/phpstan": "^1.10",
        "szepeviktor/phpstan-wordpress": "^1.3"
    },
    "scripts": { "lint": "phpcs", "lint:fix": "phpcbf", "analyze": "phpstan analyse" }
}
```

## SASS 7-1 Main Import

```scss
@use 'abstracts/variables' as *;
@use 'abstracts/mixins' as *;
@use 'vendors/normalize';
@use 'base/reset';
@use 'base/typography';
@use 'base/global';
@use 'layout/header';
@use 'layout/footer';
@use 'layout/grid';
@use 'components/buttons';
@use 'components/cards';
@use 'components/forms';
@use 'components/navigation';
@use 'pages/home';
@use 'utilities/helpers';
```

### Core Mixins

```scss
@mixin respond-to($bp) {
    $bps: ('sm': 576px, 'md': 768px, 'lg': 992px, 'xl': 1200px);
    @if map-has-key($bps, $bp) { @media (min-width: map-get($bps, $bp)) { @content; } }
}
@mixin container { width: 100%; max-width: var(--container-max); margin-inline: auto; padding-inline: var(--space-md); }
@mixin sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0,0,0,0); white-space: nowrap; border: 0; }
```

## Deploy

### wp-config.php (env-based)

```php
define( 'DB_NAME', getenv( 'DB_NAME' ) );
define( 'DB_USER', getenv( 'DB_USER' ) );
define( 'DB_PASSWORD', getenv( 'DB_PASSWORD' ) );
define( 'DB_HOST', getenv( 'DB_HOST' ) ?: 'localhost' );
define( 'WP_ENVIRONMENT_TYPE', getenv( 'WP_ENVIRONMENT_TYPE' ) ?: 'production' );

if ( 'production' !== wp_get_environment_type() ) {
    define( 'WP_DEBUG', true ); define( 'WP_DEBUG_LOG', true );
    define( 'WP_DEBUG_DISPLAY', true ); define( 'SCRIPT_DEBUG', true );
} else {
    define( 'WP_DEBUG', false ); define( 'WP_DEBUG_DISPLAY', false );
    define( 'DISALLOW_FILE_EDIT', true ); define( 'DISALLOW_FILE_MODS', true );
}
```

### GitHub Actions CI

```yaml
name: CI
on:
  pull_request:
    branches: [develop, staging, main]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: shivammathur/setup-php@v2
        with: { php-version: '8.2', tools: 'composer:v2' }
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: 'npm' }
      - run: composer install --no-interaction && npm ci
      - run: composer lint && npm run lint && composer analyze && npm run build
```

### .gitignore

```gitignore
node_modules/
vendor/
assets/dist/
.env
!.env.example
wp-content/uploads/
wp-content/debug.log
.DS_Store
```
