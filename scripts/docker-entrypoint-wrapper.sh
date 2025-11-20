#!/bin/bash
set -euo pipefail

WP_PATH="/var/www/html"
CONTENT_FILE="/tmp/content.wpress"
MARKER="$WP_PATH/.wpress_imported"
DB_HOST="$WORDPRESS_DB_HOST"

echo "=== WordPress auto-install & .wpress import ==="

# Avvia WP core in modalità "setup"
docker-entrypoint.sh true

# Attendi DB disponibile
for i in {1..60}; do
  if wp db check --allow-root >/dev/null 2>&1; then
    echo "DB ok"
    break
  fi
  echo "DB not ready ($i/60)"
  sleep 2
  if [ $i -eq 60 ]; then
    echo "ERROR: DB non raggiungibile"
    exit 1
  fi
done

# Installa WordPress core
wp core install \
  --url="https://$DB_HOST" \
  --title="Dev WP" \
  --admin_user="admin" \
  --admin_password="admin" \
  --admin_email="admin@example.com" \
  --skip-email \
  --allow-root


# Importa contenuto .wpress
if [ -f "$CONTENT_FILE" ]; then
  wp plugin install all-in-one-wp-migration --activate --allow-root
  wp ai1wm import "$CONTENT_FILE" --yes --allow-root
  echo "Import completato"
  touch "$MARKER"
  rm -f "$CONTENT_FILE"
else
  echo "Nessun .wpress trovato, skip import"
fi

# Avvia Apache
exec docker-entrypoint.sh "$@"
