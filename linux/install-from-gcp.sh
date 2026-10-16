#!/usr/bin/env bash
set -Eeuo pipefail

# GCP convenience wrapper for the same no-launch install/update workflow used elsewhere.
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ ! -f "$ROOT_DIR/linux/install.sh" || ! -d "$ROOT_DIR/game/csgo/addons" ]]; then
    echo "ERROR: Private repository payload was not found. Run this script from the repository clone." >&2
    exit 1
fi

if [[ "$EUID" -eq 0 ]]; then
    exec bash "$ROOT_DIR/linux/install.sh" "$@"
else
    exec sudo -E bash "$ROOT_DIR/linux/install.sh" "$@"
fi
