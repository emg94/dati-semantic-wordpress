#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# 1) Esegui l'entrypoint ufficiale per inizializzare WP core
#    senza avviare Apache (docker-entrypoint.sh true)
# -------------------------------------------------------
echo "Initializing WordPress core files..."
docker-entrypoint.sh true

# -------------------------------------------------------
# 2) Esegui l'import dei contenuti (.wpress) se presente
# -------------------------------------------------------
echo "Running import-content.sh (if .wpress exists)..."
/usr/local/bin/import-content.sh || true

# -------------------------------------------------------
# 3) Avvia il normale entrypoint (in foreground)
# -------------------------------------------------------
echo "Starting official WordPress entrypoint..."
exec docker-entrypoint.sh "$@"
