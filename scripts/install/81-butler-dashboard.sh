#!/usr/bin/env bash
# Butler dashboard wiki link and persistent Tailscale Serve rule. Does not start services.
set -euo pipefail

data=/var/lib/butler
wiki=/home/hermes/services/second-brain-wiki
link=$data/wiki
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

if tailscale serve status 2>/dev/null | grep -Fq ':8444' && tailscale serve status 2>/dev/null | grep -Fq 'http://127.0.0.1:3100'; then
  echo "==> Butler Tailscale Serve: already installed, skipping"
else
  sudo tailscale serve --bg --https=8444 http://127.0.0.1:3100
fi

cat <<'EOF'
Next steps after approved cutover:
  sudo systemctl link /home/ubuntu/services/personal-agent-infra/systemd/butler-backend.service
  sudo systemctl link /home/ubuntu/services/personal-agent-infra/systemd/butler-frontend.service
  sudo systemctl enable --now butler-backend butler-frontend
EOF
