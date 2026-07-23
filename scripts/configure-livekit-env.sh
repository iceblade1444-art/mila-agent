#!/usr/bin/env bash
set -euo pipefail

env_file="${1:-/opt/mila/backend/.env}"
if [[ ! -f "$env_file" ]]; then
  echo "MILA environment file not found: $env_file" >&2
  exit 1
fi

if grep -q '^LIVEKIT_API_KEY=' "$env_file"; then
  echo "LiveKit credentials already exist; no changes made."
  exit 0
fi

api_key="mila_$(openssl rand -hex 12)"
api_secret="$(openssl rand -hex 32)"

umask 077
{
  printf '\nLIVEKIT_URL=wss://agent.milanapremium.uz\n'
  printf 'LIVEKIT_INTERNAL_URL=ws://livekit:7880\n'
  printf 'LIVEKIT_API_KEY=%s\n' "$api_key"
  printf 'LIVEKIT_API_SECRET=%s\n' "$api_secret"
  printf 'LIVEKIT_KEYS="%s: %s"\n' "$api_key" "$api_secret"
} >> "$env_file"

chmod 600 "$env_file"
echo "LiveKit credentials created in $env_file."
