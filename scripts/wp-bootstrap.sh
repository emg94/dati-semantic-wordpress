#!/bin/bash
#
# wp-bootstrap.sh - bootstrap WordPress in container
# - Attende il DB
# - Garantisce che wp-config.php esista (creazione se possibile)
# - Applica DB SSL defines EARLY se siamo in PROD e il CA esiste
# - Garantisce che wp-config.php contenga WORDPRESS_CONFIG_EXTRA (idempotente)
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

# Marker per il blocco extra in wp-config.php
MARK_START="/* BEGIN WORDPRESS_CONFIG_EXTRA */"
MARK_END="/* END WORDPRESS_CONFIG_EXTRA */"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [bootstrap] $*"; }

log "DEBUG: DB_USER='${DB_USER:-}'"

# === PROD: abilita SSL MySQL solo per l'ambiente PROD ===
ENABLE_DB_SSL=false
MYSQL_SSL_CA="/etc/ssl/mysql/azure-mysql-ca-cert.pem"

# DB_SSL_DEFINES will contain PHP define() lines to be injected early in wp-config.php
DB_SSL_DEFINES=""

if [ "${DB_USER:-}" = "pd_ndc_wp_ddl" ]; then
    log "PROD environment detected — checking MySQL SSL certificate..."
    if [ -f "$MYSQL_SSL_CA" ]; then
        log "MySQL SSL certificate found at $MYSQL_SSL_CA — will enable MySQL SSL (in wp-config.php early)."
        ENABLE_DB_SSL=true
        DB_SSL_DEFINES=$(cat <<PHP
/* BEGIN MYSQL SSL DEFINES */
define( 'MYSQL_CLIENT_FLAGS', MYSQLI_CLIENT_SSL );
define( 'MYSQL_SSL_CA', '$MYSQL_SSL_CA' );
/* END MYSQL SSL DEFINES */
PHP
)
    else
        log "WARNING: PROD environment detected but SSL certificate not found at $MYSQL_SSL_CA — SSL will NOT be enabled"
        log "This may cause connection issues in production!"
    fi
else
    log "DEV/TEST environment detected — MySQL SSL will NOT be enabled"
fi

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

# Inserisce le define SSL DB all'inizio (prima del "That's all, stop editing") in modo idempotente
apply_db_ssl_defines_early() {
    # Se non abbiamo defines da aggiungere, esci
    [ -z "$DB_SSL_DEFINES" ] && return 0
    [ ! -f "$WP_CONFIG" ] && return 1

    # Controlla se sono già presenti (idempotente)
    if grep -q "MYSQL_CLIENT_FLAGS" "$WP_CONFIG" >/dev/null 2>&1; then
        log "MySQL SSL defines already present in wp-config.php, skipping injection."
        return 0
    fi

    log "Injecting MySQL SSL defines early in wp-config.php"

    # Inserisce il blocco prima della linea che contiene "stop editing" (idempotente)
    awk -v ssl="$DB_SSL_DEFINES" '
    BEGIN{done=0}
    /stop editing/ && !done {
        print ssl
        done=1
    }
    { print }
    ' "$WP_CONFIG" > "${WP_CONFIG}.tmp" && mv "${WP_CONFIG}.tmp" "$WP_CONFIG"

    log "MySQL SSL defines injected."
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

    # Creazione base del wp-config.php
    wp config create \
        --dbname="$DB_NAME" \
        --dbuser="$DB_USER" \
        --dbpass="$DB_PASSWORD" \
        --dbhost="$DB_HOST" \
        --dbprefix="$DB_PREFIX" \
        --allow-root --path="$WP_PATH"

    if [ -f "$WP_CONFIG" ]; then
        log "wp-config.php creato correttamente. Applying early DB SSL defines if needed."
        # Applica subito le define SSL (se necessario) prima di qualsiasi tentativo di connessione
        apply_db_ssl_defines_early || log "Attenzione: non è stato possibile iniettare le DB SSL defines subito dopo la creazione del wp-config.php."
        return 0
    else
        log "Creazione wp-config.php FALLITA."
        return 1
    fi
}

bootstrap_wp() {
    log "Bootstrap async started."

    # Se wp-config.php esiste, prova ad applicare le defines SSL early prima di tentare la connessione DB
    if [ -f "$WP_CONFIG" ]; then
        apply_db_ssl_defines_early || log "Attenzione: non è stato possibile applicare le DB SSL defines all'inizio."
    fi

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
        else
            # Assicura che le DB SSL defines siano presenti appena prima di provare la connessione
            apply_db_ssl_defines_early || true
        fi

        if wp db query 'SELECT 1' --allow-root --path="$WP_PATH" >/dev/null 2>&1; then
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
    wp db reset --yes --allow-root --path="$WP_PATH"

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
                if [ -n "$SITE_URL" ]; then
                    wp option update oxygen_regenerate_site_domain "$DOMAIN" --allow-root --url="$SITE_URL" --path="$WP_PATH" 2>/dev/null || true
                else
                    wp option update oxygen_regenerate_site_domain "$DOMAIN" --allow-root --path="$WP_PATH" 2>/dev/null || true
                fi
            fi
            log "Running Oxygen regeneration..."
            if [ -n "$SITE_URL" ]; then
                WP_REGENERATE_CMD="wp oxygen regenerate --force-css --allow-root --url=\"$SITE_URL\" --path=\"$WP_PATH\""
            else
                WP_REGENERATE_CMD="wp oxygen regenerate --force-css --allow-root --path=\"$WP_PATH\""
            fi
            if eval "$WP_REGENERATE_CMD" 2>&1; then
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
