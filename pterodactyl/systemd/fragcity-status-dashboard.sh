#!/usr/bin/env bash
# Live, colorized FragCity dashboard. The publisher atomically replaces this file;
# the running window detects the changed checksum and execs the latest version.
set -o pipefail

PAYLOAD_ROOT="${FRAGCITY_PAYLOAD_SOURCE:-/var/lib/pterodactyl/mounts/fragcity-addon-payload}"
STATE_ROOT="${FRAGCITY_PROVISIONER_STATE:-/var/lib/pterodactyl/fragcity-addon-provisioner}"
REPO_ROOT="${FRAGCITY_REPO_ROOT:-/opt/fragcity/cs2-kus-addons}"
REFRESH_SECONDS="${FRAGCITY_STATUS_REFRESH_SECONDS:-5}"
UI_VERSION="2.0-live"

[[ "$REFRESH_SECONDS" =~ ^[1-9][0-9]*$ ]] || REFRESH_SECONDS=5
SELF_PATH="$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")"
STARTUP_SHA="$(sha256sum -- "$SELF_PATH" 2>/dev/null | awk '{print $1}')"

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
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

unit_exists() {
  systemctl cat "$1" >/dev/null 2>&1
}

print_active_switch() {
  case "$1" in
    active|activating|reloading)
      printf '%bON%b' "$C_GREEN" "$C_RESET"
      ;;
    *)
      printf '%bOFF%b' "$C_RED" "$C_RESET"
      ;;
  esac
}

print_enabled_switch() {
  case "$1" in
    enabled|enabled-runtime|linked|linked-runtime|alias)
      printf '%bON%b' "$C_GREEN" "$C_RESET"
      ;;
    *)
      printf '%bOFF%b' "$C_RED" "$C_RESET"
      ;;
  esac
}

section() {
  printf '\n%b┌─ %s ─%b\n' "$C_CYAN" "$1" "$C_RESET"
}

show_unit() {
  local unit="$1" kind="$2" active enabled
  if ! unit_exists "$unit"; then
    printf '  %b%-39s NOT INSTALLED%b\n' "$C_RED" "$unit" "$C_RESET"
    return
  fi

  active="$(systemctl is-active "$unit" 2>/dev/null || true)"
  enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"

  printf '  %-39s ' "$unit"
  printf 'active='
  print_active_switch "$active"
  printf '   enabled='
  print_enabled_switch "$enabled"

  if [[ "$kind" == "oneshot" && "$active" != "active" ]]; then
    printf '   %b(idle between runs is normal)%b' "$C_DIM" "$C_RESET"
  fi
  printf '\n'
}

show_service_details() {
  local unit="$1" result exit_status start_time entries
  printf '\n%b%s%b\n' "$C_MAGENTA" "  ── $unit ──" "$C_RESET"

  if ! unit_exists "$unit"; then
    printf '  %bUnit is not installed.%b\n' "$C_RED" "$C_RESET"
    return
  fi

  result="$(systemctl show "$unit" --property=Result --value 2>/dev/null || true)"
  exit_status="$(systemctl show "$unit" --property=ExecMainStatus --value 2>/dev/null || true)"
  start_time="$(systemctl show "$unit" --property=ExecMainStartTimestamp --value 2>/dev/null || true)"
  [[ -n "$result" ]] || result="unknown"
  [[ -n "$exit_status" ]] || exit_status="unknown"
  [[ -n "$start_time" ]] || start_time="not recorded"

  printf '  last result: '
  case "$result" in
    success)
      printf '%bSUCCESS%b' "$C_GREEN" "$C_RESET"
      ;;
    failed)
      printf '%bFAILED%b' "$C_RED" "$C_RESET"
      ;;
    *)
      printf '%b%s%b' "$C_YELLOW" "$result" "$C_RESET"
      ;;
  esac
  printf '   exit=%s\n' "$exit_status"
  printf '  last start: %s\n' "$start_time"

  entries="$(journalctl -u "$unit" -n 5 --no-pager -o short-iso 2>/dev/null || true)"
  if [[ -n "$entries" ]]; then
    printf '%s\n' "$entries" | sed 's/^/    /'
  else
    printf '    %bNo readable journal entries yet.%b\n' "$C_DIM" "$C_RESET"
  fi
}

while true; do
  clear 2>/dev/null || true
  printf '%b╔══════════════════════════════════════════════════════════════════════════════╗%b\n' "$C_BLUE" "$C_RESET"
  printf '%b║%b  %bFRAGCITY%b  %b/ PTERODACTYL AUTOMATION%b                                      %b║%b\n' \
    "$C_BLUE" "$C_RESET" "$C_WHITE" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_BLUE" "$C_RESET"
  printf '%b╚══════════════════════════════════════════════════════════════════════════════╝%b\n' "$C_BLUE" "$C_RESET"

  printf '  %bUI%b %s   %bREFRESH%b %ss   %bLIVE RELOAD%b checksum-watch ON\n' \
    "$C_MAGENTA" "$C_RESET" "$UI_VERSION" "$C_CYAN" "$C_RESET" "$REFRESH_SECONDS" "$C_GREEN" "$C_RESET"

  source_commit="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unavailable')"
  script_sha="$(printf '%s' "$STARTUP_SHA" | cut -c1-12)"
  [[ -n "$script_sha" ]] || script_sha="unavailable"
  printf '  source commit: %b%s%b   running UI SHA: %b%s%b\n' \
    "$C_YELLOW" "$source_commit" "$C_RESET" "$C_YELLOW" "$script_sha" "$C_RESET"

  section "AUTOMATION SWITCHES"
  printf '  %bTimers must remain ON. One-shot services normally return to OFF when idle.%b\n' \
    "$C_DIM" "$C_RESET"
  show_unit "fragcity-addon-payload-sync.timer" "timer"
  show_unit "fragcity-addon-provision.timer" "timer"
  show_unit "fragcity-addon-payload-sync.service" "oneshot"
  show_unit "fragcity-addon-provision.service" "oneshot"

  section "NEXT / LAST SCHEDULED RUNS"
  systemctl list-timers --all --no-pager \
    fragcity-addon-payload-sync.timer fragcity-addon-provision.timer 2>&1 | sed 's/^/  /'

  section "PUBLISHED PAYLOAD"
  if [[ -r "$PAYLOAD_ROOT/CURRENT_COMMIT" ]]; then
    payload_commit="$(tr -d '\r\n' < "$PAYLOAD_ROOT/CURRENT_COMMIT")"
    printf '  current payload: %b%s%b\n' "$C_GREEN" "$payload_commit" "$C_RESET"
    if [[ -r "$PAYLOAD_ROOT/revisions/$payload_commit/.source-commit" ]]; then
      revision_marker="$(tr -d '\r\n' < "$PAYLOAD_ROOT/revisions/$payload_commit/.source-commit")"
      if [[ "$revision_marker" == "$payload_commit" ]]; then
        printf '  revision marker: %bMATCH%b\n' "$C_GREEN" "$C_RESET"
      else
        printf '  revision marker: %bMISMATCH — CHECK REQUIRED%b\n' "$C_RED" "$C_RESET"
      fi
    else
      printf '  %bWARNING: published revision marker is missing.%b\n' "$C_RED" "$C_RESET"
    fi
  else
    printf '  %bOFF — published payload missing: %s%b\n' "$C_RED" "$PAYLOAD_ROOT" "$C_RESET"
  fi

  section "PROVISIONER STATE"
  baseline="$STATE_ROOT/baseline-uuids.txt"
  if [[ -r "$baseline" ]]; then
    baseline_count="$(grep -Ec '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' "$baseline" 2>/dev/null || true)"
    [[ -n "$baseline_count" ]] || baseline_count=0
    printf '  baseline UUIDs: %b%s%b\n' "$C_WHITE" "$baseline_count" "$C_RESET"
  else
    printf '  %bBASELINE MISSING — watcher cannot run safely%b\n' "$C_RED" "$C_RESET"
  fi

  if [[ -d "$STATE_ROOT/processed" ]]; then
    processed_count="$(find "$STATE_ROOT/processed" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l)"
  else
    processed_count=0
  fi
  printf '  processed server markers: %b%s%b\n' "$C_WHITE" "$processed_count" "$C_RESET"

  show_service_details "fragcity-addon-provision.service"
  show_service_details "fragcity-addon-payload-sync.service"

  printf '\n%bRefreshing in %s seconds...%b  %bCtrl+C closes this window%b\n' \
    "$C_DIM" "$REFRESH_SECONDS" "$C_RESET" "$C_DIM" "$C_RESET"
  sleep "$REFRESH_SECONDS"

  # The host publisher replaces this script atomically after fetching the branch.
  # Detect that replacement and exec the new file so an already-open window updates live.
  if [[ -r "$SELF_PATH" ]]; then
    current_sha="$(sha256sum -- "$SELF_PATH" 2>/dev/null | awk '{print $1}')"
    if [[ -n "$current_sha" && "$current_sha" != "$STARTUP_SHA" ]]; then
      printf '\n%b★ LIVE UPDATE DETECTED%b — restarting the dashboard with the new UI...\n' \
        "$C_GREEN" "$C_RESET"
      sleep 1
      exec bash "$SELF_PATH"
    fi
  fi
done
