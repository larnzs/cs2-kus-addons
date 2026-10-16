#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this installer as root (for example: sudo -E bash linux/install.sh)." >&2
    exit 1
fi
if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: Run this from a clone of the private cs2-kus-addons repository." >&2
    exit 1
fi
if ! command -v flock >/dev/null 2>&1; then
    echo "ERROR: flock is required for safe shared maintenance." >&2
    exit 1
fi

LOCK_FILE="${CS2_MAINTENANCE_LOCK_FILE:-/tmp/CS2-KUS-Maintenance.lock}"
if [[ ! -e "$LOCK_FILE" ]]; then
    (umask 022; : > "$LOCK_FILE")
fi
chmod a+r "$LOCK_FILE" 2>/dev/null || true
exec 9>>"$LOCK_FILE"
if ! flock -n -x 9; then
    echo "ERROR: Shared maintenance lock is held by a running instance or another updater." >&2
    echo "Stop all CS2 instances and retry after the current operation completes." >&2
    exit 1
fi

if pgrep -x cs2 >/dev/null 2>&1; then
    echo "ERROR: A CS2 server process is running. Stop it before updating shared files." >&2
    exit 1
fi
if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
    echo "ERROR: The repository has local changes or untracked files. Commit or move them before updating." >&2
    exit 1
fi

echo "[1/2] Updating repository through linux/update.sh..."
bash "$ROOT_DIR/linux/update.sh"

echo
echo "[2/2] Updating managed plugins, Steam Linux Runtime and CS2 (server stays stopped)..."
RUN_PLUGIN_UPDATER=1 bash "$ROOT_DIR/linux/setup.sh"

echo
echo "SUCCESS: repository, plugin payload and CS2 update/deployment completed."
echo "Existing runtime files were overlaid safely; the server was NOT launched."
