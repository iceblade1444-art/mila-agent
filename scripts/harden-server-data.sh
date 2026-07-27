#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/opt/mila}"

if [ ! -d "$ROOT" ]; then
  echo "MILA deployment directory not found: $ROOT" >&2
  exit 1
fi

chmod 700 "$ROOT"

for directory in "$ROOT/backups" "$ROOT/backend/data"; do
  if [ -d "$directory" ]; then
    find "$directory" -type d -exec chmod 700 {} +
    find "$directory" -type f -exec chmod 600 {} +
  fi
done

find "$ROOT" -maxdepth 2 -type f \
  \( -name '.env' -o -name '.env.before-*' -o -name '*.db' -o -name '*.db-wal' -o -name '*.db-shm' \) \
  -exec chmod 600 {} +

echo "MILA runtime data permissions hardened under $ROOT"
