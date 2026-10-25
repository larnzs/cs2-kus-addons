#!/usr/bin/env bash
# FragCity node monitor: concise health posture, structured service tables and verified Pterodactyl Mounts.
# The host publisher installs this file atomically; an open dashboard reloads when its checksum changes.
set -o pipefail

PAYLOAD_ROOT="$(printenv FRAGCITY_PAYLOAD_SOURCE 2>/dev/null || true)"
STATE_ROOT="$(printenv FRAGCITY_PROVISIONER_STATE 2>/dev/null || true)"
REPO_ROOT="$(printenv FRAGCITY_REPO_ROOT 2>/dev/null || true)"
REFRESH_SECONDS="$(printenv FRAGCITY_STATUS_REFRESH_SECONDS 2>/dev/null || true)"
MOUNT_REFRESH_SECONDS="$(printenv FRAGCITY_STATUS_MOUNT_REFRESH_SECONDS 2>/dev/null || true)"
[[ -n "$PAYLOAD_ROOT" ]] || PAYLOAD_ROOT="/var/lib/pterodactyl/mounts/fragcity-addon-payload"
[[ -n "$STATE_ROOT" ]] || STATE_ROOT="/var/lib/pterodactyl/fragcity-addon-provisioner"
[[ -n "$REPO_ROOT" ]] || REPO_ROOT="/opt/fragcity/cs2-kus-addons"
[[ "$REFRESH_SECONDS" =~ ^[1-9][0-9]*$ ]] || REFRESH_SECONDS=5
[[ "$MOUNT_REFRESH_SECONDS" =~ ^[5-9]$|^[1-9][0-9]+$ ]] || MOUNT_REFRESH_SECONDS=5
UI_VERSION="6.1-monitor-health-and-node-scope"
SELF_PATH="$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")"

if [[ "$(id -u)" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1 && [[ -t 0 ]]; then
    exec sudo -E /bin/bash "$SELF_PATH" "$@"
  fi
  printf 'FragCity dashboard requires root access to inspect Panel data and Docker Mounts.\n'
  printf 'Launch it from an interactive terminal with sudo.\n'
  exit 1
fi

MONITOR_MODEL_PATH="$REPO_ROOT/pterodactyl/fragcity-monitor-model.sh"
if [[ ! -r "$MONITOR_MODEL_PATH" ]]; then
  printf 'FragCity monitor model is missing: %s\n' "$MONITOR_MODEL_PATH" >&2
  exit 1
fi
# Shared pure classifier; this file only reads and displays status.
source "$MONITOR_MODEL_PATH"

TERM_VALUE="$(printenv TERM 2>/dev/null || printf 'dumb')"
NO_COLOR_VALUE="$(printenv NO_COLOR 2>/dev/null || true)"
if [[ -t 1 && -z "$NO_COLOR_VALUE" && "$TERM_VALUE" != "dumb" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
  C_BLUE=$'\033[1;34m'; C_CYAN=$'\033[1;36m'; C_WHITE=$'\033[1;37m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''
  C_BLUE=''; C_CYAN=''; C_WHITE=''
fi

monitor_code_sha() {
  { sha256sum -- "$SELF_PATH" 2>/dev/null; sha256sum -- "$MONITOR_MODEL_PATH" 2>/dev/null; } |
    sha256sum 2>/dev/null | awk '{print $1}'
}
STARTUP_SHA="$(monitor_code_sha)"
MOUNT_STATUS_OUTPUT=''
MOUNT_STATUS_ERROR=''
MOUNT_LAST_REFRESH=0
MOUNT_ID='?'
MOUNT_REGISTRY='?'
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
MOUNT_INACTIVE_COUNT=0
MOUNT_ATTENTION_TOTAL=0
MOUNT_CRITICAL_SERVER_COUNT=0
MOUNT_EXTRA_ACTIVE=0
MOUNT_EXTRA_INACTIVE=0
MOUNT_EXTRA_ATTENTION=0
MOUNT_SERVER_COUNT=0
MOUNT_CURRENT_PANEL=0
MOUNT_ORPHAN_COUNT=0
MOUNT_STALE_BASELINE_COUNT=0
MOUNT_STALE_MARKER_COUNT=0
MOUNT_CONTAINER_MISSING=0
MOUNT_DOCKER_SCAN='UNKNOWN'
MOUNT_SERVER_ROWS=''
MOUNT_ORPHAN_ROWS=''
MOUNT_STALE_BASELINE_ROWS=''
MOUNT_STALE_MARKER_ROWS=''

paint_switch() {
  case "$1" in
    ON|OK|READY|MATCH|HEALTHY|active|activating|reloading|enabled|enabled-runtime|linked|linked-runtime|alias)
      printf '%b%s%b' "$C_GREEN" "$1" "$C_RESET" ;;
    FAIL|CRITICAL|ERROR|MISS|MISSING|STALE|INVALID|UNSAFE|failed|not-found)
      printf '%b%s%b' "$C_RED" "$1" "$C_RESET" ;;
    *)
      printf '%b%s%b' "$C_YELLOW" "$1" "$C_RESET" ;;
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

show_service_row() {
  local label="$1" unit="$2" active enabled
  active="$(systemctl is-active "$unit" 2>/dev/null || true)"
  enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  [[ -n "$active" ]] || active='unknown'
  [[ -n "$enabled" ]] || enabled='unknown'
  printf '  %-22s ' "$label"
  paint_switch "$(active_code "$active")"
  printf '       '
  paint_switch "$(enabled_code "$enabled")"
  printf '       %s\n' "$unit"
}

short_time() {
  local value="$1"
  case "$value" in ''|n/a|unknown) printf '—'; return ;; esac
  printf '%s\n' "$value" | awk '{ if (NF >= 3) printf "%s %s", $2, substr($3, 1, 5); else printf "%s", $0; }'
}
timer_time() {
  local unit="$1" property="$2" value
  value="$(systemctl show "$unit" --property="$property" --value 2>/dev/null || true)"
  short_time "$value"
}

system_memory_line() {
  local mem swap
  mem="$(free -b 2>/dev/null | awk '$1=="Mem:" {printf "%.1f / %.1f GiB (%d%%)", $3/1073741824, $2/1073741824, ($2 ? $3*100/$2 : 0)}')"
  swap="$(free -b 2>/dev/null | awk '$1=="Swap:" {printf "%.1f / %.1f GiB (%d%%)", $3/1073741824, $2/1073741824, ($2 ? $3*100/$2 : 0)}')"
  [[ -n "$mem" ]] || mem='unavailable'
  [[ -n "$swap" ]] || swap='unavailable'
  printf '  RAM       %-27s  SWAP %s\n' "$mem" "$swap"
}
system_disk_line() {
  local disk running total
  disk="$(df -B1 --output=used,size,pcent / 2>/dev/null | awk 'NR==2 {printf "%.1f / %.1f GiB (%s)", $1/1073741824, $2/1073741824, $3}')"
  [[ -n "$disk" ]] || disk='unavailable'
  printf '  ROOT FS   %s\n' "$disk"
  if timeout 3 docker info >/dev/null 2>&1; then
    running="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
    total="$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')"
    printf '  DOCKER    %s running / %s total containers\n' "$running" "$total"
  else
    printf '  DOCKER    unavailable\n'
  fi
}

draw_rule() {
  local width="$1" rule='' idx
  for ((idx=0; idx<width; idx++)); do rule+='─'; done
  printf '%b%s%b\n' "$C_BLUE" "$rule" "$C_RESET"
}
section_title() { printf '\n%b▸ %s%b\n' "$C_CYAN" "$1" "$C_RESET"; }

mount_inventory_parse() {
  local now kind f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 f13 f14 f15 f16
  local state name seed_state reason severity rc row
  now="$(date +%s)"
  if (( MOUNT_LAST_REFRESH > 0 && now - MOUNT_LAST_REFRESH < MOUNT_REFRESH_SECONDS )); then return; fi
  MOUNT_LAST_REFRESH="$now"

  # Capture the process status before running any other shell command.
  MOUNT_STATUS_OUTPUT="$(timeout 20 php "$REPO_ROOT/pterodactyl/server-mount-status.php" 2>&1)"
  rc=$?
  if [[ "$rc" -ne 0 || "$MOUNT_STATUS_OUTPUT" != META$'\t'OK$'\t'* ]]; then
    MOUNT_STATUS_ERROR="$(printf '%s' "$MOUNT_STATUS_OUTPUT" | tr -cd '[:print:]' | cut -c1-180)"
    [[ -n "$MOUNT_STATUS_ERROR" ]] || MOUNT_STATUS_ERROR="Status command exited with code $rc."
    MOUNT_STATUS_OUTPUT=''
  else
    MOUNT_STATUS_ERROR=''
  fi

  MOUNT_ID='?'; MOUNT_REGISTRY='?'; MOUNT_TARGET='/home/container/egg/fragcity-payload'
  MOUNT_ELIGIBLE=0; MOUNT_PANEL_ON=0; MOUNT_PANEL_OFF=0
  MOUNT_DOCKER_ON=0; MOUNT_DOCKER_OFF=0; MOUNT_PENDING=0; MOUNT_UNKNOWN=0
  MOUNT_PROCESSED=0; MOUNT_STARTUP=0
  MOUNT_SEED_PENDING=0; MOUNT_SEED_MISSING=0; MOUNT_SEED_BAD=0; MOUNT_NEW_UNREGISTERED=0
  MOUNT_ACTIVE_COUNT=0; MOUNT_INACTIVE_COUNT=0; MOUNT_ATTENTION_TOTAL=0
  MOUNT_CRITICAL_SERVER_COUNT=0
  MOUNT_EXTRA_ACTIVE=0; MOUNT_EXTRA_INACTIVE=0; MOUNT_EXTRA_ATTENTION=0
  MOUNT_SERVER_COUNT=0; MOUNT_CURRENT_PANEL=0
  MOUNT_ORPHAN_COUNT=0; MOUNT_STALE_BASELINE_COUNT=0; MOUNT_STALE_MARKER_COUNT=0
  MOUNT_CONTAINER_MISSING=0; MOUNT_DOCKER_SCAN='UNKNOWN'
  MOUNT_SERVER_ROWS=''; MOUNT_ORPHAN_ROWS=''; MOUNT_STALE_BASELINE_ROWS=''; MOUNT_STALE_MARKER_ROWS=''
  [[ -n "$MOUNT_STATUS_OUTPUT" ]] || return

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS=$'\t' read -r kind f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 f13 f14 f15 f16 <<< "$row"
    case "$kind" in
      META)
        MOUNT_ID="$f2"; MOUNT_TARGET="$f4"; MOUNT_REGISTRY="$f5"
        ;;
      SERVER)
        MOUNT_SERVER_COUNT=$((MOUNT_SERVER_COUNT + 1))
        name="$(printf '%s' "$f2" | tr -cd '[:print:]' | cut -c1-54)"
        state="$f4"; seed_state="$f9"

        # Counters are independent of the primary displayed health reason.
        # This prevents the seed classifier from hiding a genuinely missing
        # container or under-counting a new UUID with no processed marker.
        [[ "$seed_state" == PENDING ]] && MOUNT_SEED_PENDING=$((MOUNT_SEED_PENDING + 1))
        if [[ "$seed_state" == MISSING && "$f8" != ON ]]; then
          MOUNT_SEED_MISSING=$((MOUNT_SEED_MISSING + 1))
        fi
        if [[ "$seed_state" == BAD || "$seed_state" == UNSAFE ]]; then
          MOUNT_SEED_BAD=$((MOUNT_SEED_BAD + 1))
        fi
        if fragcity_is_new_unregistered "$f8" "$f6"; then
          MOUNT_NEW_UNREGISTERED=$((MOUNT_NEW_UNREGISTERED + 1))
        fi
        if [[ "$state" == ABSENT || "$f5" == PENDING ]]; then
          MOUNT_CONTAINER_MISSING=$((MOUNT_CONTAINER_MISSING + 1))
        fi

        reason="$(fragcity_classify_server "$f3" "$state" "$f5" "$f6" "$f7" "$f8" "$seed_state")"
        severity="$(fragcity_server_severity "$reason")"
        if [[ "$reason" != OK ]]; then
          MOUNT_ATTENTION_TOTAL=$((MOUNT_ATTENTION_TOTAL + 1))
        fi
        if [[ "$severity" == CRITICAL ]]; then
          MOUNT_CRITICAL_SERVER_COUNT=$((MOUNT_CRITICAL_SERVER_COUNT + 1))
        fi

        if [[ "$f5" == ON && "$state" == RUNNING ]]; then
          MOUNT_ACTIVE_COUNT=$((MOUNT_ACTIVE_COUNT + 1))
        elif [[ "$f5" == ON ]]; then
          MOUNT_INACTIVE_COUNT=$((MOUNT_INACTIVE_COUNT + 1))
        fi

        # One server per block, full UUID on its own line: no wrapped columns or
        # ambiguous ON/OFF fields when the terminal is narrower than the old table.
        MOUNT_SERVER_ROWS+="$(printf '  UUID      %s\n    NAME      %s\n    CONTAINER %s  |  PANEL MOUNT %s  |  DOCKER MOUNT %s\n    PROCESSED %s  |  STARTUP HOOK %s  |  BASELINE %s  |  FIRST SEED %s\n    HEALTH    %s  (%s)\n\n' \
          "$f1" "$name" "$state" "$f3" "$f5" "$f6" "$f7" "$f8" "$seed_state" "$severity" "$reason")"$'\n\n'
        ;;
      ORPHAN_CONTAINER)
        MOUNT_ORPHAN_ROWS+="$(printf '  UUID      %s  |  CONTAINER STATE %s  |  REASON %s\n' "$f1" "$f2" "$f3")"$'\n'
        ;;
      STALE_BASELINE)
        MOUNT_STALE_BASELINE_ROWS+="$(printf '  %s  (historical baseline; reason %s)\n' "$f1" "$f2")"$'\n'
        ;;
      STALE_MARKER)
        MOUNT_STALE_MARKER_ROWS+="$(printf '  %s  (historical processed marker; reason %s)\n' "$f1" "$f2")"$'\n'
        ;;
      DOCKER_SCAN)
        MOUNT_DOCKER_SCAN="$f1"
        ;;
      SUMMARY)
        MOUNT_ELIGIBLE="$f1"; MOUNT_PANEL_ON="$f2"; MOUNT_PANEL_OFF="$f3"
        MOUNT_DOCKER_ON="$f4"; MOUNT_DOCKER_OFF="$f5"
        MOUNT_PENDING="$f6"; MOUNT_UNKNOWN="$f7"
        MOUNT_PROCESSED="$f8"; MOUNT_STARTUP="$f9"
        MOUNT_SEED_PENDING="$f10"; MOUNT_SEED_MISSING="$f11"; MOUNT_SEED_BAD="$f12"
        MOUNT_CURRENT_PANEL="$f13"; MOUNT_ORPHAN_COUNT="$f14"
        MOUNT_STALE_BASELINE_COUNT="$f15"; MOUNT_STALE_MARKER_COUNT="$f16"
        ;;
    esac
  done <<< "$MOUNT_STATUS_OUTPUT"
}

render_mount_section() {
  section_title "CURRENT ELIGIBLE SERVER INVENTORY  ·  LIVE PANEL UUIDS"
  if [[ -z "$MOUNT_STATUS_OUTPUT" ]]; then
    printf '  STATUS: '; paint_switch CRITICAL; printf '  %s\n' "$MOUNT_STATUS_ERROR"
    printf '  Inventory could not be read; no cached/old UUID list is presented as current.\n'
    return
  fi

  printf '  Panel UUIDs total: %s  |  Eligible for this Mount: %s  |  Mounted + running: %s  |  Mounted + stopped: %s\n' \
    "$MOUNT_CURRENT_PANEL" "$MOUNT_ELIGIBLE" "$MOUNT_ACTIVE_COUNT" "$MOUNT_INACTIVE_COUNT"
  printf '  Panel Mount ON/OFF: %s/%s  |  Docker Mount ON/OFF: %s/%s  |  no container: %s  |  unknown: %s\n' \
    "$MOUNT_PANEL_ON" "$MOUNT_PANEL_OFF" "$MOUNT_DOCKER_ON" "$MOUNT_DOCKER_OFF" "$MOUNT_CONTAINER_MISSING" "$MOUNT_UNKNOWN"
  printf '  First seed: pending=%s missing=%s invalid=%s new/unregistered=%s attention=%s\n' \
    "$MOUNT_SEED_PENDING" "$MOUNT_SEED_MISSING" "$MOUNT_SEED_BAD" "$MOUNT_NEW_UNREGISTERED" "$MOUNT_ATTENTION_TOTAL"
  printf '  Mount #%s  |  baseline registry: %s  |  Docker scan: ' "$MOUNT_ID" "$MOUNT_REGISTRY"
  paint_switch "$MOUNT_DOCKER_SCAN"; printf '  |  target: %s\n' "$MOUNT_TARGET"

  if [[ -n "$MOUNT_SERVER_ROWS" ]]; then
    printf '\n%s' "$MOUNT_SERVER_ROWS"
  else
    printf '  No servers currently match the configured FragCity Egg and Node.\n'
  fi

  section_title "ORPHAN DOCKER CONTAINERS  ·  UUID NOT FOUND IN PANEL"
  if [[ "$MOUNT_DOCKER_SCAN" != OK ]]; then
    printf '  STATUS: '; paint_switch ERROR
    printf '  Docker inventory scan failed; orphan count is unknown.\n'
  elif [[ -n "$MOUNT_ORPHAN_ROWS" ]]; then
    printf '%s' "$MOUNT_ORPHAN_ROWS"
  else
    printf '  None. Every UUID-named Docker container maps to a current Panel server.\n'
  fi

  section_title "STALE UUID HISTORY  ·  NOT PART OF THE CURRENT SERVER LIST"
  printf '  Baseline UUIDs absent from Panel: %s  |  Processed markers absent from Panel: %s\n' \
    "$MOUNT_STALE_BASELINE_COUNT" "$MOUNT_STALE_MARKER_COUNT"
  if [[ -n "$MOUNT_STALE_BASELINE_ROWS" ]]; then
    printf '  Historical baseline entries:\n%s' "$MOUNT_STALE_BASELINE_ROWS"
  fi
  if [[ -n "$MOUNT_STALE_MARKER_ROWS" ]]; then
    printf '  Historical processed markers:\n%s' "$MOUNT_STALE_MARKER_ROWS"
  fi
  if [[ -z "$MOUNT_STALE_BASELINE_ROWS" && -z "$MOUNT_STALE_MARKER_ROWS" ]]; then
    printf '  No stale UUID records detected.\n'
  fi
}

latest_event() {
  local unit="$1" limit="$2" message
  message="$(journalctl -u "$unit" -n 1 --no-pager -o cat 2>/dev/null |
    awk -v width="$limit" 'NR==1 {gsub(/[[:cntrl:]]/, " "); if (length($0)>width) print substr($0,1,width-3)"..."; else print; exit}')"
  [[ -n "$message" ]] || message='No journal entry yet.'
  printf '%s' "$message"
}

render_dashboard() {
  local width="$1" node timestamp load cores uptime_value checkout_full checkout_short payload_full payload_short marker
  local baseline_count processed_count sync_result provision_result game_ports web_ports
  local critical_checks warning_groups unit service_state posture

  node="$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown-node')"
  timestamp="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  load="$(awk '{print $1" / "$2" / "$3}' /proc/loadavg 2>/dev/null)"
  cores="$(nproc 2>/dev/null || printf '?')"
  uptime_value="$(uptime -p 2>/dev/null | sed 's/^up //')"
  checkout_full="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unavailable')"
  checkout_short="$(printf '%s' "$checkout_full" | cut -c1-12)"
  payload_full="$(tr -d '\r\n' < "$PAYLOAD_ROOT/CURRENT_COMMIT" 2>/dev/null)"
  [[ "$payload_full" =~ ^[0-9a-f]{40}$ ]] || payload_full='MISSING'
  payload_short="$(printf '%s' "$payload_full" | cut -c1-12)"

  if [[ "$payload_full" =~ ^[0-9a-f]{40}$ ]] &&
     [[ -r "$PAYLOAD_ROOT/revisions/$payload_full/.source-commit" ]] &&
     [[ "$(tr -d '\r\n' < "$PAYLOAD_ROOT/revisions/$payload_full/.source-commit" 2>/dev/null)" == "$payload_full" ]]; then
    if [[ "$checkout_full" == "$payload_full" ]]; then marker=MATCH; else marker=DRIFT; fi
  else
    marker=CHECK
  fi

  critical_checks=0; warning_groups=0
  for unit in docker.service wings.service nginx.service php8.3-fpm.service pteroq.service mariadb.service redis-server.service; do
    service_state="$(systemctl is-active "$unit" 2>/dev/null || true)"
    [[ "$service_state" == active ]] || critical_checks=$((critical_checks + 1))
  done
  [[ -z "$MOUNT_STATUS_ERROR" ]] || critical_checks=$((critical_checks + 1))
  [[ "$MOUNT_DOCKER_SCAN" == OK ]] || critical_checks=$((critical_checks + 1))
  [[ "$marker" == MATCH ]] || warning_groups=$((warning_groups + 1))
  [[ "$MOUNT_REGISTRY" == READY ]] || warning_groups=$((warning_groups + 1))
  if (( MOUNT_SEED_PENDING + MOUNT_SEED_MISSING + MOUNT_SEED_BAD + MOUNT_NEW_UNREGISTERED > 0 )); then
    warning_groups=$((warning_groups + 1))
  fi
  if (( MOUNT_ATTENTION_TOTAL > 0 )); then
    warning_groups=$((warning_groups + 1))
  fi
  if [[ "$MOUNT_ORPHAN_COUNT" =~ ^[1-9][0-9]*$ ]]; then
    warning_groups=$((warning_groups + 1))
  fi
  posture="$(fragcity_system_posture "$critical_checks" "$MOUNT_CRITICAL_SERVER_COUNT" "$warning_groups" "$MOUNT_ATTENTION_TOTAL")"

  draw_rule "$width"
  printf '%bFRAGCITY%b  /  %bNODE OPERATIONS CONSOLE%b\n' "$C_WHITE" "$C_RESET" "$C_CYAN" "$C_RESET"
  printf '  NODE %-20.20s  |  %s  |  refresh %ss / Mount scan %ss  |  UI %s\n' \
    "$node" "$timestamp" "$REFRESH_SECONDS" "$MOUNT_REFRESH_SECONDS" "$UI_VERSION"
  printf '  SYSTEM POSTURE: '; paint_switch "$posture"
  printf '  | critical checks: %s  | critical servers: %s  | attention groups: %s\n' \
    "$critical_checks" "$MOUNT_CRITICAL_SERVER_COUNT" "$warning_groups"
  draw_rule "$width"

  section_title "HOST HEALTH  ·  CAPACITY"
  printf '  CPU LOAD  %-28s  CORES %s\n' "$load" "$cores"
  system_memory_line
  system_disk_line
  printf '  UPTIME    %s\n' "$uptime_value"

  section_title "SERVICE HEALTH  ·  RUNTIME / BOOT POLICY"
  printf '  %-22s %-8s %-8s %s\n' 'SERVICE' 'ACTIVE' 'BOOT' 'SYSTEMD UNIT'
  printf '  %s\n' '--------------------------------------------------------------------------------------------------'
  show_service_row 'Docker Engine' docker.service
  show_service_row 'Pterodactyl Wings' wings.service
  show_service_row 'Nginx' nginx.service
  show_service_row 'PHP-FPM 8.3' php8.3-fpm.service
  show_service_row 'Panel Queue' pteroq.service
  show_service_row 'MariaDB' mariadb.service
  show_service_row 'Redis' redis-server.service
  show_service_row 'Payload Publisher' fragcity-addon-payload-sync.timer
  show_service_row 'Server Provisioner' fragcity-addon-provision.timer

  section_title "PAYLOAD & AUTOMATION  ·  REVISION INTEGRITY"
  printf '  Checkout HEAD  %s\n' "$checkout_short"
  printf '  Published      %s  |  revision integrity: ' "$payload_short"
  paint_switch "$marker"
  printf '\n'
  printf '  Payload source %s\n' "$PAYLOAD_ROOT"
  printf '  Baseline hash registry: '
  case "$MOUNT_REGISTRY" in
    READY) paint_switch READY ;;
    MISSING|NO-BASELINE) paint_switch MISSING ;;
    STALE|INVALID|UNSAFE) paint_switch FAIL ;;
    *) paint_switch UNKNOWN ;;
  esac
  printf ' (%s)\n' "$MOUNT_REGISTRY"

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
  printf '  Historical baseline entries %s  |  Processed markers on disk %s\n' "$baseline_count" "$processed_count"
  printf '  Current Panel UUIDs %s  |  baseline UUIDs absent from Panel %s  |  processed markers absent from Panel %s\n' \
    "$MOUNT_CURRENT_PANEL" "$MOUNT_STALE_BASELINE_COUNT" "$MOUNT_STALE_MARKER_COUNT"
  printf '  Payload sync   next %-16s  last %-16s  result %s\n' \
    "$(timer_time fragcity-addon-payload-sync.timer NextElapseUSecRealtime)" \
    "$(timer_time fragcity-addon-payload-sync.timer LastTriggerUSec)" \
    "$(systemctl show fragcity-addon-payload-sync.service --property=Result --value 2>/dev/null || printf 'unknown')"
  printf '  Provisioner    next %-16s  last %-16s  result %s\n' \
    "$(timer_time fragcity-addon-provision.timer NextElapseUSecRealtime)" \
    "$(timer_time fragcity-addon-provision.timer LastTriggerUSec)" \
    "$(systemctl show fragcity-addon-provision.service --property=Result --value 2>/dev/null || printf 'unknown')"

  render_mount_section

  section_title "NETWORK SNAPSHOT"
  game_ports="$(ss -H -lun 2>/dev/null | awk '{print $5}' | grep -E ':(29[0-9]{3})$' | head -n 5 | paste -sd ', ' -)"
  web_ports="$(ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -E ':(80|443)$' | paste -sd ', ' -)"
  [[ -n "$game_ports" ]] || game_ports='none detected in UDP 29xxx range'
  [[ -n "$web_ports" ]] || web_ports='none detected'
  printf '  IPv4       %s\n' "$(ip -o -4 addr show scope global 2>/dev/null | awk '{gsub(/\/.*/, "", $4); printf "%s=%s ", $2, $4}' | cut -c1-94)"
  printf '  GAME UDP   %s\n' "$(printf '%s' "$game_ports" | cut -c1-94)"
  printf '  HTTP/S     %s\n' "$(printf '%s' "$web_ports" | cut -c1-94)"

  section_title "LATEST AUTOMATION EVENTS"
  printf '  PUBLISHER  %s\n' "$(latest_event fragcity-addon-payload-sync.service 88)"
  printf '  PROVISION  %s\n' "$(latest_event fragcity-addon-provision.service 88)"
  draw_rule "$width"
  printf '  %bLIVE%b  screen refresh %ss  |  read-only Mount scan %ss  |  Ctrl+C closes this view\n' \
    "$C_GREEN" "$C_RESET" "$REFRESH_SECONDS" "$MOUNT_REFRESH_SECONDS"
  printf '  %bRead-only view: this dashboard does not restart servers, change Mounts or modify startup commands.%b\n' "$C_DIM" "$C_RESET"
}

if [[ -t 1 ]]; then
  cols="$(tput cols 2>/dev/null || printf '80')"
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  WIDTH=$((cols - 2))
  (( WIDTH < 72 )) && WIDTH=72
  (( WIDTH > 116 )) && WIDTH=116
  printf '\033[2J\033[H'
else
  WIDTH=96
fi

while true; do
  mount_inventory_parse
  FRAME="$(render_dashboard "$WIDTH")"
  if [[ -t 1 ]]; then printf '\033[H'; fi
  while IFS= read -r frame_line; do
    if [[ -t 1 ]]; then printf '%s\033[K\n' "$frame_line"; else printf '%s\n' "$frame_line"; fi
  done <<< "$FRAME"
  if [[ -t 1 ]]; then printf '\033[J'; fi
  sleep "$REFRESH_SECONDS"

  current_sha="$(monitor_code_sha)"
  if [[ -n "$current_sha" && "$current_sha" != "$STARTUP_SHA" ]]; then
    printf '\n%bLIVE UPDATE DETECTED%b — loading the refreshed monitor...\n' "$C_GREEN" "$C_RESET"
    sleep 1
    exec /bin/bash "$SELF_PATH" "$@"
  fi
done
