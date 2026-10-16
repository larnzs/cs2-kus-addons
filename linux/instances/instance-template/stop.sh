#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INSTANCE_CONFIG="${INSTANCE_CONFIG:-$SCRIPT_DIR/instance.env}"
if [[ -f "$INSTANCE_CONFIG" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$INSTANCE_CONFIG"
    set +a
fi

CS2_USER="${CS2_USER:-steam}"
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"
if [[ "$LOG_DIR" != /* ]]; then LOG_DIR="$SCRIPT_DIR/$LOG_DIR"; fi
LOG_DIR="$(realpath -m -- "$LOG_DIR")"

if [[ "$(id -un)" != "$CS2_USER" ]]; then
    echo "ERROR: Run stop.sh as '$CS2_USER' or with sudo." >&2
    exit 2
fi

matches_script() {
    local pid="$1" expected="$2" arg proc_cwd resolved
    [[ "$pid" =~ ^[0-9]+$ && -r "/proc/$pid/cmdline" ]] || return 1
    proc_cwd="$(readlink -f -- "/proc/$pid/cwd" 2>/dev/null || true)"
    [[ -n "$proc_cwd" ]] || return 1
    while IFS= read -r -d '' arg; do
        [[ "$arg" == *.sh ]] || continue
        if [[ "$arg" == /* ]]; then
            resolved="$(realpath -m -- "$arg" 2>/dev/null || true)"
        else
            resolved="$(realpath -m -- "$proc_cwd/$arg" 2>/dev/null || true)"
        fi
        if [[ "$resolved" == "$expected" ]]; then
            return 0
        fi
    done < "/proc/$pid/cmdline"
    return 1
}

target_pid=""
target_script=""
for role in watchdog run; do
    if [[ "$role" == "watchdog" ]]; then
        pidfile="$LOG_DIR/watchdog.pid"
        expected="$SCRIPT_DIR/watchdog.sh"
    else
        pidfile="$LOG_DIR/runner.pid"
        expected="$SCRIPT_DIR/run.sh"
    fi
    [[ -f "$pidfile" ]] || continue
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    if matches_script "$pid" "$expected"; then
        target_pid="$pid"
        target_script="$expected"
        break
    else
        rm -f -- "$pidfile"
    fi
done

if [[ -z "$target_pid" ]]; then
    echo "No live watchdog or runner for this instance was found."
    exit 0
fi

echo "Sending SIGTERM to instance process $target_pid ($target_script)."
kill -TERM "$target_pid"
for _ in {1..20}; do
    if ! matches_script "$target_pid" "$target_script"; then
        echo "Instance stopped."
        exit 0
    fi
    sleep 1
done

echo "ERROR: Instance process $target_pid is still stopping; no SIGKILL was sent." >&2
exit 1
