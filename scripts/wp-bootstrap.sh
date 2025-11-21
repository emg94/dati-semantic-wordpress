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

# Variabili WP-CLI per ambiente CLI puro
export HTTP_HOST="${SITE_URL#https://}"
export WP_CLI_CHECK_REQUIREMENTS=false

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

    # --- Pulizia completa di html ---
    echo "[bootstrap] Cleaning /var/www/html completely..."
    rm -rf "$WP_PATH"/* || true

    # --- Reinstallazione WordPress ---
    echo "[bootstrap] Installing fresh WordPress..."
    wp core download --path="$WP_PATH" --allow-root

    wp config create \
        --dbname="$DB_NAME" \
        --dbuser="$DB_USER" \
        --dbpass="$DB_PASSWORD" \
        --dbhost="$DB_HOST" \
        --path="$WP_PATH" \
        --skip-check \
        --allow-root

    wp db create --allow-root --path="$WP_PATH"

    wp core install \
        --url="$SITE_URL" \
        --title="Dev WP" \
        --admin_user="admin" \
        --admin_password="admin" \
        --admin_email="admin@example.com" \
        --skip-email \
        --path="$WP_PATH" \
        --allow-root

    # --- Installa plugin a pagamento ---
    if [ -f "$PLUGIN_ZIP" ]; then
        echo "[bootstrap] Installing plugin..."
        wp plugin install "$PLUGIN_ZIP" --activate --allow-root --path="$WP_PATH"
        sleep 5
        wp cache flush --allow-root --path="$WP_PATH"
    else
        echo "[bootstrap] Plugin ZIP not found, skipping."
    fi

    # --- Import .wpress se presente ---
    if [ -f "$CONTENT_FILE" ]; then
        echo "[bootstrap] Waiting 10s before import..."
        sleep 10

        if wp help --path="$WP_PATH" | grep -q 'ai1wm'; then
            echo "[bootstrap] Importing .wpress content..."
            wp ai1wm import "$CONTENT_FILE" --yes --allow-root --path="$WP_PATH"
            touch "$MARKER"
        else
            echo "[bootstrap] ai1wm command not available, skipping import."
        fi
    fi

    # --- Rigenerazioni post-import ---
    wp rewrite flush --hard --allow-root --path="$WP_PATH"
    wp oxygen regenerate --allow-root --path="$WP_PATH" || echo "[bootstrap] Oxygen regeneration not available"
    wp oxygen clear-cache --allow-root --path="$WP_PATH" || echo "[bootstrap] Oxygen cache clearing not available"

    echo "[bootstrap] WordPress bootstrap finished."
}

# --- Esegue in background ---
bootstrap_wp &

echo "[bootstrap] Async bootstrap started, exiting postStart hook immediately."
exit 0
