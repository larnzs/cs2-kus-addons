#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# Stop CS2 processes only. The old ps|grep|xargs pipeline could match itself and
# also killed unrelated installer, HTTP-server, and SCREEN processes on the host.
CS2_USER="${CS2_USER:-steam}"
if ! command -v pgrep >/dev/null 2>&1; then
    echo "ERROR: pgrep is required to find CS2 processes."
    exit 1
fi

mapfile -t pids < <(pgrep -u "$CS2_USER" -x cs2 || true)
if [ "${#pids[@]}" -eq 0 ]; then
    echo "No CS2 processes named 'cs2' are running as user $CS2_USER."
    exit 0
fi

echo "Sending SIGTERM to CS2 PID(s): ${pids[*]}"
kill -TERM "${pids[@]}" 2>/dev/null || true

for _ in {1..15}; do
    remaining=()
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            remaining+=("$pid")
        fi
    done
    if [ "${#remaining[@]}" -eq 0 ]; then
        echo "CS2 stopped cleanly."
        exit 0
    fi
    sleep 1
done

echo "CS2 did not exit within 15 seconds; sending SIGKILL to remaining PID(s): ${remaining[*]}"
kill -KILL "${remaining[@]}" 2>/dev/null || true
