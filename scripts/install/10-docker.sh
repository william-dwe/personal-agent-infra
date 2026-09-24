#!/usr/bin/env bash
set -euo pipefail

if command -v docker &>/dev/null; then
  echo "==> Docker: already installed, skipping"
  exit 0
fi

echo "==> Installing Docker..."
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"   # takes effect on next login
