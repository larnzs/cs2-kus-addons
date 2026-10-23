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
#   addons/counterstrikesharp/plugins/disabled/
#   cfg/ and CounterStrikeSharp configs
#   Egg-managed Metamod/CounterStrikeSharp runtime directories

set -Eeuo pipefail

PAYLOAD_BASE="${FRAGCITY_PAYLOAD_BASE:-/home/container/egg/fragcity-payload}"
GAME_ROOT="${FRAGCITY_GAME_ROOT:-/home/container/game/csgo}"

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

command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required."
command -v find >/dev/null 2>&1 || die "find is required."
command -v cp >/dev/null 2>&1 || die "cp is required."
command -v mkdir >/dev/null 2>&1 || die "mkdir is required."
command -v rm >/dev/null 2>&1 || die "rm is required."
command -v awk >/dev/null 2>&1 || die "awk is required."
command -v flock >/dev/null 2>&1 || die "flock is required."

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
[[ -d "$CSS_SOURCE/shared" ]] || die "Missing staged folder: $CSS_SOURCE/shared"
[[ -d "$CSS_SOURCE/gamedata" ]] || die "Missing staged folder: $CSS_SOURCE/gamedata"
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
    "$ADDONS_SOURCE/MovementUnlocker" "$ADDONS_SOURCE/serverlistplayersfix_mm" \
    "$ADDONS_SOURCE/surf" "$ADDONS_SOURCE/scripts" "$ADDONS_SOURCE/multiaddonmanager"; do
    reject_source_symlinks "$source_path"
done
while IFS= read -r -d '' link_path; do
    die "Symlink found in managed CounterStrikeSharp plugin payload: $link_path"
done < <(
    find "$CSS_SOURCE/plugins" -mindepth 1 \
        \( -path "$CSS_SOURCE/plugins/BotAI" -o -path "$CSS_SOURCE/plugins/disabled" \) -prune \
        -o -type l -print0
)
[[ ! -L "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" ]] || die "Managed VDF must not be a symlink."

CSS_TARGET="$GAME_ROOT/addons/counterstrikesharp"
MANAGED_ROOTS=(
    "$CSS_TARGET/source"
    "$CSS_TARGET/plugins"
    "$CSS_TARGET/shared"
    "$CSS_TARGET/gamedata"
    "$GAME_ROOT/addons/MovementUnlocker"
    "$GAME_ROOT/addons/serverlistplayersfix_mm"
    "$GAME_ROOT/addons/surf"
    "$GAME_ROOT/addons/scripts"
    "$GAME_ROOT/addons/multiaddonmanager"
)

for target_path in "$GAME_ROOT" "$GAME_ROOT/addons" "$CSS_TARGET" "${MANAGED_ROOTS[@]}" "$GAME_ROOT/addons/metamod"; do
    [[ ! -L "$target_path" ]] || die "Managed target path is a symlink: $target_path"
done

# Reject symlinks inside managed targets rather than risk following a redirected path.
for managed_root in "${MANAGED_ROOTS[@]}"; do
    [[ -d "$managed_root" ]] || continue
    while IFS= read -r -d '' link_path; do
        die "Symlink found inside managed target tree: $link_path"
    done < <(
        if [[ "$managed_root" == "$CSS_TARGET/plugins" ]]; then
            find "$managed_root" -mindepth 1 \
                \( -path "$managed_root/BotAI" -o -path "$managed_root/disabled" \) -prune \
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
    local source_dir="$1" target_relative_dir="$2" exclude_botai_disabled="${3:-0}"
    local source_file relative_file
    [[ -d "$source_dir" ]] || die "Missing staged source directory: $source_dir"

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

log "Using published payload revision $SOURCE_COMMIT."
log "Building the desired-file list from the immutable snapshot."
add_tree "$CSS_SOURCE/source" "addons/counterstrikesharp/source"
add_tree "$CSS_SOURCE/plugins" "addons/counterstrikesharp/plugins" 1
add_tree "$CSS_SOURCE/shared" "addons/counterstrikesharp/shared"
add_tree "$CSS_SOURCE/gamedata" "addons/counterstrikesharp/gamedata"
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

    log "Updating $relative_path (missing or SHA-256 differs)."
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
            addons/counterstrikesharp/plugins/disabled|addons/counterstrikesharp/plugins/disabled/*)
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

for managed_root in "${MANAGED_ROOTS[@]}"; do
    if [[ "$managed_root" == "$CSS_TARGET/plugins" ]]; then
        find "$managed_root" -mindepth 1 -depth -type d -empty \
            ! -path "$managed_root/BotAI" ! -path "$managed_root/BotAI/*" \
            ! -path "$managed_root/disabled" ! -path "$managed_root/disabled/*" -delete
    else
        find "$managed_root" -mindepth 1 -depth -type d -empty -delete
    fi
done

log "Sync completed successfully."
log "Files copied: $COPIED; already matching SHA-256: $UNCHANGED; verified: $VERIFIED; stale files removed: $DELETED."
log "BotAI/ and disabled/ were not copied or pruned."
log "cfg/configs and Egg-managed Metamod/CounterStrikeSharp runtime files were not touched."
