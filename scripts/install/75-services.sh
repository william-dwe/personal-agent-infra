#!/usr/bin/env bash
# Clone application repositories under hermes, then run Butler's own `make install`.
# Toolchain checks (Go, Node) live in the Butler repo, not here. Never pulls existing checkouts.
set -euo pipefail

services=/home/hermes/services
butler=${BUTLER_REPO_URL:-https://github.com/william-dwe/butler.git}
wiki=${WIKI_REPO_URL:-https://github.com/william-dwe/second-brain-wiki.git}

clone() {
  local name=$1 url=$2 path=$services/$name
  if [ -e "$path" ]; then
    [ -d "$path/.git" ] || { echo "Refusing: $path exists but is not a Git checkout" >&2; return 1; }
    echo "==> $name: already cloned, skipping"
    return
  fi
  echo "==> Cloning $name..."
  sudo install -d -m 0755 -o hermes -g hermes "$services"
  sudo -u hermes git clone "$url" "$path"
}

command -v git >/dev/null || { echo "Git missing; install it, then re-run." >&2; exit 1; }
clone butler "$butler"
clone second-brain-wiki "$wiki"

# ponytail: "built" = backend binary + Next build ID exist; rebuild after updates with make install.
if sudo test -x "$services/butler/backend/bin/butler" && sudo test -f "$services/butler/frontend/.next/BUILD_ID"; then
  echo "==> Butler build: already installed, skipping"
else
  echo "==> Building Butler..."
  sudo -u hermes -H make -C "$services/butler" install
fi
