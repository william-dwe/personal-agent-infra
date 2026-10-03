#!/usr/bin/env bash
# Butler dashboard prerequisites, persistent Tailscale Serve rule, and Compose activation.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
data=/var/lib/butler
link=$data/wiki
mapfile -d '' -t paths < <("$root/scripts/butler-paths.sh")
[ "${#paths[@]}" -eq 2 ] || { echo "Invalid Butler path configuration." >&2; exit 1; }
butler=${paths[0]}
wiki=${paths[1]}
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
sudo "$root/scripts/dotenv-env.sh" render
sudo test -f /etc/personal-agent-infra.env && ! sudo test -L /etc/personal-agent-infra.env || { echo "Rendered environment file missing." >&2; exit 1; }
sudo install -d -m 0755 /usr/local/lib/personal-agent-infra
sudo ln -sfn "$root/scripts/butler-review-queue.sh" /usr/local/lib/personal-agent-infra/butler-review-queue.sh

if tailscale serve status 2>/dev/null | grep -Fq ':8444' && tailscale serve status 2>/dev/null | grep -Fq 'http://127.0.0.1:3100'; then
  echo "==> Butler Tailscale Serve: already installed, skipping"
else
  sudo tailscale serve --bg --https=8444 http://127.0.0.1:3100
fi

running=$(sudo env "WIKI_DIR=$wiki" docker compose --project-directory "$butler" -f "$butler/compose.yml" --env-file /etc/personal-agent-infra.env ps --status running --services)
if [ "$running" = $'backend\nfrontend' ]; then
  echo "==> Butler containers: already installed, skipping"
else
  "$root/scripts/butler.sh" up
fi
