#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this updater as root (for example: sudo -E bash linux/update.sh)." >&2
    exit 1
fi
if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: Run this from a clone of the private cs2-kus-addons repository." >&2
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

echo "[1/2] Updating integration/kus-monorepo..."
git switch integration/kus-monorepo
git pull --ff-only origin integration/kus-monorepo

echo
echo "[2/2] Updating plugins and CS2 through the unified installer (server stays stopped)..."
RUN_PLUGIN_UPDATER=1 UPDATE_ONLY=1 bash "$ROOT_DIR/linux/install.sh"

echo
echo "SUCCESS: repository, plugin payload and CS2 update/deployment completed."
echo "Existing runtime files were overlaid safely; the server was NOT launched."
