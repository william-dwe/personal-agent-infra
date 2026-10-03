#!/usr/bin/env bash
# Zero-token gate: start a librarian run only when Butler has review packets waiting.
# Runs as hermes from butler-review-queue.timer. The token never appears in argv or logs.
set -euo pipefail
token_file=/home/hermes/.hermes/profiles/librarian/secrets/butler-librarian.token
script=$(readlink -f "$0")
root=$(cd "$(dirname "$script")/.." && pwd)
prompt=$root/scripts/butler-review-queue.prompt.md
base=http://127.0.0.1:8765/api/librarian/review-packets

exec 9>/var/lib/butler/review-queue.lock
flock -n 9 || { echo "previous run still active"; exit 0; }

pending=$(curl -fsS --max-time 10 -H @- "$base/pending-count" <<<"Authorization: Bearer $(<"$token_file")" |
  python3 -c 'import json,sys; print(int(json.load(sys.stdin)["pending"]))')

if [ "$pending" -eq 0 ]; then
  exit 0
fi
echo "pending=$pending; starting librarian"
exec /home/hermes/.local/bin/hermes -p librarian chat -Q --query-file "$prompt"
