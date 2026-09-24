#!/usr/bin/env bash
set -e

echo "==> Updating System Packages..."
sudo apt-get update && sudo apt-get upgrade -y

echo "==> Installing Docker..."
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker $USER
fi

echo "==> Installing Tailscale..."
if ! command -v tailscale &> /dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
  sudo tailscale up
fi

echo "==> Installing Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  # RUNZSH=no prevents it from launching a zsh session mid-script
  # CHSH=no prevents it from interactively asking to change default shell
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo "==> Changing default shell to Zsh..."
if [ "$SHELL" != "$(which zsh)" ]; then
  sudo chsh -s $(which zsh) $USER
fi

echo "==> Locking Down Firewall (UFW)..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on tailscale0
sudo ufw allow 22/tcp
sudo ufw --force enable

echo "==> Setup finished!"
echo "Now copy your secrets into .env and run: docker compose up -d"
