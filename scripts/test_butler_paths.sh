#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
butler=$tmp/butler
wiki=$tmp/wiki
mkdir -p "$butler/.git" "$wiki/.git"
paths=$tmp/paths
printf 'BUTLER_DIR=%s\nWIKI_DIR=%s\n' "$butler" "$wiki" > "$paths"
sudo chown root:root "$paths"
sudo chmod 0644 "$paths"
mapfile -d '' -t found < <(PERSONAL_AGENT_INFRA_PATHS="$paths" "$root/scripts/butler-paths.sh")
[ "${found[0]}" = "$butler" ]
[ "${found[1]}" = "$wiki" ]
printf '%s\n' 'butler-paths.sh: ok'
