#!/usr/bin/env bash
set -Eeuo pipefail

# Deploy the already-approved KUS plugin/runtime payload to ONE private instance
# payload root. This is deliberately not the upstream release updater and it must
# never be pointed at the shared CS2 Base Game or the merged OverlayFS view.
#
# Usage:
#   bash linux/update-instance-plugins.sh --target-stopped --dry-run /path/to/private/game/csgo
#   bash linux/update-instance-plugins.sh --target-stopped             /path/to/private/game/csgo
#
# The target directory must contain its own `addons/` directory and must NOT contain
# the Base Game's `gameinfo.gi`. The caller is responsible for running this only while
# the target instance is stopped (for example, from a pre-start/provisioning hook).
# Other instances may remain running; this script intentionally does not use a global
# `pgrep cs2` check that would block all instances on the Node.
#
# Safety rules:
# - Reads only the tracked game/csgo/addons payload already present in this checkout.
# - Does not pull Git, run scripts/update/update.sh, download plugin releases, commit/push,
#   call SteamCMD, install/update CS2 or Steam Linux Runtime, edit cfg/ or root .txt files,
#   start/stop a server, or delete any target files.
# - Windows staging, CounterStrikeSharp configs, and configuration/data-like file types
#   are excluded to avoid overwriting customer settings. If a plugin later needs a new
#   non-config JSON/text asset, its sync rule must be reviewed explicitly.

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_ADDONS="$ROOT_DIR/game/csgo/addons"
DRY_RUN=0
TARGET_STOPPED=0
TARGET_CSGO=""

usage() {
    cat <<'USAGE'
Usage:
  update-instance-plugins.sh --target-stopped [--dry-run] <private-instance-game/csgo-dir>

Options:
  --target-stopped  Required acknowledgement that this target Instance is stopped.
  --dry-run         Show the planned file changes without writing them.
  -h, --help        Show this help.

The target must be the private per-Instance payload root containing addons/ (not the
shared Base Game directory and not an OverlayFS merged/runtime path).
USAGE
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

while (($#)); do
    case "$1" in
        --target-stopped) TARGET_STOPPED=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        --*) die "Unknown option: $1" ;;
        *)
            if [[ -n "$TARGET_CSGO" ]]; then
                die "Only one target path may be supplied."
            fi
            TARGET_CSGO="$1"
            ;;
    esac
    shift
done

[[ "$TARGET_STOPPED" == "1" ]] || die "Pass --target-stopped only after ensuring this specific Instance is stopped."
[[ -n "$TARGET_CSGO" ]] || { usage >&2; exit 2; }

[[ -d "$ROOT_DIR/.git" || -f "$ROOT_DIR/.git" ]] || die "The script must run from a Git checkout of cs2-kus-addons."
[[ -d "$SOURCE_ADDONS" ]] || die "Tracked plugin payload is missing: $SOURCE_ADDONS"
[[ -f "$ROOT_DIR/DEPENDENCIES.json" ]] || die "DEPENDENCIES.json is missing from the repository checkout."
command -v rsync >/dev/null 2>&1 || die "rsync is required. Install it before running this script."
command -v flock >/dev/null 2>&1 || die "flock is required to prevent concurrent writes to the same Instance."
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required to create a per-Instance lock."

TARGET_CSGO="$(realpath -e -- "$TARGET_CSGO")" || die "Target directory does not exist."
TARGET_ADDONS="$TARGET_CSGO/addons"
[[ -d "$TARGET_ADDONS" ]] || die "Target has no addons/ directory: $TARGET_ADDONS. Run initial Instance provisioning first."

# The shared game and this repository's source payload must never be update targets.
case "$TARGET_CSGO/" in
    "$ROOT_DIR/"*) die "Target is inside the repository checkout; refusing to modify source files." ;;
esac
[[ ! -e "$TARGET_CSGO/gameinfo.gi" ]] || die "Target contains gameinfo.gi and appears to be a full/shared game directory. Supply the private Instance payload root instead."

# Only committed/clean source payloads are deployable to customer Instances.
SOURCE_CHANGES="$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all -- game/csgo/addons DEPENDENCIES.json)"
[[ -z "$SOURCE_CHANGES" ]] || {
    printf 'ERROR: Plugin payload or DEPENDENCIES.json has uncommitted changes; deploy only a committed payload.\n%s\n' "$SOURCE_CHANGES" >&2
    exit 2
}

SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
TARGET_HASH="$(printf '%s' "$TARGET_CSGO" | sha256sum | awk '{print $1}')"
LOCK_FILE="${TMPDIR:-/tmp}/fragcity-instance-plugin-sync-${TARGET_HASH}.lock"
(umask 077; : >> "$LOCK_FILE") || die "Cannot create per-Instance lock file: $LOCK_FILE"
exec 9>"$LOCK_FILE"
flock -n -x 9 || die "Another plugin sync is already running for this Instance."

# Preserve mode bits/timestamps but never rewrite file owners/groups. --checksum avoids
# copying identical binaries solely because Git checkout timestamps differ. No --delete.
RSYNC_ARGS=(--recursive --links --times --perms --safe-links --checksum --human-readable --itemize-changes)
if [[ "$DRY_RUN" == "1" ]]; then
    RSYNC_ARGS+=(--dry-run)
    printf 'DRY RUN: no Instance files will be written.\n'
fi

FILTERS=(
    --exclude='/windows/***'
    --exclude='/counterstrikesharp/configs'
    --exclude='/counterstrikesharp/configs/***'
    --exclude='*.cfg'
    --exclude='*.json'
    --exclude='*.txt'
    --exclude='*.ini'
    --exclude='*.yaml'
    --exclude='*.yml'
    --exclude='*.toml'
    --exclude='*.conf'
    --exclude='*.properties'
    --exclude='*.xml'
    --exclude='*.env'
    --exclude='*.db'
    --exclude='*.sqlite'
    --exclude='*.sqlite3'
)

printf 'Source commit: %s\n' "$SOURCE_COMMIT"
printf 'Source:       %s/\n' "$SOURCE_ADDONS"
printf 'Instance:     %s\n' "$TARGET_CSGO"
printf 'Action:       sync approved Linux/shared plugin-runtime files only\n'
printf 'Protected:    cfg/, root .txt files, CSS configs/, config/data file types\n'
printf 'Deletion:     disabled (obsolete files are intentionally retained)\n\n'

rsync "${RSYNC_ARGS[@]}" "${FILTERS[@]}" "$SOURCE_ADDONS/" "$TARGET_ADDONS/"

printf '\nSUCCESS: plugin/runtime payload sync completed for this Instance.\n'
printf 'CS2, SteamCMD, Steam Linux Runtime, cfg/, designated root .txt files, and customer configs were not updated.\n'
printf 'The script did not start or stop any server.\n'
