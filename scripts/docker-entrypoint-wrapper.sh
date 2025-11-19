#!/bin/bash
set -euo pipefail

echo "Running import-content.sh (if .wpress exists)..."
/usr/local/bin/import-content.sh || true

echo "Starting official WordPress entrypoint..."
exec docker-entrypoint.sh "$@"
