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

if [[ -z "${REPO_ROOT:-}" ]]; then REPO_ROOT="$(realpath -m -- "$SCRIPT_DIR/../../..")"; fi
if [[ ! -d "$REPO_ROOT/.git" && ! -f "$REPO_ROOT/.git" ]]; then
    echo "ERROR: REPO_ROOT is not a Git checkout: $REPO_ROOT" >&2
    exit 2
fi

if pgrep -x cs2 >/dev/null 2>&1; then
    echo "Shared maintenance skipped: a CS2 process is active."
    echo "Stop every instance before updating the shared game/plugin runtime, then rerun this script."
    exit 0
fi

echo "Running the repository's no-launch Linux maintenance entrypoint..."
if [[ "$EUID" -eq 0 ]]; then
    exec bash "$REPO_ROOT/linux/install.sh"
else
    exec sudo -E bash "$REPO_ROOT/linux/install.sh"
fi
