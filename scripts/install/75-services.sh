#!/usr/bin/env bash
# Clone Butler and wiki for hermes. Never pulls existing checkouts.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
paths=/etc/personal-agent-infra.paths
butler_url=${BUTLER_REPO_URL:-https://github.com/william-dwe/butler.git}
wiki_url=${WIKI_REPO_URL:-https://github.com/william-dwe/second-brain-wiki.git}
butler=${BUTLER_DIR:-/home/hermes/services/butler}
wiki=${WIKI_DIR:-/home/hermes/services/second-brain-wiki}

valid_path() { [[ $1 == /* && $1 != / && $1 != *$'\n'* && $1 != *=* ]]; }
write_paths() {
  local tmp
  valid_path "$butler" && valid_path "$wiki" || { echo "BUTLER_DIR and WIKI_DIR must be absolute paths." >&2; exit 1; }
  sudo install -d -m 0755 -o root -g root /etc
  tmp=$(sudo mktemp /etc/.personal-agent-infra.paths.XXXXXX)
  printf 'BUTLER_DIR=%s\nWIKI_DIR=%s\n' "$butler" "$wiki" | sudo tee "$tmp" >/dev/null
  sudo chown root:root "$tmp"
  sudo chmod 0644 "$tmp"
  sudo mv -f "$tmp" "$paths"
}

if [ -e "$paths" ] || [ -L "$paths" ]; then
  [ -f "$paths" ] && [ ! -L "$paths" ] || { echo "Invalid Butler path configuration: $paths" >&2; exit 1; }
  mapfile -d '' -t configured < <("$root/scripts/butler-paths.sh")
  [ "${#configured[@]}" -eq 2 ] || { echo "Invalid Butler path configuration: $paths" >&2; exit 1; }
  butler=${configured[0]}
  wiki=${configured[1]}
else
  write_paths
fi

clone() {
  local label=$1 url=$2 path=$3
  if [ -e "$path" ]; then
    [ -d "$path/.git" ] || { echo "Refusing: $path exists but is not a Git checkout" >&2; return 1; }
    return
  fi
  echo "==> Cloning $label..."
  sudo install -d -m 0755 -o hermes -g hermes "$(dirname "$path")"
  sudo -u hermes git clone "$url" "$path"
}

command -v git >/dev/null || { echo "Git missing; install it, then re-run." >&2; exit 1; }
if [ -d "$butler/.git" ] && [ -d "$wiki/.git" ]; then
  echo "==> Services: already installed, skipping"
  exit 0
fi
clone Butler "$butler_url" "$butler"
clone second-brain-wiki "$wiki_url" "$wiki"
