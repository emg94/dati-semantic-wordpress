#!/bin/bash
set -euo pipefail

CONTENT_FILE="/tmp/content.wpress"
MARKER="/var/www/html/.wpress_imported"
WP_PATH="/var/www/html"

echo "=== Import script start ==="

# Skip se import già fatto
if [ -f "$MARKER" ]; then
  echo "Marker found - import already performed. Skipping."
  exit 0
fi

# Verifica se il file .wpress esiste
if [ ! -f "$CONTENT_FILE" ]; then
  echo "No .wpress file found at $CONTENT_FILE, skipping import."
  exit 0
fi

echo "Found .wpress file: $CONTENT_FILE"

# Attendi che i file core di WordPress siano presenti (massimo 30 secondi)
echo "Waiting for WordPress core files..."
for i in {1..30}; do
  if [ -f "/var/www/html/wp-settings.php" ]; then
    echo "WordPress core files found"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "WordPress core files not found after 30 seconds, continuing anyway"
  fi
  sleep 1
done

# Verifica la connettività al database
echo "Checking database connectivity..."
for i in {1..30}; do
  if wp db check --allow-root >/dev/null 2>&1; then
    echo "Database is reachable"
    break
  fi
  echo "Database not ready... attempt $i/30"
  if [ $i -eq 30 ]; then
    echo "ERROR: Database not reachable after 30 seconds"
    exit 1
  fi
  sleep 2
done

# Importa il file .wpress
echo "Starting .wpress import..."
wp plugin install all-in-one-wp-migration --activate --allow-root
wp ai1wm import "$CONTENT_FILE" --allow-root

# Crea il marker e pulisci
touch "$MARKER"
rm -f "$CONTENT_FILE"
echo "Import completed successfully"

echo "=== Import script end ==="
