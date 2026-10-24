#!/usr/bin/env bash
# Container-side FragCity addon synchronizer for the custom K4ryuu/Pterodactyl Egg.
#
# This script runs inside the game container, after K4ryuu updates its runtimes and
# immediately before the CS2 launch command. The private repository is NOT cloned in
# the container. The read-only host mount must expose:
#   CURRENT_COMMIT
#   .sync.lock
#   sync-addon-payload-container.sh
#   revisions/<40-char-commit>/.source-commit
#   revisions/<40-char-commit>/game/csgo/...
#
# The host-side script publishes complete immutable snapshots, then atomically swaps
# CURRENT_COMMIT. The shared lock prevents old snapshots being pruned during a sync.
#
# These paths are deliberately outside the managed sync scope:
#   addons/counterstrikesharp/plugins/BotAI/
#   addons/counterstrikesharp/plugins/CS2UpdateMonitor/
# The plugins/disabled/ directory is synced from the payload but remains in that
# directory; this script never promotes disabled plugins into the active plugins root.
#   Egg-managed Metamod/CounterStrikeSharp runtime directories
#
# Managed configuration paths (repo is authoritative; local extras are removed):
#   addons/counterstrikesharp/configs/
#   cfg/
#   gamemodes_server.txt, mapcycle.txt, mapcyclecustom.txt,
#   subscribed_collection_ids.txt, subscribed_file_ids.txt

set -Eeuo pipefail

PAYLOAD_BASE="${FRAGCITY_PAYLOAD_BASE:-/home/container/egg/fragcity-payload}"
GAME_ROOT="${FRAGCITY_GAME_ROOT:-/home/container/game/csgo}"
SERVER_UUID="${P_SERVER_UUID:-}"
VERBOSE="${FRAGCITY_SYNC_VERBOSE:-0}"

log() { printf '[fragcity-payload] %s\n' "$*"; }
die() { printf '[fragcity-payload] ERROR: %s\n' "$*" >&2; exit 1; }

validate_absolute_path() {
    local label="$1" path="$2"
    [[ "$path" == /* ]] || die "$label must be an absolute path: $path"
    case "/$path/" in
        *"/../"*) die "$label must not contain '..': $path" ;;
    esac
}

validate_absolute_path "FRAGCITY_PAYLOAD_BASE" "$PAYLOAD_BASE"
validate_absolute_path "FRAGCITY_GAME_ROOT" "$GAME_ROOT"
[[ "$VERBOSE" == "0" || "$VERBOSE" == "1" ]] || die "FRAGCITY_SYNC_VERBOSE must be 0 or 1."

# Wings injects this UUID per server. Do not run the deployment without a
# trustworthy server identity; the destination is the current server's volume.
[[ "$SERVER_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
    || die "P_SERVER_UUID is missing or invalid; refusing to sync without a verified server identity."

for command_name in sha256sum find cp mkdir rm awk flock tr chmod dirname; do
    command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required."
done

[[ -d "$PAYLOAD_BASE" && ! -L "$PAYLOAD_BASE" ]] || die "Payload mount is missing or is a symlink: $PAYLOAD_BASE"
[[ -f "$PAYLOAD_BASE/.sync.lock" && ! -L "$PAYLOAD_BASE/.sync.lock" ]] || die "Host payload lock file is missing."
[[ -f "$PAYLOAD_BASE/CURRENT_COMMIT" && ! -L "$PAYLOAD_BASE/CURRENT_COMMIT" ]] || die "No published payload snapshot is available (CURRENT_COMMIT missing)."

# Hold a shared lock until this sync completes. Host publication/pruning takes the
# exclusive lock, so the revision selected below remains present and immutable.
exec 9< "$PAYLOAD_BASE/.sync.lock"
flock -s 9

SOURCE_COMMIT="$(tr -d '\r\n' < "$PAYLOAD_BASE/CURRENT_COMMIT")"
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "CURRENT_COMMIT is not a full lowercase Git commit SHA."
PAYLOAD_ROOT="$PAYLOAD_BASE/revisions/$SOURCE_COMMIT"

[[ -d "$PAYLOAD_ROOT" && ! -L "$PAYLOAD_ROOT" ]] || die "Published revision directory is missing: $PAYLOAD_ROOT"
[[ -f "$PAYLOAD_ROOT/.source-commit" && ! -L "$PAYLOAD_ROOT/.source-commit" ]] || die "Revision marker is missing."
[[ "$(tr -d '\r\n' < "$PAYLOAD_ROOT/.source-commit")" == "$SOURCE_COMMIT" ]] || die "Revision marker does not match CURRENT_COMMIT."

GAME_SOURCE="$PAYLOAD_ROOT/game/csgo"
ADDONS_SOURCE="$GAME_SOURCE/addons"
CSS_SOURCE="$ADDONS_SOURCE/counterstrikesharp"

[[ -d "$CSS_SOURCE/source" ]] || die "Missing staged folder: $CSS_SOURCE/source"
[[ -d "$CSS_SOURCE/plugins" ]] || die "Missing staged folder: $CSS_SOURCE/plugins"
[[ -d "$CSS_SOURCE/plugins/disabled" && ! -L "$CSS_SOURCE/plugins/disabled" ]] || die "Missing or unsafe staged folder: $CSS_SOURCE/plugins/disabled"
[[ -n "$(find "$CSS_SOURCE/plugins/disabled" -type f -print -quit)" ]] || die "No files found under staged folder: $CSS_SOURCE/plugins/disabled"
[[ -d "$CSS_SOURCE/shared" ]] || die "Missing staged folder: $CSS_SOURCE/shared"
[[ -d "$CSS_SOURCE/gamedata" ]] || die "Missing staged folder: $CSS_SOURCE/gamedata"
[[ -d "$CSS_SOURCE/configs" && ! -L "$CSS_SOURCE/configs" ]] || die "Missing or unsafe staged folder: $CSS_SOURCE/configs"
[[ -n "$(find "$CSS_SOURCE/configs" -type f -print -quit)" ]] || die "No files found under staged folder: $CSS_SOURCE/configs"
[[ -d "$GAME_SOURCE/cfg" && ! -L "$GAME_SOURCE/cfg" ]] || die "Missing or unsafe staged folder: $GAME_SOURCE/cfg"
[[ -n "$(find "$GAME_SOURCE/cfg" -type f -print -quit)" ]] || die "No files found under staged folder: $GAME_SOURCE/cfg"
for name in gamemodes_server.txt mapcycle.txt mapcyclecustom.txt subscribed_collection_ids.txt subscribed_file_ids.txt; do
    [[ -f "$GAME_SOURCE/$name" && ! -L "$GAME_SOURCE/$name" ]] || die "Missing or unsafe staged CS2 config file: $GAME_SOURCE/$name"
done
[[ -f "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" ]] || die "Missing staged VDF: $ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf"

for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    [[ -d "$ADDONS_SOURCE/$name" ]] || die "Missing staged addon directory: $ADDONS_SOURCE/$name"
done

reject_source_symlinks() {
    local source_path="$1" link_path
    while IFS= read -r -d '' link_path; do
        die "Symlink found in managed payload: $link_path"
    done < <(find "$source_path" -type l -print0)
}

for source_path in \
    "$CSS_SOURCE/source" "$CSS_SOURCE/shared" "$CSS_SOURCE/gamedata" \
    "$CSS_SOURCE/configs" "$GAME_SOURCE/cfg" \
    "$ADDONS_SOURCE/MovementUnlocker" "$ADDONS_SOURCE/serverlistplayersfix_mm" \
    "$ADDONS_SOURCE/surf" "$ADDONS_SOURCE/scripts" "$ADDONS_SOURCE/multiaddonmanager"; do
    reject_source_symlinks "$source_path"
done
while IFS= read -r -d '' link_path; do
    die "Symlink found in managed CounterStrikeSharp plugin payload: $link_path"
done < <(
    find "$CSS_SOURCE/plugins" -mindepth 1 \
        \( -path "$CSS_SOURCE/plugins/BotAI" \
           -o -path "$CSS_SOURCE/plugins/CS2UpdateMonitor" \) -prune \
        -o -type l -print0
)
for name in gamemodes_server.txt mapcycle.txt mapcyclecustom.txt subscribed_collection_ids.txt subscribed_file_ids.txt; do
    [[ ! -L "$GAME_SOURCE/$name" ]] || die "Managed CS2 config file must not be a symlink: $GAME_SOURCE/$name"
done
[[ ! -L "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" ]] || die "Managed VDF must not be a symlink."

CSS_TARGET="$GAME_ROOT/addons/counterstrikesharp"
MANAGED_FILES=(
    "gamemodes_server.txt"
    "mapcycle.txt"
    "mapcyclecustom.txt"
    "subscribed_collection_ids.txt"
    "subscribed_file_ids.txt"
)
MANAGED_ROOTS=(
    "$CSS_TARGET/source"
    "$CSS_TARGET/plugins"
    "$CSS_TARGET/shared"
    "$CSS_TARGET/gamedata"
    "$CSS_TARGET/configs"
    "$GAME_ROOT/cfg"
    "$GAME_ROOT/addons/MovementUnlocker"
    "$GAME_ROOT/addons/serverlistplayersfix_mm"
    "$GAME_ROOT/addons/surf"
    "$GAME_ROOT/addons/scripts"
    "$GAME_ROOT/addons/multiaddonmanager"
)

for target_path in "$GAME_ROOT" "$GAME_ROOT/addons" "$CSS_TARGET" "${MANAGED_ROOTS[@]}" "$GAME_ROOT/addons/metamod"; do
    [[ ! -L "$target_path" ]] || die "Managed target path is a symlink: $target_path"
done
for relative_file in "${MANAGED_FILES[@]}"; do
    [[ ! -L "$GAME_ROOT/$relative_file" ]] || die "Managed target file is a symlink: $GAME_ROOT/$relative_file"
done

# Reject symlinks inside managed targets rather than risk following a redirected path.
for managed_root in "${MANAGED_ROOTS[@]}"; do
    [[ -d "$managed_root" ]] || continue
    while IFS= read -r -d '' link_path; do
        die "Symlink found inside managed target tree: $link_path"
    done < <(
        if [[ "$managed_root" == "$CSS_TARGET/plugins" ]]; then
            find "$managed_root" -mindepth 1 \
                \( -path "$managed_root/BotAI" \
                   -o -path "$managed_root/CS2UpdateMonitor" \) -prune \
                -o -type l -print0
        else
            find "$managed_root" -type l -print0
        fi
    )
done

declare -A DESIRED_SOURCE=()
declare -A DESIRED_HASH=()

add_file() {
    local relative_path="$1" source_path="$2" source_hash
    [[ -f "$source_path" ]] || die "Expected staged payload file does not exist: $source_path"
    source_hash="$(sha256sum -- "$source_path" | awk '{print $1}')"
    [[ -n "$source_hash" ]] || die "Could not calculate SHA-256 for: $source_path"
    DESIRED_SOURCE["$relative_path"]="$source_path"
    DESIRED_HASH["$relative_path"]="$source_hash"
}

add_tree() {
    local source_dir="$1" target_relative_dir="$2" skip_protected_plugin_dirs="${3:-0}"
    local source_file relative_file
    [[ -d "$source_dir" ]] || die "Missing staged source directory: $source_dir"

    if [[ "$skip_protected_plugin_dirs" -eq 1 ]]; then
        while IFS= read -r -d '' source_file; do
            relative_file="${source_file#"$source_dir"/}"
            add_file "$target_relative_dir/$relative_file" "$source_file"
        done < <(
            find "$source_dir" -mindepth 1 \
                \( -path "$source_dir/BotAI" \
                   -o -path "$source_dir/CS2UpdateMonitor" \) -prune \
                -o -type f -print0
        )
    else
        while IFS= read -r -d '' source_file; do
            relative_file="${source_file#"$source_dir"/}"
            add_file "$target_relative_dir/$relative_file" "$source_file"
        done < <(find "$source_dir" -type f -print0)
    fi
}

log "Target server UUID: $SERVER_UUID."
log "Using published payload revision $SOURCE_COMMIT."
log "Building the desired-file list from the immutable snapshot."
add_tree "$CSS_SOURCE/source" "addons/counterstrikesharp/source"
add_tree "$CSS_SOURCE/plugins" "addons/counterstrikesharp/plugins" 1
add_tree "$CSS_SOURCE/shared" "addons/counterstrikesharp/shared"
add_tree "$CSS_SOURCE/gamedata" "addons/counterstrikesharp/gamedata"
add_tree "$CSS_SOURCE/configs" "addons/counterstrikesharp/configs"
add_tree "$GAME_SOURCE/cfg" "cfg"
for name in gamemodes_server.txt mapcycle.txt mapcyclecustom.txt subscribed_collection_ids.txt subscribed_file_ids.txt; do
    add_file "$name" "$GAME_SOURCE/$name"
done
for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    add_tree "$ADDONS_SOURCE/$name" "addons/$name"
done
add_file "addons/metamod/serverlistplayersfix_mm.vdf" "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf"

for managed_root in "${MANAGED_ROOTS[@]}"; do mkdir -p -- "$managed_root"; done
mkdir -p -- "$GAME_ROOT/addons/metamod"

COPIED=0
UNCHANGED=0
VERIFIED=0

# Transfer only missing/changed files. Each changed copy is verified before cleanup.
for relative_path in "${!DESIRED_SOURCE[@]}"; do
    source_path="${DESIRED_SOURCE[$relative_path]}"
    expected_hash="${DESIRED_HASH[$relative_path]}"
    target_path="$GAME_ROOT/$relative_path"
    [[ ! -L "$target_path" ]] || die "Managed target file is a symlink: $target_path"

    actual_hash=""
    if [[ -f "$target_path" ]]; then
        actual_hash="$(sha256sum -- "$target_path" | awk 'NR == 1 {print $1}')"
    fi

    if [[ "$actual_hash" == "$expected_hash" ]]; then
        UNCHANGED=$((UNCHANGED + 1))
        VERIFIED=$((VERIFIED + 1))
        continue
    fi

    if [[ "$VERBOSE" == "1" ]]; then
        log "Updating $relative_path (missing or SHA-256 differs)."
    fi
    mkdir -p -- "$(dirname -- "$target_path")"
    # A published snapshot is read-only; deployed files should remain editable by
    # the server's container user, as in an ordinary Pterodactyl game volume.
    if [[ -e "$target_path" ]]; then
        chmod u+w -- "$target_path" || die "Could not make managed target writable before copy: $target_path"
    fi
    cp -- "$source_path" "$target_path"
    chmod u+w -- "$target_path" || die "Could not make managed target writable after copy: $target_path"

    actual_hash="$(sha256sum -- "$target_path" | awk 'NR == 1 {print $1}')"
    [[ "$actual_hash" == "$expected_hash" ]] || die "SHA-256 verification failed after copy: $relative_path"
    COPIED=$((COPIED + 1))
    VERIFIED=$((VERIFIED + 1))
done

# Stale cleanup runs only after all desired files have passed hash verification.
DELETED=0
for managed_root in "${MANAGED_ROOTS[@]}"; do
    while IFS= read -r -d '' target_path; do
        relative_path="${target_path#"$GAME_ROOT"/}"
        case "$relative_path" in
            addons/counterstrikesharp/plugins/BotAI|addons/counterstrikesharp/plugins/BotAI/*|\
            addons/counterstrikesharp/plugins/CS2UpdateMonitor|addons/counterstrikesharp/plugins/CS2UpdateMonitor/*)
                continue
                ;;
        esac
        if [[ -z "${DESIRED_SOURCE[$relative_path]+present}" ]]; then
            log "Removing stale managed file: $relative_path"
            rm -f -- "$target_path"
            DELETED=$((DELETED + 1))
        fi
    done < <(find "$managed_root" -type f -print0)
done

for relative_path in "${MANAGED_FILES[@]}"; do
    target_path="$GAME_ROOT/$relative_path"
    [[ ! -L "$target_path" ]] || die "Managed target file is a symlink: $target_path"
    if [[ -e "$target_path" && -z "${DESIRED_SOURCE[$relative_path]+present}" ]]; then
        log "Removing stale managed file: $relative_path"
        rm -f -- "$target_path"
        DELETED=$((DELETED + 1))
    fi
done

for managed_root in "${MANAGED_ROOTS[@]}"; do
    if [[ "$managed_root" == "$CSS_TARGET/plugins" ]]; then
        find "$managed_root" -mindepth 1 -depth -type d -empty \
            ! -path "$managed_root/BotAI" ! -path "$managed_root/BotAI/*" \
            ! -path "$managed_root/CS2UpdateMonitor" ! -path "$managed_root/CS2UpdateMonitor/*" -delete
    else
        find "$managed_root" -mindepth 1 -depth -type d -empty -delete
    fi
done

log "Sync completed successfully."
log "Files copied: $COPIED; already matching SHA-256: $UNCHANGED; verified: $VERIFIED; stale files removed: $DELETED."
log "BotAI/ and CS2UpdateMonitor/ plugin directories were not copied or pruned."
log "plugins/disabled/ was synced from the published payload and remains under disabled/."
log "CounterStrikeSharp configs/, cfg/, and the five top-level CS2 config/list files were synced from the repository."
log "Egg-managed Metamod/CounterStrikeSharp runtime files were not touched."
