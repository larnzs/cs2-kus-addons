#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker/docker-compose.yml"
cd "$ROOT_DIR"

for command_name in git bash docker; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "ERROR: Required command is missing: $command_name" >&2
        exit 1
    fi
done
if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: Docker Compose v2 is required (docker compose)." >&2
    exit 1
fi
if [[ ! -f "$ROOT_DIR/.env" ]]; then
    echo "ERROR: Missing $ROOT_DIR/.env. Create it from .env.example and set deployment settings." >&2
    exit 1
fi
if [[ -n "$(docker ps --filter name=cs2-modded-server --filter status=running --quiet)" ]]; then
    echo "ERROR: The CS2 container is running. Stop it before updating its persistent game volume." >&2
    exit 1
fi
if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: Run this from a clone of the private cs2-kus-addons repository." >&2
    exit 1
fi
if [[ -n "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]]; then
    echo "ERROR: The repository has local changes or untracked files. Commit or move them before updating." >&2
    exit 1
fi

echo "[1/4] Updating integration/kus-monorepo..."
git switch integration/kus-monorepo
git pull --ff-only origin integration/kus-monorepo

echo
echo "[2/4] Checking and updating managed plugin payloads..."
bash "$ROOT_DIR/scripts/update/update.sh" --no-pull
git -C "$ROOT_DIR" push origin HEAD:refs/heads/integration/kus-monorepo

echo
echo "[3/4] Building the updated container image (does not start a container)..."
docker compose -f "$COMPOSE_FILE" build cs2_modded_server

echo
echo "[4/4] Updating the persistent CS2 game volume in a one-shot container..."
echo "UPDATE_ONLY=1 prevents the image entrypoint from launching the game server."
UPDATE_ONLY=1 docker compose -f "$COMPOSE_FILE" run --rm --name cs2-modded-server-update --no-deps -e UPDATE_ONLY=1 cs2_modded_server

echo
echo "SUCCESS: repository, plugin payload, image and persistent game volume were updated."
echo "The CS2 server was NOT launched."
