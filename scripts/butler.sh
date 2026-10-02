#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
butler=/home/hermes/services/butler
env=/etc/personal-agent-infra.env
usage() {
  echo "Usage: $0 {up|restart|down|status|logs}" >&2
  exit 2
}

[ $# -eq 1 ] || usage
case $1 in up|restart|down|status|logs) ;; *) usage ;; esac
[ "$root" = /home/ubuntu/services/personal-agent-infra ] && [ -d "$root/.git" ] || { echo "Missing infra checkout: /home/ubuntu/services/personal-agent-infra" >&2; exit 1; }
[ -d "$butler/.git" ] || { echo "Missing Butler checkout: $butler" >&2; exit 1; }
sudo test -f "$env" && ! sudo test -L "$env" || { echo "Missing environment file: $env" >&2; exit 1; }

compose=(sudo docker compose --project-directory "$butler" -f "$butler/compose.yml" --env-file "$env")

migrate_legacy_units() {
  local unit link legacy=0
  for unit in butler-backend.service butler-frontend.service; do
    link=/etc/systemd/system/$unit
    if [ -e "$link" ] || [ -L "$link" ] || [ -e "/etc/systemd/system/multi-user.target.wants/$unit" ] || [ -L "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
      sudo systemctl stop "$unit" || true
      sudo rm -f "$link" /etc/systemd/system/*.wants/$unit
      legacy=1
    fi
  done
  [ "$legacy" -eq 1 ] || return 0
  sudo rm -f /etc/systemd/system/butler-backend.service.d/9router.conf
  sudo rmdir /etc/systemd/system/butler-backend.service.d 2>/dev/null || true
  sudo systemctl daemon-reload
}
prepare_data_access() {
  sudo setfacl -Rm u:root:rwX /var/lib/butler
}


export_cli() (
  set -e
  local tmp= created=0 container
  cleanup() {
    [ -z "$tmp" ] || sudo rm -f "$tmp"
    [ "$created" -eq 0 ] || "${compose[@]}" rm -f backend >/dev/null || true
  }
  trap cleanup EXIT

  sudo install -d -m 0755 -o hermes -g hermes "$butler/backend/bin"
  tmp=$(sudo mktemp "$butler/backend/bin/.butler.XXXXXX")
  "${compose[@]}" create backend
  created=1
  container=$("${compose[@]}" ps --all --quiet backend)
  [ -n "$container" ] || { echo "Butler backend export container missing" >&2; exit 1; }
  sudo docker cp "$container:/usr/local/bin/butler" "$tmp"
  sudo chown hermes:hermes "$tmp"
  sudo chmod 0755 "$tmp"
  sudo mv -f "$tmp" "$butler/backend/bin/butler"
  tmp=
)

case $1 in
  up)
    prepare_data_access
    migrate_legacy_units
    "${compose[@]}" build
    export_cli
    "${compose[@]}" up -d --wait
    ;;
  restart) "${compose[@]}" restart ;;
  down) "${compose[@]}" down ;;
  status) "${compose[@]}" ps ;;
  logs) "${compose[@]}" logs ;;
esac
