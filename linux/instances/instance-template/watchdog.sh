#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INSTANCE_CONFIG="${INSTANCE_CONFIG:-$SCRIPT_DIR/instance.env}"
if [[ ! -f "$INSTANCE_CONFIG" ]]; then
    echo "ERROR: Missing instance configuration: $INSTANCE_CONFIG" >&2
    echo "Copy instance.example.env to instance.env and edit it first." >&2
    exit 2
fi
set -a
# shellcheck disable=SC1090
source "$INSTANCE_CONFIG"
set +a

CS2_USER="${CS2_USER:-steam}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
if [[ "$LOG_DIR" != /* ]]; then LOG_DIR="$SCRIPT_DIR/$LOG_DIR"; fi
LOG_DIR="$(realpath -m -- "$LOG_DIR")"
mkdir -p "$LOG_DIR"

if [[ "$(id -un)" != "$CS2_USER" ]]; then
    echo "ERROR: Run the watchdog as '$CS2_USER' (for example: sudo -u $CS2_USER bash \"$SCRIPT_DIR/watchdog.sh\")." >&2
    exit 2
fi

exec 8>"$SCRIPT_DIR/.instance.lock"
if ! flock -n 8; then
    echo "ERROR: This instance already has a watchdog/runner. Use stop.sh before starting another." >&2
    exit 2
fi

WATCHDOG_PID_FILE="$LOG_DIR/watchdog.pid"
RUNNER_PID_FILE="$LOG_DIR/runner.pid"
printf '%s\n' "$$" > "$WATCHDOG_PID_FILE"

RUN_PID=""
STOP_REQUESTED=0
cleanup_pidfile() {
    if [[ -f "$WATCHDOG_PID_FILE" ]] && [[ "$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || true)" == "$$" ]]; then
        rm -f -- "$WATCHDOG_PID_FILE"
    fi
}
stop_supervisor() {
    STOP_REQUESTED=1
    if [[ -n "$RUN_PID" ]] && kill -0 "$RUN_PID" 2>/dev/null; then
        kill -TERM "$RUN_PID" 2>/dev/null || true
        wait "$RUN_PID" 2>/dev/null || true
    fi
    if [[ -f "$RUNNER_PID_FILE" ]]; then
        local pid
        pid="$(cat "$RUNNER_PID_FILE" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && [[ -r "/proc/$pid/cmdline" ]]; then
            local cmdline
            cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
            if [[ "$cmdline" == *"$SCRIPT_DIR/run.sh"* ]]; then
                kill -TERM "$pid" 2>/dev/null || true
            fi
        fi
    fi
    cleanup_pidfile
    exit 0
}
trap 'stop_supervisor' TERM INT HUP

echo "CS2 watchdog started for $SCRIPT_DIR"
while true; do
    echo "[$(date '+%F %T')] Starting one CS2 launch attempt."
    INSTANCE_CONFIG="$INSTANCE_CONFIG" INSTANCE_SUPERVISED=1 "$SCRIPT_DIR/run.sh" >> "$LOG_DIR/server.log" 2>&1 &
    RUN_PID=$!
    wait "$RUN_PID" && RUN_RC=0 || RUN_RC=$?
    RUN_PID=""

    if (( STOP_REQUESTED )); then break; fi
    if (( RUN_RC == 100 )); then
        sleep 0.1
    else
        echo "[$(date '+%F %T')] Runner returned exit code $RUN_RC; retrying in 5 seconds."
        sleep 5
    fi
done

cleanup_pidfile
exit 0
