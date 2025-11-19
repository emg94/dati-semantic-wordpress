#!/bin/bash
set -euo pipefail

CONTENT_FILE="/tmp/content.wpress"
MARKER="/var/www/html/.wpress_imported"
WP_PATH="/var/www/html"
WP_LOAD="$WP_PATH/wp-load.php"

echo "Import script start..."

# -------------------------------------------------------
# 0) Skip se import già fatto
# -------------------------------------------------------
if [ -f "$MARKER" ]; then
  echo "Marker found ($MARKER). Import already performed. Skipping."
  exit 0
fi

# -------------------------------------------------------
# 1) Attende che i file core di WordPress siano presenti
# -------------------------------------------------------
MAX_WAIT=60   # secondi massimi di attesa
SLEEP=1
n=0
echo "Waiting up to $MAX_WAIT seconds for WordPress core files..."
while [ ! -f "$WP_LOAD" ] && [ "$n" -lt "$MAX_WAIT" ]; do
  sleep $SLEEP
  n=$((n + SLEEP))
done

if [ ! -f "$WP_LOAD" ]; then
  echo "Warning: WordPress core files not found at $WP_PATH after $MAX_WAIT seconds."
  echo "Continuing anyway (some operations may fail)."
fi

# -------------------------------------------------------
# 2) Pulizia WordPress solo se WP non è valido
# -------------------------------------------------------
if [ ! -f "$WP_PATH/wp-config.php" ]; then
  echo "Cleaning existing WordPress installation (fresh install)..."
  rm -rf "$WP_PATH"/* || true
fi

# -------------------------------------------------------
# 3) Crea wp-config.php se manca (solo se wp-cli disponibile e core presente)
# -------------------------------------------------------
if [ ! -f "$WP_PATH/wp-config.php" ] && command -v wp >/dev/null 2>&1 && [ -f "$WP_LOAD" ]; then
  echo "Generating wp-config.php..."
  wp config create \
    --dbname="$WORDPRESS_DB_NAME" \
    --dbuser="$WORDPRESS_DB_USER" \
    --dbpass="$WORDPRESS_DB_PASSWORD" \
    --dbhost="$WORDPRESS_DB_HOST" \
    --skip-check \
    --allow-root
fi

# -------------------------------------------------------
# 4) Attendere DB se necessario
# -------------------------------------------------------
echo "Checking database connectivity..."
MAX_RETRIES=30
SLEEP_DB=3
for i in $(seq 1 $MAX_RETRIES); do
  if wp db check --allow-root >/dev/null 2>&1; then
    echo "DB reachable."
    break
  fi
  echo "DB not ready yet... retry $i/$MAX_RETRIES"
  sleep $SLEEP_DB
done

if ! wp db check --allow-root >/dev/null 2>&1; then
  echo "ERROR: DB not reachable after $((MAX_RETRIES * SLEEP_DB)) seconds."
  exit 1
fi

# -------------------------------------------------------
# 5) Installazione WordPress core se non presente
# -------------------------------------------------------
if ! wp core is-installed --allow-root >/dev/null 2>&1; then
  echo "Installing WordPress core..."
  wp core install \
    --url="https://localhost" \
    --title="Dev WP" \
    --admin_user="admin" \
    --admin_password="admin" \
    --admin_email="admin@example.com" \
    --skip-email \
    --allow-root
fi

# -------------------------------------------------------
# 6) Import del file .wpress
# -------------------------------------------------------
if [ -f "$CONTENT_FILE" ]; then
  echo "Importing $CONTENT_FILE..."
  wp plugin install all-in-one-wp-migration --activate --allow-root
  wp ai1wm import "$CONTENT_FILE" --allow-root
  touch "$MARKER"
  rm -f "$CONTENT_FILE"
  echo "Import completed."
else
  echo "No .wpress found, skipping import."
fi

echo "Import script end."
