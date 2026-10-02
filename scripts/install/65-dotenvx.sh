#!/usr/bin/env bash
set -euo pipefail

if command -v dotenvx >/dev/null; then
  echo "==> dotenvx CLI: already installed, skipping"
else
  echo "==> Installing dotenvx CLI..."
  curl -sfS https://dotenvx.sh | sudo sh
  dotenvx --version
fi

# Global (machine-level) git clean filter; blocks committing plaintext .env*, lets encrypted content through.
dotenvx protect >/dev/null
