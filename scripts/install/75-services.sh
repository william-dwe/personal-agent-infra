#!/usr/bin/env bash
# Clone Butler and wiki for hermes. Never pulls existing checkouts.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
paths=/etc/personal-agent-infra.paths
butler_url=${BUTLER_REPO_URL:-git@github.com:william-dwe/butler.git}
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

# Pinned, not scanned: GitHub's own published ed25519 host key.
# Fingerprint SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
github_known_hosts_line='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
trust_github_host_key() {
  local hermes_known_hosts=/home/hermes/.ssh/known_hosts
  sudo -u hermes grep -qF "$github_known_hosts_line" "$hermes_known_hosts" 2>/dev/null && return 0
  echo "==> Trusting github.com SSH host key for hermes (pinned, not scanned)..."
  sudo install -d -m 0700 -o hermes -g hermes /home/hermes/.ssh
  printf '%s\n' "$github_known_hosts_line" | sudo -u hermes tee -a "$hermes_known_hosts" >/dev/null
}

# $butler and $wiki live under /home/hermes (0750/0770, hermes:hermes), unreadable
# to the invoking (non-hermes) user. Every existence/type check below must run
# as root or hermes; a plain `[ -e ... ]` here silently returns false on
# permission-denied, indistinguishable from "doesn't exist" -> re-clone attempt
# -> git refuses on the real leftover dir, even though the dir already existed.
clone() {
  local label=$1 url=$2 path=$3
  if sudo test -e "$path"; then
    sudo test -d "$path/.git" || { echo "Refusing: $path exists but is not a Git checkout" >&2; return 1; }
    return
  fi
  echo "==> Cloning $label..."
  sudo install -d -m 0755 -o hermes -g hermes "$(dirname "$path")"
  [[ $url == git@* ]] && trust_github_host_key
  sudo -u hermes git clone "$url" "$path"
}

command -v git >/dev/null || { echo "Git missing; install it, then re-run." >&2; exit 1; }
if sudo test -d "$butler/.git" && sudo test -d "$wiki/.git"; then
  echo "==> Services: already installed, skipping"
  exit 0
fi
clone Butler "$butler_url" "$butler"
clone second-brain-wiki "$wiki_url" "$wiki"
