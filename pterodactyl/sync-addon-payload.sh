#!/usr/bin/env bash
# Host-side FragCity addon synchronizer for K4ryuu/Pterodactyl CS2 containers.
#
# The full Git checkout is the source of truth. By default this safely
# fast-forwards the checkout before syncing; it does not download addons one
# by one because the repo's existing updater workflow manages repo contents.
#
# Usage:
#   bash pterodactyl/sync-addon-payload.sh <container-name-or-id> [container-game-root]
#   bash pterodactyl/sync-addon-payload.sh --no-pull <container-name-or-id> [container-game-root]
#
# Run on the Docker/Wings host. The target container must already be running.
# This is synchronous and returns only after copy/hash verification/pruning.
#
# These paths are excluded from automatic sync and stale-file deletion:
#   addons/counterstrikesharp/plugins/BotAI/
#   addons/counterstrikesharp/plugins/disabled/
# cfg/configs and the Egg-managed Metamod/CounterStrikeSharp runtimes are out
# of scope and are never copied.

set -Eeuo pipefail

PULL_REPO=1
if [[ "${1:-}" == "--no-pull" ]]; then
    PULL_REPO=0
    shift
fi

usage() {
    cat <<'USAGE'
Usage:
  sync-addon-payload.sh [--no-pull] <container-name-or-id> [container-game-root]

Options:
  --no-pull   Use the current local checkout without pulling from its Git upstream.
USAGE
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage >&2
    exit 2
fi

CONTAINER="$1"
TARGET_GAME_ROOT="${2:-/home/container/game/csgo}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '[fragcity-sync] %s\n' "$*"
}

command -v docker >/dev/null 2>&1 || die "docker CLI was not found on this host."
command -v git >/dev/null 2>&1 || die "git is required."
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required."
command -v flock >/dev/null 2>&1 || die "flock is required."
command -v find >/dev/null 2>&1 || die "find is required."

[[ "$TARGET_GAME_ROOT" == /* ]] || die "The container game root must be an absolute path."
[[ "$TARGET_GAME_ROOT" != *"/../"* && "$TARGET_GAME_ROOT" != */.. ]] || die "The container game root cannot contain '..'."

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
GAME_SOURCE="$REPO_ROOT/game/csgo"
ADDONS_SOURCE="$GAME_SOURCE/addons"
CSS_SOURCE="$ADDONS_SOURCE/counterstrikesharp"

[[ -d "$REPO_ROOT/.git" ]] || die "Repo checkout not found at $REPO_ROOT (expected a normal Git checkout)."

# Serialize Git pulls and syncs so concurrent starts cannot read a changing tree.
exec 9>"$REPO_ROOT/.git/fragcity-addon-sync.lock"
flock -x 9

if [[ "$PULL_REPO" -eq 1 ]]; then
    if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
        die "The repo has local modifications/untracked files; commit/stash them first, or rerun with --no-pull."
    fi
    log "Fast-forwarding the local repository from its configured Git upstream."
    git -C "$REPO_ROOT" pull --ff-only --quiet || die "Git pull failed. Check branch/upstream/network, or use --no-pull for the current checkout."
else
    log "Using the current checkout without contacting GitHub."
fi

SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
log "Source checkout: $SOURCE_COMMIT"

docker inspect "$CONTAINER" >/dev/null 2>&1 || die "Docker container does not exist: $CONTAINER"
RUNNING="$(docker inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)"
[[ "$RUNNING" == "true" ]] || die "Container is not running: $CONTAINER"

[[ -d "$CSS_SOURCE/source" ]] || die "Missing folder: $CSS_SOURCE/source"
[[ -d "$CSS_SOURCE/plugins" ]] || die "Missing folder: $CSS_SOURCE/plugins"
[[ -d "$CSS_SOURCE/shared" ]] || die "Missing folder: $CSS_SOURCE/shared"
[[ -d "$CSS_SOURCE/gamedata" ]] || die "Missing folder: $CSS_SOURCE/gamedata"
[[ -f "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" ]] || die "Missing VDF: $ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf"

for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    [[ -d "$ADDONS_SOURCE/$name" ]] || die "Missing addon directory: $ADDONS_SOURCE/$name"
done

# Reject symlinks in managed payloads; they do not have portable content hashes.
while IFS= read -r -d '' link_path; do
    die "Symlink found in managed payload (not supported): $link_path"
done < <(
    find \
        "$CSS_SOURCE/source" "$CSS_SOURCE/shared" "$CSS_SOURCE/gamedata" \
        "$ADDONS_SOURCE/MovementUnlocker" "$ADDONS_SOURCE/serverlistplayersfix_mm" \
        "$ADDONS_SOURCE/surf" "$ADDONS_SOURCE/scripts" "$ADDONS_SOURCE/multiaddonmanager" \
        "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" \
        -type l -print0 2>/dev/null
)

# Paths in these maps are relative to TARGET_GAME_ROOT.
declare -A DESIRED_SOURCE=()
declare -A DESIRED_HASH=()

add_file() {
    local relative_path="$1"
    local source_path="$2"
    local source_hash
    [[ -f "$source_path" ]] || die "Expected source file does not exist: $source_path"
    source_hash="$(sha256sum -- "$source_path" | awk '{print $1}')"
    DESIRED_SOURCE["$relative_path"]="$source_path"
    DESIRED_HASH["$relative_path"]="$source_hash"
}

add_tree() {
    local source_dir="$1"
    local target_relative_dir="$2"
    local exclude_botai_disabled="${3:-0}"
    local source_file
    local relative_file

    [[ -d "$source_dir" ]] || die "Missing source directory: $source_dir"

    if [[ "$exclude_botai_disabled" -eq 1 ]]; then
        while IFS= read -r -d '' source_file; do
            relative_file="${source_file#"$source_dir"/}"
            add_file "$target_relative_dir/$relative_file" "$source_file"
        done < <(
            find "$source_dir" -mindepth 1 \
                \( -path "$source_dir/BotAI" -o -path "$source_dir/disabled" \) -prune \
                -o -type f -print0
        )
    else
        while IFS= read -r -d '' source_file; do
            relative_file="${source_file#"$source_dir"/}"
            add_file "$target_relative_dir/$relative_file" "$source_file"
        done < <(find "$source_dir" -type f -print0)
    fi
}

log "Building the desired-file list from the local repo checkout."
add_tree "$CSS_SOURCE/source" "addons/counterstrikesharp/source"
add_tree "$CSS_SOURCE/plugins" "addons/counterstrikesharp/plugins" 1
add_tree "$CSS_SOURCE/shared" "addons/counterstrikesharp/shared"
add_tree "$CSS_SOURCE/gamedata" "addons/counterstrikesharp/gamedata"

for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    add_tree "$ADDONS_SOURCE/$name" "addons/$name"
done
add_file "addons/metamod/serverlistplayersfix_mm.vdf" "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf"

CSS_TARGET="$TARGET_GAME_ROOT/addons/counterstrikesharp"
MANAGED_ROOTS=(
    "$CSS_TARGET/source"
    "$CSS_TARGET/plugins"
    "$CSS_TARGET/shared"
    "$CSS_TARGET/gamedata"
    "$TARGET_GAME_ROOT/addons/MovementUnlocker"
    "$TARGET_GAME_ROOT/addons/serverlistplayersfix_mm"
    "$TARGET_GAME_ROOT/addons/surf"
    "$TARGET_GAME_ROOT/addons/scripts"
    "$TARGET_GAME_ROOT/addons/multiaddonmanager"
)

for managed_root in "${MANAGED_ROOTS[@]}"; do
    docker exec "$CONTAINER" mkdir -p "$managed_root"
done
docker exec "$CONTAINER" mkdir -p "$TARGET_GAME_ROOT/addons/metamod"

COPIED=0
UNCHANGED=0
VERIFIED=0

# Compare hashes first and transfer only missing/changed files. Verify each copy.
for relative_path in "${!DESIRED_SOURCE[@]}"; do
    source_path="${DESIRED_SOURCE[$relative_path]}"
    expected_hash="${DESIRED_HASH[$relative_path]}"
    target_path="$TARGET_GAME_ROOT/$relative_path"
    actual_hash="$(docker exec "$CONTAINER" sha256sum -- "$target_path" 2>/dev/null | awk 'NR == 1 {print $1}' || true)"

    if [[ "$actual_hash" == "$expected_hash" ]]; then
        UNCHANGED=$((UNCHANGED + 1))
        VERIFIED=$((VERIFIED + 1))
        continue
    fi

    log "Updating $relative_path (SHA-256 differs or file is missing)."
    docker exec "$CONTAINER" mkdir -p "$(dirname -- "$target_path")"
    docker cp "$source_path" "$CONTAINER:$target_path"

    actual_hash="$(docker exec "$CONTAINER" sha256sum -- "$target_path" 2>/dev/null | awk 'NR == 1 {print $1}' || true)"
    [[ "$actual_hash" == "$expected_hash" ]] || die "SHA-256 verification failed after copy: $relative_path"

    COPIED=$((COPIED + 1))
    VERIFIED=$((VERIFIED + 1))
done

# Stale cleanup runs only after every desired file has passed hash verification.
# The script only prunes its explicitly managed directory trees.
DELETED=0
for managed_root in "${MANAGED_ROOTS[@]}"; do
    while IFS= read -r target_path; do
        [[ -n "$target_path" ]] || continue
        [[ "$target_path" == "$TARGET_GAME_ROOT/"* ]] || continue
        relative_path="${target_path#"$TARGET_GAME_ROOT"/}"

        case "$relative_path" in
            addons/counterstrikesharp/plugins/BotAI|addons/counterstrikesharp/plugins/BotAI/*|addons/counterstrikesharp/plugins/disabled|addons/counterstrikesharp/plugins/disabled/*)
                continue
                ;;
        esac

        if [[ -z "${DESIRED_SOURCE[$relative_path]+present}" ]]; then
            log "Removing stale managed file: $relative_path"
            docker exec "$CONTAINER" rm -f -- "$target_path"
            DELETED=$((DELETED + 1))
        fi
    done < <(docker exec "$CONTAINER" find "$managed_root" -type f -print 2>/dev/null || true)
done

# Metamod is not mirrored: only serverlistplayersfix_mm.vdf is managed.
# Remove empty directories under managed roots, but protect the excluded trees.
for managed_root in "${MANAGED_ROOTS[@]}"; do
    if [[ "$managed_root" == "$CSS_TARGET/plugins" ]]; then
        docker exec "$CONTAINER" find "$managed_root" -mindepth 1 -depth -type d -empty \
            ! -path "$managed_root/BotAI" ! -path "$managed_root/BotAI/*" \
            ! -path "$managed_root/disabled" ! -path "$managed_root/disabled/*" \
            -delete
    else
        docker exec "$CONTAINER" find "$managed_root" -mindepth 1 -depth -type d -empty -delete
    fi
done

log "Sync completed successfully for container: $CONTAINER"
log "Files copied: $COPIED; already matching SHA-256: $UNCHANGED; verified: $VERIFIED; stale files removed: $DELETED."
log "Source commit: $SOURCE_COMMIT"
log "BotAI/ and disabled/ were not copied or pruned."
log "No cfg/configs or Egg-managed runtime directories were copied."
log "The script is synchronous. An Egg/host startup hook is still required to invoke it automatically before CS2 starts."
