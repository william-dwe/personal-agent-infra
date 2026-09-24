#!/usr/bin/env bash
set -euo pipefail

# ponytail: "installed" = apt lists refreshed in the last 24h. FORCE=1 to override.
stamp=/var/lib/apt/periodic/update-success-stamp
if [ -z "${FORCE:-}" ] && [ -n "$(find "$stamp" -mmin -1440 2>/dev/null)" ]; then
  echo "==> System packages: updated within 24h, skipping"
  exit 0
fi

echo "==> Updating system packages..."
sudo apt-get update
sudo apt-get upgrade -y
sudo touch "$stamp"
