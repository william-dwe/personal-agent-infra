#!/usr/bin/env bash
# VPS control panel (whiptail TUI): guided new-VPS setup, install steps, dashboard user, logs.
# Usage: ./scripts/menu.sh
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
set -uo pipefail
cd "$(dirname "$0")/.."
if ! command -v whiptail &>/dev/null; then
  echo "Installing whiptail for VPS setup..."
  sudo apt-get update && sudo apt-get install -y whiptail || { echo "whiptail install failed." >&2; exit 1; }
fi

TITLE="VPS control panel"
pause() { read -rp $'\nPress Enter to return to the menu...' _; }

status_text() {
  local user note="" unit active holder ip router headroom
  user=$(cat .dashboard-user 2>/dev/null) || { user=hermes; note=undeployed; }
  unit="hermes-dashboard@$user"
  active=$(systemctl list-units 'hermes-dashboard@*' --state=active --plain --no-legend | awk '{print $1}' | xargs)
  holder=$(ps -eo user=,args= | awk '/hermes dashboard/ && /9119/ && !/awk/ {print $1; exit}')
  ip=$(tailscale ip -4 2>/dev/null | head -1)
  # ponytail: no docker group yet (needs re-login after 10-docker) reads as "unknown"; sudo would prompt inside the TUI.
  router=$(docker inspect -f '{{.State.Status}}' 9router 2>/dev/null) || router="unknown (not created / no docker access)"
  headroom=$(docker inspect -f '{{.State.Status}}' headroom 2>/dev/null) || headroom="unknown (not created / no docker access)"

  # Session groups (id -Gn) vs. account groups (id -Gn $me): differ right after usermod, until re-login.
  local me groups relogin=""
  me=$(id -un)
  groups=$(id -Gn | tr ' ' '\n' | grep -xE 'sudo|docker|hermes' | xargs)
  id -Gn "$me" | grep -qw docker && ! id -Gn | grep -qw docker && relogin=" (re-login for docker)"

  section() { printf '[ %s ]\n' "$1"; }
  row() { printf '  %-17s%s\n' "$@"; }

  section "Session"
  row "Current User:"    "$me" \
      "Groups:"          "${groups:-none}$relogin" \
      "Connected From:"  "$([ -n "${SSH_CONNECTION:-}" ] && echo "ssh ${SSH_CONNECTION%% *}" || echo local)"
  section "Host"
  row "Hostname:"        "$(hostname) (up $(uptime -p | sed 's/^up //'))" \
      "Resources:"       "load $(cut -d' ' -f1 /proc/loadavg) | disk / $(df -h --output=pcent / | tail -1 | xargs) | mem $(free -h | awk '/^Mem/{print $3"/"$2}')"
  section "Tailscale"
  row "IP:"              "${ip:-not connected}"
  section "Hermes Dashboard"
  row "Configured User:" "$([ -n "$note" ] && echo "not deployed yet (default: $user)" || echo "$user")" \
      "Service Name:"    "$unit" \
      "URL:"             "http://${ip:-<no tailscale ip>}:9119"
  if [ -n "$holder" ] && [ -z "$active" ]; then
    row "[ ! ] Warning" "manual (non-systemd) run as $holder holds :9119;" "" "stop it before deploying."
  elif [ -n "$active" ] && [ "$active" != "$unit.service" ]; then
    row "[ ! ] Warning" "running $active differs from configured user;" "" "use \"Switch dashboard user\"."
  fi
  section "9router (docker)"
  row "Container:"       "$router" \
      "URL:"             "http://${ip:-<no tailscale ip>}:20128"
  section "Headroom (docker)"
  row "Container:"       "$headroom" \
      "URL:"             "http://headroom:8787 (Docker-internal only)"
}

pick_user() {
  local cur; cur=$(cat .dashboard-user 2>/dev/null || echo hermes)
  whiptail --title "$TITLE" --radiolist "Run the dashboard as (space to select):" 12 60 2 \
    hermes "dedicated non-root user" "$([ "$cur" = hermes ] && echo ON || echo OFF)" \
    ubuntu "admin user"              "$([ "$cur" = ubuntu ] && echo ON || echo OFF)" \
    3>&1 1>&2 2>&3
}

switch_user() {
  local user; user=$(pick_user) || return
  whiptail --title "$TITLE" --yesno "Switch dashboard to '$user'?\n\nThe dashboard restarts: open browser sessions (including an agent chat running inside it) will disconnect." 12 64 || return
  clear; ./scripts/deploy.sh "$user"; pause
}

dotenv_key_ready() {
  local key=/etc/dotenvx/personal-agent-infra.env.keys
  sudo test -f "$key" && sudo test ! -L "$key" && [ "$(sudo stat -c '%u:%g:%a' "$key" 2>/dev/null)" = 0:0:600 ]
}

restore_dotenv_key() {
  local choice source user
  choice=$(whiptail --title "$TITLE" --menu "Restore dotenvx private key" 15 76 4 \
    1 "Show one-time authorization command for old VPS" \
    2 "Copy directly from trusted old VPS over SSH" \
    3 "I restored it manually; recheck" \
    b "Cancel setup" 3>&1 1>&2 2>&3) || return 1
  case $choice in
    1)
      user=$(whiptail --title "$TITLE" --inputbox "Source SSH user on old VPS, for example ubuntu:" 10 70 3>&1 1>&2 2>&3) || return 1
      clear
      ./scripts/dotenv-restore-ssh-key.sh authorization "$user"
      pause
      restore_dotenv_key
      ;;
    2)
      source=$(whiptail --title "$TITLE" --inputbox \
        "Source SSH target, for example ubuntu@old-vps.\n\nRun 'Show one-time authorization command' there first. Unknown host fingerprints require explicit terminal acceptance. Key never appears in chat, Git, argv, or logs." \
        14 76 3>&1 1>&2 2>&3) || return 1
      clear
      ./scripts/dotenv-key-transfer.sh "$source"; echo "exit: $?"; pause
      ;;
    3) ;;
    b) return 1 ;;
  esac
}

guided_vps_setup() {
  whiptail --title "$TITLE" --yesno \
    "New VPS setup runs package updates, Tailscale login, Docker, Hermes, dotenvx, firewall, Butler/wiki clones, and service startup.\n\nYou must securely restore dotenvx private key before services start.\n\nContinue?" \
    16 76 || return

  clear
  if ! ./scripts/init.sh 00-system 10-docker 20-tailscale 30-zsh 40-firewall 50-hermes-user 60-hermes-agent 65-dotenvx; then
    echo "Bootstrap prerequisites failed. Fix failed step, then run guided setup again."
    pause
    return
  fi
  sudo install -d -m 0700 /etc/dotenvx


  while ! dotenv_key_ready; do
    if ! restore_dotenv_key; then
      echo "dotenvx private key not restored; services were not started."
      pause
      return
    fi
    if ! dotenv_key_ready; then
      whiptail --title "$TITLE" --msgbox \
        "dotenvx private key missing or invalid.\n\nRequired path: /etc/dotenvx/personal-agent-infra.env.keys\nRequired owner and mode: root:root, 0600.\n\nTransfer failure leaves any existing destination key unchanged." \
        14 76
    fi
  done

  clear
  if ! ./scripts/init.sh; then
    echo "Full bootstrap failed. Fix failed step, then re-run guided setup; finished steps skip."
    pause
    return
  fi

  local user; user=$(pick_user) || return
  whiptail --title "$TITLE" --yesno \
    "Start Hermes dashboard and gateway as '$user'?\n\nThis restarts dashboard service and disconnects open dashboard sessions." \
    12 76 || return
  clear
  ./scripts/deploy.sh "$user" || { pause; return; }
  sudo ./scripts/check-headroom.sh
  pause
}

pick_steps() {
  local args=() f desc
  for f in scripts/install/[0-9][0-9]-*.sh; do
    desc=$(grep -oP '==> \K[^."]+' "$f" | tail -1)   # last ==> line: "Installing Docker", ...
    args+=("$(basename "$f" .sh)" "${desc:-step}" ON)
  done
  whiptail --title "$TITLE" --separate-output --checklist \
    "Install steps (already-installed ones are skipped):" 18 60 10 "${args[@]}" 3>&1 1>&2 2>&3
}

run_install() {
  local steps; steps=$(pick_steps) || return
  [ -n "$steps" ] || return
  clear
  # shellcheck disable=SC2086  # one step name per line -> separate args
  ./scripts/init.sh $steps
  pause
}

toggle_hermes_sudo() {
  local f=/etc/sudoers.d/90-hermes-agent action msg
  clear; echo "Checking hermes sudo grant (your sudo password may be asked)..."
  if sudo test -f "$f"; then
    action=off; msg="REVOKE hermes passwordless sudo?\n\nRemoves $f. hermes' sudo group membership and Docker access are NOT changed."
  else
    action=on;  msg="GRANT hermes passwordless sudo?\n\nhermes (and every agent running as hermes) gets unrestricted root without a password."
  fi
  whiptail --title "$TITLE" --yesno "$msg" 12 70 || return
  clear; sudo ./scripts/hermes-sudo.sh "$action"; pause
}

dashboard_menu() {
  local choice
  choice=$(whiptail --title "$TITLE" --menu "Dashboard controls" 14 64 3 \
    1 "Switch dashboard user" \
    2 "Restart dashboard" \
    3 "Follow dashboard logs" \
    b "Back" 3>&1 1>&2 2>&3) || return
  local user; user=$(cat .dashboard-user 2>/dev/null || echo hermes)
  case $choice in
    1) switch_user ;;
    2) clear; sudo systemctl restart "hermes-dashboard@$user" && echo restarted; pause ;;
    3) clear; journalctl -u "hermes-dashboard@$user" -n 50 -f; pause ;;
  esac
}

install_menu() {
  local choice
  choice=$(whiptail --title "$TITLE" --menu "Install and repair" 12 64 2 \
    1 "Run selected install steps" \
    2 "Run all install steps" \
    b "Back" 3>&1 1>&2 2>&3) || return
  case $choice in
    1) run_install ;;
    2) clear; ./scripts/init.sh; pause ;;
  esac
}

while true; do
  status=$(status_text)
  # ponytail: capped at terminal height; on very short terminals the header gets clipped.
  h=$(( $(wc -l <<<"$status") + 12 )); rows=$(tput lines 2>/dev/null || echo 24); (( h > rows )) && h=$rows
  choice=$(whiptail --title "$TITLE" --menu "$status" "$h" 76 6 \
    1 "Status" \
    2 "Set up new VPS" \
    3 "Dashboard controls" \
    4 "Install or repair" \
    5 "Hermes sudo access" \
    q "Quit" 3>&1 1>&2 2>&3) || break
  user=$(cat .dashboard-user 2>/dev/null || echo hermes)
  case $choice in
    1) clear; systemctl --no-pager status "hermes-dashboard@$user"; pause ;;
    2) guided_vps_setup ;;
    3) dashboard_menu ;;
    4) install_menu ;;
    5) toggle_hermes_sudo ;;
    q) break ;;
  esac
done
clear
