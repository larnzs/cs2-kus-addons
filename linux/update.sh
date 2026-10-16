#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: Clone this private Git repository before running linux/update.sh." >&2
    exit 1
fi

CURRENT_BRANCH="$(git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD)" || {
    echo "ERROR: Detached HEAD. Check out the intended branch before updating." >&2
    exit 1
}
REMOTE="${CS2_GIT_REMOTE:-origin}"

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
    echo "ERROR: Working tree has changes; commit or move them before updating." >&2
    exit 1
fi
if ! git -C "$ROOT_DIR" remote get-url "$REMOTE" >/dev/null 2>&1; then
    echo "ERROR: Git remote '$REMOTE' is not configured." >&2
    exit 1
fi

echo "Updating current branch '$CURRENT_BRANCH' from '$REMOTE' (fast-forward only)..."
git -C "$ROOT_DIR" pull --ff-only "$REMOTE" "$CURRENT_BRANCH"

echo "SUCCESS: Current branch updated. No plugin payload, runtime, or CS2 files were installed by this script."
