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
sudo "$PWD/scripts/dotenv-env.sh" render
sudo test -f /etc/personal-agent-infra.env && ! sudo test -L /etc/personal-agent-infra.env || { echo "Rendered environment file missing." >&2; exit 1; }
sudo install -d -m 0755 /usr/local/lib/personal-agent-infra
sudo ln -sfn "$PWD/scripts/butler-review-queue.sh" /usr/local/lib/personal-agent-infra/butler-review-queue.sh
compose=(sudo docker compose --project-directory "$PWD" --env-file /etc/personal-agent-infra.env)
"${compose[@]}" config --quiet
"${compose[@]}" up -d --wait --wait-timeout 120 headroom 9router
printf '%s\n' 'In 9router Token Saver, set Headroom URL to http://headroom:8787 and enable compression.'
