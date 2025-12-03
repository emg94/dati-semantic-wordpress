#!/bin/bash

set -euo pipefail

WP_PATH="/var/www/html"
CONTENT_FILE="/tmp/content.wpress"
MARKER="$WP_PATH/.wpress_imported"
PLUGIN_DIR="/tmp/plugins"
PLUGIN_ZIP="$PLUGIN_DIR/all-in-one-wp-migration-unlimited-extension.zip"

DB_HOST="${WORDPRESS_DB_HOST}"
DB_USER="${WORDPRESS_DB_USER}"
DB_PASSWORD="${WORDPRESS_DB_PASSWORD}"
DB_NAME="${WORDPRESS_DB_NAME}"
SITE_URL="https://wp-ndc-dev.apps.cloudpub.testedev.istat.it"

echo "[bootstrap] Launching async WordPress bootstrap..."

bootstrap_wp() {
    echo "[bootstrap] Waiting for WordPress DB connection (max 60s)..."
    
    TIMEOUT=60
    END=$((SECONDS + TIMEOUT))
    DB_OK=false
    set +e
    
    while [ $SECONDS -lt $END ]; do
        if wp db query 'SELECT 1' --allow-root --url="$SITE_URL" >/dev/null 2>&1; then
            DB_OK=true
            break
        fi
        echo "[bootstrap] DB not ready, retrying..."
        sleep 3
    done
    set -e
    
    if [ "$DB_OK" = false ]; then
        echo "[bootstrap] DB not reachable — skipping."
        return
    fi
    
    echo "[bootstrap] DB OK — resetting WordPress..."
    wp db reset --yes --allow-root --url="$SITE_URL"
    
    wp core install \
        --url="$SITE_URL" \
        --title="Dev WP" \
        --admin_user="admin" \
        --admin_password="admin" \
        --admin_email="admin@example.com" \
        --skip-email \
        --allow-root
    
    echo "[bootstrap] Installing AI1WM Unlimited..."
    wp plugin install "$PLUGIN_ZIP" --activate --allow-root
    
    echo "[bootstrap] Updating AI1WM Unlimited plugin..."
    wp plugin update all-in-one-wp-migration-unlimited-extension --allow-root || echo "[bootstrap] Plugin update failed or no update available"
    
    echo "[bootstrap] Waiting 10s before running import..."
    sleep 10
    
    if [ -f "$CONTENT_FILE" ]; then
        echo "[bootstrap] Copying .wpress into ai1wm-backups..."
        mkdir -p "$WP_PATH/wp-content/ai1wm-backups"
        cp "$CONTENT_FILE" "$WP_PATH/wp-content/ai1wm-backups/"
        
        echo "[bootstrap] Importing .wpress..."
        wp ai1wm restore "$(basename "$CONTENT_FILE")" --yes --allow-root
        
        echo "[bootstrap] Regenerating permalinks..."
        wp rewrite flush --hard --allow-root
        
        # Regenerate Oxygen Builder shortcodes and CSS cache
        echo "[bootstrap] Regenerating Oxygen Builder shortcodes and CSS cache..."
        
        # Check if oxygen-regenerate.php mu-plugin exists
        if [ ! -f "$WP_PATH/wp-content/mu-plugins/oxygen-regenerate.php" ]; then
            echo "[bootstrap] WARNING: oxygen-regenerate.php mu-plugin not found!"
            echo "[bootstrap]    The plugin must be installed in: $WP_PATH/wp-content/mu-plugins/oxygen-regenerate.php"
            echo "[bootstrap]    Skipping Oxygen regeneration."
        else
            # Extract domain from SITE_URL for Oxygen CSS URL generation
            # This ensures CSS URLs are correct even in WP-CLI context
            DOMAIN=$(echo "$SITE_URL" | sed -E 's|^https?://||' | sed 's|/.*||')
            if [ -n "$DOMAIN" ]; then
                echo "[bootstrap] Configuring Oxygen domain: $DOMAIN"
                wp option update oxygen_regenerate_site_domain "$DOMAIN" --allow-root --url="$SITE_URL" 2>/dev/null || true
            fi
            
            # The wp oxygen regenerate command automatically manages cache state:
            # - Enables cache temporarily if disabled (required for CSS generation)
            # - Keeps cache enabled after generating CSS files (required for CSS to load)
            # - Only restores original state if no CSS files were generated
            echo "[bootstrap] Running Oxygen regeneration (cache state managed automatically)..."
            
            if wp oxygen regenerate --force-css --allow-root --url="$SITE_URL" 2>&1; then
                echo "[bootstrap] Oxygen regeneration completed successfully."
            else
                echo "[bootstrap] Oxygen regeneration completed with warnings (check output above)."
            fi
            
            # Verify final cache state
            FINAL_CACHE_STATE=$(wp option get oxygen_vsb_universal_css_cache --allow-root --url="$SITE_URL" 2>/dev/null || echo "false")
            echo "[bootstrap] Final universal CSS cache state: $FINAL_CACHE_STATE"
        fi
        
        touch "$MARKER"
        echo "[bootstrap] Import completed."
    else
        echo "[bootstrap] No .wpress found, skipping restore."
    fi
    
    echo "[bootstrap] Bootstrap finished."
}

bootstrap_wp &

echo "[bootstrap] Async bootstrap launched."

exit 0