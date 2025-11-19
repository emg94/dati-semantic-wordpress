#!/bin/bash
set -euo pipefail

CONTENT_FILE="/tmp/content.wpress"
MARKER="/var/www/html/.wpress_imported"
WP_PATH="/var/www/html"

echo "Import script start..."

# 1) Se marker esiste -> skip
if [ -f "$MARKER" ]; then
  echo "Marker found ($MARKER). Import already performed. Skipping."
  exit 0
fi

# 2) Pulizia del WordPress precedente
if [ -d "$WP_PATH/wp-content" ]; then
  echo "Cleaning existing WordPress installation..."
  rm -rf "$WP_PATH"/*
fi

# 3) Aspetto il DB pronto
MAX_DB_WAIT=60
SLEEP_SEC=5
count=0
until wp db check --allow-root >/dev/null 2>&1; do
  count=$((count+1))
  if [ $count -ge $MAX_DB_WAIT ]; then
    echo "DB not reachable after $((count*SLEEP_SEC)) seconds. Exiting."
    exit 1
  fi
  sleep $SLEEP_SEC
done
echo "DB reachable."

# 4) Installazione WordPress se non installato
if ! wp core is-installed --allow-root >/dev/null 2>&1; then
  echo "Installing WordPress..."
  wp core install \
    --url="https://localhost" \
    --title="Dev WP" \
    --admin_user="admin" \
    --admin_password="admin" \
    --admin_email="admin@example.com" \
    --skip-email \
    --allow-root
fi

# 5) Importazione del .wpress se presente
if [ -f "$CONTENT_FILE" ]; then
  echo "Found content package: $CONTENT_FILE"
  wp plugin install all-in-one-wp-migration --activate --allow-root || true
  wp ai1wm import "$CONTENT_FILE" --allow-root || true
  touch "$MARKER"
  rm -f "$CONTENT_FILE"
  echo "Import completed, marker created."
else
  echo "No .wpress found at $CONTENT_FILE. Skipping import."
fi

echo "Import script end."
