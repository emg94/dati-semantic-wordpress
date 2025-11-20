#!/bin/bash
set -euo pipefail

WP_PATH="/var/www/html"
CONTENT_FILE="/tmp/content.wpress"
MARKER="$WP_PATH/.wpress_imported"

echo "=== WordPress auto-install & .wpress import ==="

docker-entrypoint.sh true

echo "Waiting for DB..."
for i in {1..60}; do
  if wp db check --allow-root >/dev/null 2>&1; then
    echo "DB ok"
    break
  fi
  echo "DB not ready ($i/60)"
  sleep 2
  if [ $i -eq 60 ]; then
    echo "ERROR: DB not reachable"; exit 1
  fi
done

echo "Installing WordPress core..."
wp core install \
  --url="https://localhost" \
  --title="Dev WP" \
  --admin_user="admin" \
  --admin_password="admin" \
  --admin_email="admin@example.com" \
  --skip-email \
  --allow-root

echo "Importing content..."
if [ -f "$CONTENT_FILE" ]; then
  wp plugin install all-in-one-wp-migration --activate --allow-root
  wp ai1wm import "$CONTENT_FILE" --yes --allow-root
  echo "Import complete"
  touch "$MARKER"
  rm -f "$CONTENT_FILE"
else
  echo "No .wpress found"
fi

echo "Starting Apache..."
exec docker-entrypoint.sh "$@"
