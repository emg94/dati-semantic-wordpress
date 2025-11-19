#!/bin/bash
set -euo pipefail

# -------------------------------------------------------
# 1) Esegui l'import dei contenuti (.wpress) se presente
#    PRIMA di inizializzare WordPress
# -------------------------------------------------------
echo "Running import-content.sh (if .wpress exists)..."
/usr/local/bin/import-content.sh || echo "Import script completed with status: $?"

# -------------------------------------------------------
# 2) Avvia il normale entrypoint di WordPress
# -------------------------------------------------------
echo "Starting official WordPress entrypoint..."
exec docker-entrypoint.sh "$@"
