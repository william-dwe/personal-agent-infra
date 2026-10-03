#!/usr/bin/env bash
# Copy the dotenvx private key directly from a trusted old VPS. Never prints key material.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
key_dir=/etc/dotenvx
key=$key_dir/personal-agent-infra.env.keys
source_key=/etc/dotenvx/personal-agent-infra.env.keys

usage() {
  echo "Usage: $0 user@trusted-old-vps" >&2
  exit 2
}

[ $# -eq 1 ] || usage
source=$1
[[ -n $source && $source != -* && $source != *$'\n'* && $source != *$'\r'* && $source != *' '* ]] || usage
command -v ssh >/dev/null || { echo "SSH client missing." >&2; exit 1; }
command -v dotenvx >/dev/null || { echo "dotenvx CLI missing." >&2; exit 1; }
[ -f "$root/.env" ] && [ ! -L "$root/.env" ] || { echo "Encrypted infra .env missing." >&2; exit 1; }

identity=$("$root/scripts/dotenv-restore-ssh-key.sh" prepare)
sudo install -d -m 0700 -o root -g root "$key_dir"
tmp=$(sudo mktemp "$key_dir/.personal-agent-infra.env.keys.XXXXXX")
cleanup() { sudo rm -f "$tmp"; }
trap cleanup EXIT
sudo chmod 0600 "$tmp"

# StrictHostKeyChecking=ask requires explicit fingerprint acceptance for an unknown source host.
if ! ssh -i "$identity" -o IdentitiesOnly=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=ask -- "$source" "sudo -n /usr/bin/cat '$source_key'" | sudo tee "$tmp" >/dev/null; then
  echo "Key transfer failed. Verify SSH host fingerprint and source sudo -n access." >&2
  exit 1
fi

# Prove source key decrypts this repo's committed ciphertext before replacing the destination key.
if ! sudo dotenvx decrypt -f "$root/.env" -fk "$tmp" --stdout >/dev/null 2>&1; then
  echo "Transferred key cannot decrypt this infra .env; destination unchanged." >&2
  exit 1
fi
sudo chown root:root "$tmp"
sudo chmod 0600 "$tmp"
sudo mv -f "$tmp" "$key"
trap - EXIT
echo "dotenvx private key restored."
