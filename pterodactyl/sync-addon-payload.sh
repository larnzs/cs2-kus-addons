#!/usr/bin/env bash
# Host-side sync helper for FragCity's CS2 addon payload.
# Windows development checkout: D:\cs2-kus-addons
# On Debian, the source paths are resolved relative to this file in the repo.
#
# Usage:
#   ./pterodactyl/sync-addon-payload.sh <container-name-or-id> [container-game-root]
#
# Example game root:
#   /home/container/game/csgo
#
# Run this on the Docker/Wings host. The container must already exist.
# This is a sync helper only; it does not alter the K4ryuu Egg startup command.
# Config/cfg files are intentionally out of scope for this script.
# BotAI and the disabled plugin tree are excluded from the automatic plugin copy.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
GAME_SOURCE="$REPO_ROOT/game/csgo"
ADDONS_SOURCE="$GAME_SOURCE/addons"
CSS_SOURCE="$ADDONS_SOURCE/counterstrikesharp"

if [[ $# -lt 1 || $# -gt 2 ]]; then
    printf 'Usage: %s <container-name-or-id> [container-game-root]\n' "$0" >&2
    exit 2
fi

CONTAINER="$1"
TARGET_GAME_ROOT="/home/container/game/csgo"
if [[ $# -eq 2 ]]; then
    TARGET_GAME_ROOT="$2"
fi
CSS_TARGET="$TARGET_GAME_ROOT/addons/counterstrikesharp/"
ADDONS_TARGET="$TARGET_GAME_ROOT/addons/"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '[fragcity-sync] %s\n' "$*"
}

command -v docker >/dev/null 2>&1 || die "docker CLI was not found on this host."
command -v tar >/dev/null 2>&1 || die "tar is required but was not found."
docker inspect "$CONTAINER" >/dev/null 2>&1 || die "Docker container does not exist: $CONTAINER"

[[ -d "$CSS_SOURCE/source" ]] || die "Missing folder: $CSS_SOURCE/source"
[[ -d "$CSS_SOURCE/plugins" ]] || die "Missing folder: $CSS_SOURCE/plugins"
[[ -d "$CSS_SOURCE/shared" ]] || die "Missing folder: $CSS_SOURCE/shared"
[[ -d "$CSS_SOURCE/gamedata" ]] || die "Missing folder: $CSS_SOURCE/gamedata"
[[ -f "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" ]] || die "Missing VDF: $ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf"

for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    [[ -d "$ADDONS_SOURCE/$name" ]] || die "Missing addon directory: $ADDONS_SOURCE/$name"
done

STAGE="$(mktemp -d)"
trap 'rm -rf -- "$STAGE"' EXIT
mkdir -p "$STAGE/plugins"

# Build a temporary filtered copy. The checkout itself is not changed or moved.
log "Preparing CounterStrikeSharp plugins (excluding BotAI and disabled/)."
tar \
    --exclude='./BotAI' \
    --exclude='./disabled' \
    -C "$CSS_SOURCE/plugins" \
    -cf - . \
    | tar -C "$STAGE/plugins" -xf -

copy_dir() {
    local source_path="$1"
    local target_parent="$2"
    log "Copying directory: $source_path"
    docker cp "$source_path" "$CONTAINER:$target_parent"
}

copy_file() {
    local source_path="$1"
    local target_parent="$2"
    log "Copying file: $source_path"
    docker cp "$source_path" "$CONTAINER:$target_parent"
}

# Copy only these CounterStrikeSharp paths. Runtime folders such as api, bin,
# configs, dotnet, and lang are deliberately omitted; K4ryuu Egg installs the
# Metamod/CounterStrikeSharp runtime. The config/cfg sync will be separate.
copy_dir "$CSS_SOURCE/source" "$CSS_TARGET"
copy_dir "$STAGE/plugins" "$CSS_TARGET"
copy_dir "$CSS_SOURCE/shared" "$CSS_TARGET"
copy_dir "$CSS_SOURCE/gamedata" "$CSS_TARGET"

# Only the requested top-level addon folders are copied.
for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    copy_dir "$ADDONS_SOURCE/$name" "$ADDONS_TARGET"
done

# Copy just this VDF into the Egg-installed Metamod directory.
copy_file "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" "$TARGET_GAME_ROOT/addons/metamod/"

log "Sync completed for container: $CONTAINER"
log "No config/cfg files or Metamod/CounterStrikeSharp runtime folders were copied."
