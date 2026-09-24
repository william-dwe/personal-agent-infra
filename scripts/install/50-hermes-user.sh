#!/usr/bin/env bash
set -euo pipefail

if id hermes &>/dev/null && sudo test -s /home/hermes/.ssh/authorized_keys; then
  echo "==> 'hermes' user: already installed, skipping"
  exit 0
fi

echo "==> Creating non-root 'hermes' user..."
if ! id hermes &>/dev/null; then
  sudo adduser --disabled-password --gecos "" hermes
  sudo usermod -aG sudo hermes
fi

# Copy SSH keys so you can log in as hermes directly.
sudo mkdir -p /home/hermes/.ssh
sudo cp -r "$HOME/.ssh/." /home/hermes/.ssh/
sudo chown -R hermes:hermes /home/hermes/.ssh
sudo chmod 700 /home/hermes/.ssh
