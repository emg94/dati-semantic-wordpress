#!/bin/bash
#
# wp-bootstrap.sh - bootstrap WordPress in container
# - Attende il DB
# - Garantisce che wp-config.php esista (creazione se possibile)
# - Applica WORDPRESS_CONFIG_EXTRA
# - Esegue reset/install/import/plugin/oxygen come prima
#
set -euo pipefail

WP_PATH="/var/www/html"
WP_CONFIG="$WP_PATH/wp-config.php"
CONTENT_FILE="/tmp/content.wpress"
MARKER_IMPORTED="$WP_PATH/.wpress_imported"
PLUGIN_DIR="/tmp/plugins"
PLUGIN_ZIP="$PLUGIN_DIR/all-in-one-wp-migration-unlimited-extension.zip"

# ENV
SITE_URL="${WORDPRESS_SITE_URL:-}"
DB_NAME="${WORDPRESS_DB_NAME:-}"
DB_USER="${WORDPRESS_DB_USER:-}"
DB_PASSWORD="${WORDPRESS_DB_PASSWORD:-}"
DB_HOST="${WORDPRESS_DB_HOST:-}"
DB_PREFIX="${WORDPRESS_TABLE_PREFIX:-wp_}"
WP_CONFIG_EXTRA="${WORDPRESS_CONFIG_EXTRA:-}"

# === PROD: abilita SSL MySQL solo per l'ambiente PROD ===
if [ "$DB_USER" = "pd_ndc_wp_ddl" ]; then
    log "PROD environment detected — enabling MySQL SSL"

    WP_CONFIG_EXTRA="${WP_CONFIG_EXTRA}
define( 'MYSQL_CLIENT_FLAGS', MYSQLI_CLIENT_SSL );
define( 'MYSQL_SSL_CA', '/etc/ssl/mysql/azure-mysql-ca-cert.pem' );
"
fi

# Marker per il blocco extra in wp-config.php
MARK_START="/* BEGIN WORDPRESS_CONFIG_EXTRA */"
MARK_END="/* END WORDPRESS_CONFIG_EXTRA */"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [bootstrap] $*"; }

# Rimuove eventuale blocco precedente e appende il blocco extra in modo idempotente
apply_wp_config_extra() {
    if [ -z "${WP_CONFIG_EXTRA:-}" ]; then
        log "No WORDPRESS_CONFIG_EXTRA set, skipping."
        return 0
    fi

    if [ ! -f "$WP_CONFIG" ]; then
        log "wp-config.php non trovato; non posso applicare WORDPRESS_CONFIG_EXTRA ora."
        return 1
    fi

    log "Applying WORDPRESS_CONFIG_EXTRA in an idempotent way..."

    # Rimuovi blocco precedente se esiste
    awk -v s="$MARK_START" -v e="$MARK_END" '
    BEGIN{inblock=0}
    {
      if (index($0,s)) { inblock=1; next }
      if (index($0,e)) { inblock=0; next }
      if (!inblock) print
    }' "$WP_CONFIG" > "${WP_CONFIG}.tmp" && mv "${WP_CONFIG}.tmp" "$WP_CONFIG"

    # Appende il nuovo blocco alla fine del file
    {
        printf "\n%s\n" "$MARK_START"
        printf "%s\n" "$WP_CONFIG_EXTRA"
        printf "%s\n" "$MARK_END"
    } >> "$WP_CONFIG"

    log "WORDPRESS_CONFIG_EXTRA applied."
    return 0
}

# Se wp-config.php non esiste, prova a crearlo usando le ENV standard
ensure_wp_config() {
    if [ -f "$WP_CONFIG" ]; then
        log "wp-config.php esiste già."
        return 0
    fi

    # Se non abbiamo almeno DB_NAME e DB_USER, non possiamo creare il config
    if [ -z "${DB_NAME}" ] || [ -z "${DB_USER}" ]; then
        log "Impossibile creare wp-config.php: manca WORDPRESS_DB_NAME o WORDPRESS_DB_USER."
        return 1
    fi

    log "wp-config.php non trovato: provo a crearne uno con wp-cli..."
    # Esegui wp config create
    wp config create \
        --dbname="$DB_NAME" \
        --dbuser="$DB_USER" \
        --dbpass="$DB_PASSWORD" \
        --dbhost="$DB_HOST" \
        --dbprefix="$DB_PREFIX" \
        --allow-root --path="$WP_PATH"

    if [ -f "$WP_CONFIG" ]; then
        log "wp-config.php creato correttamente."
        return 0
    else
        log "Creazione wp-config.php FALLITA."
        return 1
    fi
}

bootstrap_wp() {
    log "Bootstrap async started."

    # Attendi il DB (max 60s)
    log "Waiting for WordPress DB connection (max 60s)..."
    TIMEOUT=60
    END=$((SECONDS + TIMEOUT))
    DB_OK=false
    set +e
    while [ $SECONDS -lt $END ]; do
        # Se wp-config.php non esiste, wp db query fallirà: tenta comunque di creare wp-config.php se possibile
        if [ ! -f "$WP_CONFIG" ]; then
            ensure_wp_config || true
        fi

        if wp db query 'SELECT 1' --allow-root --path="$WP_PATH" --url="$SITE_URL" >/dev/null 2>&1; then
            DB_OK=true
            break
        fi

        log "DB not ready, retrying..."
        sleep 3
    done
    set -e

    if [ "$DB_OK" = false ]; then
        log "DB not reachable — skipping bootstrap."
        return 0
    fi

    # Se wp-config.php esiste ora, applica sempre le extra (idempotente)
    if [ -f "$WP_CONFIG" ]; then
        apply_wp_config_extra || log "Attenzione: non è stato possibile applicare WORDPRESS_CONFIG_EXTRA in questa fase."
    else
        log "wp-config.php ancora mancante dopo la connessione DB. Procedo comunque."
    fi

    # Reset DB e installare WordPress
    log "DB OK — resetting WordPress..."
    wp db reset --yes --allow-root --path="$WP_PATH" --url="$SITE_URL"

    log "Running wp core install..."
    wp core install \
        --url="$SITE_URL" \
        --title="Dev WP" \
        --admin_user="admin" \
        --admin_password="admin" \
        --admin_email="admin@example.com" \
        --skip-email \
        --allow-root \
        --path="$WP_PATH"

    # Se per qualche motivo sono state aggiunte le extra dopo l'install, riproviamo ad applicarle
    if [ -f "$WP_CONFIG" ]; then
        apply_wp_config_extra || true
    fi

    # Installa plugin incluso nello image
    if [ -f "$PLUGIN_ZIP" ]; then
        log "Installing AI1WM Unlimited plugin..."
        wp plugin install "$PLUGIN_ZIP" --activate --allow-root --path="$WP_PATH"
        log "Updating AI1WM Unlimited plugin (if available)..."
        wp plugin update all-in-one-wp-migration-unlimited-extension --allow-root --path="$WP_PATH" || log "Plugin update failed or not available"
    else
        log "Plugin zip non presente ($PLUGIN_ZIP) — skipping plugin install."
    fi

    log "Waiting 10s before running import..."
    sleep 10

    if [ -f "$CONTENT_FILE" ]; then
        log "Copying .wpress into ai1wm-backups..."
        mkdir -p "$WP_PATH/wp-content/ai1wm-backups"
        cp "$CONTENT_FILE" "$WP_PATH/wp-content/ai1wm-backups/"

        log "Importing .wpress..."
        wp ai1wm restore "$(basename "$CONTENT_FILE")" --yes --allow-root --path="$WP_PATH"

        log "Regenerating permalinks..."
        wp rewrite flush --hard --allow-root --path="$WP_PATH"

        # Oxygen Builder regeneration
        if [ ! -f "$WP_PATH/wp-content/mu-plugins/oxygen-regenerate.php" ]; then
            log "WARNING: oxygen-regenerate.php mu-plugin not found! Skipping Oxygen regeneration."
        else
            DOMAIN=$(echo "$SITE_URL" | sed -E 's|^https?://||' | sed 's|/.*||')
            if [ -n "$DOMAIN" ]; then
                log "Configuring Oxygen domain: $DOMAIN"
                wp option update oxygen_regenerate_site_domain "$DOMAIN" --allow-root --url="$SITE_URL" --path="$WP_PATH" 2>/dev/null || true
            fi
            log "Running Oxygen regeneration..."
            if wp oxygen regenerate --force-css --allow-root --url="$SITE_URL" --path="$WP_PATH" 2>&1; then
                log "Oxygen regeneration completed successfully."
            else
                log "Oxygen regeneration completed with warnings (check output above)."
            fi
        fi

        touch "$MARKER_IMPORTED"
        log "Import completed."
    else
        log "No .wpress found, skipping restore."
    fi

    # Assicura ownership corretta
    if command -v chown >/dev/null 2>&1; then
        log "Setting ownership $WP_PATH -> www-data:www-data (if applicabile)..."
        chown -R www-data:www-data "$WP_PATH" || true
    fi

    log "Bootstrap finished."
}

# Lancia in background
bootstrap_wp &

log "Async bootstrap launched."

exit 0
