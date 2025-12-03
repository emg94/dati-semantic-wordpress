#!/bin/bash
set -e

WP_PATH="/var/www/html"

echo "[entrypoint] Cleaning $WP_PATH before WordPress installation..."
rm -rf ${WP_PATH:?}/*

echo "[entrypoint] Handing off to original WordPress entrypoint..."
exec docker-entrypoint.sh "$@"
