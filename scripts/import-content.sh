#!/bin/bash
set -euo pipefail

CONTENT_FILE="/tmp/content.wpress"
MARKER="/var/www/html/.wpress_imported"
WP_PATH="/var/www/html"

echo "Import script start..."

# -------------------------------------------------------
# 1) Skip se import già fatto
# -------------------------------------------------------
if [ -f "$MARKER" ]; then
  echo "Marker found ($MARKER). Import already performed. Skipping."
  exit 0
fi

# -------------------------------------------------------
# 2) Pulizia WordPress solo se WP non è valido
# -------------------------------------------------------
if [ ! -f "$WP_PATH/wp-config.php" ]; then
  echo "Cleaning existing WordPress installation (fresh install)..."
  rm -rf "$WP_PATH"/*
fi

# -------------------------------------------------------
# 3) Crea wp-config.php se manca
# -------------------------------------------------------
if [ ! -f "$WP_PATH/wp-config.php" ]; then
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
# 4) aspettava il DB solo se serve davvero
# -------------------------------------------------------
echo "Waiting for database to become reachable..."
MAX_RETRIES=30
SLEEP=3
for i in $(seq 1 $MAX_RETRIES); do
  if wp db check --allow-root >/dev/null 2>&1; then
    echo "DB reachable."
    break
  fi
  echo "DB not ready yet... retry $i/$MAX_RETRIES"
  sleep $SLEEP
done

if ! wp db check --allow-root >/dev/null 2>&1; then
  echo "ERROR: DB not reachable after $((MAX_RETRIES * SLEEP)) seconds."
  exit 1
fi

# -------------------------------------------------------
# 5) Installazione WordPress solo se non installato
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

