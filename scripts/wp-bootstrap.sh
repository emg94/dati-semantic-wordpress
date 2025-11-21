#!/bin/bash
set -euo pipefail

# --- Configurazioni ---
WP_PATH="/var/www/html"
CONTENT_FILE="/tmp/content.wpress"
MARKER="$WP_PATH/.wpress_imported"
PLUGIN_ZIP="/tmp/plugins/all-in-one-wp-migration-unlimited-extension.zip"

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
        echo "[bootstrap] DB not reachable within ${TIMEOUT}s — skipping install/import."
        return
    fi

    echo "[bootstrap] DB reachable — resetting and installing WordPress..."
    wp db reset --yes --allow-root --url="$SITE_URL"

    wp core install \
        --url="$SITE_URL" \
        --title="Dev WP" \
        --admin_user="admin" \
        --admin_password="admin" \
        --admin_email="admin@example.com" \
        --skip-email \
        --allow-root

    # --- Installa il plugin Unlimited Extension ---
    if [ -f "$PLUGIN_ZIP" ]; then
        echo "[bootstrap] Installing All-in-One WP Migration Unlimited Extension..."
        wp plugin install "$PLUGIN_ZIP" --activate --allow-root
    else
        echo "[bootstrap] Plugin Unlimited Extension not found, skipping."
    fi

    # --- Import .wpress ---
    if [ -f "$CONTENT_FILE" ]; then
        echo "[bootstrap] Waiting 60s before import..."
        sleep 60  # attesa prima dell'import per sicurezza

        echo "[bootstrap] Importing .wpress content..."
        wp ai1wm import "$CONTENT_FILE" --yes --allow-root
        touch "$MARKER"
        echo "[bootstrap] Import completed."

        # --- Rigenerazioni post-import ---
        echo "[bootstrap] Regenerating permalinks..."
        wp rewrite flush --hard --allow-root

        echo "[bootstrap] Regenerating Oxygen Builder shortcodes..."
        wp oxygen regenerate --allow-root || echo "[bootstrap] Oxygen shortcode regeneration not available"

        echo "[bootstrap] Clearing Oxygen Builder cache..."
        wp oxygen clear-cache --allow-root || echo "[bootstrap] Oxygen cache clearing not available"
    else
        echo "[bootstrap] No .wpress file found, skipping import."
    fi

    echo "[bootstrap] WordPress bootstrap finished."
}

# --- Lancia in background, non bloccare il postStart ---
bootstrap_wp &

echo "[bootstrap] Async bootstrap started, exiting postStart hook immediately."
exit 0
