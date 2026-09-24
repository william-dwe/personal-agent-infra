#!/usr/bin/env bash
set -euo pipefail

if command -v zsh &>/dev/null && [ -d "$HOME/.oh-my-zsh" ] && [ "$(getent passwd "$USER" | cut -d: -f7)" = "$(command -v zsh)" ]; then
  echo "==> Zsh + Oh My Zsh: already installed, skipping"
  exit 0
fi

echo "==> Installing Zsh + Oh My Zsh..."
command -v zsh &>/dev/null || sudo apt-get install -y zsh

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  # RUNZSH=no: don't drop into zsh mid-script. CHSH=no: we set the shell below.
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

sudo chsh -s "$(command -v zsh)" "$USER"
