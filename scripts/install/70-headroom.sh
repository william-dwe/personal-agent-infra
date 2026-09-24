#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

echo "==> Setting up Headroom compression service..."
# Desired state: no tailnet listener, no Docker host port, no proxy token.
# 9router calls http://headroom:8787/v1/compress without auth headers.
# Remove ONLY the obsolete Headroom forwarding rule; preserve other services.
if tailscale serve status | grep -qE ':8787([[:space:]]|$)'; then
  sudo tailscale serve --tcp=8787 off
fi

# Must reconcile Compose even when healthy: a previous install may expose :8787.
# sudo docker also works before the installer's docker-group re-login.
[ -r .env ] || { echo "Fill .env with NINEROUTER_* secrets first, then re-run." >&2; exit 1; }
sudo docker compose config --quiet
sudo docker compose up -d --wait --wait-timeout 120 headroom 9router
printf '%s\n' 'In 9router Token Saver, set Headroom URL to http://headroom:8787 and enable compression.'
