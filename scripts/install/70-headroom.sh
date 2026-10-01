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
ip=$(tailscale ip -4 2>/dev/null | head -n1)
[[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "Tailscale has no IPv4 address. Connect it, then re-run." >&2; exit 1; }
if grep -q '^TAILSCALE_IP=' .env; then sed -i "s/^TAILSCALE_IP=.*/TAILSCALE_IP=$ip/" .env; else printf '\nTAILSCALE_IP=%s\n' "$ip" >>.env; fi
host=$(tailscale status --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"].get("DNSName", "").rstrip("."))')
if [[ $host == *.ts.net ]]; then
  for key in BUTLER_ORIGIN BUTLER_WEB_ORIGIN; do
    value=https://$host:8444
    if grep -q "^$key=" .env; then sed -i "s|^$key=.*|$key=$value|" .env; else printf '\n%s=%s\n' "$key" "$value" >>.env; fi
  done
else
  echo "Tailscale MagicDNS name unavailable; Butler origins unchanged."
fi
sudo ln -sfn "$PWD/.env" /etc/personal-agent-infra.env
sudo install -d -m 0755 /usr/local/lib/personal-agent-infra
sudo ln -sfn "$PWD/scripts/butler-review-queue.sh" /usr/local/lib/personal-agent-infra/butler-review-queue.sh
sudo docker compose config --quiet
sudo docker compose up -d --wait --wait-timeout 120 headroom 9router
printf '%s\n' 'In 9router Token Saver, set Headroom URL to http://headroom:8787 and enable compression.'
