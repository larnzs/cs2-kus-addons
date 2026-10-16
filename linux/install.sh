#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this installer as root (for example: sudo -E bash linux/install.sh)." >&2
    exit 1
fi
if [[ ! -e "$ROOT_DIR/.git" ]]; then
    echo "ERROR: Run this from a clone of the private cs2-kus-addons repository." >&2
    exit 1
fi
if [[ ! -d "$ROOT_DIR/game/csgo/addons" ]]; then
    echo "ERROR: Tracked plugin payload is missing: $ROOT_DIR/game/csgo/addons" >&2
    exit 1
fi

# Git must run as the checkout owner so its read-only HTTPS credentials are reused;
# the root installer only updates system packages and deploys files to runtime paths.
REPO_OWNER="$(stat -c '%U' "$ROOT_DIR")"
REPO_USER="$REPO_OWNER"
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" && "$SUDO_USER" == "$REPO_OWNER" ]]; then
    REPO_USER="$SUDO_USER"
fi
if [[ "$REPO_USER" == "root" ]] || ! id "$REPO_USER" >/dev/null 2>&1; then
    echo "ERROR: Keep the repository checkout owned by a non-root operator and run this script with sudo from that account." >&2
    exit 1
fi

run_as_repo_user() {
    sudo -u "$REPO_USER" -- "$@"
}
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
if [[ -n "$(run_as_repo_user git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
    echo "ERROR: The repository has local changes or untracked files. Commit or move them before updating." >&2
    exit 1
fi

echo "[1/2] Updating the active repository branch (read-only Git access)..."
if ! run_as_repo_user bash "$ROOT_DIR/linux/update.sh"; then
    echo "ERROR: Repository update failed. No game/runtime deployment was started." >&2
    exit 1
fi

echo
echo "[2/2] Installing/updating Steam Linux Runtime, CS2 and the committed plugin payload (server stays stopped)..."
if ! bash "$ROOT_DIR/linux/setup.sh"; then
    echo "ERROR: Linux setup/install did not complete. Review the first failing step and its diagnostic log." >&2
    exit 1
fi

echo
echo "SUCCESS: repository, Steam Linux Runtime, CS2 and the committed plugin payload are installed/updated."
echo "This workflow uses read-only Git access and never pushes to GitHub."
echo "Existing runtime files were overlaid safely; the server was NOT launched."
