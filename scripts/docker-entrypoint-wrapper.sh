#!/bin/bash
set -euo pipefail

WP_PATH="/var/www/html"
CONTENT_FILE="/tmp/content.wpress"
MARKER="$WP_PATH/.wpress_imported"

echo "=== Starting fresh WordPress installation with .wpress import ==="

# Inizializza WordPress core (copie dei file base)
echo "Initializing WordPress core..."
docker-entrypoint.sh true
echo "WordPress core initialized"

# Attendi la disponibilità del database
echo "Waiting for database connectivity..."
for i in {1..60}; do
    if wp db check --allow-root >/dev/null 2>&1; then
        echo "Database is reachable"
        break
    fi
    echo "Database not ready... attempt $i/60"
    if [ $i -eq 60 ]; then
        echo "ERROR: Database not reachable after 2 minutes"
        exit 1
    fi
    sleep 2
done

# Installa WordPress da zero
echo "Installing WordPress core..."
wp core install \
    --url="https://localhost" \
    --title="Dev WP" \
    --admin_user="admin" \
    --admin_password="admin" \
    --admin_email="admin@example.com" \
    --skip-email \
    --allow-root
echo "WordPress installed"

# Importa il contenuto .wpress
if [ -f "$CONTENT_FILE" ]; then
    echo "Found .wpress file: $CONTENT_FILE"
    wp plugin install all-in-one-wp-migration --activate --allow-root
    wp ai1wm import "$CONTENT_FILE" --yes --allow-root
    echo "Import completed"
    touch "$MARKER"
    rm -f "$CONTENT_FILE"
else
    echo "No .wpress file found at $CONTENT_FILE, skipping import"
fi

# Avvia Apache
echo "Starting Apache..."
exec docker-entrypoint.sh "$@"

