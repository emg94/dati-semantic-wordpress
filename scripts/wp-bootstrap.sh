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
SITE_URL="https://${HOSTNAME:-localhost}"

echo "[bootstrap] Launching async WordPress bootstrap..."

# --- Funzione bootstrap ---
bootstrap_wp() {
    # Attendi massimo 10 secondi il DB
    echo "[bootstrap] Waiting for DB (${DB_HOST}) max 10s..."
    TIMEOUT=10
    END=$((SECONDS + TIMEOUT))
    DB_OK=false

    set +e
    while [ $SECONDS -lt $END ]; do
        mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" --ssl-mode=REQUIRED \
            -e "SELECT 1;" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            DB_OK=true
            break
        fi
        sleep 1
    done
    set -e

    if [ "$DB_OK" = false ]; then
        echo "[bootstrap] DB not reachable within ${TIMEOUT}s — skipping installation."
        return
    fi

    echo "[bootstrap] DB reachable — installing WordPress..."

    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" --ssl-mode=REQUIRED \
          -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\`;"

    wp core install \
        --url="$SITE_URL" \
        --title="Dev WP" \
        --admin_user="admin" \
        --admin_password="admin" \
        --admin_email="admin@example.com" \
        --skip-email \
        --allow-root

    if [ -f "$CONTENT_FILE" ]; then
        echo "[bootstrap] Importing .wpress..."
        wp plugin install all-in-one-wp-migration --activate --allow-root
        wp ai1wm import "$CONTENT_FILE" --yes --allow-root
        touch "$MARKER"
        rm -f "$CONTENT_FILE"
        echo "[bootstrap] Import completed."
    fi

    echo "[bootstrap] WordPress bootstrap finished."
}

# --- Lancia in background ---
bootstrap_wp &

echo "[bootstrap] Async bootstrap started, exiting postStart hook immediately."
exit 0
