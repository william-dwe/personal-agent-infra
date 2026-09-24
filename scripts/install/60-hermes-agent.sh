#!/usr/bin/env bash
set -euo pipefail

if sudo test -x /home/hermes/.local/bin/hermes; then
  echo "==> Hermes Agent: already installed, skipping"
  exit 0
fi

echo "==> Installing Hermes Agent for user 'hermes'..."
sudo -iu hermes bash -c 'curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash'
