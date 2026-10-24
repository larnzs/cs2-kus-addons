#!/usr/bin/env bash
# Read-only live dashboard for the FragCity Pterodactyl systemd timers.
set -u

PAYLOAD_ROOT="${FRAGCITY_PAYLOAD_SOURCE:-/var/lib/pterodactyl/mounts/fragcity-addon-payload}"
STATE_ROOT="${FRAGCITY_PROVISIONER_STATE:-/var/lib/pterodactyl/fragcity-addon-provisioner}"
REFRESH_SECONDS="${FRAGCITY_STATUS_REFRESH_SECONDS:-5}"
SERVICES=(
  fragcity-addon-payload-sync.service
  fragcity-addon-provision.service
)
TIMERS=(
  fragcity-addon-payload-sync.timer
  fragcity-addon-provision.timer
)

[[ "$REFRESH_SECONDS" =~ ^[1-9][0-9]*$ ]] || REFRESH_SECONDS=5

unit_exists() {
  systemctl cat "$1" >/dev/null 2>&1
}

show_unit() {
  local unit="$1" active enabled
  if ! unit_exists "$unit"; then
    printf '  %-42s %s\n' "$unit" 'NOT INSTALLED'
    return
  fi
  active="$(systemctl is-active "$unit" 2>/dev/null || true)"
  enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  printf '  %-42s active=%-10s enabled=%s\n' "$unit" "${active:-unknown}" "${enabled:-unknown}"
}

show_service_details() {
  local unit="$1"
  printf '\n--- %s ---\n' "$unit"
  if unit_exists "$unit"; then
    systemctl show "$unit" --no-pager \
      -p LoadState -p ActiveState -p SubState -p Result -p ExecMainStatus -p ExecMainStartTimestamp \
      2>/dev/null | sed 's/^/  /'
    local entries
    entries="$(journalctl -u "$unit" -n 7 --no-pager -o short-iso 2>/dev/null || true)"
    if [[ -n "$entries" ]]; then
      printf '%s\n' "$entries"
    else
      printf '  No readable journal entries yet (or this desktop user lacks journal access).\n'
    fi
  else
    printf '  Unit is not installed; install-host-services.sh has not installed it.\n'
  fi
}

while true; do
  clear 2>/dev/null || true
  printf '============================================================\n'
  printf ' FragCity | Pterodactyl automation status\n'
  printf ' Refreshed: %s | Refresh: %ss | Ctrl+C closes this window\n' "$(date '+%F %T %Z')" "$REFRESH_SECONDS"
  printf '============================================================\n'

  printf '\n[SERVICES]\n'
  for unit in "${SERVICES[@]}"; do show_unit "$unit"; done
  printf '\n[TIMERS]\n'
  for unit in "${TIMERS[@]}"; do show_unit "$unit"; done

  printf '\n[NEXT / LAST TIMER RUNS]\n'
  if systemctl cat "${TIMERS[0]}" >/dev/null 2>&1 || systemctl cat "${TIMERS[1]}" >/dev/null 2>&1; then
    systemctl list-timers --all --no-pager "${TIMERS[@]}" 2>&1 | sed 's/^/  /'
  else
    printf '  No FragCity timers are installed.\n'
  fi

  printf '\n[PAYLOAD]\n'
  if [[ -r "$PAYLOAD_ROOT/CURRENT_COMMIT" ]]; then
    commit="$(tr -d '\r\n' < "$PAYLOAD_ROOT/CURRENT_COMMIT")"
    printf '  Published commit: %s\n' "$commit"
    if [[ -r "$PAYLOAD_ROOT/revisions/$commit/.source-commit" ]]; then
      marker="$(tr -d '\r\n' < "$PAYLOAD_ROOT/revisions/$commit/.source-commit")"
      printf '  Revision marker:  %s\n' "$marker"
      [[ "$marker" == "$commit" ]] || printf '  WARNING: CURRENT_COMMIT and revision marker differ.\n'
    else
      printf '  WARNING: published revision marker is missing.\n'
    fi
  else
    printf '  Published payload is missing: %s\n' "$PAYLOAD_ROOT"
  fi

  printf '\n[PROVISIONER STATE]\n'
  baseline="$STATE_ROOT/baseline-uuids.txt"
  if [[ -r "$baseline" ]]; then
    baseline_count="$(grep -Ec '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' "$baseline" 2>/dev/null || true)"
    printf '  Baseline UUIDs: %s\n' "${baseline_count:-0}"
  else
    printf '  Baseline: MISSING (watcher cannot run safely)\n'
  fi
  if [[ -d "$STATE_ROOT/processed" ]]; then
    processed_count="$(find "$STATE_ROOT/processed" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l)"
  else
    processed_count=0
  fi
  printf '  Processed server markers: %s\n' "$processed_count"

  show_service_details "${SERVICES[0]}"
  show_service_details "${SERVICES[1]}"

  printf '\nRefreshing in %s seconds...\n' "$REFRESH_SECONDS"
  sleep "$REFRESH_SECONDS"
done
