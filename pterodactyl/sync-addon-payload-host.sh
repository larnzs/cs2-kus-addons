#!/usr/bin/env bash
# Host-side FragCity payload publisher.
#
# Run on the Debian/Pterodactyl host from a clean checkout of this private repo.
# The host uses its own read-only GitHub credentials; no credential is passed to
# a Pterodactyl container and no .git directory or updater scripts are exposed.
#
# It stages a minimal allowlisted payload into immutable revisions and publishes
# the selected revision by atomically replacing CURRENT_COMMIT. The matching
# container-side synchronizer uses SHA-256 and never touches user-owned BotAI/,
# disabled/, cfg/configs, or Egg-managed framework runtimes.
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
command -v sort >/dev/null 2>&1 || die "sort is required."

[[ "$MOUNT_ROOT" == /* ]] || die "FRAGCITY_PAYLOAD_MOUNT must be an absolute path."
case "/$MOUNT_ROOT/" in *"/../"*) die "FRAGCITY_PAYLOAD_MOUNT must not contain '..'." ;; esac
[[ ! -L "$MOUNT_ROOT" ]] || die "Payload mount root must not be a symlink: $MOUNT_ROOT"
[[ -d "$REPO_ROOT/.git" ]] || die "Run this script from a normal Git checkout; expected .git at $REPO_ROOT."

current_branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD)" || die "Repository is on a detached HEAD."
[[ "$current_branch" == "$BRANCH" ]] || die "Expected branch '$BRANCH', got '$current_branch'."

# Serialize fetches/staging from this checkout. Never discard local edits.
exec 8> "$REPO_ROOT/.git/fragcity-payload-stage.lock"
flock -x 8
[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || die "Git checkout is not clean; commit/stash changes before staging."
log "Fetching latest $BRANCH from origin."
git -C "$REPO_ROOT" fetch --quiet origin "$BRANCH" || die "git fetch failed. Check host-side read-only GitHub authentication."
git -C "$REPO_ROOT" merge --ff-only --quiet FETCH_HEAD || die "Could not fast-forward to origin/$BRANCH; resolve the checkout manually."
[[ "$(git -C "$REPO_ROOT" rev-parse HEAD)" == "$(git -C "$REPO_ROOT" rev-parse FETCH_HEAD)" ]] || die "Local checkout differs from the fetched remote commit."
[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || die "Checkout became dirty during staging."
SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
log "Source commit: $SOURCE_COMMIT"

GAME_SOURCE="$REPO_ROOT/game/csgo"
ADDONS_SOURCE="$GAME_SOURCE/addons"
CSS_SOURCE="$ADDONS_SOURCE/counterstrikesharp"
[[ -d "$CSS_SOURCE/source" ]] || die "Missing source folder: $CSS_SOURCE/source"
[[ -d "$CSS_SOURCE/plugins" ]] || die "Missing source folder: $CSS_SOURCE/plugins"
[[ -d "$CSS_SOURCE/shared" ]] || die "Missing source folder: $CSS_SOURCE/shared"
[[ -d "$CSS_SOURCE/gamedata" ]] || die "Missing source folder: $CSS_SOURCE/gamedata"
[[ -f "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" ]] || die "Missing VDF: $ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf"
for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
    [[ -d "$ADDONS_SOURCE/$name" ]] || die "Missing addon source directory: $ADDONS_SOURCE/$name"
done

reject_symlinks() {
    local source_path="$1" link_path
    while IFS= read -r -d '' link_path; do
        die "Symlinks are not supported in the staged allowlist: $link_path"
    done < <(find "$source_path" -type l -print0)
}
for source_path in \
    "$CSS_SOURCE/source" "$CSS_SOURCE/shared" "$CSS_SOURCE/gamedata" \
    "$ADDONS_SOURCE/MovementUnlocker" "$ADDONS_SOURCE/serverlistplayersfix_mm" \
    "$ADDONS_SOURCE/surf" "$ADDONS_SOURCE/scripts" "$ADDONS_SOURCE/multiaddonmanager"; do
    reject_symlinks "$source_path"
done
while IFS= read -r -d '' link_path; do
    die "Symlink found in managed plugin source: $link_path"
done < <(
    find "$CSS_SOURCE/plugins" -mindepth 1 \
        \( -path "$CSS_SOURCE/plugins/BotAI" \
           -o -path "$CSS_SOURCE/plugins/disabled" \
           -o -path "$CSS_SOURCE/plugins/CS2UpdateMonitor" \) -prune \
        -o -type l -print0
)
[[ ! -L "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" ]] || die "Managed VDF must not be a symlink."

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
    local root="$1"
    [[ -d "$root" && ! -L "$root" ]] || return 1
    [[ -f "$root/.source-commit" && ! -L "$root/.source-commit" ]] || return 1
    [[ "$(tr -d '\r\n' < "$root/.source-commit")" == "$SOURCE_COMMIT" ]] || return 1
    [[ -d "$root/game/csgo/addons/counterstrikesharp/source" ]] || return 1
    [[ -d "$root/game/csgo/addons/counterstrikesharp/plugins" ]] || return 1
    # Do not publish CS2UpdateMonitor as an active plugin on new servers.
    [[ ! -e "$root/game/csgo/addons/counterstrikesharp/plugins/CS2UpdateMonitor" ]] || return 1
    [[ -d "$root/game/csgo/addons/counterstrikesharp/shared" ]] || return 1
    [[ -d "$root/game/csgo/addons/counterstrikesharp/gamedata" ]] || return 1
    [[ -f "$root/game/csgo/addons/metamod/serverlistplayersfix_mm.vdf" ]] || return 1
    local name
    for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
        [[ -d "$root/game/csgo/addons/$name" ]] || return 1
    done
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
    [[ ! -e "$FINAL_REVISION" ]] || rm -rf -- "$FINAL_REVISION"
    STAGING="$(mktemp -d "$REVISION_ROOT/.staging.XXXXXX")"
    trap 'if [[ -n "${STAGING:-}" && -d "$STAGING" ]]; then rm -rf -- "$STAGING"; fi' EXIT
    STAGING_GAME="$STAGING/game/csgo"
    STAGING_ADDONS="$STAGING_GAME/addons"
    STAGING_CSS="$STAGING_ADDONS/counterstrikesharp"

    copy_tree() {
        local source="$1" destination="$2"
        [[ -d "$source" ]] || die "Required source directory does not exist: $source"
        mkdir -p -- "$destination"
        rsync -a --safe-links -- "$source/" "$destination/"
    }
    copy_tree "$CSS_SOURCE/source" "$STAGING_CSS/source"
    mkdir -p -- "$STAGING_CSS/plugins"
    rsync -a --safe-links \
        --exclude='/BotAI/***' \
        --exclude='/disabled/***' \
        --exclude='/CS2UpdateMonitor/***' \
        -- "$CSS_SOURCE/plugins/" "$STAGING_CSS/plugins/"
    copy_tree "$CSS_SOURCE/shared" "$STAGING_CSS/shared"
    copy_tree "$CSS_SOURCE/gamedata" "$STAGING_CSS/gamedata"
    for name in MovementUnlocker serverlistplayersfix_mm surf scripts multiaddonmanager; do
        copy_tree "$ADDONS_SOURCE/$name" "$STAGING_ADDONS/$name"
    done
    mkdir -p -- "$STAGING_ADDONS/metamod"
    install -m 0444 "$ADDONS_SOURCE/metamod/serverlistplayersfix_mm.vdf" \
        "$STAGING_ADDONS/metamod/serverlistplayersfix_mm.vdf"
    printf '%s\n' "$SOURCE_COMMIT" > "$STAGING/.source-commit"
    validate_revision "$STAGING" || die "Staged revision failed required-file validation."

    # Publish an immutable snapshot, but keep it readable/traversable by the
    # unprivileged Pterodactyl container user. mktemp creates STAGING as 0700,
    # so chmod -R a-w alone would leave the revision root at 0500 and hide the
    # marker from the game container.
    chmod -R a-w "$STAGING"
    find "$STAGING" -type d -exec chmod a+rx {} +
    find "$STAGING" -type f -exec chmod a+r {} +
    revision_permissions_ok "$STAGING" || die "Staged revision is not readable by container users."
    mv -- "$STAGING" "$FINAL_REVISION"
    STAGING=""
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
