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

        echo "[bootstrap] Flushing permalinks..."
        wp rewrite flush --hard --allow-root

        echo "[bootstrap] Forcing WordPress reload..."
        wp cache flush --allow-root || true
        wp transient delete --all --allow-root || true
        curl -k -s "$SITE_URL" >/dev/null 2>&1 || true


        # Lista possibili slug Oxygen
        OXYGEN_SLUGS=("oxygen" "oxygen-builder" "oxygen-core" "oxygen-functions" "oxygen-addon")
        FOUND_OXYGEN=false

        echo "[bootstrap] Checking for Oxygen plugins..."
        for slug in "${OXYGEN_SLUGS[@]}"; do
            if wp plugin is-installed "$slug" --allow-root >/dev/null 2>&1; then
                echo "[bootstrap] Found Oxygen plugin: $slug"
                FOUND_OXYGEN=true
                if ! wp plugin is-active "$slug" --allow-root >/dev/null 2>&1; then
                    echo "[bootstrap] Activating plugin $slug..."
                    wp plugin activate "$slug" --allow-root || echo "[bootstrap] Failed activating $slug"
                fi
            fi
        done

        if [ "$FOUND_OXYGEN" = false ]; then
            echo "[bootstrap] WARNING: No Oxygen plugin found among slugs: ${OXYGEN_SLUGS[*]}"
        fi

        echo "[bootstrap] Waiting for Oxygen functions (max 60s)..."
        MAX_WAIT=60
        END_WAIT=$((SECONDS + MAX_WAIT))
        OXYREADY=false

        set +e
        while [ $SECONDS -lt $END_WAIT ]; do
            HAS_CT=$(wp eval 'echo function_exists("ct_sign_shortcode") ? "1" : "0";' --allow-root 2>/dev/null || echo "0")
            HAS_CSS=$(wp eval 'echo function_exists("oxygen_vsb_cache_css") ? "1" : "0";' --allow-root 2>/dev/null || echo "0")

            if [ "$HAS_CT" = "1" ] || [ "$HAS_CSS" = "1" ]; then
                OXYREADY=true
                break
            fi

            echo "[bootstrap] Oxygen not ready — retrying in 3s..."
            curl -k -s "$SITE_URL" >/dev/null 2>&1 || true
            wp cache flush --allow-root || true
            sleep 3
        done
        set -e

        if [ "$OXYREADY" = false ]; then
            echo "[bootstrap] WARNING: Oxygen functions never became available — skipping Oxygen regen."
        else
            echo "[bootstrap] Oxygen OK — regenerating shortcodes and CSS"

            echo "[bootstrap] Regenerating Oxygen shortcodes (all post types)..."
            wp eval '
                if (function_exists("ct_sign_shortcode")) {
                    $types = get_post_types(["public" => true]);
                    foreach ($types as $t) {
                        ct_sign_shortcode($t);
                        echo "Shortcodes regenerated for $t\n";
                    }
                } else {
                    echo "ct_sign_shortcode() NOT FOUND\n";
                }
            ' --allow-root

            echo "[bootstrap] Regenerating Oxygen CSS cache..."
            wp eval '
                if (function_exists("oxygen_vsb_cache_css")) {
                    oxygen_vsb_cache_css();
                    echo "CSS cache regenerated\n";
                } else {
                    echo "oxygen_vsb_cache_css() NOT FOUND\n";
                }
            ' --allow-root
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
