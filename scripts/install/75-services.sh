#!/usr/bin/env bash
# Clone Butler and wiki checkouts under hermes. Never pulls existing checkouts.
set -euo pipefail

services=/home/hermes/services
butler=${BUTLER_REPO_URL:-https://github.com/william-dwe/butler.git}
wiki=${WIKI_REPO_URL:-https://github.com/william-dwe/second-brain-wiki.git}

clone() {
  local name=$1 url=$2 path=$services/$name
  if [ -e "$path" ]; then
    [ -d "$path/.git" ] || { echo "Refusing: $path exists but is not a Git checkout" >&2; return 1; }
    return
  fi
  echo "==> Cloning $name..."
  sudo install -d -m 0755 -o hermes -g hermes "$services"
  sudo -u hermes git clone "$url" "$path"
}

command -v git >/dev/null || { echo "Git missing; install it, then re-run." >&2; exit 1; }
if [ -d "$services/butler/.git" ] && [ -d "$services/second-brain-wiki/.git" ]; then
  echo "==> Services: already installed, skipping"
  exit 0
fi
clone butler "$butler"
clone second-brain-wiki "$wiki"
