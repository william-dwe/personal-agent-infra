#!/usr/bin/env bash
# Shared Butler task-tracker data: hermes (CLI) and ubuntu (Telegram gateway) both read and write.
# Named-user ACLs instead of a new group: no group membership change, so no re-login or gateway restart.
set -euo pipefail
dir=/var/lib/butler

if getfacl -p "$dir" 2>/dev/null | grep -qx 'default:user:ubuntu:rwx'; then
  echo "==> Butler data dir: already installed, skipping"
  exit 0
fi

echo "==> Creating shared Butler data dir $dir..."
command -v setfacl >/dev/null || sudo apt-get install -y acl
sudo install -d -m 0770 -o hermes -g hermes "$dir"
# Defaults make new files/subdirs rw for both users whatever their umask; tasks.py creates the DB 0660.
# ponytail: existing contents are not re-ACLed; add `setfacl -R` if files were copied in by hand.
sudo setfacl -m u:ubuntu:rwx,d:u:hermes:rwx,d:u:ubuntu:rwx,d:g::---,d:o::--- "$dir"
