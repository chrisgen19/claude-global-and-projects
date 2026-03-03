# Runtime Patterns

## REST API Controller

```php
<?php
declare( strict_types=1 );
namespace Theme_Slug\Inc;
defined( 'ABSPATH' ) || exit;

use WP_REST_Request; use WP_REST_Response; use WP_REST_Server; use WP_Error;

class Rest_Api {
    private const NS = 'theme-slug/v1';

    public function init(): void { add_action( 'rest_api_init', [ $this, 'register_routes' ] ); }

    public function register_routes(): void {
        register_rest_route( self::NS, '/services', [
            'methods'             => WP_REST_Server::READABLE,
            'callback'            => [ $this, 'get_services' ],
            'permission_callback' => '__return_true',
            'args' => [
                'page'     => [ 'default' => 1, 'sanitize_callback' => 'absint' ],
                'per_page' => [ 'default' => 10, 'sanitize_callback' => 'absint',
                    'validate_callback' => fn( $p ) => absint( $p ) <= 100 ],
            ],
        ] );

        register_rest_route( self::NS, '/contact', [
            'methods'             => WP_REST_Server::CREATABLE,
            'callback'            => [ $this, 'submit_contact' ],
            'permission_callback' => '__return_true',
            'args' => [
                'name'    => [ 'required' => true, 'sanitize_callback' => 'sanitize_text_field' ],
                'email'   => [ 'required' => true, 'sanitize_callback' => 'sanitize_email',
                    'validate_callback' => fn( $p ) => is_email( $p ) ],
                'message' => [ 'required' => true, 'sanitize_callback' => 'sanitize_textarea_field' ],
            ],
        ] );
    }

    public function get_services( WP_REST_Request $req ): WP_REST_Response {
        $q = new \WP_Query( [
            'post_type' => 'theme_slug_service', 'posts_per_page' => $req->get_param( 'per_page' ),
            'paged' => $req->get_param( 'page' ), 'post_status' => 'publish',
        ] );
        $data = array_map( fn( $p ) => [
            'id' => $p->ID, 'title' => get_the_title( $p ), 'excerpt' => get_the_excerpt( $p ),
            'permalink' => get_permalink( $p ),
            'thumbnail' => get_the_post_thumbnail_url( $p, 'theme-slug-card' ) ?: null,
        ], $q->posts );

        $r = new WP_REST_Response( $data, 200 );
        $r->header( 'X-WP-Total', (string) $q->found_posts );
        $r->header( 'X-WP-TotalPages', (string) $q->max_num_pages );
        return $r;
    }

    public function submit_contact( WP_REST_Request $req ): WP_REST_Response|WP_Error {
        $sent = wp_mail( get_option( 'admin_email' ),
            sprintf( 'Contact: %s', $req->get_param( 'name' ) ),
            $req->get_param( 'message' ),
            [ "Reply-To: {$req->get_param('name')} <{$req->get_param('email')}>" ] );
        return $sent
            ? new WP_REST_Response( [ 'success' => true ], 200 )
            : new WP_Error( 'mail_failed', 'Failed to send.', [ 'status' => 500 ] );
    }
}
```

## Security Quick Reference

### Input Sanitization
```php
$id      = absint( $_GET['id'] ?? 0 );
$title   = sanitize_text_field( wp_unslash( $_POST['title'] ?? '' ) );
$email   = sanitize_email( $_POST['email'] ?? '' );
$url     = esc_url_raw( $_POST['website'] ?? '' );
$content = wp_kses_post( wp_unslash( $_POST['content'] ?? '' ) );

// Whitelist pattern
$allowed = [ 'post', 'page', 'product' ];
$type = in_array( $_GET['type'] ?? '', $allowed, true ) ? $_GET['type'] : 'post';
```

### Nonces
```php
// Form
wp_nonce_field( 'theme_slug_save', 'theme_slug_nonce' );

// Verify
if ( ! isset( $_POST['theme_slug_nonce'] )
    || ! wp_verify_nonce( sanitize_text_field( wp_unslash( $_POST['theme_slug_nonce'] ) ), 'theme_slug_save' )
) { wp_die( 'Security check failed.' ); }

// AJAX
check_ajax_referer( 'theme_slug_ajax', 'nonce' );
```

### SQL with prepare()
```php
global $wpdb;
$results = $wpdb->get_results( $wpdb->prepare(
    "SELECT * FROM {$wpdb->prefix}custom_table WHERE status = %s AND user_id = %d LIMIT %d",
    $status, $user_id, $limit
) );

// IN clause
$ids = array_map( 'absint', $ids );
$placeholders = implode( ', ', array_fill( 0, count( $ids ), '%d' ) );
$results = $wpdb->get_results( $wpdb->prepare(
    "SELECT * FROM {$wpdb->prefix}custom_table WHERE id IN ($placeholders)", ...$ids
) );
```

## Optimized Queries

```php
// Performance-optimized WP_Query
$query = new WP_Query( [
    'post_type' => 'theme_slug_service', 'posts_per_page' => 12, 'post_status' => 'publish',
    'no_found_rows' => true, 'fields' => 'ids',
    'update_post_meta_cache' => false, 'update_post_term_cache' => false,
] );
if ( $query->have_posts() ) {
    while ( $query->have_posts() ) { $query->the_post();
        get_template_part( 'template-parts/content/card', 'service' );
    }
    wp_reset_postdata();
}

// Transient caching
$key = 'theme_slug_featured';
$data = get_transient( $key );
if ( false === $data ) {
    $data = get_posts( [ 'post_type' => 'theme_slug_service', 'posts_per_page' => 6,
        'meta_key' => '_featured', 'meta_value' => '1' ] );
    set_transient( $key, $data, HOUR_IN_SECONDS );
}
add_action( 'save_post_theme_slug_service', fn() => delete_transient( 'theme_slug_featured' ) );
```

## Template Parts

```php
<?php // Usage
get_template_part( 'template-parts/components/card', 'post', [
    'post_id' => $post->ID, 'show_image' => true, 'heading_tag' => 'h3',
] ); ?>

<?php // template-parts/components/card-post.php
defined( 'ABSPATH' ) || exit;
$post_id     = $args['post_id'] ?? get_the_ID();
$show_image  = $args['show_image'] ?? true;
$heading_tag = $args['heading_tag'] ?? 'h2';
?>
<article class="card">
    <?php if ( $show_image && has_post_thumbnail( $post_id ) ) : ?>
        <div class="card__image">
            <?php echo get_the_post_thumbnail( $post_id, 'theme-slug-card', [ 'loading' => 'lazy' ] ); ?>
        </div>
    <?php endif; ?>
    <<?php echo esc_attr( $heading_tag ); ?> class="card__title">
        <a href="<?php echo esc_url( get_permalink( $post_id ) ); ?>">
            <?php echo esc_html( get_the_title( $post_id ) ); ?>
        </a>
    </<?php echo esc_attr( $heading_tag ); ?>>
</article>
```

## WooCommerce Hooks

```php
// Hook-based customization (preferred over template overrides)
remove_action( 'woocommerce_single_product_summary', 'woocommerce_template_single_meta', 40 );

add_filter( 'woocommerce_product_tabs', function ( array $tabs ): array {
    $tabs['specs'] = [ 'title' => 'Specifications', 'priority' => 15, 'callback' => 'theme_slug_specs_tab' ];
    unset( $tabs['reviews'] );
    return $tabs;
} );

add_filter( 'woocommerce_checkout_fields', function ( array $fields ): array {
    $fields['billing']['billing_company']['required'] = false;
    unset( $fields['order']['order_comments'] );
    return $fields;
} );

// Always use CRUD methods for orders
$order = wc_get_order( $order_id );
if ( $order instanceof \WC_Order ) {
    $total = $order->get_total(); // Never use get_post_meta for order data
}
```

## Remove Unused Assets

```php
add_action( 'wp_enqueue_scripts', function (): void {
    wp_dequeue_style( 'wp-block-library' );
    wp_dequeue_style( 'wp-block-library-theme' );
    wp_dequeue_style( 'wc-blocks-style' );
    wp_dequeue_style( 'global-styles' );
} );
remove_action( 'wp_head', 'print_emoji_detection_script', 7 );
remove_action( 'wp_print_styles', 'print_emoji_styles' );
remove_action( 'wp_head', 'wp_generator' );
```
