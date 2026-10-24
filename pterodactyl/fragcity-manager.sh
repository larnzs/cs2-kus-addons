#!/usr/bin/env bash
# FragCity Control Center: root-safe terminal management of the Pterodactyl timers.
set -o pipefail
REPO_ROOT="/opt/fragcity/cs2-kus-addons"
SELF_PATH="$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")"
STARTUP_SHA="$(sha256sum -- "$SELF_PATH" 2>/dev/null | awk '{print $1}')"

if [[ "$(id -u)" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || { echo "sudo is required."; read -r -p "Press Enter..."; exit 1; }
  exec sudo -E /bin/bash "$SELF_PATH" "$@"
fi

R='' G='' Y='' C='' B='' M='' D=''
if [[ -t 1 && -z "$NO_COLOR" && "$TERM" != dumb ]]; then
  R=$'\033[1;31m'; G=$'\033[1;32m'; Y=$'\033[1;33m'
  C=$'\033[1;36m'; B=$'\033[1;34m'; M=$'\033[1;35m'; D=$'\033[2m'; Z=$'\033[0m'
else Z=''; fi

a() { systemctl is-active "$1" 2>/dev/null || true; }
e() { systemctl is-enabled "$1" 2>/dev/null || true; }
sw() { case "$1" in active|activating|reloading|enabled|enabled-runtime|linked|linked-runtime|alias) printf '%bON%b' "$G" "$Z";; *) printf '%bOFF%b' "$R" "$Z";; esac; }
timerrow() {
  local title="$1" unit="$2" av ev
  av="$(a "$unit")"; ev="$(e "$unit")"
  printf '  %-29s active=' "$title"; sw "$av"; printf '  boot='; sw "$ev"; printf '  %b(%s / %s)%b\n' "$D" "$av" "$ev" "$Z"
}
pause() { printf '\n'; read -r -p 'Press Enter to return to the menu...'; }
reload_if_updated() {
  local now
  now="$(sha256sum -- "$SELF_PATH" 2>/dev/null | awk '{print $1}')"
  if [[ -n "$now" && "$now" != "$STARTUP_SHA" ]]; then
    clear 2>/dev/null || true
    printf '%bLIVE UPDATE DETECTED%b — loading the new manager...\n' "$G" "$Z"
    sleep 1
    exec /bin/bash "$SELF_PATH"
  fi
}
choice_read() {
  CHOICE=''
  while true; do
    if IFS= read -r -t 2 CHOICE; then
      reload_if_updated
      return 0
    fi
    reload_if_updated
  done
}
showstatus() {
  clear 2>/dev/null || true
  printf '%bFRAGCITY — SYSTEM STATUS%b\n\n' "$C" "$Z"
  timerrow 'Payload auto-sync' fragcity-addon-payload-sync.timer
  timerrow 'New-server provisioner' fragcity-addon-provision.timer
  printf '\n%bNext scheduled runs%b\n' "$M" "$Z"
  systemctl list-timers --all --no-pager fragcity-addon-payload-sync.timer fragcity-addon-provision.timer 2>&1
  printf '\n%bPublished payload%b\n' "$M" "$Z"
  cat /var/lib/pterodactyl/mounts/fragcity-addon-payload/CURRENT_COMMIT 2>/dev/null || echo 'Payload marker missing'
  printf '\n%bRepository head%b\n' "$M" "$Z"
  git -C "$REPO_ROOT" log -1 --format='%h %cs %s' 2>&1
  printf '\n%bProcessed server markers%b\n' "$M" "$Z"
  if [[ -d /var/lib/pterodactyl/fragcity-addon-provisioner/processed ]]; then
    find /var/lib/pterodactyl/fragcity-addon-provisioner/processed -maxdepth 1 -type f -name '*.json' | wc -l
  else echo 0; fi
  pause
}
runservice() {
  local unit="$1" title="$2" rc=0
  printf '\n%bRunning: %s%b\n' "$C" "$title" "$Z"
  systemctl start "$unit" || rc=$?
  if [[ "$rc" -eq 0 ]]; then printf '%bCompleted.%b\n' "$G" "$Z"; else printf '%bService returned an error (status %s).%b\n' "$R" "$rc" "$Z"; fi
  journalctl -u "$unit" -n 35 --no-pager -o short-iso 2>&1
  pause
}
toggle() {
  local unit="$1" title="$2" av ev ans
  av="$(a "$unit")"; ev="$(e "$unit")"
  case "$av:$ev" in
    active:*|*:enabled|*:enabled-runtime|*:linked|*:linked-runtime|*:alias)
      printf '\n%bTurn OFF %s?%b This disables it now and after reboot.\nType YES to confirm: ' "$Y" "$title" "$Z"
      read -r ans
      if [[ "$ans" == YES ]]; then
        if systemctl disable --now "$unit"; then printf '%b%s is OFF.%b\n' "$R" "$title" "$Z"; else printf '%bFailed; inspect systemctl status.%b\n' "$R" "$Z"; fi
      else echo 'Cancelled; no changes made.'; fi
      ;;
    *)
      if systemctl enable --now "$unit"; then printf '%b%s is ON and persistent across reboot.%b\n' "$G" "$title" "$Z"; else printf '%bFailed; inspect systemctl status.%b\n' "$R" "$Z"; fi
      ;;
  esac
  pause
}
recentlogs() {
  clear 2>/dev/null || true
  printf '%bPROVISIONER%b\n' "$M" "$Z"
  journalctl -u fragcity-addon-provision.service -n 35 --no-pager -o short-iso 2>&1
  printf '\n%bPAYLOAD SYNC%b\n' "$M" "$Z"
  journalctl -u fragcity-addon-payload-sync.service -n 35 --no-pager -o short-iso 2>&1
  pause
}
followlogs() {
  clear 2>/dev/null || true
  printf '%bFollowing both service logs — Ctrl+C returns to the menu.%b\n\n' "$C" "$Z"
  journalctl -f -u fragcity-addon-provision.service -u fragcity-addon-payload-sync.service -o short-iso
}
dashboard() {
  if [[ ! -r /usr/local/libexec/fragcity-status-dashboard.sh ]]; then
    printf '%bDashboard not installed.%b\n' "$R" "$Z"; pause; return
  fi
  printf '%bDashboard in this terminal — Ctrl+C returns to the manager.%b\n' "$C" "$Z"
  sleep 1
  bash /usr/local/libexec/fragcity-status-dashboard.sh
}
while true; do
  clear 2>/dev/null || true
  printf '%b╔══════════════════════════════════════════════════════════════════════════════╗%b\n' "$B" "$Z"
  printf '%b║%b  %bFRAGCITY CONTROL CENTER%b  %b| PTERODACTYL%b                                  %b║%b\n' "$B" "$Z" "$G" "$Z" "$C" "$Z" "$B" "$Z"
  printf '%b╚══════════════════════════════════════════════════════════════════════════════╝%b\n' "$B" "$Z"
  printf '  %bAuto-update: ON%b — checks for updated manager every 2 seconds\n' "$G" "$Z"
  printf '\n%b[TIMER SWITCHES]%b\n' "$C" "$Z"
  timerrow '1) Payload auto-sync' fragcity-addon-payload-sync.timer
  timerrow '2) New-server provisioner' fragcity-addon-provision.timer
  printf '\n%b[ACTIONS]%b\n' "$C" "$Z"
  printf '  %b3%b  Update from GitHub + publish payload/dashboard\n' "$G" "$Z"
  printf '  %b4%b  Run provisioner once (confirmed)\n' "$G" "$Z"
  printf '  %b5%b  Open live dashboard in this terminal\n' "$G" "$Z"
  printf '  %b6%b  Recent logs\n' "$G" "$Z"
  printf '  %b7%b  Follow live logs (Ctrl+C returns)\n' "$G" "$Z"
  printf '  %b8%b  Full system status\n' "$G" "$Z"
  printf '  %b0%b  Exit\n\nChoose 0–8, then press Enter: ' "$Y" "$Z"
  if ! choice_read; then continue; fi
  case "$CHOICE" in
    1) toggle fragcity-addon-payload-sync.timer 'Payload auto-sync timer' ;;
    2) printf '\nTurning OFF pauses future automatic provisioning; existing server mounts are not detached.\n'; toggle fragcity-addon-provision.timer 'New-server provisioner' ;;
    3) runservice fragcity-addon-payload-sync.service 'Update from GitHub and publish latest payload/dashboard' ;;
    4)
      printf '\nProvisioning may attach the Mount and change Startup for eligible stopped servers.\nType YES to run one pass: '
      read -r ans
      if [[ "$ans" == YES ]]; then runservice fragcity-addon-provision.service 'Manual provisioning pass'; else echo 'Cancelled.'; sleep 1; fi
      ;;
    5) dashboard; printf '\nReturned to manager.\n'; sleep 1 ;;
    6) recentlogs ;;
    7) followlogs ;;
    8) showstatus ;;
    0) echo 'FragCity Control Center closed.'; exit 0 ;;
    *) printf '%bInvalid choice.%b\n' "$R" "$Z"; sleep 1 ;;
  esac
  reload_if_updated
done
