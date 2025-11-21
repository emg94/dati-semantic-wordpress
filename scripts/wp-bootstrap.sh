#!/bin/bash
set -euo pipefail

# --- Configurazioni ---
WP_PATH="/var/www/html"
CONTENT_FILE="/tmp/content.wpress"
MARKER="$WP_PATH/.wpress_imported"

DB_HOST="${WORDPRESS_DB_HOST}"
DB_USER="${WORDPRESS_DB_USER}"
DB_PASSWORD="${WORDPRESS_DB_PASSWORD}"
DB_NAME="${WORDPRESS_DB_NAME}"
SITE_URL="https://wp-ndc-dev.apps.cloudpub.testedev.istat.it"

echo "[bootstrap] Launching async WordPress bootstrap..."

# --- Funzione bootstrap ---
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
        echo "[bootstrap] DB not reachable within ${TIMEOUT}s — skipping installation."
        return
    fi

    echo "[bootstrap] DB reachable — resetting and installing WordPress..."


    # Reset DB
    echo "[bootstrap] Resetting database..."
    wp db reset --yes --allow-root --url="$SITE_URL"

    echo "[bootstrap] Installing WordPress core..."
    wp core install \
        --url="$SITE_URL" \
        --title="Dev WP" \
        --admin_user="admin" \
        --admin_password="admin" \
        --admin_email="admin@example.com" \
        --skip-email \
        --allow-root

    if [ -f "$CONTENT_FILE" ]; then
        echo "[bootstrap] Importing .wpress content..."
        wp plugin install all-in-one-wp-migration --activate --allow-root
        wp ai1wm import "$CONTENT_FILE" --yes --allow-root
        touch "$MARKER"
        rm -f "$CONTENT_FILE"
        echo "[bootstrap] Import completed."
    else
        echo "[bootstrap] No .wpress file found, skipping import."
    fi

    echo "[bootstrap] WordPress bootstrap finished."
}

# --- Lancia in background ---
bootstrap_wp &

echo "[bootstrap] Async bootstrap started, exiting postStart hook immediately."
exit 0
