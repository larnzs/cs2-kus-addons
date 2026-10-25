#!/usr/bin/env bash
# FragCity live node monitor: host health, services, automation and real Docker Mount state.
# The host publisher deploys this script atomically; this process hot-reloads on checksum change.
set -o pipefail

PAYLOAD_ROOT="${FRAGCITY_PAYLOAD_SOURCE:-/var/lib/pterodactyl/mounts/fragcity-addon-payload}"
STATE_ROOT="${FRAGCITY_PROVISIONER_STATE:-/var/lib/pterodactyl/fragcity-addon-provisioner}"
REPO_ROOT="${FRAGCITY_REPO_ROOT:-/opt/fragcity/cs2-kus-addons}"
REFRESH_SECONDS="${FRAGCITY_STATUS_REFRESH_SECONDS:-5}"
MOUNT_REFRESH_SECONDS="${FRAGCITY_STATUS_MOUNT_REFRESH_SECONDS:-15}"

[[ "$REFRESH_SECONDS" =~ ^[1-9][0-9]*$ ]] || REFRESH_SECONDS=5
[[ "$MOUNT_REFRESH_SECONDS" =~ ^[5-9][0-9]*$|^[1-9][0-9]+$ ]] || MOUNT_REFRESH_SECONDS=15
UI_VERSION="3.1-first-install-state"
SELF_PATH="$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")"

# This inventory deliberately requires root because it reads Panel's database and
# Docker's actual Mounts. Elevate in the visible terminal so the status is truthful.
if [[ "$(id -u)" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1 && [[ -t 0 ]]; then
    exec sudo -E /bin/bash "$SELF_PATH" "$@"
  fi
  printf 'FragCity dashboard needs root access to inspect actual Docker Mounts.\n'
  printf 'Launch it from an interactive terminal with sudo.\n'
  exit 1
fi

STARTUP_SHA="$(sha256sum -- "$SELF_PATH" 2>/dev/null | awk '{print $1}')"
term_value="$(printenv TERM 2>/dev/null || printf 'dumb')"
no_color_value="$(printenv NO_COLOR 2>/dev/null || true)"

if [[ -t 1 && -z "$no_color_value" && "$term_value" != "dumb" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[1;31m'
  C_GREEN=$'\033[1;32m'
  C_YELLOW=$'\033[1;33m'
  C_BLUE=$'\033[1;34m'
  C_CYAN=$'\033[1;36m'
  C_MAGENTA=$'\033[1;35m'
  C_WHITE=$'\033[1;37m'
else
  C_RESET=''
  C_BOLD=''
  C_DIM=''
  C_RED=''
  C_GREEN=''
  C_YELLOW=''
  C_BLUE=''
  C_CYAN=''
  C_MAGENTA=''
  C_WHITE=''
fi

MOUNT_STATUS_OUTPUT=''
MOUNT_STATUS_ERROR=''
MOUNT_LAST_REFRESH=0
MOUNT_ID='?'
MOUNT_SOURCE="$PAYLOAD_ROOT"
MOUNT_TARGET='/home/container/egg/fragcity-payload'
MOUNT_ELIGIBLE=0
MOUNT_PANEL_ON=0
MOUNT_PANEL_OFF=0
MOUNT_DOCKER_ON=0
MOUNT_DOCKER_OFF=0
MOUNT_PENDING=0
MOUNT_UNKNOWN=0
MOUNT_PROCESSED=0
MOUNT_STARTUP=0
MOUNT_SEED_PENDING=0
MOUNT_SEED_MISSING=0
MOUNT_SEED_BAD=0
MOUNT_NEW_UNREGISTERED=0
MOUNT_ACTIVE_COUNT=0
MOUNT_INACTIVE_NAMES=''
MOUNT_ACTIVE_ROWS=''
MOUNT_ATTENTION_ROWS=''
MOUNT_ATTENTION_EXTRA=0
MOUNT_EXTRA_ACTIVE=0

paint_switch() {
  case "$1" in
    ON) printf '%bON%b' "$C_GREEN" "$C_RESET" ;;
    FAIL|OFF|MISS) printf '%b%s%b' "$C_RED" "$1" "$C_RESET" ;;
    *) printf '%b%s%b' "$C_YELLOW" "$1" "$C_RESET" ;;
  esac
}

active_code() {
  case "$1" in
    active|activating|reloading) printf ON ;;
    failed) printf FAIL ;;
    not-found) printf MISS ;;
    *) printf OFF ;;
  esac
}

enabled_code() {
  case "$1" in
    enabled|enabled-runtime|linked|linked-runtime|alias) printf ON ;;
    not-found) printf MISS ;;
    *) printf OFF ;;
  esac
}

show_service_triplet() {
  local left_label="$1" left_unit="$2" middle_label="$3" middle_unit="$4" right_label="$5" right_unit="$6"
  local active enabled code
  printf '  %-7s ' "$left_label"
  active="$(systemctl is-active "$left_unit" 2>/dev/null || true)"
  enabled="$(systemctl is-enabled "$left_unit" 2>/dev/null || true)"
  code="$(active_code "$active")"; paint_switch "$code"; printf '/'
  code="$(enabled_code "$enabled")"; paint_switch "$code"
  printf '  │  %-8s ' "$middle_label"
  active="$(systemctl is-active "$middle_unit" 2>/dev/null || true)"
  enabled="$(systemctl is-enabled "$middle_unit" 2>/dev/null || true)"
  code="$(active_code "$active")"; paint_switch "$code"; printf '/'
  code="$(enabled_code "$enabled")"; paint_switch "$code"
  printf '  │  %-10s ' "$right_label"
  active="$(systemctl is-active "$right_unit" 2>/dev/null || true)"
  enabled="$(systemctl is-enabled "$right_unit" 2>/dev/null || true)"
  code="$(active_code "$active")"; paint_switch "$code"; printf '/'
  code="$(enabled_code "$enabled")"; paint_switch "$code"
  printf '\n'
}

short_time() {
  local value="$1"
  case "$value" in
    ''|n/a|unknown) printf '—'; return ;;
  esac
  printf '%s\n' "$value" | awk '{
    if (NF >= 3) printf "%s %s", $2, substr($3, 1, 5);
    else printf "%s", $0;
  }'
}

timer_time() {
  local unit="$1" property="$2" value
  value="$(systemctl show "$unit" --property="$property" --value 2>/dev/null || true)"
  short_time "$value"
}

system_memory_line() {
  local mem swap
  mem="$(free -b 2>/dev/null | awk '$1=="Mem:" {printf "%.1f GiB / %.1f GiB (%d%%)", $3/1073741824, $2/1073741824, ($2 ? $3*100/$2 : 0)}')"
  swap="$(free -b 2>/dev/null | awk '$1=="Swap:" {printf "%.1f GiB / %.1f GiB (%d%%)", $3/1073741824, $2/1073741824, ($2 ? $3*100/$2 : 0)}')"
  [[ -n "$mem" ]] || mem='unavailable'
  [[ -n "$swap" ]] || swap='unavailable'
  printf '  RAM   %-28s  SWAP %s\n' "$mem" "$swap"
}

system_disk_line() {
  local disk counts total
  disk="$(df -B1 --output=used,size,pcent / 2>/dev/null | awk 'NR==2 {printf "%.1f / %.1f GiB (%s)", $1/1073741824, $2/1073741824, $3}')"
  [[ -n "$disk" ]] || disk='unavailable'
  printf '  ROOT  %-33s' "$disk"
  if timeout 3 docker info >/dev/null 2>&1; then
    counts="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
    total="$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')"
    printf '  DOCKER %s running / %s total\n' "$counts" "$total"
  else
    printf '  DOCKER unavailable\n'
  fi
}

draw_rule() {
  local width="$1" rule='' idx
  for ((idx=0; idx<width; idx++)); do rule+='─'; done
  printf '%b%s%b\n' "$C_BLUE" "$rule" "$C_RESET"
}

section_title() {
  printf '\n%b▸ %s%b\n' "$C_CYAN" "$1" "$C_RESET"
}

mount_inventory_parse() {
  local now kind f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 state uuid_short row name seed_state reason
  now="$(date +%s)"
  if (( MOUNT_LAST_REFRESH > 0 && now - MOUNT_LAST_REFRESH < MOUNT_REFRESH_SECONDS )); then
    return
  fi
  MOUNT_LAST_REFRESH="$now"
  MOUNT_STATUS_OUTPUT="$(timeout 20 php "$REPO_ROOT/pterodactyl/server-mount-status.php" 2>&1)"
  local rc=$?
  if [[ "$rc" -ne 0 || "$MOUNT_STATUS_OUTPUT" != META$'\t'OK$'\t'* ]]; then
    MOUNT_STATUS_ERROR="$(printf '%s' "$MOUNT_STATUS_OUTPUT" | tr -cd '[:print:]' | cut -c1-150)"
    [[ -n "$MOUNT_STATUS_ERROR" ]] || MOUNT_STATUS_ERROR="Status command exited with code $rc."
    MOUNT_STATUS_OUTPUT=''
  else
    MOUNT_STATUS_ERROR=''
  fi

  MOUNT_ID='?'
  MOUNT_SOURCE="$PAYLOAD_ROOT"
  MOUNT_TARGET='/home/container/egg/fragcity-payload'
  MOUNT_ELIGIBLE=0; MOUNT_PANEL_ON=0; MOUNT_PANEL_OFF=0
  MOUNT_DOCKER_ON=0; MOUNT_DOCKER_OFF=0; MOUNT_PENDING=0; MOUNT_UNKNOWN=0
  MOUNT_PROCESSED=0; MOUNT_STARTUP=0
  MOUNT_SEED_PENDING=0; MOUNT_SEED_MISSING=0; MOUNT_SEED_BAD=0; MOUNT_NEW_UNREGISTERED=0
  MOUNT_ACTIVE_COUNT=0
  MOUNT_INACTIVE_NAMES=''; MOUNT_ACTIVE_ROWS=''; MOUNT_ATTENTION_ROWS=''
  MOUNT_ATTENTION_EXTRA=0; MOUNT_EXTRA_ACTIVE=0

  [[ -n "$MOUNT_STATUS_OUTPUT" ]] || return
  while IFS= read -r row; do
    IFS=$'\t' read -r kind f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 <<< "$row"
    case "$kind" in
      META)
        MOUNT_ID="$f2"; MOUNT_SOURCE="$f3"; MOUNT_TARGET="$f4"
        ;;
      SERVER)
        uuid_short="$(printf '%s' "$f1" | cut -c1-8)"
        name="$(printf '%s' "$f2" | tr -cd '[:print:]' | cut -c1-20)"
        state="$f4"
        seed_state="$f9"
        reason=''
        if [[ "$f8" == OFF && "$f6" != ON ]]; then
          MOUNT_NEW_UNREGISTERED=$((MOUNT_NEW_UNREGISTERED + 1))
          reason='NEW-NOT-REGISTERED'
        elif [[ "$seed_state" == PENDING ]]; then
          reason='SEED-PENDING'
        elif [[ "$seed_state" == MISSING ]]; then
          reason='SEED-MISSING'
        elif [[ "$seed_state" == BAD || "$seed_state" == UNSAFE ]]; then
          reason='SEED-ERROR'
        fi
        if [[ -n "$reason" ]]; then
          if (( MOUNT_ATTENTION_EXTRA < 5 )); then
            MOUNT_ATTENTION_ROWS+="$(printf '  %-8s %-20s %-20s base=%-3s proc=%-3s seed=%-8s state=%s\n' "$uuid_short" "$name" "$reason" "$f8" "$f6" "$seed_state" "$state")"
            MOUNT_ATTENTION_EXTRA=$((MOUNT_ATTENTION_EXTRA + 1))
          fi
        fi

        if [[ "$f5" == ON && "$state" == RUNNING ]]; then
          MOUNT_ACTIVE_COUNT=$((MOUNT_ACTIVE_COUNT + 1))
          if (( MOUNT_ACTIVE_COUNT <= 5 )); then
            MOUNT_ACTIVE_ROWS+="$(printf '  %-8s %-20s %-9s %-6s %-7s %-6s %-7s %-6s %-8s\n' "$uuid_short" "$name" "$state" "$f3" "$f5" "$f6" "$f7" "$f8" "$seed_state")"
          else
            MOUNT_EXTRA_ACTIVE=$((MOUNT_EXTRA_ACTIVE + 1))
          fi
        elif [[ "$f5" == ON ]]; then
          if [[ -n "$MOUNT_INACTIVE_NAMES" ]]; then MOUNT_INACTIVE_NAMES+=", "; fi
          MOUNT_INACTIVE_NAMES+="$name ($state)"
        fi
        ;;
      SUMMARY)
        MOUNT_ELIGIBLE="$f1"; MOUNT_PANEL_ON="$f2"; MOUNT_PANEL_OFF="$f3"
        MOUNT_DOCKER_ON="$f4"; MOUNT_DOCKER_OFF="$f5"
        MOUNT_PENDING="$f6"; MOUNT_UNKNOWN="$f7"
        MOUNT_PROCESSED="$f8"; MOUNT_STARTUP="$f9"
        MOUNT_SEED_PENDING="$f10"; MOUNT_SEED_MISSING="$f11"; MOUNT_SEED_BAD="$f12"
        ;;
    esac
  done <<< "$MOUNT_STATUS_OUTPUT"
}

render_mount_section() {
  section_title "ACTIVE MOUNTED SERVERS  ·  REAL DOCKER STATE"
  if [[ -z "$MOUNT_STATUS_OUTPUT" ]]; then
    printf '  %bINVENTORY UNAVAILABLE%b  %s\n' "$C_RED" "$C_RESET" "$MOUNT_STATUS_ERROR"
    printf '  The read-only check validates Panel assignment and Docker source/target/read-only flags.\n'
    return
  fi
  printf '  Active %b%d%b  │ Mounted %d  │ Eligible %d  │ Panel ON %d  │ Docker pending %d  │ Unknown %d\n' \
    "$C_GREEN" "$MOUNT_ACTIVE_COUNT" "$C_RESET" "$MOUNT_DOCKER_ON" "$MOUNT_ELIGIBLE" "$MOUNT_PANEL_ON" "$MOUNT_PENDING" "$MOUNT_UNKNOWN"
  printf '  First-install: pending=%s  missing(new)=%s  invalid=%s  new/unregistered=%s\n' \
    "$MOUNT_SEED_PENDING" "$MOUNT_SEED_MISSING" "$MOUNT_SEED_BAD" "$MOUNT_NEW_UNREGISTERED"
  printf '  UUID     SERVER NAME          STATE     PANEL  DOCKER  PROC   STARTUP BASE   SEED\n'
  if [[ -n "$MOUNT_ACTIVE_ROWS" ]]; then
    printf '%s' "$MOUNT_ACTIVE_ROWS"
    if (( MOUNT_EXTRA_ACTIVE > 0 )); then printf '  ... plus %d more active mounted server(s)\n' "$MOUNT_EXTRA_ACTIVE"; fi
  else
    printf '  %bNo running container currently has the actual FragCity Docker Mount.%b\n' "$C_YELLOW" "$C_RESET"
  fi
  if [[ -n "$MOUNT_ATTENTION_ROWS" ]]; then
    printf '  %bFirst-install / registration attention:%b\n' "$C_YELLOW" "$C_RESET"
    printf '  UUID     SERVER NAME          REASON               BASE PROC SEED     STATE\n'
    printf '%s' "$MOUNT_ATTENTION_ROWS"
    if (( MOUNT_NEW_UNREGISTERED > 5 )); then
      printf '  ... plus %d more new/unregistered server(s)\n' "$((MOUNT_NEW_UNREGISTERED - 5))"
    fi
  fi
  if [[ -n "$MOUNT_INACTIVE_NAMES" ]]; then
    printf '  %bMounted but not active:%b %s\n' "$C_YELLOW" "$C_RESET" "$(printf '%s' "$MOUNT_INACTIVE_NAMES" | cut -c1-70)"
  fi
  printf '  Mount #%s  ·  read-only target: %s\n' "$MOUNT_ID" "$MOUNT_TARGET"
}

latest_event() {
  local unit="$1" limit="$2" message
  message="$(journalctl -u "$unit" -n 1 --no-pager -o cat 2>/dev/null | awk -v width="$limit" 'NR==1 {gsub(/[[:cntrl:]]/, " "); if (length($0)>width) print substr($0,1,width-3)"..."; else print; exit}')"
  [[ -n "$message" ]] || message='No journal entry yet.'
  printf '%s' "$message"
}

render_dashboard() {
  local width="$1" hostname_label timestamp load cores uptime_value source_commit payload_commit marker
  hostname_label="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown-node')"
  timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  load="$(awk '{print $1" / "$2" / "$3}' /proc/loadavg 2>/dev/null)"
  cores="$(nproc 2>/dev/null || printf '?')"
  uptime_value="$(uptime -p 2>/dev/null | sed 's/^up //')"
  source_commit="$(git -C "$REPO_ROOT" rev-parse --short=12 HEAD 2>/dev/null || printf 'unavailable')"
  payload_commit="$(tr -d '\r\n' < "$PAYLOAD_ROOT/CURRENT_COMMIT" 2>/dev/null | cut -c1-12)"
  [[ -n "$payload_commit" ]] || payload_commit='MISSING'
  if [[ -r "$PAYLOAD_ROOT/revisions/$payload_commit/.source-commit" ]] &&
     [[ "$(tr -d '\r\n' < "$PAYLOAD_ROOT/revisions/$payload_commit/.source-commit" 2>/dev/null)" == "$(tr -d '\r\n' < "$PAYLOAD_ROOT/CURRENT_COMMIT" 2>/dev/null)" ]]; then
    marker='MATCH'
  else
    marker='CHECK'
  fi

  draw_rule "$width"
  printf '%bFRAGCITY%b  /  %bLIVE NODE MONITOR%b\n' "$C_WHITE" "$C_RESET" "$C_CYAN" "$C_RESET"
  printf '  NODE %-20.20s  ·  %s  ·  refresh %ss  ·  UI %s\n' "$hostname_label" "$timestamp" "$REFRESH_SECONDS" "$UI_VERSION"
  draw_rule "$width"

  section_title "HOST HEALTH"
  printf '  CPU load %-23s  cores %s\n' "$load" "$cores"
  system_memory_line
  system_disk_line
  printf '  UPTIME  %-68.68s\n' "$uptime_value"

  section_title "SERVICE HEALTH  ·  ACTIVE / ENABLED AT BOOT"
  show_service_triplet Docker docker.service Wings wings.service Nginx nginx.service
  show_service_triplet PHP-FPM php8.3-fpm.service PanelQ pteroq.service MariaDB mariadb.service
  show_service_triplet Redis redis-server.service SyncT fragcity-addon-payload-sync.timer ProvT fragcity-addon-provision.timer

  section_title "AUTOMATION / PUBLISH STATUS"
  printf '  Source %s  │  Published %s  │  Revision marker ' "$source_commit" "$payload_commit"
  if [[ "$marker" == MATCH ]]; then paint_switch ON; else paint_switch CHECK; fi
  printf '\n'
  printf '  Sync timer: next %-16s last %-16s\n' \
    "$(timer_time fragcity-addon-payload-sync.timer NextElapseUSecRealtime)" \
    "$(timer_time fragcity-addon-payload-sync.timer LastTriggerUSec)"
  printf '  Watch timer: next %-16s last %-16s\n' \
    "$(timer_time fragcity-addon-provision.timer NextElapseUSecRealtime)" \
    "$(timer_time fragcity-addon-provision.timer LastTriggerUSec)"
  local baseline_count processed_count last_sync last_provision
  if [[ -r "$STATE_ROOT/baseline-uuids.txt" ]]; then
    baseline_count="$(grep -Ec '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' "$STATE_ROOT/baseline-uuids.txt" 2>/dev/null || true)"
    [[ -n "$baseline_count" ]] || baseline_count=0
  else
    baseline_count='MISSING'
  fi
  if [[ -d "$STATE_ROOT/processed" ]]; then
    processed_count="$(find "$STATE_ROOT/processed" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  else
    processed_count=0
  fi
  printf '  Baseline %s UUIDs  │  Processed markers %s\n' "$baseline_count" "$processed_count"
  last_sync="$(systemctl show fragcity-addon-payload-sync.service --property=Result --value 2>/dev/null || printf 'unknown')"
  last_provision="$(systemctl show fragcity-addon-provision.service --property=Result --value 2>/dev/null || printf 'unknown')"
  printf '  Last run result: sync %-9s  │  provisioner %s\n' "$last_sync" "$last_provision"

  render_mount_section

  section_title "NETWORK SNAPSHOT"
  printf '  IPv4  %s\n' "$(ip -o -4 addr show scope global 2>/dev/null | awk '{gsub(/\/.*/, "", $4); printf "%s=%s ", $2, $4}' | cut -c1-70)"
  local game_ports web_ports
  game_ports="$(ss -H -lun 2>/dev/null | awk '{print $5}' | grep -E ':(29[0-9]{3})$' | head -n 4 | paste -sd ', ' -)"
  web_ports="$(ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -E ':(80|443)$' | paste -sd ', ' -)"
  [[ -n "$game_ports" ]] || game_ports='none detected in UDP 29xxx range'
  [[ -n "$web_ports" ]] || web_ports='none detected'
  printf '  Game UDP  %s\n' "$(printf '%s' "$game_ports" | cut -c1-70)"
  printf '  HTTP      %s\n' "$(printf '%s' "$web_ports" | cut -c1-70)"

  section_title "LATEST AUTOMATION EVENTS"
  printf '  SYNC  %s\n' "$(latest_event fragcity-addon-payload-sync.service 70)"
  printf '  WATCH %s\n' "$(latest_event fragcity-addon-provision.service 70)"
  draw_rule "$width"
  printf '  %bLIVE%b  host checks %ss  ·  Panel/Docker Mount scan %ss  ·  Ctrl+C closes window\n' \
    "$C_GREEN" "$C_RESET" "$REFRESH_SECONDS" "$MOUNT_REFRESH_SECONDS"
  printf '  %bRead-only monitor: closing this window does not stop or disable systemd timers.%b\n' "$C_DIM" "$C_RESET"
}

if [[ -t 1 ]]; then
  cols="$(tput cols 2>/dev/null || printf '80')"
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  WIDTH=$((cols - 2))
  (( WIDTH < 72 )) && WIDTH=72
  (( WIDTH > 116 )) && WIDTH=116
  printf '\033[2J\033[H'
else
  WIDTH=78
fi

while true; do
  mount_inventory_parse
  FRAME="$(render_dashboard "$WIDTH")"
  # Home-and-overwrite redraw avoids repeated full-screen clear/flicker.
  # Clear each printed line and the remaining screen to prevent stale characters.
  if [[ -t 1 ]]; then printf '\033[H'; fi
  while IFS= read -r frame_line; do
    if [[ -t 1 ]]; then printf '%s\033[K\n' "$frame_line"; else printf '%s\n' "$frame_line"; fi
  done <<< "$FRAME"
  if [[ -t 1 ]]; then printf '\033[J'; fi
  sleep "$REFRESH_SECONDS"

  # The publisher replaces this file atomically after a successful fetch.
  current_sha="$(sha256sum -- "$SELF_PATH" 2>/dev/null | awk '{print $1}')"
  if [[ -n "$current_sha" && "$current_sha" != "$STARTUP_SHA" ]]; then
    printf '\n%bLIVE UPDATE DETECTED%b — launching the refreshed monitor...\n' "$C_GREEN" "$C_RESET"
    sleep 1
    exec /bin/bash "$SELF_PATH" "$@"
  fi
done
