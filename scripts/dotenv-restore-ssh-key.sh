#!/usr/bin/env bash
# Create one local SSH key restricted on the source VPS to read only the dotenvx private key.
set -euo pipefail

ssh_dir=$HOME/.ssh
key=${DOTENVX_RESTORE_SSH_KEY:-$ssh_dir/id_ed25519_dotenvx_restore}
pub=$key.pub
source_key=/etc/dotenvx/personal-agent-infra.env.keys

usage() {
  echo "Usage: $0 {prepare|authorization SOURCE_USER}" >&2
  exit 2
}

valid_user() { [[ $1 =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; }
valid_key() {
  [ -f "$key" ] && [ ! -L "$key" ] && [ "$(stat -c '%u:%a' "$key")" = "$(id -u):600" ] &&
    [ -f "$pub" ] && [ ! -L "$pub" ]
}

prepare() {
  command -v ssh-keygen >/dev/null || { echo "OpenSSH client missing." >&2; exit 1; }
  if valid_key; then
    echo "$key"
    return
  fi
  [ ! -e "$key" ] && [ ! -L "$key" ] && [ ! -e "$pub" ] && [ ! -L "$pub" ] || {
    echo "Invalid existing restore SSH key: $key" >&2
    exit 1
  }
  umask 077
  install -d -m 0700 "$ssh_dir"
  ssh-keygen -q -t ed25519 -N '' -C dotenvx-restore -f "$key"
  valid_key || { echo "Failed to create restore SSH key." >&2; exit 1; }
  echo "$key"
}

authorization() {
  local user public
  user=$1
  valid_user "$user" || usage
  prepare >/dev/null
  public=$(<"$pub")
  printf '%s\n' "Run these commands in an authenticated console on old VPS as $user:"
  printf '%s\n' "sudo install -d -m 0700 \"\$HOME/.ssh\""
  printf '%s\n' "printf '%s\\n' 'restrict,command=\"sudo -n /usr/bin/cat $source_key\" $public dotenvx-restore' >> \"\$HOME/.ssh/authorized_keys\""
  printf '%s\n' "chmod 600 \"\$HOME/.ssh/authorized_keys\""
  printf '%s\n' "printf '%s\\n' '$user ALL=(root) NOPASSWD: /usr/bin/cat $source_key' | sudo tee /etc/sudoers.d/90-dotenvx-key-restore >/dev/null"
  printf '%s\n' "sudo chmod 440 /etc/sudoers.d/90-dotenvx-key-restore && sudo visudo -cf /etc/sudoers.d/90-dotenvx-key-restore"
  printf '%s\n' "After a successful transfer, remove that authorized_keys line and sudoers file from old VPS."
}

[ $# -ge 1 ] || usage
case $1 in
  prepare) [ $# -eq 1 ] || usage; prepare ;;
  authorization) [ $# -eq 2 ] || usage; authorization "$2" ;;
  *) usage ;;
esac
