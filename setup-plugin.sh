#!/bin/bash

echo "Creating TabletopFactory Builder Plugin..."

# Create all directories
mkdir -p includes src/components src/hooks assets/js/dist assets/css assets/images/haunted-graveyard assets/data languages

# Main plugin file
cat > tabletopfactory-builder.php << 'EOF'
<?php
/**
 * Plugin Name: TabletopFactory Builder
 * Description: A WordPress/WooCommerce extension for designing custom dungeon layouts.
 * Version: 1.0.0
 * Author: cruiseback
 * Text Domain: tabletopfactory-builder
 * Requires PHP: 7.4
 * WC requires at least: 8.0
 */

if (!defined('ABSPATH')) exit;

define('TTF_BUILDER_VERSION', '1.0.0');
define('TTF_BUILDER_PLUGIN_DIR', plugin_dir_path(__FILE__));
define('TTF_BUILDER_PLUGIN_URL', plugin_dir_url(__FILE__));

class TabletopFactory_Builder {
    private static $_instance = null;
    
    public static function instance() {
        if (is_null(self::$_instance)) {
            self::$_instance = new self();
        }
        return self::$_instance;
    }
    
    public function __construct() {
        add_action('init', array($this, 'init'), 0);
        add_action('plugins_loaded', array($this, 'plugins_loaded'));
        register_activation_hook(__FILE__, array($this, 'activate'));
        $this->includes();
    }
    
    public function includes() {
        include_once TTF_BUILDER_PLUGIN_DIR . 'includes/class-admin.php';
        include_once TTF_BUILDER_PLUGIN_DIR . 'includes/class-public.php';
        if (class_exists('WooCommerce')) {
            include_once TTF_BUILDER_PLUGIN_DIR . 'includes/class-woocommerce.php';
        }
    }
    
    public function init() {
        load_plugin_textdomain('tabletopfactory-builder', false, dirname(plugin_basename(__FILE__)) . '/languages/');
        TTF_Builder_Admin::instance();
        TTF_Builder_Public::instance();
        if (class_exists('WooCommerce')) {
            TTF_Builder_WooCommerce::instance();
        }
    }
    
    public function plugins_loaded() {
        if (!class_exists('WooCommerce')) {
            add_action('admin_notices', array($this, 'woocommerce_missing_notice'));
        }
    }
    
    public function woocommerce_missing_notice() {
        echo '<div class="error"><p><strong>TabletopFactory Builder requires WooCommerce to be installed and active.</strong></p></div>';
    }
    
    public function activate() {
        $default_options = array(
            'default_grid_size' => 4,
            'replacement_mode' => 'prompt',
            'active_campaign' => 'haunted-graveyard',
            'campaigns' => array(
                'haunted-graveyard' => array(
                    'name' => 'Haunted Graveyard',
                    'blocks_file' => 'haunted-graveyard.json',
                    'image_dir' => 'haunted-graveyard'
                )
            )
        );
        add_option('ttf_builder_options', $default_options);
    }
}

function TTF_Builder() {
    return TabletopFactory_Builder::instance();
}
TTF_Builder();
EOF

# Admin class
cat > includes/class-admin.php << 'EOF'
<?php
if (!defined('ABSPATH')) exit;

class TTF_Builder_Admin {
    private static $_instance = null;
    
    public static function instance() {
        if (is_null(self::$_instance)) {
            self::$_instance = new self();
        }
        return self::$_instance;
    }
    
    public function __construct() {
        add_action('admin_menu', array($this, 'admin_menu'));
        add_action('admin_init', array($this, 'admin_init'));
    }
    
    public function admin_menu() {
        add_options_page(
            'TabletopFactory Builder',
            'TabletopFactory Builder',
            'manage_options',
            'ttf-builder-settings',
            array($this, 'settings_page')
        );
    }
    
    public function admin_init() {
        register_setting('ttf_builder_settings', 'ttf_builder_options');
        
        add_settings_section('ttf_builder_general', 'General Settings', null, 'ttf-builder-settings');
        
        add_settings_field('default_grid_size', 'Default Grid Size', array($this, 'grid_size_callback'), 'ttf-builder-settings', 'ttf_builder_general');
        add_settings_field('replacement_mode', 'Block Replacement Mode', array($this, 'replacement_mode_callback'), 'ttf-builder-settings', 'ttf_builder_general');
    }
    
    public function settings_page() {
        ?>
        <div class="wrap">
            <h1>TabletopFactory Builder Settings</h1>
            <form action="options.php" method="post">
                <?php
                settings_fields('ttf_builder_settings');
                do_settings_sections('ttf-builder-settings');
                submit_button();
                ?>
            </form>
        </div>
        <?php
    }
    
    public function grid_size_callback() {
        $options = get_option('ttf_builder_options');
        $value = isset($options['default_grid_size']) ? $options['default_grid_size'] : 4;
        ?>
        <select name="ttf_builder_options[default_grid_size]">
            <option value="3" <?php selected($value, 3); ?>>3x3</option>
            <option value="4" <?php selected($value, 4); ?>>4x4</option>
            <option value="5" <?php selected($value, 5); ?>>5x5</option>
            <option value="6" <?php selected($value, 6); ?>>6x6</option>
        </select>
        <?php
    }
    
    public function replacement_mode_callback() {
        $options = get_option('ttf_builder_options');
        $value = isset($options['replacement_mode']) ? $options['replacement_mode'] : 'prompt';
        ?>
        <label><input type="radio" name="ttf_builder_options[replacement_mode]" value="prompt" <?php checked($value, 'prompt'); ?>> Prompt before replacing</label><br>
        <label><input type="radio" name="ttf_builder_options[replacement_mode]" value="auto" <?php checked($value, 'auto'); ?>> Auto-replace</label>
        <?php
    }
}
EOF

# Public class
cat > includes/class-public.php << 'EOF'
<?php
if (!defined('ABSPATH')) exit;

class TTF_Builder_Public {
    private static $_instance = null;
    
    public static function instance() {
        if (is_null(self::$_instance)) {
            self::$_instance = new self();
        }
        return self::$_instance;
    }
    
    public function __construct() {
        add_action('wp_enqueue_scripts', array($this, 'enqueue_scripts'));
        add_shortcode('tabletop_builder', array($this, 'builder_shortcode'));
        add_action('wp_ajax_ttf_save_layout', array($this, 'save_layout'));
        add_action('wp_ajax_nopriv_ttf_save_layout', array($this, 'save_layout'));
        add_action('wp_ajax_ttf_get_blocks', array($this, 'get_blocks'));
        add_action('wp_ajax_nopriv_ttf_get_blocks', array($this, 'get_blocks'));
    }
    
    public function enqueue_scripts() {
        if (!$this->has_shortcode()) return;
        
        wp_enqueue_script('ttf-builder-react', TTF_BUILDER_PLUGIN_URL . 'assets/js/dist/builder.js', array(), TTF_BUILDER_VERSION, true);
        wp_enqueue_style('ttf-builder-frontend', TTF_BUILDER_PLUGIN_URL . 'assets/css/builder.css', array(), TTF_BUILDER_VERSION);
        
        wp_localize_script('ttf-builder-react', 'ttfBuilder', array(
            'ajaxUrl' => admin_url('admin-ajax.php'),
            'nonce' => wp_create_nonce('ttf_builder_nonce'),
            'options' => get_option('ttf_builder_options'),
            'pluginUrl' => TTF_BUILDER_PLUGIN_URL,
            'strings' => array(
                'selectBlock' => 'Select a block',
                'selectCell' => 'Select a cell',
                'confirmReplace' => 'Replace existing block?',
                'saveToCart' => 'Save to Cart',
                'clearGrid' => 'Clear Grid',
                'undo' => 'Undo',
                'redo' => 'Redo'
            )
        ));
    }
    
    private function has_shortcode() {
        global $post;
        if (is_a($post, 'WP_Post')) {
            return has_shortcode($post->post_content, 'tabletop_builder');
        }
        return false;
    }
    
    public function builder_shortcode($atts) {
        $atts = shortcode_atts(array(
            'campaign' => '',
            'default_size' => '',
            'height' => '600px'
        ), $atts, 'tabletop_builder');
        
        static $instance = 0;
        $instance++;
        $builder_id = 'ttf-builder-' . $instance;
        
        ob_start();
        ?>
        <div id="<?php echo esc_attr($builder_id); ?>" 
             class="ttf-builder-container" 
             style="height: <?php echo esc_attr($atts['height']); ?>;"
             data-campaign="<?php echo esc_attr($atts['campaign']); ?>"
             data-default-size="<?php echo esc_attr($atts['default_size']); ?>">
            <div class="ttf-builder-loading">Loading TabletopFactory Builder...</div>
        </div>
        <?php
        return ob_get_clean();
    }
    
    public function save_layout() {
        check_ajax_referer('ttf_builder_nonce', 'nonce');
        
        $layout_data = sanitize_text_field($_POST['layout_data']);
        $layout = json_decode(stripslashes($layout_data), true);
        
        if (json_last_error() !== JSON_ERROR_NONE) {
            wp_send_json_error('Invalid layout data');
        }
        
        WC()->session->set('ttf_builder_layout', $layout);
        wp_send_json_success(array('redirect' => wc_get_cart_url()));
    }
    
    public function get_blocks() {
        check_ajax_referer('ttf_builder_nonce', 'nonce');
        $blocks = $this->get_sample_blocks();
        wp_send_json_success($blocks);
    }
    
    private function get_sample_blocks() {
        return array(
            'regular' => array(
                array('id' => 'HG_001', 'name' => 'Graveyard Corner', 'image' => 'hg_001.png', 'size' => array('width' => 1, 'height' => 1)),
                array('id' => 'HG_002', 'name' => 'Tombstone Path', 'image' => 'hg_002.png', 'size' => array('width' => 1, 'height' => 1)),
                array('id' => 'HG_003', 'name' => 'Crypt Entrance', 'image' => 'hg_003.png', 'size' => array('width' => 1, 'height' => 1)),
            ),
            'level' => array(
                array('id' => 'LVL_1x1', 'name' => 'Level 1x1', 'image' => 'level_1x1.png', 'size' => array('width' => 1, 'height' => 1)),
                array('id' => 'LVL_1x2', 'name' => 'Level 1x2', 'image' => 'level_1x2.png', 'size' => array('width' => 1, 'height' => 2)),
                array('id' => 'LVL_1x3', 'name' => 'Level 1x3', 'image' => 'level_1x3.png', 'size' => array('width' => 1, 'height' => 3)),
            )
        );
    }
}
EOF

# WooCommerce integration
cat > includes/class-woocommerce.php << 'EOF'
<?php
if (!defined('ABSPATH')) exit;

class TTF_Builder_WooCommerce {
    private static $_instance = null;
    
    public static function instance() {
        if (is_null(self::$_instance)) {
            self::$_instance = new self();
        }
        return self::$_instance;
    }
    
    public function __construct() {
        add_action('woocommerce_before_calculate_totals', array($this, 'add_custom_product_to_cart'));
        add_filter('woocommerce_cart_item_name', array($this, 'display_custom_cart_item_data'), 10, 3);
        add_action('woocommerce_checkout_create_order_line_item', array($this, 'save_custom_order_item_data'), 10, 4);
    }
    
    public function add_custom_product_to_cart() {
        if (is_admin() && !defined('DOING_AJAX')) return;
        
        $layout_data = WC()->session->get('ttf_builder_layout');
        if (!$layout_data || WC()->session->get('ttf_builder_added_to_cart')) return;
        
        $product_id = $this->get_or_create_builder_product();
        if (!$product_id) return;
        
        $cart_item_data = array('ttf_layout_data' => $layout_data);
        WC()->cart->add_to_cart($product_id, 1, 0, array(), $cart_item_data);
        WC()->session->set('ttf_builder_added_to_cart', true);
        WC()->session->__unset('ttf_builder_layout');
    }
    
    private function get_or_create_builder_product() {
        $products = get_posts(array(
            'post_type' => 'product',
            'meta_key' => '_ttf_builder_product',
            'meta_value' => 'yes',
            'posts_per_page' => 1
        ));
        
        if (!empty($products)) return $products[0]->ID;
        
        $product = new WC_Product_Simple();
        $product->set_name('Custom Dungeon Layout');
        $product->set_price(25.00);
        $product->set_status('publish');
        $product->set_catalog_visibility('hidden');
        $product->set_virtual(true);
        
        $product_id = $product->save();
        update_post_meta($product_id, '_ttf_builder_product', 'yes');
        return $product_id;
    }
    
    public function display_custom_cart_item_data($item_name, $cart_item, $cart_item_key) {
        if (!isset($cart_item['ttf_layout_data'])) return $item_name;
        
        $layout_data = $cart_item['ttf_layout_data'];
        $item_name .= '<br><small>Grid: ' . $layout_data['gridSize'] . 'x' . $layout_data['gridSize'] . '</small>';
        return $item_name;
    }
    
    public function save_custom_order_item_data($item, $cart_item_key, $values, $order) {
        if (isset($values['ttf_layout_data'])) {
            $item->add_meta_data('_ttf_layout_data', $values['ttf_layout_data']);
        }
    }
}
EOF

# Package.json
cat > package.json << 'EOF'
{
  "name": "tabletopfactory-builder",
  "version": "1.0.0",
  "scripts": {
    "dev": "vite",
    "build": "vite build"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.1",
    "vite": "^5.0.8"
  }
}
EOF

# Vite config
cat > vite.config.js << 'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'assets/js/dist',
    rollupOptions: {
      input: 'src/index.js',
      output: {
        entryFileNames: 'builder.js'
      }
    }
  }
})
EOF

# React main component
cat > src/index.js << 'EOF'
import React from 'react';
import { createRoot } from 'react-dom/client';
import TabletopBuilder from './components/TabletopBuilder';

document.addEventListener('DOMContentLoaded', function() {
    const builderContainers = document.querySelectorAll('.ttf-builder-container');
    
    builderContainers.forEach(container => {
        const root = createRoot(container);
        root.render(<TabletopBuilder config={window.ttfBuilder} />);
    });
});
EOF

# Main React component
cat > src/components/TabletopBuilder.jsx << 'EOF'
import React, { useState, useEffect } from 'react';

const TabletopBuilder = ({ config }) => {
    const [gridSize, setGridSize] = useState(4);
    const [blocks, setBlocks] = useState({ regular: [], level: [] });
    const [placements, setPlacements] = useState([]);
    const [selectedBlock, setSelectedBlock] = useState(null);

    useEffect(() => {
        loadBlocks();
    }, []);

    const loadBlocks = async () => {
        try {
            const response = await fetch(config.ajaxUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({
                    action: 'ttf_get_blocks',
                    nonce: config.nonce,
                    campaign: 'haunted-graveyard'
                })
            });
            const result = await response.json();
            if (result.success) setBlocks(result.data);
        } catch (error) {
            console.error('Error loading blocks:', error);
        }
    };

    const handleSaveToCart = async () => {
        const layoutData = { gridSize, placements };
        
        try {
            const response = await fetch(config.ajaxUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({
                    action: 'ttf_save_layout',
                    nonce: config.nonce,
                    layout_data: JSON.stringify(layoutData)
                })
            });
            const result = await response.json();
            if (result.success && result.data.redirect) {
                window.location.href = result.data.redirect;
            }
        } catch (error) {
            console.error('Save error:', error);
        }
    };

    return (
        <div className="ttf-builder">
            <div className="ttf-toolbar">
                <select value={gridSize} onChange={(e) => setGridSize(parseInt(e.target.value))}>
                    <option value={3}>3×3</option>
                    <option value={4}>4×4</option>
                    <option value={5}>5×5</option>
                    <option value={6}>6×6</option>
                </select>
                <button onClick={handleSaveToCart}>Save to Cart</button>
            </div>
            
            <div className="ttf-builder-main">
                <div className="ttf-grid" style={{
                    display: 'grid',
                    gridTemplateColumns: `repeat(${gridSize}, 1fr)`,
                    gridTemplateRows: `repeat(${gridSize}, 1fr)`
                }}>
                    {Array(gridSize * gridSize).fill(null).map((_, index) => (
                        <div key={index} className="ttf-grid-cell"></div>
                    ))}
                </div>
                
                <div className="ttf-sidebar">
                    <h3>Blocks</h3>
                    {blocks.regular.map(block => (
                        <div key={block.id} className="ttf-block-item">
                            {block.name}
                        </div>
                    ))}
                </div>
            </div>
        </div>
    );
};

export default TabletopBuilder;
EOF

# CSS
cat > assets/css/builder.css << 'EOF'
.ttf-builder {
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px;
}

.ttf-toolbar {
    display: flex;
    justify-content: space-between;
    padding: 15px;
    background: #f8f9fa;
    border: 1px solid #dee2e6;
    border-radius: 8px;
    margin-bottom: 20px;
}

.ttf-builder-main {
    display: grid;
    grid-template-columns: 1fr 300px;
    gap: 20px;
}

.ttf-grid {
    aspect-ratio: 1;
    max-width: 600px;
    gap: 2px;
    background: #6c757d;
    border: 2px solid #495057;
    padding: 2px;
}

.ttf-grid-cell {
    background: #f8f9fa;
    border: 1px solid #dee2e6;
    cursor: pointer;
}

.ttf-grid-cell:hover {
    background: #e9ecef;
}

.ttf-sidebar {
    background: white;
    border: 1px solid #dee2e6;
    border-radius: 8px;
    padding: 20px;
}

.ttf-block-item {
    padding: 10px;
    border: 1px solid #dee2e6;
    margin-bottom: 5px;
    cursor: pointer;
}

.ttf-block-item:hover {
    background: #e7f3ff;
}

.ttf-builder-loading {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 400px;
    background: #f8f9fa;
    border: 1px solid #dee2e6;
}
EOF

# Sample data
cat > assets/data/haunted-graveyard.json << 'EOF'
{
  "regular": [
    {"id": "HG_001", "name": "Graveyard Corner", "image": "hg_001.png", "size": {"width": 1, "height": 1}},
    {"id": "HG_002", "name": "Tombstone Path", "image": "hg_002.png", "size": {"width": 1, "height": 1}},
    {"id": "HG_003", "name": "Crypt Entrance", "image": "hg_003.png", "size": {"width": 1, "height": 1}}
  ],
  "level": [
    {"id": "LVL_1x1", "name": "Level 1x1", "image": "level_1x1.png", "size": {"width": 1, "height": 1}},
    {"id": "LVL_1x2", "name": "Level 1x2", "image": "level_1x2.png", "size": {"width": 1, "height": 2}}
  ]
}
EOF

# Create README
cat > README.md << 'EOF'
# TabletopFactory Builder

A WordPress/WooCommerce plugin for designing custom dungeon layouts.

## Installation

1. Upload to `/wp-content/plugins/`
2. Activate the plugin
3. Run `npm install && npm run build`
4. Use shortcode `[tabletop_builder]` on any page

## Development

```bash
npm install
npm run dev    # Development mode
npm run build  # Production build
