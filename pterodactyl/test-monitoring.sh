#!/usr/bin/env bash
# Regression tests for FragCity's read-only monitoring model.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
MODEL="$ROOT/pterodactyl/fragcity-monitor-model.sh"
STATUS="$ROOT/pterodactyl/server-mount-status.php"
PROVISIONER="$ROOT/pterodactyl/provision-addon-servers.php"
DASHBOARD="$ROOT/pterodactyl/systemd/fragcity-status-dashboard.sh"
MANAGER="$ROOT/pterodactyl/fragcity-manager.sh"
PUBLISHER_UNIT="$ROOT/pterodactyl/systemd/fragcity-addon-payload-sync.service"

[[ -r "$MODEL" ]] || { echo "FAIL: shared monitor model is missing." >&2; exit 1; }
# shellcheck source=/dev/null
source "$MODEL"

assert_reason() {
  local expected="$1" actual
  shift
  actual="$(fragcity_classify_server "$@")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: expected health=%s, got health=%s; args: %s\n' "$expected" "$actual" "$*" >&2
    exit 1
  fi
}

assert_value() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s expected %s, got %s\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
}

# Arguments: panel-mount container-state docker-mount processed startup baseline seed.
assert_reason OK ON RUNNING ON ON ON ON DONE
assert_reason STARTUP-HOOK-OFF ON RUNNING ON ON OFF ON DONE
assert_reason PANEL-MOUNT-OFF OFF RUNNING ON ON ON ON DONE
assert_reason DOCKER-MOUNT-OFF ON RUNNING OFF ON ON ON DONE
assert_reason CONTAINER-ABSENT ON ABSENT PENDING OFF ON OFF MISSING
assert_reason DOCKER-STATE-UNKNOWN ON ERROR UNKNOWN ON ON ON DONE
assert_reason FIRST-SEED-ERROR ON RUNNING ON ON ON ON UNSAFE
assert_reason FIRST-SEED-ERROR ON RUNNING ON ON ON ON BAD
assert_reason PROCESSED-MARKER-UNSAFE ON RUNNING ON UNSAFE ON ON DONE
assert_reason PROCESSED-MARKER-MISSING ON RUNNING ON OFF ON ON LEGACY
assert_reason NEW-NOT-REGISTERED ON RUNNING ON OFF ON OFF DONE
assert_reason FIRST-SEED-PENDING ON RUNNING ON OFF ON OFF PENDING
assert_reason FIRST-SEED-UNKNOWN ON RUNNING ON ON ON ON UNKNOWN

assert_value CRITICAL "$(fragcity_server_severity FIRST-SEED-ERROR)" "unsafe seed severity"
assert_value CRITICAL "$(fragcity_server_severity PROCESSED-MARKER-UNSAFE)" "unsafe marker severity"
assert_value ATTENTION "$(fragcity_server_severity STARTUP-HOOK-OFF)" "startup hook severity"
assert_value HEALTHY "$(fragcity_server_severity OK)" "healthy severity"

assert_value CRITICAL "$(fragcity_system_posture 0 1 0 0)" "critical server elevates global posture"
assert_value CRITICAL "$(fragcity_system_posture 1 0 0 0)" "critical host check elevates global posture"
assert_value ATTENTION "$(fragcity_system_posture 0 0 1 0)" "warning group elevates global posture"
assert_value ATTENTION "$(fragcity_system_posture 0 0 0 1)" "server attention elevates global posture"
assert_value HEALTHY "$(fragcity_system_posture 0 0 0 0)" "fully healthy global posture"

if fragcity_is_new_unregistered OFF OFF && ! fragcity_is_new_unregistered ON OFF; then
  :
else
  echo "FAIL: new/unregistered counter classifier returned an incorrect result." >&2
  exit 1
fi

# Static integration guards: local Docker containers are compared to this Node,
# history is compared to this Mount's eligible inventory, and publisher may update
# only the dedicated installed dashboard directory inside its sandbox.
grep -Fq 'if (validUuid($containerName) && !isset($nodePanelUuidSet[$containerName]))' "$STATUS"
grep -Fq "'PANEL_SERVER_NOT_ON_THIS_NODE'" "$STATUS"
grep -Fq "'PANEL_UUID_DELETED'" "$STATUS"
grep -Fq 'if (!isset($currentEligibleUuidSet[$baselineUuid]))' "$STATUS"
grep -Fq 'if (validUuid($markerUuid) && !isset($currentEligibleUuidSet[$markerUuid]))' "$STATUS"
grep -Fq 'ReadWritePaths=/usr/local/libexec' "$PUBLISHER_UNIT"
grep -Fq 'fragcity_classify_server' "$DASHBOARD"
grep -Fq 'fragcity_system_posture' "$DASHBOARD"
grep -Fq 'fragcity_classify_server' "$MANAGER"
grep -Fq 'STALE PROCESSED MARKER' "$MANAGER"
grep -Fq 'manage_install_marks()' "$MANAGER"
grep -Fq 'screen_deleted_uuid_history()' "$MANAGER"
grep -Fq 'M|m) manage_install_marks' "$MANAGER"
grep -Fq 'D|d) screen_deleted_uuid_history' "$MANAGER"
grep -Fq 'Are you sure? [y/n]' "$MANAGER"
grep -Fq -- '--set-config-seed' "$PROVISIONER"
grep -Fq 'mode=' "$PROVISIONER"
grep -Fq 'Detailed UUID list: open FragCity Control Center and choose D' "$DASHBOARD"

echo "PASS: per-server health classification, unsafe states, startup hook, new UUID counters, node-local Docker orphans, separate UUID history, manual first-install controls, and dashboard sandbox write access."
