#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: Clone this private Git repository before running linux/update.sh." >&2
    exit 1
fi

echo "Updating repository branch integration/kus-monorepo..."
git -C "$ROOT_DIR" switch integration/kus-monorepo
git -C "$ROOT_DIR" pull --ff-only origin integration/kus-monorepo

echo "SUCCESS: Repository branch updated. Plugins, game files, and runtime were not changed."
