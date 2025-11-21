#!/bin/bash
set -euo pipefail

WP_PATH="/var/www/html"
CONTENT_FILE="/tmp/content.wpress"
PLUGIN_ZIP="/tmp/plugins/all-in-one-wp-migration-unlimited-extension.zip"
MARKER="${WP_PATH}/.import_done"

SITE_URL="https://wp-ndc-dev.apps.cloudpub.testedev.istat.it"

DB_HOST="${WORDPRESS_DB_HOST}"
DB_USER="${WORDPRESS_DB_USER}"
DB_PASSWORD="${WORDPRESS_DB_PASSWORD}"
DB_NAME="${WORDPRESS_DB_NAME}"

echo "[bootstrap] Starting WordPress bootstrap…"

bootstrap_wp() {

    #
    # 1) Attesa DB
    #
    echo "[bootstrap] Waiting for DB connection (max 60s)…"

    for i in {1..20}; do
        if wp db check --allow-root --path="$WP_PATH" --quiet > /dev/null 2>&1; then
            echo "[bootstrap] DB is reachable."
            break
        fi
        echo "[bootstrap] DB not reachable, retrying…"
        sleep 3
    done


    #
    # 2) Se WordPress è già installato → esci
    #
    if wp core is-installed --allow-root --path="$WP_PATH" > /dev/null 2>&1; then
        echo "[bootstrap] WordPress already installed, skipping installation."
        return
    fi


    #
    # 3) Installa WordPress
    #
    echo "[bootstrap] Installing WordPress…"

    wp core install \
        --url="$SITE_URL" \
        --title="Dev WP" \
        --admin_user="admin" \
        --admin_password="admin" \
        --admin_email="admin@example.com" \
        --skip-email \
        --allow-root \
        --path="$WP_PATH"


    #
    # 4) Installa plugin Unlimited Extension
    #
    if [ -f "$PLUGIN_ZIP" ]; then
        echo "[bootstrap] Installing Migration Unlimited Extension…"
        wp plugin install "$PLUGIN_ZIP" --activate --allow-root --path="$WP_PATH"
    else
        echo "[bootstrap] Unlimited Extension plugin missing, skipping."
    fi


    #
    # 5) Import .wpress SOLO la prima volta
    #
    if [ -f "$MARKER" ]; then
        echo "[bootstrap] Import already done, skipping."
    else
        if [ -f "$CONTENT_FILE" ]; then
            echo "[bootstrap] Waiting 40s before import… (Apache warm-up)"
            sleep 40

            echo "[bootstrap] Importing .wpress backup…"
            wp ai1wm import "$CONTENT_FILE" --yes --allow-root --path="$WP_PATH"

            touch "$MARKER"
            echo "[bootstrap] Import completed."
        else
            echo "[bootstrap] No .wpress found, skipping import."
        fi
    fi


    #
    # 6) Rigenera permalink
    #
    echo "[bootstrap] Flushing permalinks…"
    wp rewrite flush --hard --allow-root --path="$WP_PATH"


    #
    # 7) Oxygen optional
    #
    wp oxygen regenerate --allow-root --path="$WP_PATH" \
        || echo "[bootstrap] Oxygen regenerate not available."

    wp oxygen clear-cache --allow-root --path="$WP_PATH" \
        || echo "[bootstrap] Oxygen cache not available."

    echo "[bootstrap] Bootstrap completed."
}

bootstrap_wp &

echo "[bootstrap] Launched async bootstrap."
exit 0
