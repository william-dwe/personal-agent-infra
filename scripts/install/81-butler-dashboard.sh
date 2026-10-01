#!/usr/bin/env bash
# Butler dashboard wiki link and persistent Tailscale Serve rule. Does not start services.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
services=/home/hermes/services
butler=$services/butler
wiki=$services/second-brain-wiki
data=/var/lib/butler
link=$data/wiki
[ -d "$butler/.git" ] && [ -d "$wiki/.git" ] || { echo "Run install step 75-services first." >&2; exit 1; }
if [ -e "$link" ] || [ -L "$link" ]; then
  if [ -L "$link" ] && [ "$(readlink -f "$link")" = "$wiki" ]; then
    echo "==> Butler wiki link: already installed, skipping"
  elif [ -L "$link" ]; then
    sudo -u hermes ln -sfnT "$wiki" "$link"
  else
    echo "Refusing: $link exists and is not a symlink" >&2
    exit 1
  fi
else
  sudo -u hermes ln -sfnT "$wiki" "$link"
fi

# Stable system paths avoid checkout paths in unit files.
[ -r "$root/.env" ] && sudo ln -sfn "$root/.env" /etc/personal-agent-infra.env
sudo install -d -m 0755 /usr/local/lib/personal-agent-infra
sudo ln -sfn "$root/scripts/butler-review-queue.sh" /usr/local/lib/personal-agent-infra/butler-review-queue.sh

if tailscale serve status 2>/dev/null | grep -Fq ':8444' && tailscale serve status 2>/dev/null | grep -Fq 'http://127.0.0.1:3100'; then
  echo "==> Butler Tailscale Serve: already installed, skipping"
else
  sudo tailscale serve --bg --https=8444 http://127.0.0.1:3100
fi

cat <<EOF
Next steps after approved cutover:
  sudo systemctl link $root/systemd/butler-backend.service
  sudo systemctl link $root/systemd/butler-frontend.service
  sudo systemctl enable --now butler-backend butler-frontend
EOF
