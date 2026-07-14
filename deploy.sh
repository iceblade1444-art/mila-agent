#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f backend/.env ]; then
  echo "Missing backend/.env. Create it from backend/.env.example before deploy." >&2
  exit 1
fi

mkdir -p backend/data downloads

BIND_ADDRESS="$(sed -n 's/^BIND_ADDRESS=//p' backend/.env | tail -n1)"
HOST_PORT="$(sed -n 's/^HOST_PORT=//p' backend/.env | tail -n1)"
BIND_ADDRESS="${BIND_ADDRESS:-127.0.0.1}"
HOST_PORT="${HOST_PORT:-8791}"
export BIND_ADDRESS HOST_PORT
HEALTH_HOST="$BIND_ADDRESS"
[ "$HEALTH_HOST" = "0.0.0.0" ] && HEALTH_HOST="127.0.0.1"

git pull --ff-only

if docker ps >/dev/null 2>&1; then
  DOCKER="docker"
else
  DOCKER="sudo docker"
fi

$DOCKER compose up -d --build

set +e
for attempt in {1..20}; do
  health_response="$(curl -fsS "http://${HEALTH_HOST}:${HOST_PORT}/health" 2>/dev/null)"
  health_status=$?
  if [ "$health_status" -eq 0 ]; then
    echo "$health_response"
    echo
    echo "MILA backend deployed."
    exit 0
  fi
  sleep 1
done
set -e

echo
echo "MILA backend did not become healthy in time." >&2
exit 1
