#!/usr/bin/env bash
set -euo pipefail

if sudo ufw status 2>/dev/null | grep -q "Status: active" && sudo ufw status | grep -q tailscale0; then
  echo "==> Firewall (UFW): already installed, skipping"
  exit 0
fi

echo "==> Locking down firewall (UFW)..."
command -v ufw &>/dev/null || sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on tailscale0
sudo ufw allow 22/tcp
sudo ufw --force enable
