#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f backend/.env ]; then
  echo "Missing backend/.env. Create it from backend/.env.example before deploy." >&2
  exit 1
fi

mkdir -p backend/data downloads

git pull --ff-only

if docker ps >/dev/null 2>&1; then
  DOCKER="docker"
else
  DOCKER="sudo docker"
fi

$DOCKER compose up -d --build

curl -fsS http://127.0.0.1:8787/health
echo
echo "MILA backend deployed."
