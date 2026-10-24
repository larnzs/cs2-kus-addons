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
# Configs are one-time first-install seed files, not update-managed files:
#   Only a newly provisioned volume carrying .fragcity-config-seed-v1.state with
#   mode=pending receives the repository CounterStrikeSharp configs/, listed custom
#   cfg/ files, and five top-level CS2 config/list files. On success, mode=completed
#   is appended to that per-volume state file. Existing volumes without a state file
#   are treated as legacy and their configs are never overwritten or pruned.
# Plugin/source/shared/gamedata and allowlisted addon payloads continue to sync
# every normal server start with SHA-256 validation and stale managed-file cleanup.

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

case "$GAME_ROOT" in
    */game/csgo) SERVER_ROOT="${GAME_ROOT%/game/csgo}" ;;
    *) die "FRAGCITY_GAME_ROOT must end in /game/csgo so the server volume root can be identified safely." ;;
esac
[[ -d "$SERVER_ROOT" && ! -L "$SERVER_ROOT" ]] || die "Server volume root is missing or unsafe: $SERVER_ROOT"

CONFIG_SEED_STATE="$SERVER_ROOT/.fragcity-config-seed-v1.state"
MANAGED_MANIFEST="$SERVER_ROOT/.fragcity-managed-payload-v1.list"
CONFIG_SEED_ACTIVE=0
[[ ! -L "$MANAGED_MANIFEST" ]] || die "Managed-payload manifest must not be a symlink: $MANAGED_MANIFEST"
[[ ! -e "$MANAGED_MANIFEST" || -f "$MANAGED_MANIFEST" ]] || die "Managed-payload manifest must be a regular file: $MANAGED_MANIFEST"

[[ ! -L "$CONFIG_SEED_STATE" ]] || die "Config seed state file must not be a symlink: $CONFIG_SEED_STATE"
[[ ! -e "$CONFIG_SEED_STATE" || -f "$CONFIG_SEED_STATE" ]] || die "Config seed state path must be a regular file: $CONFIG_SEED_STATE"

if [[ -f "$CONFIG_SEED_STATE" ]]; then
    grep -Fxq 'fragcity-config-seed-v1' "$CONFIG_SEED_STATE" \
        && grep -Fxq "server_uuid=$SERVER_UUID" "$CONFIG_SEED_STATE" \
        || die "Config-seed state does not match this server UUID."
    if grep -Fxq 'mode=completed' "$CONFIG_SEED_STATE"; then
        log "First-install config seed already completed; all cfg/configs/txt files will be preserved."
    elif grep -Fxq 'mode=pending' "$CONFIG_SEED_STATE"; then
        [[ -w "$CONFIG_SEED_STATE" ]] || die "Pending config-seed state is not writable; refusing to seed configs without being able to record completion."
        CONFIG_SEED_ACTIVE=1
        log "New-server first-install config seed is pending; config files will be installed once."
    else
        die "Config-seed state has no recognized pending/completed mode."
    fi
else
    # Existing servers from before this feature have no state marker. Do not
    # initialize a seed marker here: no marker means preserve all customer config.
    log "No first-install marker found; treating this as an existing server and preserving all cfg/configs/txt files."
fi

for command_name in sha256sum find cp mkdir rm awk flock tr chmod dirname grep date sort mv; do
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
CONFIG_FILES=(
    "gamemodes_server.txt"
    "mapcycle.txt"
    "mapcyclecustom.txt"
    "subscribed_collection_ids.txt"
    "subscribed_file_ids.txt"
)
CONFIG_ROOT="$CSS_TARGET/configs"
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
if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    # These are included in managed paths only during a brand-new server's seed.
    # On subsequent starts they are omitted from both copy and stale cleanup.
    MANAGED_ROOTS+=("$CONFIG_ROOT")
fi

for target_path in "$GAME_ROOT" "$GAME_ROOT/addons" "$CSS_TARGET" "${MANAGED_ROOTS[@]}" "$GAME_ROOT/addons/metamod"; do
    [[ ! -L "$target_path" ]] || die "Managed target path is a symlink: $target_path"
done
if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    [[ ! -L "$CONFIG_ROOT" && ! -L "$GAME_ROOT/cfg" ]] || die "First-install config target path is a symlink."
    for relative_file in "${CONFIG_FILES[@]}"; do
        [[ ! -L "$GAME_ROOT/$relative_file" ]] || die "First-install config target file is a symlink: $GAME_ROOT/$relative_file"
    done
fi

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

assert_no_symlink_parent_components() {
    local target_path="$1" relative_path current_path part component_index
    local -a components=()

    case "$target_path" in
        "$GAME_ROOT"/*) relative_path="${target_path#"$GAME_ROOT"/}" ;;
        *) die "Refusing to write outside GAME_ROOT: $target_path" ;;
    esac

    IFS='/' read -r -a components <<< "$relative_path"
    current_path="$GAME_ROOT"
    for ((component_index = 0; component_index < ${#components[@]} - 1; component_index++)); do
        part="${components[$component_index]}"
        current_path="$current_path/$part"
        [[ ! -L "$current_path" ]] || die "Refusing to write through symlinked parent path: $current_path"
    done
}

# Only files shipped by this payload are eligible for manifest-based stale cleanup.
# Anything created by a running plugin but absent from the repository is unmanaged
# and must not be deleted (for example PlayerSettings/settings.sqlite or bans.db).
is_payload_managed_path() {
    local path="$1"
    [[ -n "$path" && "$path" != /* && "$path" != *
log "Target server UUID: $SERVER_UUID."
log "Using published payload revision $SOURCE_COMMIT."
log "Building the desired-file list from the immutable snapshot."
add_tree "$CSS_SOURCE/source" "addons/counterstrikesharp/source"
add_tree "$CSS_SOURCE/plugins" "addons/counterstrikesharp/plugins" 1
add_tree "$CSS_SOURCE/shared" "addons/counterstrikesharp/shared"
add_tree "$CSS_SOURCE/gamedata" "addons/counterstrikesharp/gamedata"
if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    add_tree "$CSS_SOURCE/configs" "addons/counterstrikesharp/configs"
    add_tree "$GAME_SOURCE/cfg" "cfg"
    for name in "${CONFIG_FILES[@]}"; do
        add_file "$name" "$GAME_SOURCE/$name"
    done
fi
for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    add_tree "$ADDONS_SOURCE/$name" "addons/$name"
done
add_file "addons/metamod/serverlistplayersfix_mm.vdf" "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf"

# Read the last successful managed-file inventory before writing anything. A missing
# manifest is the safe rollout path: preserve all untracked files this first time.
declare -A PREVIOUS_MANAGED=()
MANIFEST_PRESENT=0
if [[ -f "$MANAGED_MANIFEST" ]]; then
    MANIFEST_PRESENT=1
    while IFS= read -r previous_path || [[ -n "$previous_path" ]]; do
        [[ -z "$previous_path" || "$previous_path" == "# fragcity-managed-payload-v1" ]] && continue
        is_payload_managed_path "$previous_path" || die "Unsafe path in managed-payload manifest: $previous_path"
        PREVIOUS_MANAGED["$previous_path"]=1
    done < "$MANAGED_MANIFEST"
fi

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
    assert_no_symlink_parent_components "$target_path"
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

# Stale cleanup is allowed only for files listed in the previous successful manifest.
# Never delete an untracked file merely because it lives inside a plugin directory.
DELETED=0
if [[ "$MANIFEST_PRESENT" -eq 1 ]]; then
    for relative_path in "${!PREVIOUS_MANAGED[@]}"; do
        [[ -n "${DESIRED_SOURCE[$relative_path]+present}" ]] && continue
        target_path="$GAME_ROOT/$relative_path"
        assert_no_symlink_parent_components "$target_path"
        [[ ! -L "$target_path" ]] || die "Previous managed payload target is a symlink: $target_path"
        if [[ -e "$target_path" ]]; then
            [[ -f "$target_path" ]] || die "Previous managed payload target is not a regular file: $target_path"
            log "Removing stale previously-managed payload file: $relative_path"
            rm -f -- "$target_path"
            DELETED=$((DELETED + 1))
        fi
    done
else
    log "No prior managed-payload manifest; skipping stale-file deletion on this rollout to preserve existing plugin/runtime data."
fi

# CounterStrikeSharp configs/ is pruned only while a new server is receiving its
# one-time config seed. After that, customer edits and generated files are untouched.
if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    while IFS= read -r -d '' target_path; do
        relative_path="${target_path#"$GAME_ROOT"/}"
        if [[ -z "${DESIRED_SOURCE[$relative_path]+present}" ]]; then
            assert_no_symlink_parent_components "$target_path"
            [[ ! -L "$target_path" ]] || die "First-install config target is a symlink: $target_path"
            log "Removing stale first-install config file: $relative_path"
            rm -f -- "$target_path"
            DELETED=$((DELETED + 1))
        fi
    done < <(find "$CONFIG_ROOT" -type f -print0)
fi

if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    for relative_path in "${CONFIG_FILES[@]}"; do
        target_path="$GAME_ROOT/$relative_path"
        [[ ! -L "$target_path" ]] || die "First-install config target file is a symlink: $target_path"
        if [[ -e "$target_path" && -z "${DESIRED_SOURCE[$relative_path]+present}" ]]; then
            log "Removing stale first-install config file: $relative_path"
            rm -f -- "$target_path"
            DELETED=$((DELETED + 1))
        fi
    done
fi

for managed_root in "${MANAGED_ROOTS[@]}"; do
    # Empty plugin directories may belong to runtime/plugin data; leave them alone.
    [[ "$managed_root" == "$CSS_TARGET/plugins" ]] && continue
    find "$managed_root" -mindepth 1 -depth -type d -empty -delete
done

# Publish the new manifest atomically only after copies and cleanup have succeeded.
manifest_tmp="$MANAGED_MANIFEST.tmp.$BASHPID"
[[ ! -e "$manifest_tmp" && ! -L "$manifest_tmp" ]] || die "Managed-payload manifest temp path already exists."
{
    printf '# fragcity-managed-payload-v1\n'
    for relative_path in "${!DESIRED_SOURCE[@]}"; do
        if is_payload_managed_path "$relative_path"; then
            printf '%s\n' "$relative_path"
        fi
    done
} | sort -u > "$manifest_tmp" || die "Could not write managed-payload manifest."
chmod 0644 "$manifest_tmp" || die "Could not set managed-payload manifest permissions."
mv -f -- "$manifest_tmp" "$MANAGED_MANIFEST" || die "Could not atomically publish managed-payload manifest."

if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    # The host provisioner creates this per-volume state file with mode 0666:
    # the isolated game-container user can record completion even if it cannot
    # create new entries in the root of the bind-mounted server volume.
    printf 'mode=completed\nsource_commit=%s\ncompleted_at_utc=%s\n' "$SOURCE_COMMIT" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$CONFIG_SEED_STATE" \
        || die "Could not record one-time config-seed completion; refusing to report a successful sync."
    log "First-install config seed completed successfully; future starts will never overwrite or prune cfg/configs/txt files."
else
    log "First-install config seed not active; all existing cfg/configs/txt settings were preserved."
fi

log "Sync completed successfully."
log "Files copied: $COPIED; already matching SHA-256: $UNCHANGED; verified: $VERIFIED; stale files removed: $DELETED."
log "BotAI/ and CS2UpdateMonitor/ plugin directories were not copied or pruned."
log "plugins/disabled/ was synced from the published payload and remains under disabled/."
if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    log "CounterStrikeSharp configs/, listed cfg/ files, and five top-level CS2 config/list files were installed as first-install defaults."
else
    log "CounterStrikeSharp configs/, cfg/, and five top-level CS2 config/list files were not copied or stale-pruned."
fi
log "Egg-managed Metamod/CounterStrikeSharp runtime files were not touched."
\n'* && "$path" != *
log "Target server UUID: $SERVER_UUID."
log "Using published payload revision $SOURCE_COMMIT."
log "Building the desired-file list from the immutable snapshot."
add_tree "$CSS_SOURCE/source" "addons/counterstrikesharp/source"
add_tree "$CSS_SOURCE/plugins" "addons/counterstrikesharp/plugins" 1
add_tree "$CSS_SOURCE/shared" "addons/counterstrikesharp/shared"
add_tree "$CSS_SOURCE/gamedata" "addons/counterstrikesharp/gamedata"
if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    add_tree "$CSS_SOURCE/configs" "addons/counterstrikesharp/configs"
    add_tree "$GAME_SOURCE/cfg" "cfg"
    for name in "${CONFIG_FILES[@]}"; do
        add_file "$name" "$GAME_SOURCE/$name"
    done
fi
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
    assert_no_symlink_parent_components "$target_path"
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

if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    for relative_path in "${CONFIG_FILES[@]}"; do
        target_path="$GAME_ROOT/$relative_path"
        [[ ! -L "$target_path" ]] || die "First-install config target file is a symlink: $target_path"
        if [[ -e "$target_path" && -z "${DESIRED_SOURCE[$relative_path]+present}" ]]; then
            log "Removing stale first-install config file: $relative_path"
            rm -f -- "$target_path"
            DELETED=$((DELETED + 1))
        fi
    done
fi

for managed_root in "${MANAGED_ROOTS[@]}"; do
    if [[ "$managed_root" == "$CSS_TARGET/plugins" ]]; then
        find "$managed_root" -mindepth 1 -depth -type d -empty \
            ! -path "$managed_root/BotAI" ! -path "$managed_root/BotAI/*" \
            ! -path "$managed_root/CS2UpdateMonitor" ! -path "$managed_root/CS2UpdateMonitor/*" -delete
    else
        find "$managed_root" -mindepth 1 -depth -type d -empty -delete
    fi
done

if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    # The host provisioner creates this per-volume state file with mode 0666:
    # the isolated game-container user can record completion even if it cannot
    # create new entries in the root of the bind-mounted server volume.
    printf 'mode=completed\nsource_commit=%s\ncompleted_at_utc=%s\n' "$SOURCE_COMMIT" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$CONFIG_SEED_STATE" \
        || die "Could not record one-time config-seed completion; refusing to report a successful sync."
    log "First-install config seed completed successfully; future starts will never overwrite or prune cfg/configs/txt files."
else
    log "First-install config seed not active; all existing cfg/configs/txt settings were preserved."
fi

log "Sync completed successfully."
log "Files copied: $COPIED; already matching SHA-256: $UNCHANGED; verified: $VERIFIED; stale files removed: $DELETED."
log "BotAI/ and CS2UpdateMonitor/ plugin directories were not copied or pruned."
log "plugins/disabled/ was synced from the published payload and remains under disabled/."
if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    log "CounterStrikeSharp configs/, listed cfg/ files, and five top-level CS2 config/list files were installed as first-install defaults."
else
    log "CounterStrikeSharp configs/, cfg/, and five top-level CS2 config/list files were not copied or stale-pruned."
fi
log "Egg-managed Metamod/CounterStrikeSharp runtime files were not touched."
\r'* ]] || return 1
    case "/$path/" in
        *"/../"*|*"/./"*|*"//"*) return 1 ;;
    esac
    case "$path" in
        addons/counterstrikesharp/source/*|\
        addons/counterstrikesharp/plugins/*|\
        addons/counterstrikesharp/shared/*|\
        addons/counterstrikesharp/gamedata/*|\
        addons/MovementUnlocker/*|\
        addons/serverlistplayersfix_mm/*|\
        addons/surf/*|\
        addons/scripts/*|\
        addons/multiaddonmanager/*|\
        addons/metamod/serverlistplayersfix_mm.vdf)
            ;;
        *)
            return 1
            ;;
    esac
    case "$path" in
        addons/counterstrikesharp/plugins/BotAI|addons/counterstrikesharp/plugins/BotAI/*|\
        addons/counterstrikesharp/plugins/CS2UpdateMonitor|addons/counterstrikesharp/plugins/CS2UpdateMonitor/*)
            return 1
            ;;
    esac
    return 0
}

log "Target server UUID: $SERVER_UUID."
log "Using published payload revision $SOURCE_COMMIT."
log "Building the desired-file list from the immutable snapshot."
add_tree "$CSS_SOURCE/source" "addons/counterstrikesharp/source"
add_tree "$CSS_SOURCE/plugins" "addons/counterstrikesharp/plugins" 1
add_tree "$CSS_SOURCE/shared" "addons/counterstrikesharp/shared"
add_tree "$CSS_SOURCE/gamedata" "addons/counterstrikesharp/gamedata"
if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    add_tree "$CSS_SOURCE/configs" "addons/counterstrikesharp/configs"
    add_tree "$GAME_SOURCE/cfg" "cfg"
    for name in "${CONFIG_FILES[@]}"; do
        add_file "$name" "$GAME_SOURCE/$name"
    done
fi
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
    assert_no_symlink_parent_components "$target_path"
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

if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    for relative_path in "${CONFIG_FILES[@]}"; do
        target_path="$GAME_ROOT/$relative_path"
        [[ ! -L "$target_path" ]] || die "First-install config target file is a symlink: $target_path"
        if [[ -e "$target_path" && -z "${DESIRED_SOURCE[$relative_path]+present}" ]]; then
            log "Removing stale first-install config file: $relative_path"
            rm -f -- "$target_path"
            DELETED=$((DELETED + 1))
        fi
    done
fi

for managed_root in "${MANAGED_ROOTS[@]}"; do
    if [[ "$managed_root" == "$CSS_TARGET/plugins" ]]; then
        find "$managed_root" -mindepth 1 -depth -type d -empty \
            ! -path "$managed_root/BotAI" ! -path "$managed_root/BotAI/*" \
            ! -path "$managed_root/CS2UpdateMonitor" ! -path "$managed_root/CS2UpdateMonitor/*" -delete
    else
        find "$managed_root" -mindepth 1 -depth -type d -empty -delete
    fi
done

if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    # The host provisioner creates this per-volume state file with mode 0666:
    # the isolated game-container user can record completion even if it cannot
    # create new entries in the root of the bind-mounted server volume.
    printf 'mode=completed\nsource_commit=%s\ncompleted_at_utc=%s\n' "$SOURCE_COMMIT" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$CONFIG_SEED_STATE" \
        || die "Could not record one-time config-seed completion; refusing to report a successful sync."
    log "First-install config seed completed successfully; future starts will never overwrite or prune cfg/configs/txt files."
else
    log "First-install config seed not active; all existing cfg/configs/txt settings were preserved."
fi

log "Sync completed successfully."
log "Files copied: $COPIED; already matching SHA-256: $UNCHANGED; verified: $VERIFIED; stale files removed: $DELETED."
log "BotAI/ and CS2UpdateMonitor/ plugin directories were not copied or pruned."
log "plugins/disabled/ was synced from the published payload and remains under disabled/."
if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    log "CounterStrikeSharp configs/, listed cfg/ files, and five top-level CS2 config/list files were installed as first-install defaults."
else
    log "CounterStrikeSharp configs/, cfg/, and five top-level CS2 config/list files were not copied or stale-pruned."
fi
log "Egg-managed Metamod/CounterStrikeSharp runtime files were not touched."
