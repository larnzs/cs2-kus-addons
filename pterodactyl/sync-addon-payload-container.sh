#!/usr/bin/env bash
# Container-side FragCity addon synchronizer for the custom K4ryuu/Pterodactyl Egg.
#
# This script runs INSIDE the game container, after K4ryuu has updated the
# Metamod/CounterStrikeSharp runtime and immediately before CS2 is launched.
# The Egg installer must stage this script and the selected payload under:
#   /home/container/egg/fragcity-payload/
# with the repo-relative layout preserved (including game/csgo and pterodactyl/).
#
# Only FragCity-managed addon paths are synced/pruned. The Egg-managed runtime,
# cfg/configs, and these user-managed plugin folders are deliberately untouched:
#   addons/counterstrikesharp/plugins/BotAI/
#   addons/counterstrikesharp/plugins/disabled/

set -Eeuo pipefail

PAYLOAD_ROOT="${FRAGCITY_PAYLOAD_ROOT:-/home/container/egg/fragcity-payload}"
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

validate_absolute_path "FRAGCITY_PAYLOAD_ROOT" "$PAYLOAD_ROOT"
validate_absolute_path "FRAGCITY_GAME_ROOT" "$GAME_ROOT"

command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required in the container."
command -v find >/dev/null 2>&1 || die "find is required in the container."
command -v cp >/dev/null 2>&1 || die "cp is required in the container."
command -v mkdir >/dev/null 2>&1 || die "mkdir is required in the container."
command -v rm >/dev/null 2>&1 || die "rm is required in the container."
command -v awk >/dev/null 2>&1 || die "awk is required in the container."

REPO_ROOT="$PAYLOAD_ROOT"
GAME_SOURCE="$REPO_ROOT/game/csgo"
ADDONS_SOURCE="$GAME_SOURCE/addons"
CSS_SOURCE="$ADDONS_SOURCE/counterstrikesharp"

[[ -d "$PAYLOAD_ROOT" ]] || die "Staged payload root not found: $PAYLOAD_ROOT (Egg install script must stage it first)."
[[ -d "$CSS_SOURCE/source" ]] || die "Missing staged folder: $CSS_SOURCE/source"
[[ -d "$CSS_SOURCE/plugins" ]] || die "Missing staged folder: $CSS_SOURCE/plugins"
[[ -d "$CSS_SOURCE/shared" ]] || die "Missing staged folder: $CSS_SOURCE/shared"
[[ -d "$CSS_SOURCE/gamedata" ]] || die "Missing staged folder: $CSS_SOURCE/gamedata"
[[ -f "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" ]] || die "Missing staged VDF: $ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf"

for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    [[ -d "$ADDONS_SOURCE/$name" ]] || die "Missing staged addon directory: $ADDONS_SOURCE/$name"
done

# Reject symlinks in managed source content. BotAI/ and disabled/ are excluded
# from the sync contract and therefore pruned from checks, copies, and cleanup.
reject_source_symlinks() {
    local source_path="$1"
    local source_label="$2"
    local link_path
    while IFS= read -r -d '' link_path; do
        die "Symlink found in managed payload ($source_label): $link_path"
    done < <(find "$source_path" -type l -print0)
}

for source_path in \
    "$CSS_SOURCE/source" "$CSS_SOURCE/shared" "$CSS_SOURCE/gamedata" \
    "$ADDONS_SOURCE/MovementUnlocker" "$ADDONS_SOURCE/serverlistplayersfix_mm" \
    "$ADDONS_SOURCE/surf" "$ADDONS_SOURCE/scripts" "$ADDONS_SOURCE/multiaddonmanager"; do
    reject_source_symlinks "$source_path" "$source_path"
done
while IFS= read -r -d '' link_path; do
    die "Symlink found in managed payload (CounterStrikeSharp plugins): $link_path"
done < <(
    find "$CSS_SOURCE/plugins" -mindepth 1 \
        \( -path "$CSS_SOURCE/plugins/BotAI" -o -path "$CSS_SOURCE/plugins/disabled" \) -prune \
        -o -type l -print0
)
[[ ! -L "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" ]] || die "Managed VDF must not be a symlink."

# Managed paths inside the CS2 game directory. No other paths are modified.
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

# Avoid following symlinked directory roots, which could redirect writes or
# deletion outside the explicitly managed tree.
for managed_path in \
    "$GAME_ROOT" "$GAME_ROOT/addons" "$CSS_TARGET" \
    "${MANAGED_ROOTS[@]}" "$GAME_ROOT/addons/metamod"; do
    [[ ! -L "$managed_path" ]] || die "Managed target path is a symlink: $managed_path"
done

# Symlinks anywhere inside managed roots are unexpected; fail safely rather
# than copy through or prune a path whose destination is ambiguous.
for managed_root in "${MANAGED_ROOTS[@]}"; do
    if [[ -d "$managed_root" ]]; then
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
    fi
done

declare -A DESIRED_SOURCE=()
declare -A DESIRED_HASH=()

add_file() {
    local relative_path="$1"
    local source_path="$2"
    local source_hash
    [[ -f "$source_path" ]] || die "Expected staged payload file does not exist: $source_path"
    source_hash="$(sha256sum -- "$source_path" | awk '{print $1}')"
    [[ -n "$source_hash" ]] || die "Could not calculate SHA-256 for: $source_path"
    DESIRED_SOURCE["$relative_path"]="$source_path"
    DESIRED_HASH["$relative_path"]="$source_hash"
}

add_tree() {
    local source_dir="$1"
    local target_relative_dir="$2"
    local exclude_botai_disabled="${3:-0}"
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

log "Building the desired-file list from staged FragCity payload."
add_tree "$CSS_SOURCE/source" "addons/counterstrikesharp/source"
add_tree "$CSS_SOURCE/plugins" "addons/counterstrikesharp/plugins" 1
add_tree "$CSS_SOURCE/shared" "addons/counterstrikesharp/shared"
add_tree "$CSS_SOURCE/gamedata" "addons/counterstrikesharp/gamedata"
for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    add_tree "$ADDONS_SOURCE/$name" "addons/$name"
done
add_file "addons/metamod/serverlistplayersfix_mm.vdf" "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf"

for managed_root in "${MANAGED_ROOTS[@]}"; do
    mkdir -p -- "$managed_root"
done
mkdir -p -- "$GAME_ROOT/addons/metamod"

COPIED=0
UNCHANGED=0
VERIFIED=0

# Hash-first sync: don't write files already identical to the staged payload.
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

    log "Updating ${relative_path} (missing or SHA-256 differs)."
    mkdir -p -- "$(dirname -- "$target_path")"
    cp -p -- "$source_path" "$target_path"

    actual_hash="$(sha256sum -- "$target_path" | awk 'NR == 1 {print $1}')"
    [[ "$actual_hash" == "$expected_hash" ]] || die "SHA-256 verification failed after copy: $relative_path"
    COPIED=$((COPIED + 1))
    VERIFIED=$((VERIFIED + 1))
done

# Only prune stale files after every staged file was copied/verified.
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

# Remove only empty directories under the managed roots, while protecting the
# user-managed BotAI/ and disabled/ subtrees from even empty-dir pruning.
for managed_root in "${MANAGED_ROOTS[@]}"; do
    if [[ "$managed_root" == "$CSS_TARGET/plugins" ]]; then
        find "$managed_root" -mindepth 1 -depth -type d -empty \
            ! -path "$managed_root/BotAI" ! -path "$managed_root/BotAI/*" \
            ! -path "$managed_root/disabled" ! -path "$managed_root/disabled/*" \
            -delete
    else
        find "$managed_root" -mindepth 1 -depth -type d -empty -delete
    fi
done

log "Sync completed successfully."
log "Files copied: $COPIED; already matching SHA-256: $UNCHANGED; verified: $VERIFIED; stale files removed: $DELETED."
log "BotAI/ and disabled/ were not copied or pruned."
log "cfg/configs and Egg-managed Metamod/CounterStrikeSharp runtime files were not touched."
