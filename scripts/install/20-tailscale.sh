#!/usr/bin/env bash
set -euo pipefail

if command -v tailscale &>/dev/null && tailscale status &>/dev/null; then
  echo "==> Tailscale: already installed, skipping"
  exit 0
fi

echo "==> Installing Tailscale..."
command -v tailscale &>/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up                 # interactive: prints a login URL
