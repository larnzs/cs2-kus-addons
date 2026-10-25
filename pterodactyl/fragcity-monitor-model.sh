#!/usr/bin/env bash
# Shared, side-effect-free health classification for FragCity's read-only monitors.
# Arguments to fragcity_classify_server:
#   panel_mount container_state docker_mount processed_marker startup_hook baseline seed_state

fragcity_classify_server() {
  local panel_mount="$1"
  local container_state="$2"
  local docker_mount="$3"
  local processed_marker="$4"
  local startup_hook="$5"
  local baseline="$6"
  local seed_state="$7"

  # Unsafe state files must remain visible as critical even if another field is bad.
  if [[ "$seed_state" == BAD || "$seed_state" == UNSAFE ]]; then
    printf 'FIRST-SEED-ERROR'
  elif [[ "$processed_marker" == UNSAFE ]]; then
    printf 'PROCESSED-MARKER-UNSAFE'
  elif [[ "$container_state" == ERROR || "$docker_mount" == UNKNOWN ]]; then
    printf 'DOCKER-STATE-UNKNOWN'
  elif [[ "$container_state" == ABSENT || "$docker_mount" == PENDING ]]; then
    printf 'CONTAINER-ABSENT'
  elif [[ "$panel_mount" != ON ]]; then
    printf 'PANEL-MOUNT-OFF'
  elif [[ "$docker_mount" != ON ]]; then
    printf 'DOCKER-MOUNT-OFF'
  elif [[ "$startup_hook" != ON ]]; then
    printf 'STARTUP-HOOK-OFF'
  elif [[ "$seed_state" == PENDING ]]; then
    printf 'FIRST-SEED-PENDING'
  elif [[ "$seed_state" == MISSING ]]; then
    printf 'FIRST-SEED-MISSING'
  elif [[ "$seed_state" == UNKNOWN ]]; then
    printf 'FIRST-SEED-UNKNOWN'
  elif [[ "$processed_marker" != ON && "$baseline" == ON ]]; then
    printf 'PROCESSED-MARKER-MISSING'
  elif [[ "$baseline" != ON && "$processed_marker" == OFF ]]; then
    printf 'NEW-NOT-REGISTERED'
  else
    printf 'OK'
  fi
}

fragcity_server_severity() {
  case "$1" in
    FIRST-SEED-ERROR|PROCESSED-MARKER-UNSAFE) printf 'CRITICAL' ;;
    OK) printf 'HEALTHY' ;;
    *) printf 'ATTENTION' ;;
  esac
}

# Count this independently from the row's primary health reason. A new server
# can simultaneously be unregistered and have a missing/pending first-install seed.
fragcity_is_new_unregistered() {
  [[ "$1" != ON && "$2" == OFF ]]
}

# Global posture is a pure decision function so regressions can be tested without
# running systemd, Docker, or a live Panel database.
# Arguments: critical_host_checks critical_servers warning_groups server_attention_count
fragcity_system_posture() {
  local critical_checks="$1"
  local critical_servers="$2"
  local warning_groups="$3"
  local server_attention="$4"

  if (( critical_checks > 0 || critical_servers > 0 )); then
    printf 'CRITICAL'
  elif (( warning_groups > 0 || server_attention > 0 )); then
    printf 'ATTENTION'
  else
    printf 'HEALTHY'
  fi
}
