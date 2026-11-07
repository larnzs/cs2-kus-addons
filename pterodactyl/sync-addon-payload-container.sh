#!/usr/bin/env bash
# Full-tree FragCity game payload synchronizer for the custom K4ryuu/Pterodactyl Egg.
#
# The immutable host snapshot contains the complete deployable tree under repository game/,
# excluding only the exact K4ryuu-managed runtime paths. Every deployable file, including
# CFGs and plugin configs, is synchronized from the published revision on every startup.
# The per-server first-sync marker is retained for new-server registration and completion
# tracking; it does not protect config files from later updates.
# If the state marker is absent, FRAGCITY_BASELINE_SHA256 distinguishes known legacy UUIDs
# from new UUIDs. New UUIDs wait for host registration; CS2 is not launched before the
# provisioner creates a matching pending marker. Legacy volumes are also fully synchronized.
# Files found only in the upstream CS2 installation remain intact. Stale cleanup may remove
# previously managed files, including config files, when they disappear from the repository.
set -Eeuo pipefail

PAYLOAD_BASE="${FRAGCITY_PAYLOAD_BASE:-/home/container/egg/fragcity-payload}"
GAME_ROOT="${FRAGCITY_GAME_ROOT:-/home/container/game}"
SERVER_UUID="${P_SERVER_UUID:-}"
VERBOSE="${FRAGCITY_SYNC_VERBOSE:-0}"

log() { printf '[fragcity-payload] %s\n' "$*"; }
die() { printf '[fragcity-payload] ERROR: %s\n' "$*" >&2; exit 1; }

validate_absolute_path() {
    local label="$1" path="$2"
    [[ "$path" == /* ]] || die "$label must be an absolute path: $path"
    case "/$path/" in *"/../"*) die "$label must not contain '..': $path" ;; esac
}
validate_relative_path() {
    local path="$1" component
    [[ -n "$path" && "$path" != /* && "$path" != *".."* && "$path" != *"//"* \
        && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
    local -a parts=()
    IFS='/' read -r -a parts <<< "$path"
    for component in "${parts[@]}"; do
        [[ -n "$component" && "$component" != "." && "$component" != ".." ]] || return 1
    done
}

# These exact runtime paths belong to the K4ryuu Egg. They must neither be copied
# from the repository nor removed as stale files from manifests written by older versions.
# Do not broaden this list: every other repository path, including plugins/disabled/, is managed.
is_runtime_excluded_path() {
    local path="$1"
    case "$path" in
        csgo/addons/counterstrikesharp/api/*|csgo/addons/counterstrikesharp/bin/*|\
        csgo/addons/counterstrikesharp/dotnet/*|csgo/addons/counterstrikesharp/lang/*|\
        csgo/addons/metamod/bin/*|\
        csgo/addons/metamod/counterstrikesharp.vdf|csgo/addons/metamod/metaplugins.ini)
            return 0
            ;;
    esac
    return 1
}

validate_absolute_path "FRAGCITY_PAYLOAD_BASE" "$PAYLOAD_BASE"
validate_absolute_path "FRAGCITY_GAME_ROOT" "$GAME_ROOT"
[[ "$VERBOSE" == "0" || "$VERBOSE" == "1" ]] || die "FRAGCITY_SYNC_VERBOSE must be 0 or 1."
[[ "$SERVER_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
    || die "P_SERVER_UUID is missing or invalid; refusing to sync without a verified server identity."

case "$GAME_ROOT" in
    */game) SERVER_ROOT="${GAME_ROOT%/game}" ;;
    *) die "FRAGCITY_GAME_ROOT must end in /game so the server volume root can be identified safely." ;;
esac
[[ -d "$SERVER_ROOT" && ! -L "$SERVER_ROOT" ]] || die "Server volume root is missing or unsafe: $SERVER_ROOT"
[[ ! -L "$GAME_ROOT" ]] || die "Game root must not be a symlink: $GAME_ROOT"
if [[ -e "$GAME_ROOT" && ! -d "$GAME_ROOT" ]]; then
    die "Game root exists but is not a directory: $GAME_ROOT"
fi

# Keep the historical state filename so volumes provisioned by older versions remain valid.
# It now records first full-game synchronization; it no longer gates configuration copying.
INITIAL_STATE="$SERVER_ROOT/.fragcity-config-seed-v1.state"
MANAGED_MANIFEST="$SERVER_ROOT/.fragcity-managed-payload-v1.list"
[[ ! -L "$MANAGED_MANIFEST" ]] || die "Managed-payload manifest must not be a symlink: $MANAGED_MANIFEST"
[[ ! -e "$MANAGED_MANIFEST" || -f "$MANAGED_MANIFEST" ]] || die "Managed-payload manifest must be a regular file: $MANAGED_MANIFEST"
[[ ! -L "$INITIAL_STATE" ]] || die "Initial-sync state file must not be a symlink: $INITIAL_STATE"
[[ ! -e "$INITIAL_STATE" || -f "$INITIAL_STATE" ]] || die "Initial-sync state path must be a regular file: $INITIAL_STATE"

for command_name in sha256sum find cp mkdir rm awk flock tr chmod dirname grep date sort mv wc sleep; do
    command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required."
done

CONFIG_SEED_ACTIVE=0
CONFIG_SEED_STATE_MISSING=0
if [[ -f "$INITIAL_STATE" ]]; then
    grep -Fxq 'fragcity-config-seed-v1' "$INITIAL_STATE" \
        && grep -Fxq "server_uuid=$SERVER_UUID" "$INITIAL_STATE" \
        || die "Initial-sync state does not match this server UUID."
    # A completed state file contains both the pending line and the appended
    # completed line, so prefer completed when both are present.
    if grep -Fxq 'mode=completed' "$INITIAL_STATE"; then
        log "First full game/ sync is complete; all repository-managed files continue syncing on every start."
    elif grep -Fxq 'mode=pending' "$INITIAL_STATE"; then
        [[ -w "$INITIAL_STATE" ]] || die "Pending config-seed state is not writable; refusing to seed configs without recording completion."
        CONFIG_SEED_ACTIVE=1
        log "First full-payload sync is pending; the complete repository game/ tree will be deployed and verified."
    else
        die "Initial-sync state has no recognized pending/completed mode."
    fi
else
    CONFIG_SEED_STATE_MISSING=1
fi

[[ -d "$PAYLOAD_BASE" && ! -L "$PAYLOAD_BASE" ]] || die "Payload mount is missing or is a symlink: $PAYLOAD_BASE"
[[ -f "$PAYLOAD_BASE/.sync.lock" && ! -L "$PAYLOAD_BASE/.sync.lock" ]] || die "Host payload lock file is missing."
[[ -f "$PAYLOAD_BASE/CURRENT_COMMIT" && ! -L "$PAYLOAD_BASE/CURRENT_COMMIT" ]] || die "No published payload snapshot is available (CURRENT_COMMIT missing)."

# Hold the shared lock until every source file has been copied and verified.
exec 9< "$PAYLOAD_BASE/.sync.lock"
flock -s 9
SOURCE_COMMIT="$(tr -d '\r\n' < "$PAYLOAD_BASE/CURRENT_COMMIT")"
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || die "CURRENT_COMMIT is not a full lowercase Git commit SHA."
PAYLOAD_ROOT="$PAYLOAD_BASE/revisions/$SOURCE_COMMIT"
[[ -d "$PAYLOAD_ROOT" && ! -L "$PAYLOAD_ROOT" ]] || die "Published revision directory is missing: $PAYLOAD_ROOT"
[[ -f "$PAYLOAD_ROOT/.source-commit" && ! -L "$PAYLOAD_ROOT/.source-commit" ]] || die "Revision marker is missing."
[[ "$(tr -d '\r\n' < "$PAYLOAD_ROOT/.source-commit")" == "$SOURCE_COMMIT" ]] || die "Revision marker does not match CURRENT_COMMIT."

# If there is no per-volume state file yet, classify this UUID against the hashed
# host baseline. UUIDs present at baseline time are legacy/existing and preserve configs.
# A UUID absent from that baseline is new: wait for the host provisioner to create the
# pending marker rather than accidentally launching CS2 without its first-install seed.
if [[ "$CONFIG_SEED_STATE_MISSING" -eq 1 ]]; then
    BASELINE_HASHES="$PAYLOAD_BASE/FRAGCITY_BASELINE_SHA256"
    [[ -f "$BASELINE_HASHES" && ! -L "$BASELINE_HASHES" ]] \
        || die "First-install state is missing and the baseline hash registry is unavailable; refusing to guess whether this server is new or legacy."

    while IFS= read -r baseline_hash || [[ -n "$baseline_hash" ]]; do
        [[ "$baseline_hash" =~ ^[0-9a-f]{64}$ ]] \
            || die "Baseline hash registry contains an invalid SHA-256 entry."
    done < "$BASELINE_HASHES"

    SERVER_UUID_HASH="$(printf '%s' "$SERVER_UUID" | sha256sum | awk '{print $1}')"
    if grep -Fxq "$SERVER_UUID_HASH" "$BASELINE_HASHES"; then
        log "Server UUID belongs to the one-time baseline; treating this as an existing/legacy volume and synchronizing all deployable repository files."
    else
        log "Server UUID is not in the baseline; waiting up to 90 seconds for the host provisioner to register first-install state."
        WAIT_ATTEMPT=0
        while [[ ! -e "$INITIAL_STATE" && ! -L "$INITIAL_STATE" ]] && (( WAIT_ATTEMPT < 45 )); do
            sleep 2
            WAIT_ATTEMPT=$((WAIT_ATTEMPT + 1))
        done

        [[ ! -L "$INITIAL_STATE" ]] || die "Host provisioner created an unsafe symlink for initial-sync state."
        [[ -f "$INITIAL_STATE" ]] \
            || die "New server UUID was not registered by the host provisioner within 90 seconds; refusing to launch CS2 without first-install config policy."

        grep -Fxq 'fragcity-config-seed-v1' "$INITIAL_STATE" \
            && grep -Fxq "server_uuid=$SERVER_UUID" "$INITIAL_STATE" \
            || die "New-server initial-sync state does not match this server UUID."
        if grep -Fxq 'mode=pending' "$INITIAL_STATE"; then
            [[ -w "$INITIAL_STATE" ]] || die "Pending config-seed state is not writable; refusing to seed configs without being able to record completion."
            CONFIG_SEED_ACTIVE=1
            log "Host provisioner registered this new server; its first full-payload sync is active."
        elif grep -Fxq 'mode=completed' "$INITIAL_STATE"; then
            log "Host provisioner reports the first full game/ sync is already completed; normal full-payload synchronization will continue."
        else
            die "New-server initial-sync state has no recognized pending/completed mode."
        fi
    fi
fi

GAME_SOURCE="$PAYLOAD_ROOT/game"
GAME_INVENTORY="$PAYLOAD_ROOT/.fragcity-game-files-v1.list"
[[ -d "$GAME_SOURCE" && ! -L "$GAME_SOURCE" ]] || die "Published revision is missing the full repository game/ folder."
[[ -f "$GAME_INVENTORY" && ! -L "$GAME_INVENTORY" ]] || die "Published full-game file inventory is missing."
[[ -d "$GAME_SOURCE/csgo/addons/counterstrikesharp/plugins/disabled" && ! -L "$GAME_SOURCE/csgo/addons/counterstrikesharp/plugins/disabled" ]] \
    || die "Published game tree is missing plugins/disabled/."
[[ -n "$(find "$GAME_SOURCE/csgo/addons/counterstrikesharp/plugins/disabled" -type f -print -quit)" ]] \
    || die "Published plugins/disabled/ folder contains no files."
[[ -z "$(find "$GAME_SOURCE" -type l -print -quit)" ]] || die "Symlinks are not allowed anywhere in repository game/."

declare -A DESIRED_SOURCE=()
declare -A DESIRED_HASH=()
declare -A PREVIOUS_MANAGED=()
MANIFEST_PRESENT=0

add_file() {
    local relative_path="$1" source_path="$2" source_hash
    validate_relative_path "$relative_path" || die "Unsafe repository-relative path: $relative_path"
    [[ -f "$source_path" && ! -L "$source_path" ]] || die "Expected full-tree payload file is missing or unsafe: $source_path"
    source_hash="$(sha256sum -- "$source_path" | awk '{print $1}')"
    [[ -n "$source_hash" ]] || die "Could not calculate SHA-256 for: $source_path"
    DESIRED_SOURCE["$relative_path"]="$source_path"
    DESIRED_HASH["$relative_path"]="$source_hash"
}

EXPECTED_SOURCE_COUNT="$(wc -l < "$GAME_INVENTORY")"
[[ "$EXPECTED_SOURCE_COUNT" =~ ^[1-9][0-9]*$ ]] || die "Published deployable-game inventory is empty or invalid."
[[ "$(LC_ALL=C sort -u "$GAME_INVENTORY" | awk 'END { print NR + 0 }')" -eq "$EXPECTED_SOURCE_COUNT" ]] || die "Published deployable-game inventory contains duplicate paths."
grep -q '^csgo/addons/counterstrikesharp/plugins/disabled/' "$GAME_INVENTORY" || die "Deployable inventory omitted plugins/disabled files."
while IFS= read -r relative_path || [[ -n "$relative_path" ]]; do
    validate_relative_path "$relative_path" || die "Unsafe path in deployable-game inventory: $relative_path"
    is_runtime_excluded_path "$relative_path" && die "Published inventory contains a K4ryuu-managed runtime path that must be excluded: $relative_path"
    add_file "$relative_path" "$GAME_SOURCE/$relative_path"
done < "$GAME_INVENTORY"
for required_seed_path in csgo/subscribed_collection_ids.txt csgo/subscribed_file_ids.txt; do
    [[ -n "${DESIRED_SOURCE[$required_seed_path]+present}" ]] \
        || die "Required first-install seed file is missing from the published inventory: $required_seed_path"
done
ACTUAL_SOURCE_COUNT="$(find "$GAME_SOURCE" -type f | wc -l)"
[[ "$ACTUAL_SOURCE_COUNT" -eq "$EXPECTED_SOURCE_COUNT" ]] || die "Deployable-game inventory mismatch: inventory=$EXPECTED_SOURCE_COUNT actual=$ACTUAL_SOURCE_COUNT."

# Old v1 manifests used /home/container/game/csgo as their root. Prefix those
# entries with csgo/ so stale-file cleanup still targets the same legacy paths.
if [[ -f "$MANAGED_MANIFEST" ]]; then
    MANIFEST_PRESENT=1
    while IFS= read -r previous_path || [[ -n "$previous_path" ]]; do
        [[ -z "$previous_path" || "$previous_path" == "# fragcity-managed-payload-v1" ]] && continue
        validate_relative_path "$previous_path" || die "Unsafe path in managed-payload manifest: $previous_path"
        [[ "$previous_path" == csgo/* ]] || previous_path="csgo/$previous_path"
        PREVIOUS_MANAGED["$previous_path"]=1
    done < "$MANAGED_MANIFEST"
fi

# The Egg's game/cs2.sh is outside repository game/ and is not overwritten by this overlay.
mkdir -p -- "$GAME_ROOT"
[[ ! -L "$GAME_ROOT" ]] || die "Game root became a symlink: $GAME_ROOT"

assert_no_symlink_parent_components() {
    local target_path="$1" relative_path current_path part component_index
    local -a components=()
    case "$target_path" in
        "$GAME_ROOT"/*) relative_path="${target_path#"$GAME_ROOT"/}" ;;
        *) die "Refusing to write outside GAME_ROOT: $target_path" ;;
    esac
    validate_relative_path "$relative_path" || die "Unsafe target-relative path: $relative_path"
    IFS='/' read -r -a components <<< "$relative_path"
    current_path="$GAME_ROOT"
    [[ ! -L "$current_path" ]] || die "Game root is a symlink: $current_path"
    for ((component_index = 0; component_index < ${#components[@]} - 1; component_index++)); do
        part="${components[$component_index]}"
        current_path="$current_path/$part"
        [[ ! -L "$current_path" ]] || die "Refusing to write through symlinked parent path: $current_path"
    done
}

COPIED=0
UNCHANGED=0
VERIFIED=0
log "Target server UUID: $SERVER_UUID."
log "Using published payload revision $SOURCE_COMMIT."
log "Loaded the complete deployable game/ inventory: $EXPECTED_SOURCE_COUNT files; only the seven explicit K4ryuu runtime paths are excluded; all repository-managed files are synchronized on every start."

for relative_path in "${!DESIRED_SOURCE[@]}"; do
    source_path="${DESIRED_SOURCE[$relative_path]}"
    expected_hash="${DESIRED_HASH[$relative_path]}"
    target_path="$GAME_ROOT/$relative_path"
    assert_no_symlink_parent_components "$target_path"
    [[ ! -L "$target_path" ]] || die "Managed target file is a symlink: $target_path"

    actual_hash=""
    if [[ -f "$target_path" ]]; then
        actual_hash="$(sha256sum -- "$target_path" | awk '{print $1}')"
    elif [[ -e "$target_path" ]]; then
        die "Managed target path exists but is not a regular file: $target_path"
    fi
    if [[ "$actual_hash" == "$expected_hash" ]]; then
        UNCHANGED=$((UNCHANGED + 1))
        VERIFIED=$((VERIFIED + 1))
        continue
    fi

    [[ "$VERBOSE" != "1" ]] || log "Updating $relative_path (missing or SHA-256 differs)."
    mkdir -p -- "$(dirname -- "$target_path")"
    assert_no_symlink_parent_components "$target_path"
    [[ ! -L "$target_path" ]] || die "Managed target file became a symlink: $target_path"
    if [[ -e "$target_path" ]]; then
        [[ -f "$target_path" ]] || die "Managed target path is not a regular file: $target_path"
        chmod u+w -- "$target_path" || die "Could not make managed target writable before copy: $target_path"
    fi
    cp -- "$source_path" "$target_path"
    chmod u+w -- "$target_path" || die "Could not make managed target writable after copy: $target_path"
    actual_hash="$(sha256sum -- "$target_path" | awk '{print $1}')"
    [[ "$actual_hash" == "$expected_hash" ]] || die "SHA-256 verification failed after copy: $relative_path"
    COPIED=$((COPIED + 1))
    VERIFIED=$((VERIFIED + 1))
done

# First-install mode is not complete unless both subscribed-ID files are present and
# SHA-256 verified at their repository-defined paths. They are refreshed on every sync
# like every other repository-managed file. Empty files are valid.
if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    for required_seed_path in csgo/subscribed_collection_ids.txt csgo/subscribed_file_ids.txt; do
        target_path="$GAME_ROOT/$required_seed_path"
        [[ -f "$target_path" && ! -L "$target_path" ]] || die "First-install seed did not create required file: $required_seed_path"
        actual_hash="$(sha256sum -- "$target_path" | awk '{print $1}')"
        [[ "$actual_hash" == "${DESIRED_HASH[$required_seed_path]}" ]] \
            || die "First-install seed file failed SHA-256 verification: $required_seed_path"
    done
    log "Required subscribed_*_ids.txt files were present and SHA-256 verified on the first full sync."
fi

# Required Workshop list files must remain present after any sync. They are normal
# repository-managed files and are refreshed from the published revision every time.
for required_seed_path in csgo/subscribed_collection_ids.txt csgo/subscribed_file_ids.txt; do
    target_path="$GAME_ROOT/$required_seed_path"
    [[ -f "$target_path" && ! -L "$target_path" ]] \
        || die "Required subscribed-ID file is missing or unsafe after sync: $target_path"
done

# Only previously managed files that are now absent from the deployable inventory can be
# deleted. Runtime paths owned by K4ryuu are never deleted, including from old manifests.
# Without a prior manifest, unrecognized CS2 engine/runtime files are preserved.
DELETED=0
if [[ "$MANIFEST_PRESENT" -eq 1 ]]; then
    for relative_path in "${!PREVIOUS_MANAGED[@]}"; do
        if is_runtime_excluded_path "$relative_path"; then
            log "Leaving K4ryuu-managed runtime path untouched: $relative_path"
            continue
        fi
        [[ -n "${DESIRED_SOURCE[$relative_path]+present}" ]] && continue
        target_path="$GAME_ROOT/$relative_path"
        assert_no_symlink_parent_components "$target_path"
        [[ ! -L "$target_path" ]] || die "Previously managed payload target is a symlink: $target_path"
        if [[ -e "$target_path" ]]; then
            [[ -f "$target_path" ]] || die "Previously managed payload target is not a regular file: $target_path"
            log "Removing stale previously-managed payload file: $relative_path"
            rm -f -- "$target_path"
            DELETED=$((DELETED + 1))
        fi
    done
else
    log "No prior managed-payload manifest; skipping stale-file deletion on this rollout to preserve unknown game/runtime files."
fi

manifest_tmp="$MANAGED_MANIFEST.tmp.$BASHPID"
[[ ! -e "$manifest_tmp" && ! -L "$manifest_tmp" ]] || die "Managed-payload manifest temp path already exists."
{
    printf '# fragcity-managed-payload-v1\n'
    for relative_path in "${!DESIRED_SOURCE[@]}"; do printf '%s\n' "$relative_path"; done
} | LC_ALL=C sort -u > "$manifest_tmp" || die "Could not write managed-payload manifest."
chmod 0644 "$manifest_tmp" || die "Could not set managed-payload manifest permissions."
mv -f -- "$manifest_tmp" "$MANAGED_MANIFEST" || die "Could not publish managed-payload manifest atomically."

if [[ "$CONFIG_SEED_ACTIVE" -eq 1 ]]; then
    printf 'mode=completed\nsource_commit=%s\ncompleted_at_utc=%s\n' "$SOURCE_COMMIT" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$INITIAL_STATE" \
        || die "Could not record first-install completion; refusing to report a successful sync."
    log "First full game/ deployment completed and recorded; all repository-managed files, including configs, will continue updating on every start."
elif [[ -f "$INITIAL_STATE" ]]; then
    log "First-sync state is completed; the full repository-managed payload was synchronized."
else
    log "No first-sync marker found; this legacy volume was classified through the baseline and its full repository-managed payload was synchronized."
fi

log "Sync completed successfully."
log "Files copied: $COPIED; already matching SHA-256: $UNCHANGED; verified: $VERIFIED; stale managed files removed: $DELETED."
log "All deployable repository game/ files are inventoried and synchronized on every start, including configs and CFGs."
log "The only excluded paths are the seven explicit K4ryuu-managed runtime paths; plugins/disabled/ remains managed payload."
