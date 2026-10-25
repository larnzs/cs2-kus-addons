#!/usr/bin/env bash
# Host-side FragCity payload publisher.
#
# Run on the Debian/Pterodactyl host from a clean checkout of the repository.
# Any Git credentials are host-only; no credential, .git directory, or updater
# script is exposed inside a Pterodactyl game container.
#
# It stages a minimal allowlisted payload into immutable revisions and publishes
# the selected revision by atomically replacing CURRENT_COMMIT. The matching
# container-side synchronizer uses SHA-256, preserves the active BotAI/ and
# CS2UpdateMonitor/ plugin directories plus Egg-managed runtimes, and manages
# plugins/disabled/, CounterStrikeSharp configs/, cfg/, and five top-level CS2 files.
#
# Environment overrides:
#   FRAGCITY_PAYLOAD_MOUNT  default /var/lib/pterodactyl/mounts/fragcity-addon-payload
#   FRAGCITY_GIT_BRANCH     default integration/kus-monorepo
#   FRAGCITY_KEEP_REVISIONS default 5

set -Eeuo pipefail
umask 022

BRANCH="${FRAGCITY_GIT_BRANCH:-integration/kus-monorepo}"
MOUNT_ROOT="${FRAGCITY_PAYLOAD_MOUNT:-/var/lib/pterodactyl/mounts/fragcity-addon-payload}"
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
KEEP_REVISIONS="${FRAGCITY_KEEP_REVISIONS:-5}"

log() { printf '[fragcity-stage] %s\n' "$*"; }
die() { printf '[fragcity-stage] ERROR: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required."
command -v rsync >/dev/null 2>&1 || die "rsync is required."
command -v find >/dev/null 2>&1 || die "find is required."
command -v flock >/dev/null 2>&1 || die "flock is required."
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required."
command -v install >/dev/null 2>&1 || die "install is required."
command -v cmp >/dev/null 2>&1 || die "cmp is required."
command -v sort >/dev/null 2>&1 || die "sort is required."
command -v grep >/dev/null 2>&1 || die "grep is required."
command -v wc >/dev/null 2>&1 || die "wc is required."

[[ "$MOUNT_ROOT" == /* ]] || die "FRAGCITY_PAYLOAD_MOUNT must be an absolute path."
case "/$MOUNT_ROOT/" in *"/../"*) die "FRAGCITY_PAYLOAD_MOUNT must not contain '..'." ;; esac
[[ ! -L "$MOUNT_ROOT" ]] || die "Payload mount root must not be a symlink: $MOUNT_ROOT"
[[ -d "$REPO_ROOT/.git" ]] || die "Run this script from a normal Git checkout; expected .git at $REPO_ROOT."

current_branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD)" || die "Repository is on a detached HEAD."
[[ "$current_branch" == "$BRANCH" ]] || die "Expected branch '$BRANCH', got '$current_branch'."

# Record the publisher script version before the fetch. If the fast-forward updates
# this script itself, the running Bash process still contains the old version. It
# must release the checkout lock and restart before publishing any payload.
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "$0")"
case "$SCRIPT_PATH" in
    "$REPO_ROOT"/*) SCRIPT_RELATIVE_PATH="${SCRIPT_PATH#"$REPO_ROOT"/}" ;;
    *) die "Publisher script must be inside the repository checkout: $SCRIPT_PATH" ;;
esac
INITIAL_SCRIPT_BLOB="$(git -C "$REPO_ROOT" rev-parse "HEAD:$SCRIPT_RELATIVE_PATH")"     || die "Could not identify the checked-out publisher script."

# Serialize fetches/staging from this checkout. Never discard local edits.
exec 8> "$REPO_ROOT/.git/fragcity-payload-stage.lock"
flock -x 8
[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || die "Git checkout is not clean; commit/stash changes before staging."
log "Fetching latest $BRANCH from origin."
git -C "$REPO_ROOT" fetch --quiet origin "$BRANCH" || die "git fetch failed. Check host-side read-only GitHub authentication."
git -C "$REPO_ROOT" merge --ff-only --quiet FETCH_HEAD || die "Could not fast-forward to origin/$BRANCH; resolve the checkout manually."
[[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$(git -C "$REPO_ROOT" rev-parse FETCH_HEAD)" ]] || die "Local checkout differs from the fetched remote commit."
[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || die "Checkout became dirty during staging."

UPDATED_SCRIPT_BLOB="$(git -C "$REPO_ROOT" rev-parse "HEAD:$SCRIPT_RELATIVE_PATH")"     || die "Could not identify the updated publisher script."
if [[ "$UPDATED_SCRIPT_BLOB" != "$INITIAL_SCRIPT_BLOB" ]]; then
    log "Publisher script changed during fast-forward; restarting with the updated checkout before staging."
    flock -u 8
    exec 8>&-
    exec bash "$SCRIPT_PATH" "$@"
fi

SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
log "Source commit: $SOURCE_COMMIT"

REPO_GAME_ROOT="$REPO_ROOT/game"
GAME_SOURCE="$REPO_GAME_ROOT/csgo"
CSS_SOURCE="$GAME_SOURCE/addons/counterstrikesharp"
[[ -d "$REPO_GAME_ROOT" && ! -L "$REPO_GAME_ROOT" ]] || die "Missing or unsafe repository game/ folder: $REPO_GAME_ROOT"
[[ -n "$(find "$REPO_GAME_ROOT" -type f -print -quit)" ]] || die "Repository game/ folder contains no files."
[[ -d "$CSS_SOURCE/plugins/disabled" && ! -L "$CSS_SOURCE/plugins/disabled" ]] || die "Missing or unsafe source folder: $CSS_SOURCE/plugins/disabled"
[[ -n "$(find "$CSS_SOURCE/plugins/disabled" -type f -print -quit)" ]] || die "No files found under source folder: $CSS_SOURCE/plugins/disabled"

reject_symlinks() {
    local source_path="$1" link_path
    while IFS= read -r -d '' link_path; do
        die "Symlinks are not supported anywhere under game/: $link_path"
    done < <(find "$source_path" -type l -print0)
}
reject_symlinks "$REPO_GAME_ROOT"

mkdir -p -- "$MOUNT_ROOT"
[[ ! -L "$MOUNT_ROOT" ]] || die "Payload mount root must not be a symlink."
REVISION_ROOT="$MOUNT_ROOT/revisions"
FINAL_REVISION="$REVISION_ROOT/$SOURCE_COMMIT"
[[ ! -L "$REVISION_ROOT" ]] || die "Revision root must not be a symlink."
mkdir -p -- "$REVISION_ROOT"
[[ ! -L "$MOUNT_ROOT/.sync.lock" ]] || die "Lock path must not be a symlink."
touch "$MOUNT_ROOT/.sync.lock"
chmod 0644 "$MOUNT_ROOT/.sync.lock"

# Hold the exclusive lock while validating/replacing revision directories as well
# as while publishing CURRENT_COMMIT. Without this, recovery from a malformed
# revision could remove a snapshot a container is currently reading.
exec 9> "$MOUNT_ROOT/.sync.lock"
flock -x 9

validate_revision() {
    local root="$1" game_inventory relative_path expected_count actual_count
    [[ -d "$root" && ! -L "$root" ]] || return 1
    [[ -f "$root/.source-commit" && ! -L "$root/.source-commit" ]] || return 1
    [[ "$(tr -d '\r\n' < "$root/.source-commit")" == "$SOURCE_COMMIT" ]] || return 1
    [[ -d "$root/game/csgo" && ! -L "$root/game/csgo" ]] || return 1
    [[ -n "$(find "$root/game" -type f -print -quit)" ]] || return 1
    [[ -z "$(find "$root/game" -type l -print -quit)" ]] || return 1
    [[ -d "$root/game/csgo/addons/counterstrikesharp/plugins/disabled" && ! -L "$root/game/csgo/addons/counterstrikesharp/plugins/disabled" ]] || return 1
    [[ -n "$(find "$root/game/csgo/addons/counterstrikesharp/plugins/disabled" -type f -print -quit)" ]] || return 1
    game_inventory="$root/.fragcity-game-files-v1.list"
    [[ -f "$game_inventory" && ! -L "$game_inventory" ]] || return 1
    expected_count="$(wc -l < "$game_inventory")"
    [[ "$expected_count" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ "$(LC_ALL=C sort -u "$game_inventory" | wc -l)" -eq "$expected_count" ]] || return 1
    while IFS= read -r relative_path || [[ -n "$relative_path" ]]; do
        [[ -n "$relative_path" && "$relative_path" != /* && "$relative_path" != *".."* && "$relative_path" != *"//"* ]] || return 1
        [[ -f "$root/game/$relative_path" && ! -L "$root/game/$relative_path" ]] || return 1
    done < "$game_inventory"
    actual_count="$(find "$root/game" -type f | wc -l)"
    [[ "$actual_count" -eq "$expected_count" ]] || return 1
}

# A structurally valid revision can still be unusable in a container if its
# directories are owner-only (for example, mktemp creates the revision root as 0700).
# Validate access bits as well, so older broken snapshots are safely re-staged.
revision_permissions_ok() {
    local root="$1"
    [[ -z "$(find "$root" -type d ! -perm -0005 -print -quit)" ]] || return 1
    [[ -z "$(find "$root" -type f ! -perm -0004 -print -quit)" ]] || return 1
}

if [[ -d "$FINAL_REVISION" ]] && validate_revision "$FINAL_REVISION" && revision_permissions_ok "$FINAL_REVISION"; then
    log "Revision is already staged and passes the required-file checks."
else
    # Build and validate a complete replacement before touching the existing revision.
    # If copying or validation fails, CURRENT_COMMIT must not lose its prior directory.
    STAGING="$(mktemp -d "$REVISION_ROOT/.staging.XXXXXX")"
    cleanup_staging() {
        if [[ -n "${STAGING:-}" && -d "$STAGING" ]]; then
            # The staged tree becomes read-only before publication, so restore owner-write
            # on this unpublished temporary tree before cleaning it up on an error.
            chmod -R u+w -- "$STAGING" 2>/dev/null || true
            rm -rf -- "$STAGING" 2>/dev/null || true
        fi
    }
    trap cleanup_staging EXIT
    STAGING_GAME="$STAGING/game"

    copy_tree() {
        local source="$1" destination="$2"
        [[ -d "$source" ]] || die "Required source directory does not exist: $source"
        mkdir -p -- "$destination"
        rsync -a --safe-links -- "$source/" "$destination/"
    }
    # Publish every tracked file under repository game/, with no path exclusions.
    copy_tree "$REPO_GAME_ROOT" "$STAGING_GAME"
    printf '%s\n' "$SOURCE_COMMIT" > "$STAGING/.source-commit"
    GAME_INVENTORY="$STAGING/.fragcity-game-files-v1.list"
    find "$REPO_GAME_ROOT" -type f -printf '%P\n' | LC_ALL=C sort > "$GAME_INVENTORY"
    source_count="$(find "$REPO_GAME_ROOT" -type f | wc -l)"
    staged_count="$(find "$STAGING_GAME" -type f | wc -l)"
    [[ "$source_count" -gt 0 && "$source_count" -eq "$staged_count" ]] || die "Full game/ staging file count mismatch: source=$source_count staged=$staged_count"
    validate_revision "$STAGING" || die "Staged full game/ revision failed validation."

    # Immutable for containers, but readable/traversable by the non-root game user.
    chmod -R a-w "$STAGING"
    find "$STAGING" -type d -exec chmod a+rx {} +
    find "$STAGING" -type f -exec chmod a+r {} +
    revision_permissions_ok "$STAGING" || die "Staged revision is not readable by container users."

    # Swap under the exclusive payload lock. Keep the old revision under a hidden
    # backup name until the complete replacement is in place, so a failed mv can
    # roll the old directory back before the lock is released.
    BACKUP_REVISION=""
    if [[ -e "$FINAL_REVISION" || -L "$FINAL_REVISION" ]]; then
        [[ "$FINAL_REVISION" == "$REVISION_ROOT/$SOURCE_COMMIT" ]] || die "Refusing to replace unexpected revision path: $FINAL_REVISION"
        BACKUP_REVISION="$REVISION_ROOT/.invalid-$SOURCE_COMMIT-$$"
        [[ ! -e "$BACKUP_REVISION" && ! -L "$BACKUP_REVISION" ]] || die "Recovery backup path already exists: $BACKUP_REVISION"
        mv -- "$FINAL_REVISION" "$BACKUP_REVISION" || die "Could not move invalid revision to recovery backup: $FINAL_REVISION"
    fi

    if ! mv -- "$STAGING" "$FINAL_REVISION"; then
        if [[ -n "$BACKUP_REVISION" && ( -e "$BACKUP_REVISION" || -L "$BACKUP_REVISION" ) ]]; then
            mv -- "$BACKUP_REVISION" "$FINAL_REVISION" || die "Could not publish staging or restore the previous revision; manual recovery required."
            BACKUP_REVISION=""
        fi
        die "Could not publish validated staging snapshot: $FINAL_REVISION"
    fi
    STAGING=""

    if [[ -n "$BACKUP_REVISION" && ( -e "$BACKUP_REVISION" || -L "$BACKUP_REVISION" ) ]]; then
        if [[ -L "$BACKUP_REVISION" ]]; then
            rm -f -- "$BACKUP_REVISION" || die "Could not remove invalid revision symlink backup: $BACKUP_REVISION"
        else
            chmod -R u+w -- "$BACKUP_REVISION" || die "Could not make invalid revision backup removable: $BACKUP_REVISION"
            rm -rf -- "$BACKUP_REVISION" || die "Could not remove invalid revision backup: $BACKUP_REVISION"
        fi
    fi

    trap - EXIT
    log "Staged a new immutable revision."
fi

# We hold the exclusive payload lock from revision validation/staging through
# atomic publication and pruning. Container syncs hold a shared lock throughout copy.
SCRIPT_TEMP="$MOUNT_ROOT/.sync-addon-container.tmp.$$"
install -m 0555 "$REPO_ROOT/pterodactyl/sync-addon-payload-container.sh" "$SCRIPT_TEMP"
mv -f -- "$SCRIPT_TEMP" "$MOUNT_ROOT/sync-addon-payload-container.sh"

POINTER_TEMP="$MOUNT_ROOT/.CURRENT_COMMIT.tmp.$$"
printf '%s\n' "$SOURCE_COMMIT" > "$POINTER_TEMP"
chmod 0444 "$POINTER_TEMP"
mv -f -- "$POINTER_TEMP" "$MOUNT_ROOT/CURRENT_COMMIT"
touch "$FINAL_REVISION"
log "Published CURRENT_COMMIT=$SOURCE_COMMIT"

# Keep the current revision plus the newest historical revisions. Container syncs
# hold a shared .sync.lock, so pruning waits until active syncs finish.
[[ "$KEEP_REVISIONS" =~ ^[1-9][0-9]*$ ]] || die "FRAGCITY_KEEP_REVISIONS must be a positive integer."
kept=1
while IFS=' ' read -r _mtime revision_name; do
    [[ -n "$revision_name" && "$revision_name" != "$SOURCE_COMMIT" ]] || continue
    if (( kept < KEEP_REVISIONS )); then
        kept=$((kept + 1))
    else
        log "Pruning old staged revision: $revision_name"
        rm -rf -- "$REVISION_ROOT/$revision_name"
    fi
done < <(find "$REVISION_ROOT" -mindepth 1 -maxdepth 1 -type d -name '[0-9a-f]*' -printf '%T@ %f\n' | sort -rn)

log "Payload staging finished successfully."
# Keep the XFCE operator dashboard current from the same branch as the payload.
# This affects only the root-owned host dashboard, never files inside game volumes.
# The dashboard itself detects atomic replacement and reloads in an already-open window.
publish_status_dashboard() {
    [[ "$(id -u)" -eq 0 ]] || return 0

    local dashboard_source="$REPO_ROOT/pterodactyl/systemd/fragcity-status-dashboard.sh"
    local dashboard_target="/usr/local/libexec/fragcity-status-dashboard.sh"
    local temporary

    if [[ ! -f "$dashboard_source" || -L "$dashboard_source" ]]; then
        log "WARNING: dashboard source is missing or unsafe; payload publishing remains successful."
        return 0
    fi
    if ! bash -n "$dashboard_source"; then
        log "WARNING: dashboard shell syntax check failed; installed dashboard was left unchanged."
        return 0
    fi
    if [[ -L "/usr/local/libexec" || -L "$dashboard_target" ]]; then
        log "WARNING: refusing dashboard deployment through a symlink; installed dashboard was left unchanged."
        return 0
    fi
    if ! install -d -o root -g root -m 0755 /usr/local/libexec; then
        log "WARNING: could not prepare /usr/local/libexec; payload publishing remains successful."
        return 0
    fi

    temporary="$(mktemp /usr/local/libexec/.fragcity-status-dashboard.sh.XXXXXX)" || {
        log "WARNING: could not create an atomic dashboard update file."
        return 0
    }
    if ! install -o root -g root -m 0755 -- "$dashboard_source" "$temporary"; then
        rm -f -- "$temporary"
        log "WARNING: could not stage the new dashboard; installed dashboard was left unchanged."
        return 0
    fi

    if [[ -f "$dashboard_target" ]] && cmp -s -- "$temporary" "$dashboard_target"; then
        rm -f -- "$temporary"
        return 0
    fi

    if mv -f -- "$temporary" "$dashboard_target"; then
        log "Updated live status dashboard. Any open dashboard window will reload the new UI automatically."
    else
        rm -f -- "$temporary"
        log "WARNING: could not publish the dashboard update; installed dashboard was left unchanged."
    fi
}

publish_status_dashboard
