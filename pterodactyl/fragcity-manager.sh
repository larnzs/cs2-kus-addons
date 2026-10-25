#!/usr/bin/env bash
# FragCity Control Center: root-safe terminal management of the Pterodactyl timers.
set -o pipefail
REPO_ROOT="/opt/fragcity/cs2-kus-addons"
SELF_PATH="$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")"

if [[ "$(id -u)" -ne 0 ]]; then
  command -v sudo >/dev/null 2>&1 || { echo "sudo is required."; read -r -p "Press Enter..."; exit 1; }
  exec sudo -E /bin/bash "$SELF_PATH" "$@"
fi

MONITOR_MODEL_PATH="$REPO_ROOT/pterodactyl/fragcity-monitor-model.sh"
if [[ ! -r "$MONITOR_MODEL_PATH" ]]; then
  printf 'FragCity monitor model is missing: %s\n' "$MONITOR_MODEL_PATH" >&2
  exit 1
fi
source "$MONITOR_MODEL_PATH"

monitor_code_sha() {
  { sha256sum -- "$SELF_PATH" 2>/dev/null; sha256sum -- "$MONITOR_MODEL_PATH" 2>/dev/null; } |
    sha256sum 2>/dev/null | awk '{print $1}'
}
STARTUP_SHA="$(monitor_code_sha)"

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
  now="$(monitor_code_sha)"
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
    if IFS= read -r -t 60 CHOICE; then
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

installation_wizard() {
  local mode timers exclude ans rc baseline confirm
  baseline="/var/lib/pterodactyl/fragcity-addon-provisioner/baseline-uuids.txt"
  heading "FULL INSTALL / REINSTALL"
  printf '\n%bThis wizard installs or repairs the FragCity host automation files.%b\n' "$C" "$Z"
  printf '  It does NOT delete Docker volumes, game-server data, Mount assignments, or the baseline.\n'
  if [[ -f "$baseline" && ! -L "$baseline" ]]; then
    printf '  Existing baseline: %bPRESENT — it will be preserved%b\n' "$G" "$Z"
  elif [[ -e "$baseline" || -L "$baseline" ]]; then
    printf '  Baseline path: %bINVALID TYPE / SYMLINK — installer will refuse%b\n' "$R" "$Z"
  else
    printf '  Existing baseline: %bMISSING — installer may create the initial baseline%b\n' "$Y" "$Z"
  fi
  printf '\n%bSelect mode%b\n' "$M" "$Z"
  printf '  %b1%b  FULL FIRST INSTALL — install units/dashboard and choose timer policy\n' "$G" "$Z"
  printf '  %b2%b  REINSTALL / REPAIR — replace installed unit/script files; preserve current timer settings\n' "$Y" "$Z"
  printf '  %b0%b  Cancel\n\nMode: ' "$D" "$Z"
  read -r mode
  exclude=''
  case "$mode" in
    1)
      if [[ ! -e "$baseline" && ! -L "$baseline" ]]; then
        printf '\nOptional: enter one eligible server UUID to exclude from the initial baseline.\n'
        printf 'Leave empty to baseline every currently eligible server: '
        read -r exclude
        if [[ -n "$exclude" && ! "$exclude" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
          printf '%bInvalid UUID format; cancelled.%b\n' "$R" "$Z"; pause; return
        fi
      fi
      printf '\nTimer policy for the full install:\n'
      printf '  %b1%b  Turn both automation timers ON (persistent across reboot)\n' "$G" "$Z"
      printf '  %b2%b  Keep current timer settings (fresh installs stay OFF)\n\nChoice: ' "$G" "$Z"
      read -r timers
      case "$timers" in
        1) timers=1 ;;
        2) timers=0 ;;
        *) printf '%bInvalid choice; cancelled.%b\n' "$R" "$Z"; pause; return ;;
      esac
      confirm='INSTALL'
      ;;
    2)
      timers=0
      printf '\nReinstall keeps each timer in its current enabled/disabled state.\n'
      printf 'It preserves the existing baseline and does not remove Mounts or server data.\n'
      confirm='REINSTALL'
      ;;
    0|'') return ;;
    *) printf '%bInvalid mode.%b\n' "$R" "$Z"; pause; return ;;
  esac
  printf '\n%bThis operation will overwrite the four FragCity systemd unit files and refresh the host dashboard/autostart files.%b\n' "$Y" "$Z"
  printf 'For a full install with timers ON, a provisioning pass may modify eligible stopped servers.\n'
  printf 'Type %b%s%b to continue, or anything else to cancel: ' "$Y" "$confirm" "$Z"
  read -r ans
  if [[ "$ans" != "$confirm" ]]; then echo 'Cancelled; no changes made.'; pause; return; fi

  printf '\n%bRunning installer...%b\n' "$C" "$Z"
  rc=0
  if [[ -n "$exclude" ]]; then
    FRAGCITY_BASELINE_EXCLUDE_UUID="$exclude" FRAGCITY_ENABLE_TIMERS="$timers" FRAGCITY_LAUNCH_DASHBOARD=0 \
      bash "$REPO_ROOT/pterodactyl/install-host-services.sh" || rc=$?
  else
    FRAGCITY_ENABLE_TIMERS="$timers" FRAGCITY_LAUNCH_DASHBOARD=0 \
      bash "$REPO_ROOT/pterodactyl/install-host-services.sh" || rc=$?
  fi
  if [[ "$rc" -eq 0 ]]; then
    printf '\n%bInstaller completed successfully.%b\n' "$G" "$Z"
  else
    printf '\n%bInstaller failed with exit status %s. Check the output above and the service journals.%b\n' "$R" "$rc" "$Z"
  fi
  printf '\n%bTimer state after installer%b\n' "$M" "$Z"
  timerrow "Payload auto-sync" fragcity-addon-payload-sync.timer
  timerrow "New-server provisioner" fragcity-addon-provision.timer
  printf '\n%bRecent installer-related logs%b\n' "$M" "$Z"
  journalctl -u fragcity-addon-payload-sync.service -u fragcity-addon-provision.service -n 20 --no-pager -o short-iso 2>&1
  pause
}

dashboard() {
  if [[ ! -r /usr/local/libexec/fragcity-status-dashboard.sh ]]; then
    printf '%bDashboard not installed.%b\n' "$R" "$Z"; pause; return
  fi
  printf '%bDashboard in this terminal — Ctrl+C returns to the manager.%b\n' "$C" "$Z"
  sleep 1
  bash /usr/local/libexec/fragcity-status-dashboard.sh
}

heading() {
  clear 2>/dev/null || true
  printf '%b╔══════════════════════════════════════════════════════════════════════════════╗%b\n' "$B" "$Z"
  printf '%b║%b  %bFRAGCITY CONTROL CENTER%b  %b/ %s%b\n' "$B" "$Z" "$G" "$Z" "$C" "$1" "$Z"
  printf '%b╚══════════════════════════════════════════════════════════════════════════════╝%b\n' "$B" "$Z"
}

service_card() {
  local title="$1" unit="$2" av ev sub fragment
  printf '\n%b── %s ──%b\n' "$M" "$title" "$Z"
  if ! systemctl cat "$unit" >/dev/null 2>&1; then
    printf '  Unit: %s\n  State: %bNOT INSTALLED%b\n' "$unit" "$R" "$Z"
    return
  fi
  av="$(a "$unit")"; ev="$(e "$unit")"
  sub="$(systemctl show "$unit" --property=SubState --value 2>/dev/null || true)"
  fragment="$(systemctl show "$unit" --property=FragmentPath --value 2>/dev/null || true)"
  printf '  Unit: %-28s active=' "$unit"; sw "$av"; printf '  boot='; sw "$ev"; printf '\n'
  printf '  Raw state: %s   Unit file: %s\n' "$sub" "$fragment"
  [[ "$av" != failed ]] || printf '  %bWARNING: systemd marks this service failed.%b\n' "$R" "$Z"
}

logs_for() {
  local unit="$1" count="$2"
  if systemctl cat "$unit" >/dev/null 2>&1; then
    printf '\n%bRecent log: %s%b\n' "$C" "$unit" "$Z"
    journalctl -u "$unit" -n "$count" --no-pager -o short-iso 2>&1 | sed 's/^/  /'
  else
    printf '  No service unit named %s was found.\n' "$unit"
  fi
}

listen_ports() {
  local filter="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntup 2>/dev/null | grep -E "$filter" || printf '  No matching listener detected.\n'
  else
    printf '  ss command is not installed.\n'
  fi
}

screen_docker() {
  heading "DOCKER ENGINE & CONTAINERS"
  service_card "Docker Engine" docker.service
  printf '\n%bDocker version%b\n' "$C" "$Z"
  docker --version 2>&1 || true
  if docker info >/dev/null 2>&1; then
    docker info --format '  Engine={{.ServerVersion}} | Root={{.DockerRootDir}} | Total={{.Containers}} | Running={{.ContainersRunning}} | Paused={{.ContainersPaused}} | Stopped={{.ContainersStopped}}' 2>&1 || true
    printf '\n%bRunning containers%b\n' "$C" "$Z"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}' 2>&1 | head -n 25
    printf '\n%bServer UUID containers%b\n' "$C" "$Z"
    docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null |
      awk -F '\t' '$1 ~ /^[0-9a-f]{8}-[0-9a-f-]{27,}$/ {print "  "$0; found=1} END {if (!found) print "  No UUID-named server containers found."}'
  else
    printf '  %bDocker CLI cannot reach the engine.%b\n' "$R" "$Z"
  fi
  logs_for docker.service 12
  pause
}

screen_wings() {
  heading "PTERODACTYL WINGS"
  service_card "Wings daemon" wings.service
  printf '\n%bBinary / version%b\n' "$C" "$Z"
  if command -v wings >/dev/null 2>&1; then
    command -v wings
    timeout 4 wings --version 2>&1 || true
  else
    printf '  Wings binary not found in PATH.\n'
  fi
  printf '\n%bConfiguration%b\n' "$C" "$Z"
  if [[ -r /etc/pterodactyl/config.yml ]]; then
    stat -c '  %n | permissions=%a | owner=%U:%G | modified=%y' /etc/pterodactyl/config.yml
  else
    printf '  %bMissing /etc/pterodactyl/config.yml%b\n' "$R" "$Z"
  fi
  printf '\n%bCommon Wings ports%b\n' "$C" "$Z"
  listen_ports ':(8080|2022)\b'
  logs_for wings.service 18
  pause
}

screen_cs2node() {
  heading "CS2NODE / SHARED GAME DATA"
  if command -v cs2node >/dev/null 2>&1; then
    printf '  cs2node binary: %bFOUND%b\n' "$G" "$Z"
    command -v cs2node
    stat -c '  modified=%y | permissions=%a | owner=%U:%G' "$(command -v cs2node)"
    printf '  SHA-256: '; sha256sum "$(command -v cs2node)" 2>/dev/null | awk '{print $1}'
  else
    printf '  cs2node binary: %bNOT FOUND%b\n' "$R" "$Z"
  fi
  node_processes="$(pgrep -af '[c]s2node' 2>/dev/null || true)"
  printf '\n%bCS2Node process%b\n' "$C" "$Z"
  if [[ -n "$node_processes" ]]; then printf '%s\n' "$node_processes" | sed 's/^/  /'
  else
    printf '  No long-running cs2node process detected; it may run as a command or timer job.\n'
  fi
  printf '\n%bConfiguration%b\n' "$C" "$Z"
  if [[ -f /etc/cs2node/config.json ]]; then
    stat -c '  %n | permissions=%a | owner=%U:%G | modified=%y' /etc/cs2node/config.json
    if python3 -m json.tool /etc/cs2node/config.json >/dev/null 2>&1; then
      printf '  JSON syntax: %bVALID%b\n' "$G" "$Z"
      python3 -c 'import json; d=json.load(open("/etc/cs2node/config.json")); print("  Top-level setting names: "+", ".join(sorted(map(str,d.keys()))))' 2>/dev/null || true
    else printf '  JSON syntax: %bINVALID%b\n' "$R" "$Z"; fi
  else printf '  Config not found at /etc/cs2node/config.json\n'; fi
  printf '\n%bShared game files%b\n' "$C" "$Z"
  if [[ -d /srv/cs2-shared/game ]]; then
    du -sh /srv/cs2-shared/game 2>&1
    stat -c '  %n | owner=%U:%G | permissions=%a' /srv/cs2-shared/game
  else printf '  Shared game directory not found at /srv/cs2-shared/game.\n'; fi
  printf '\n%bCS2 / Steam-related processes%b\n' "$C" "$Z"
  pgrep -af '[c]s2|[s]rcds|[s]teamcmd' 2>/dev/null | head -n 12 || printf '  No matching process detected.\n'
  pause
}

screen_php() {
  heading "PHP CLI / PHP-FPM"
  printf '\n%bPHP CLI%b\n' "$C" "$Z"
  if command -v php >/dev/null 2>&1; then
    command -v php
    php -v 2>&1 | head -n 3
    printf '  Loaded module count: '
    php -m 2>/dev/null | grep -c '^[[:alnum:]_]' || true
  else printf '  %bPHP CLI not installed.%b\n' "$R" "$Z"; fi
  printf '\n%bLoaded PHP-FPM units%b\n' "$C" "$Z"
  fpm_units="$(systemctl list-units --type=service --all 'php*-fpm.service' --no-legend 2>/dev/null || true)"
  if [[ -n "$fpm_units" ]]; then
    printf '%s\n' "$fpm_units" | while read -r unit load active sub description; do
      [[ -n "$unit" ]] || continue
      printf '  %-24s active=' "$unit"; sw "$active"; printf '  (%s)\n' "$sub"
    done
  else printf '  No loaded php*-fpm service unit matched.\n'; fi
  service_card "PHP 8.3 FPM (expected)" php8.3-fpm.service
  printf '\n%bPterodactyl Laravel runtime%b\n' "$C" "$Z"
  if [[ -f /var/www/pterodactyl/artisan ]] && command -v php >/dev/null 2>&1; then
    (cd /var/www/pterodactyl && php artisan --version) 2>&1 || true
  else printf '  Panel artisan file or PHP CLI not found.\n'; fi
  logs_for php8.3-fpm.service 12
  pause
}

screen_nginx() {
  heading "NGINX / HTTP ENDPOINTS"
  service_card "Nginx web server" nginx.service
  printf '\n%bVersion%b\n' "$C" "$Z"
  nginx -v 2>&1 || true
  printf '\n%bConfiguration test (read-only)%b\n' "$C" "$Z"
  if nginx -t 2>&1; then printf '  Config test: %bPASS%b\n' "$G" "$Z"; else printf '  Config test: %bFAIL%b\n' "$R" "$Z"; fi
  printf '\n%bHTTP / HTTPS listeners%b\n' "$C" "$Z"
  listen_ports ':(80|443)\b'
  printf '\n%bEnabled site links%b\n' "$C" "$Z"
  if [[ -d /etc/nginx/sites-enabled ]]; then
    find /etc/nginx/sites-enabled -maxdepth 1 \( -type l -o -type f \) -printf '  %f%l\n' 2>/dev/null
  else printf '  /etc/nginx/sites-enabled not found.\n'; fi
  logs_for nginx.service 12
  pause
}

screen_panel() {
  heading "PTERODACTYL PANEL / QUEUE"
  printf '\n%bPanel application%b\n' "$C" "$Z"
  if [[ -f /var/www/pterodactyl/artisan ]]; then
    printf '  Files: %bFOUND%b (/var/www/pterodactyl)\n' "$G" "$Z"
    (cd /var/www/pterodactyl && php artisan --version) 2>&1 || true
    stat -c '  artisan modified: %y' /var/www/pterodactyl/artisan
  else printf '  %bPanel files not found%b\n' "$R" "$Z"; fi
  printf '\n%bQueue worker%b\n' "$C" "$Z"
  service_card "Pterodactyl queue" pteroq.service
  logs_for pteroq.service 15
  printf '\n%bLocal HTTPS check%b\n' "$C" "$Z"
  if command -v curl >/dev/null 2>&1; then
    http_code="$(curl -k -sS -o /dev/null -w '%{http_code}' https://127.0.0.1/ --max-time 3 2>/dev/null || true)"
    if [[ -n "$http_code" ]]; then printf '  https://127.0.0.1/ -> HTTP %s (default virtual host/TLS may affect this check)\n' "$http_code"
    else printf '  Local HTTPS not reachable without the Panel Host header.\n'; fi
  else printf '  curl not installed; skipped HTTP check.\n'; fi
  pause
}

screen_mariadb() {
  heading "MARIADB / DATABASE"
  service_card "MariaDB database" mariadb.service
  printf '\n%bClient version%b\n' "$C" "$Z"
  if command -v mariadb >/dev/null 2>&1; then mariadb --version 2>&1
  elif command -v mysql >/dev/null 2>&1; then mysql --version 2>&1
  else printf '  MariaDB client binary not found.\n'; fi
  printf '\n%bPort 3306%b\n' "$C" "$Z"
  listen_ports ':(3306)\b'
  printf '\n%bLocal socket%b\n' "$C" "$Z"
  if [[ -S /run/mysqld/mysqld.sock ]]; then stat -c '  %n | owner=%U:%G' /run/mysqld/mysqld.sock
  elif [[ -S /var/run/mysqld/mysqld.sock ]]; then stat -c '  %n | owner=%U:%G' /var/run/mysqld/mysqld.sock
  else printf '  Standard local socket not found.\n'; fi
  logs_for mariadb.service 15
  pause
}

screen_redis() {
  heading "REDIS CACHE"
  service_card "Redis server" redis-server.service
  printf '\n%bVersion%b\n' "$C" "$Z"
  if command -v redis-server >/dev/null 2>&1; then redis-server --version 2>&1
  else printf '  redis-server binary not found.\n'; fi
  printf '\n%bConnectivity (read-only PING)%b\n' "$C" "$Z"
  if command -v redis-cli >/dev/null 2>&1; then
    redis_result="$(timeout 3 redis-cli ping 2>&1 || true)"
    case "$redis_result" in
      PONG) printf '  Redis PING: %bPONG%b\n' "$G" "$Z" ;;
      NOAUTH*) printf '  Redis is reachable but requires authentication: %bREACHABLE%b\n' "$Y" "$Z" ;;
      *) printf '  Response: %s\n' "$redis_result" ;;
    esac
  else printf '  redis-cli not installed.\n'; fi
  printf '\n%bPort 6379%b\n' "$C" "$Z"
  listen_ports ':(6379)\b'
  logs_for redis-server.service 12
  pause
}

screen_fragcity() {
  heading "FRAGCITY AUTOMATION"
  printf '\n%bTimer status%b\n' "$C" "$Z"
  timerrow "Payload auto-sync" fragcity-addon-payload-sync.timer
  timerrow "New-server provisioner" fragcity-addon-provision.timer
  printf '\n%bNext scheduled runs%b\n' "$C" "$Z"
  systemctl list-timers --all --no-pager fragcity-addon-payload-sync.timer fragcity-addon-provision.timer 2>&1
  printf '\n%bPublished payload%b\n' "$C" "$Z"
  if [[ -r /var/lib/pterodactyl/mounts/fragcity-addon-payload/CURRENT_COMMIT ]]; then
    payload_commit="$(tr -d '\r\n' < /var/lib/pterodactyl/mounts/fragcity-addon-payload/CURRENT_COMMIT)"
    printf '  Commit: %b%s%b\n' "$G" "$payload_commit" "$Z"
  else printf '  %bPayload marker missing%b\n' "$R" "$Z"; fi
  printf '\n%bRepository head%b\n' "$C" "$Z"
  git -C "$REPO_ROOT" log -1 --format='  %h %cs %s' 2>&1
  printf '\n%bProvisioner state%b\n' "$C" "$Z"
  baseline="/var/lib/pterodactyl/fragcity-addon-provisioner/baseline-uuids.txt"
  if [[ -r "$baseline" ]]; then
    baseline_count="$(grep -Ec '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' "$baseline" 2>/dev/null || true)"
    printf '  Baseline UUIDs: %s\n' "$baseline_count"
  else printf '  %bBASELINE MISSING%b\n' "$R" "$Z"; fi
  processed="/var/lib/pterodactyl/fragcity-addon-provisioner/processed"
  processed_count=0
  [[ -d "$processed" ]] && processed_count="$(find "$processed" -maxdepth 1 -type f -name '*.json' | wc -l)"
  printf '  Processed server markers: %s\n' "$processed_count"
  logs_for fragcity-addon-provision.service 10
  logs_for fragcity-addon-payload-sync.service 10
  pause
}

screen_all() {
  heading "ALL SERVICE SUMMARY"
  printf '\n%-25s %-10s %-10s\n' "COMPONENT" "ACTIVE" "BOOT"
  printf '%s\n' '--------------------------------------------------------'
  while IFS='|' read -r title unit; do
    av="$(a "$unit")"; ev="$(e "$unit")"
    printf '%-25s ' "$title"; sw "$av"; printf '       '; sw "$ev"; printf '\n'
  done <<'UNITS'
Docker|docker.service
Wings|wings.service
PHP-FPM 8.3|php8.3-fpm.service
Nginx|nginx.service
Pterodactyl queue|pteroq.service
MariaDB|mariadb.service
Redis|redis-server.service
Payload timer|fragcity-addon-payload-sync.timer
Provisioner timer|fragcity-addon-provision.timer
UNITS
  printf '\n%bCS2Node binary%b: ' "$C" "$Z"
  if command -v cs2node >/dev/null 2>&1; then printf '%bINSTALLED%b\n' "$G" "$Z"; else printf '%bMISSING%b\n' "$R" "$Z"; fi
  printf '\n%bRunning Docker containers%b\n' "$C" "$Z"
  docker ps --format '  {{.Names}}\t{{.Status}}\t{{.Image}}' 2>&1 | head -n 20
  printf '\n%bKey listeners%b\n' "$C" "$Z"
  listen_ports ':(80|443|3306|6379|8080|2022)\b'
  pause
}

screen_host() {
  heading "HOST RESOURCES"
  printf '\n%bOS / kernel%b\n' "$C" "$Z"
  sed -n '1,8p' /etc/os-release 2>/dev/null
  uname -a
  printf '\n%bUptime / load%b\n' "$C" "$Z"; uptime
  printf '\n%bMemory%b\n' "$C" "$Z"; free -h
  printf '\n%bFilesystem usage%b\n' "$C" "$Z"; df -hT / /var/lib/pterodactyl 2>&1
  printf '\n%bNetwork interfaces%b\n' "$C" "$Z"; ip -brief address 2>&1 || true
  pause
}


MAIN_MOUNT_STATUS_CACHE=''
MAIN_MOUNT_STATUS_ERROR=''
MAIN_MOUNT_STATUS_CACHE_AT=0

status_badge() {
  case "$1" in
    ON|OK|READY|MATCH|HEALTHY|active|enabled|enabled-runtime|linked|linked-runtime|alias)
      printf '%bON%b' "$G" "$Z" ;;
    OFF|inactive|disabled|dead|not-found|failed)
      printf '%bOFF%b' "$R" "$Z" ;;
    PENDING|UNKNOWN|UNSAFE|ERROR|N/A|ABSENT)
      printf '%b%s%b' "$Y" "$1" "$Z" ;;
    *)
      printf '%b%s%b' "$D" "$1" "$Z" ;;
  esac
}

main_service_pair() {
  local left_title="$1" left_unit="$2" right_title="$3" right_unit="$4"
  local av ev
  av="$(a "$left_unit")"; ev="$(e "$left_unit")"
  printf '  %-18s active=' "$left_title"; status_badge "$av"
  printf ' boot='; status_badge "$ev"
  av="$(a "$right_unit")"; ev="$(e "$right_unit")"
  printf '    | %-18s active=' "$right_title"; status_badge "$av"
  printf ' boot='; status_badge "$ev"
  printf '\n'
}

main_service_single() {
  local title="$1" unit="$2" av ev
  av="$(a "$unit")"; ev="$(e "$unit")"
  printf '  %-18s active=' "$title"; status_badge "$av"
  printf ' boot='; status_badge "$ev"
  printf '\n'
}

main_cs2node_status() {
  printf '  %-18s active=' 'CS2Node binary'
  if command -v cs2node >/dev/null 2>&1; then status_badge ON; else status_badge OFF; fi
  printf ' boot='; status_badge N/A
  printf '\n'
}

refresh_main_mount_status() {
  local now result rc
  now="$(date +%s)"
  if (( MAIN_MOUNT_STATUS_CACHE_AT > 0 && now - MAIN_MOUNT_STATUS_CACHE_AT < 5 )); then
    return
  fi

  MAIN_MOUNT_STATUS_CACHE_AT="$now"
  result="$(timeout 18 php "$REPO_ROOT/pterodactyl/server-mount-status.php" 2>&1)"
  rc=$?
  if [[ "$rc" -eq 0 && "$result" == META$'\t'OK$'\t'* ]]; then
    MAIN_MOUNT_STATUS_CACHE="$result"
    MAIN_MOUNT_STATUS_ERROR=''
  else
    MAIN_MOUNT_STATUS_CACHE=''
    MAIN_MOUNT_STATUS_ERROR="$result"
    [[ -n "$MAIN_MOUNT_STATUS_ERROR" ]] || MAIN_MOUNT_STATUS_ERROR="Status command exited with code $rc."
  fi
}

render_server_mount_status() {
  local line kind f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 f13 f14 f15 f16
  local docker_scan='UNKNOWN' reason severity
  refresh_main_mount_status
  printf '\n%b[ CURRENT ELIGIBLE SERVER INVENTORY — LIVE PANEL UUIDs ]%b\n' "$C" "$Z"
  if [[ -z "$MAIN_MOUNT_STATUS_CACHE" ]]; then
    printf '  %bMount inventory unavailable%b\n' "$R" "$Z"
    printf '  %s\n' "$MAIN_MOUNT_STATUS_ERROR"
    printf '  No stale/cached UUID list is presented as current. Check Panel DB and Docker access.\n'
    return
  fi

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r kind f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 f13 f14 f15 f16 <<< "$line"
    case "$kind" in
      META)
        printf '  Mount ID: %s | source: %s\n' "$f2" "$f3"
        printf '  Target: %s | baseline registry: %s\n' "$f4" "$f5"
        ;;
      SERVER)
        printf '\n  UUID: %s\n' "$f1"
        printf '  Name: %s\n' "$f2"
        printf '  Container state: %s\n' "$f4"
        printf '  Panel Mount: '; status_badge "$f3"
        printf '  | Docker Mount: '; status_badge "$f5"; printf '\n'
        printf '  Processed marker: '; status_badge "$f6"
        printf '  | Startup hook: '; status_badge "$f7"; printf '\n'
        printf '  Baseline: '; status_badge "$f8"
        printf '  | First-install seed: '; status_badge "$f9"; printf '\n'
        reason="$(fragcity_classify_server "$f3" "$f4" "$f5" "$f6" "$f7" "$f8" "$f9")"
        severity="$(fragcity_server_severity "$reason")"
        if [[ "$reason" == OK ]]; then
          printf '  HEALTH: %bOK%b\n' "$G" "$Z"
        elif [[ "$severity" == CRITICAL ]]; then
          printf '  HEALTH: %bCRITICAL — %s%b\n' "$R" "$reason" "$Z"
        else
          printf '  HEALTH: %bATTENTION — %s%b\n' "$Y" "$reason" "$Z"
        fi
        ;;
      ORPHAN_CONTAINER)
        printf '  %bORPHAN DOCKER CONTAINER%b — UUID %s | state %s | reason %s\n' "$Y" "$Z" "$f1" "$f2" "$f3"
        ;;
      STALE_BASELINE|STALE_MARKER)
        # Historical UUID details are shown only in the dedicated D menu.
        ;;
      DOCKER_SCAN)
        docker_scan="$f1"
        ;;
      SUMMARY)
        printf '\n  LIVE COUNTS\n'
        printf '  All Panel UUIDs: %s | Eligible for this Mount: %s\n' "$f13" "$f1"
        printf '  Panel Mount ON/OFF: '; status_badge "$f2"; printf '/'
        status_badge "$f3"
        printf ' | Docker Mount ON/OFF: '; status_badge "$f4"; printf '/'
        status_badge "$f5"; printf '\n'
        printf '  No container: '; status_badge "$f6"
        printf ' | Unknown: '; status_badge "$f7"
        printf ' | Processed markers on eligible UUIDs: '; status_badge "$f8"
        printf ' | Startup hooks: '; status_badge "$f9"; printf '\n'
        printf '  Seed pending: '; status_badge "$f10"
        printf ' | seed missing (new): '; status_badge "$f11"
        printf ' | seed invalid: '; status_badge "$f12"; printf '\n'
        printf '  Orphan Docker containers: '; status_badge "$f14"
        printf ' | Baseline UUIDs stale for this Mount: '; status_badge "$f15"
        printf ' | Processed markers stale for this Mount: '; status_badge "$f16"; printf '\n'
        printf '  Docker inventory scan: '; status_badge "$docker_scan"; printf '\n'
        ;;
    esac
  done <<< "$MAIN_MOUNT_STATUS_CACHE"
}


screen_deleted_uuid_history() {
  MAIN_MOUNT_STATUS_CACHE_AT=0
  refresh_main_mount_status
  heading "DELETED / STALE UUID HISTORY"
  printf '\nThis page contains historical Baseline and processed-marker UUIDs, not the live server inventory.\n'
  if [[ -z "$MAIN_MOUNT_STATUS_CACHE" ]]; then
    printf '\n%bHistory is unavailable because the live Panel/Mount query failed.%b\n' "$R" "$Z"
    printf '  %s\n' "$MAIN_MOUNT_STATUS_ERROR"
    pause
    return
  fi

  local line kind f1 f2 found=0 baseline_count=0 marker_count=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r kind f1 f2 _ <<< "$line"
    case "$kind" in
      STALE_BASELINE)
        if (( baseline_count == 0 )); then
          printf '\n%bSTALE BASELINE UUID HISTORY%b\n' "$M" "$Z"
        fi
        baseline_count=$((baseline_count + 1))
        found=1
        printf '  %s  | reason: %s\n' "$f1" "$f2"
        ;;
      STALE_MARKER)
        if (( marker_count == 0 )); then
          printf '\n%bSTALE PROCESSED MARKER HISTORY%b\n' "$M" "$Z"
        fi
        marker_count=$((marker_count + 1))
        found=1
        printf '  %s  | reason: %s\n' "$f1" "$f2"
        ;;
    esac
  done <<< "$MAIN_MOUNT_STATUS_CACHE"

  if (( found == 0 )); then
    printf '\nNo stale UUID history entries were detected.\n'
  else
    printf '\nEntries shown: Baseline=%s, processed markers=%s\n' "$baseline_count" "$marker_count"
    printf 'PANEL_UUID_DELETED means the UUID is absent from Panel; SERVER_NOT_ELIGIBLE_FOR_MOUNT means the Panel record still exists but is no longer eligible for this Mount/Egg/Node.\n'
  fi
  pause
}

manage_install_marks() {
  local line kind f1 f2 f3 f4 f5 f6 f7 f8 f9
  local selected answer action rc output index uuid name panel_mount container_state docker_mount startup seed
  local count=0 i
  local -a ids=() names=() panel_mounts=() container_states=() docker_mounts=() startups=() seeds=()

  while true; do
    MAIN_MOUNT_STATUS_CACHE_AT=0
    refresh_main_mount_status
    heading "MANUAL FIRST-INSTALL MARKS"

    if [[ -z "$MAIN_MOUNT_STATUS_CACHE" ]]; then
      printf '\n%bCurrent server inventory is unavailable; no state can be changed.%b\n' "$R" "$Z"
      printf '  %s\n' "$MAIN_MOUNT_STATUS_ERROR"
      pause
      return
    fi

    ids=(); names=(); panel_mounts=(); container_states=(); docker_mounts=(); startups=(); seeds=()
    count=0
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      IFS=$'\t' read -r kind f1 f2 f3 f4 f5 f6 f7 f8 f9 _ <<< "$line"
      [[ "$kind" == SERVER ]] || continue
      if [[ ! "$f1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        continue
      fi
      ids+=("${f1}")
      names+=("${f2}")
      panel_mounts+=("${f3}")
      container_states+=("${f4}")
      docker_mounts+=("${f5}")
      startups+=("${f7}")
      seeds+=("${f9}")
      count=$((count + 1))
    done <<< "$MAIN_MOUNT_STATUS_CACHE"

    printf '\nChoose a currently eligible server UUID:\n'
    if (( count == 0 )); then
      printf '  No eligible Panel servers were found.\n'
      pause
      return
    fi
    for ((i=0; i<count; i++)); do
      printf '  %2d) %-24.24s | seed=%-9s | Panel Mount=%-3s | Docker Mount=%-3s | Startup=%-3s\n' \
        "$((i + 1))" "${names[$i]}" "${seeds[$i]}" "${panel_mounts[$i]}" "${docker_mounts[$i]}" "${startups[$i]}"
      printf '      UUID: %s\n' "${ids[$i]}"
    done
    printf '\n  0) Return to main monitor\n\nServer number: '
    read -r selected
    if [[ "$selected" == 0 || -z "$selected" ]]; then
      return
    fi
    if [[ ! "$selected" =~ ^[0-9]+$ ]]; then
      printf '%bInvalid selection.%b\n' "$R" "$Z"
      sleep 1
      continue
    fi
    index=$((10#$selected))
    if (( index < 1 || index > count )); then
      printf '%bSelection out of range.%b\n' "$R" "$Z"
      sleep 1
      continue
    fi
    index=$((index - 1))
    uuid="${ids[$index]}"
    name="${names[$index]}"
    panel_mount="${panel_mounts[$index]}"
    container_state="${container_states[$index]}"
    docker_mount="${docker_mounts[$index]}"
    startup="${startups[$index]}"
    seed="${seeds[$index]}"

    heading "FIRST-INSTALL STATE — $name"
    printf '  UUID: %s\n' "$uuid"
    printf '  Current seed state: %s\n' "$seed"
    printf '  Container: %s | Panel Mount: %s | Docker Mount: %s | Startup hook: %s\n' \
      "$container_state" "$panel_mount" "$docker_mount" "$startup"
    printf '\n'
    printf '  1) Mark as a new install (mode=pending; seed repository config defaults)\n'
    printf '  2) Mark as installed (mode=completed; ignore server config seeding)\n'
    printf '  0) Back to server list\n\nAction: '
    read -r action

    case "$action" in
      1)
        printf '\n%bWARNING%b: on the next startup, FragCity will run the full first-install Payload sync and copy repository config defaults. This can overwrite server-specific files under csgo/cfg/, CounterStrikeSharp configs/, gamemodes_server.txt, mapcycle files and subscribed-ID files.\n' "$Y" "$Z"
        printf 'This changes only the per-server seed-state file; it does not configure the Mount or Startup hook. The change takes effect on the next startup.\n'
        printf 'Are you sure? [y/n]: '
        read -r answer
        case "$answer" in
          y|Y)
            output="$(php "$REPO_ROOT/pterodactyl/provision-addon-servers.php" --set-config-seed "$uuid" pending 2>&1)"
            rc=$?
            printf '\n%s\n' "$output"
            if (( rc == 0 )); then
              printf '%bState updated: this UUID is marked as a new install.%b\n' "$G" "$Z"
              MAIN_MOUNT_STATUS_CACHE_AT=0
            else
              printf '%bState was not changed (exit %s).%b\n' "$R" "$rc" "$Z"
            fi
            pause
            break
            ;;
          *) printf 'Cancelled; no changes made.\n'; sleep 1 ;;
        esac
        ;;
      2)
        printf '\nThis marks initial config seeding as complete. The next startup will preserve existing server config paths; normal non-config payload syncing still runs.\n'
        printf 'This changes only the per-server seed-state file; it does not configure the Mount or Startup hook.\n'
        printf 'Are you sure? [y/n]: '
        read -r answer
        case "$answer" in
          y|Y)
            output="$(php "$REPO_ROOT/pterodactyl/provision-addon-servers.php" --set-config-seed "$uuid" completed 2>&1)"
            rc=$?
            printf '\n%s\n' "$output"
            if (( rc == 0 )); then
              printf '%bState updated: first-install config seeding is marked complete.%b\n' "$G" "$Z"
              MAIN_MOUNT_STATUS_CACHE_AT=0
            else
              printf '%bState was not changed (exit %s).%b\n' "$R" "$Z" "$rc"
            fi
            pause
            break
            ;;
          *) printf 'Cancelled; no changes made.\n'; sleep 1 ;;
        esac
        ;;
      0|'') continue ;;
      *) printf '%bInvalid action.%b\n' "$R" "$Z"; sleep 1 ;;
    esac
  done
}


render_main_status() {
  printf '\n%b[ HOST SERVICES — ACTIVE / ENABLED AT BOOT ]%b\n' "$C" "$Z"
  main_service_pair Docker docker.service Wings wings.service
  main_service_pair PHP-FPM php8.3-fpm.service Nginx nginx.service
  main_service_pair 'Pterodactyl queue' pteroq.service MariaDB mariadb.service
  main_service_pair Redis redis-server.service 'Payload timer' fragcity-addon-payload-sync.timer
  main_service_single 'Provisioner timer' fragcity-addon-provision.timer
  main_cs2node_status
  render_server_mount_status
}


render_main_page() {
  printf '%b╔══════════════════════════════════════════════════════════════════════════════╗%b\n' "$B" "$Z"
  printf '%b║%b  %bFRAGCITY CONTROL CENTER%b  %b/ LIVE HOST MONITORING%b                         %b║%b\n' "$B" "$Z" "$G" "$Z" "$C" "$Z" "$B" "$Z"
  printf '%b╚══════════════════════════════════════════════════════════════════════════════╝%b\n' "$B" "$Z"
  printf '  %bCode auto-update: ON%b — checks the local manager file every 60 seconds\n' "$G" "$Z"

  render_main_status

  printf '\n%b[ SERVICE DETAIL PAGES ]%b\n' "$C" "$Z"
  printf '  1 Docker   2 Wings   3 CS2Node   4 PHP-FPM   5 Nginx   6 Panel   7 MariaDB   8 Redis\n'
  printf '  9 All services   H Host resources   F FragCity automation\n'
  printf '\n%b[ MANAGEMENT ]%b\n' "$C" "$Z"
  printf '  U Update payload   I First install / reinstall   P Provision once\n'
  printf '  M Manage install marks   D Deleted UUID history\n'
  printf '  T Toggle payload timer   N Toggle provisioner timer\n'
  printf '  R Refresh status now   L Recent logs   W Follow logs   0 Exit\n'
}

HOME_RENDERED=''

while true; do
  # Refresh the server inventory in the main shell so its 15-second cache persists.
  refresh_main_mount_status
  CURRENT_HOME="$(render_main_page)"

  # Redraw only when visible status/content actually changes. This prevents the
  # old clear-and-repaint flicker on every two-second input timeout.
  if [[ "$CURRENT_HOME" != "$HOME_RENDERED" ]]; then
    clear 2>/dev/null || true
    printf '%s\n' "$CURRENT_HOME"
    HOME_RENDERED="$CURRENT_HOME"
  fi

  CHOICE=''
  if IFS= read -r -t 60 -p $'\rChoose an option: ' CHOICE; then
    reload_if_updated
    case "$CHOICE" in
      1) screen_docker ;;
      2) screen_wings ;;
      3) screen_cs2node ;;
      4) screen_php ;;
      5) screen_nginx ;;
      6) screen_panel ;;
      7) screen_mariadb ;;
      8) screen_redis ;;
      9) screen_all ;;
      H|h) screen_host ;;
      F|f) screen_fragcity ;;
      U|u) runservice fragcity-addon-payload-sync.service 'Update from GitHub and publish latest payload/dashboard' ;;
      I|i) installation_wizard ;;
      M|m) manage_install_marks ;;
      D|d) screen_deleted_uuid_history ;;
      P|p)
        printf '\nProvisioning may attach the Mount and change Startup for eligible stopped servers.\nType YES to run one pass: '
        read -r ans
        if [[ "$ans" == YES ]]; then
          runservice fragcity-addon-provision.service 'Manual provisioning pass'
        else
          echo 'Cancelled.'
          sleep 1
        fi
        ;;
      T|t) toggle fragcity-addon-payload-sync.timer 'Payload auto-sync timer' ;;
      N|n)
        printf '\nOFF pauses future automatic provisioning; existing Mount assignments remain intact.\n'
        toggle fragcity-addon-provision.timer 'New-server provisioner timer'
        ;;
      R|r)
        MAIN_MOUNT_STATUS_CACHE_AT=0
        HOME_RENDERED=''
        continue
        ;;
      L|l) recentlogs ;;
      W|w) followlogs ;;
      0) echo 'FragCity Control Center closed.'; exit 0 ;;
      *) printf '%bInvalid option.%b\n' "$R" "$Z"; sleep 1 ;;
    esac
    # Return from any detail/action to the main page. If sync changed this file,
    # reload_if_updated below will exec the updated version before the next draw.
    HOME_RENDERED=''
    reload_if_updated
  else
    # Timeout is not a reason to clear/redraw. Check whether a new manager was
    # published; next iteration redraws only if status text changed.
    printf '\r\033[K'
    reload_if_updated
  fi
done
