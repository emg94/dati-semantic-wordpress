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
        if wp db check --allow-root --url="$SITE_URL" >/dev/null 2>&1; then
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

        echo "[bootstrap] Regenerating Oxygen shortcodes..."
        wp oxygen regenerate --allow-root || echo "[bootstrap] Oxygen regenerate not available"

        echo "[bootstrap] Clearing Oxygen cache..."
        wp oxygen clear-cache --allow-root || echo "[bootstrap] Oxygen cache clear not available"

        touch "$MARKER"
        echo "[bootstrap] Import and Oxygen rebuild completed."
    else
        echo "[bootstrap] No .wpress found, skipping restore."
    fi

    echo "[bootstrap] Bootstrap finished."
}

bootstrap_wp &
echo "[bootstrap] Async bootstrap launched."
exit 0
