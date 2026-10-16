#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

# Create a complete Linux Instance bundle from the committed repository payload.
# Each target contains the Linux lifecycle scripts at its root and the private
# allowlisted CS2 payload in ./instance/, which run.sh consumes via CUSTOM_FOLDER=instance.
# This does not copy CS2 binaries/Base Game or gameinfo.gi, call SteamCMD/Panel APIs,
# or launch/stop any server process.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
CONFIG_FILE="${INSTANCE_CONFIG_FILE:-$SCRIPT_DIR/instance.env}"
INSTANCE_TEMPLATE_DIR="$REPO_ROOT/linux/instances/instance-template"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

[[ -f "$CONFIG_FILE" ]] || die "Missing config: $CONFIG_FILE. Copy instance/instance.example.env to instance/instance.env first."
set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

INSTANCE_STORAGE_ROOT="${INSTANCE_STORAGE_ROOT:-/var/lib/fragcity/instances}"
[[ "$INSTANCE_STORAGE_ROOT" == /* ]] || die "INSTANCE_STORAGE_ROOT must be an absolute path."
INSTANCE_STORAGE_ROOT="$(realpath -m -- "$INSTANCE_STORAGE_ROOT")"
INSTANCE_OWNER="${INSTANCE_OWNER:-}"
INSTANCE_GROUP="${INSTANCE_GROUP:-}"
[[ "$INSTANCE_OWNER" != *:* && "$INSTANCE_GROUP" != *:* ]] || die "INSTANCE_OWNER and INSTANCE_GROUP must not contain a colon."
case "$INSTANCE_STORAGE_ROOT/" in "$REPO_ROOT/"*) die "INSTANCE_STORAGE_ROOT must be outside the Git checkout." ;; esac

SOURCE_CSGO="$REPO_ROOT/game/csgo"
[[ -d "$SOURCE_CSGO/addons" ]] || die "Missing source addons/: $SOURCE_CSGO/addons"
[[ -d "$SOURCE_CSGO/cfg" ]] || die "Missing source cfg/: $SOURCE_CSGO/cfg"
[[ -d "$INSTANCE_TEMPLATE_DIR" ]] || die "Missing Linux Instance template: $INSTANCE_TEMPLATE_DIR"
[[ -f "$INSTANCE_TEMPLATE_DIR/run.sh" && -f "$INSTANCE_TEMPLATE_DIR/watchdog.sh" && -f "$INSTANCE_TEMPLATE_DIR/stop.sh" && -f "$INSTANCE_TEMPLATE_DIR/update.sh" && -f "$INSTANCE_TEMPLATE_DIR/instance.example.env" ]] || die "Linux Instance template is incomplete."

git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Run this from a Git checkout."
[[ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- game/csgo linux/instances/instance-template)" ]] || die "game/csgo or linux/instances/instance-template has uncommitted or untracked files; review and commit them before seeding an Instance."

INSTANCE_ID=""
DRY_RUN=0
usage() {
    cat <<'USAGE'
Usage: sudo bash instance/create-instance.sh [--dry-run] <instance-id>
ID: 1-64 letters, numbers, hyphens or underscores; first character must be a letter/number.
Creates: <INSTANCE_STORAGE_ROOT>/<instance-id>/ with run.sh, watchdog.sh, stop.sh,
update.sh, instance.env and the private payload in <instance-id>/instance/.
Existing Instance directories are never overwritten.
USAGE
}
while (($#)); do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        --*) die "Unknown option: $1" ;;
        *) [[ -z "$INSTANCE_ID" ]] || die "Supply one instance ID only."; INSTANCE_ID="$1" ;;
    esac
    shift
done

[[ -n "$INSTANCE_ID" ]] || { usage >&2; exit 2; }
[[ "$INSTANCE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]] || die "Invalid instance ID."
FINAL_INSTANCE_ROOT="$INSTANCE_STORAGE_ROOT/$INSTANCE_ID"
[[ ! -e "$FINAL_INSTANCE_ROOT" && ! -L "$FINAL_INSTANCE_ROOT" ]] || die "Target exists; refusing to overwrite: $FINAL_INSTANCE_ROOT"

command -v rsync >/dev/null 2>&1 || die "rsync is required."
command -v flock >/dev/null 2>&1 || die "flock is required."
command -v realpath >/dev/null 2>&1 || die "realpath is required."

# The Linux lifecycle scripts are designed to run as the steam service user.
# Require root so the finished bundle is accessible to that user after creation.
[[ "$EUID" -eq 0 ]] || die "Run as root (for example: sudo bash instance/create-instance.sh <instance-id>)."
id steam >/dev/null 2>&1 || die "The 'steam' service account is missing. Run linux/setup.sh first."

# First matching rsync rule wins. Seed only the per-Instance allowlist from game/csgo:
# addons/ except Windows staging, cfg/, and top-level *.txt files. No --delete is used.
RSYNC_FILTERS=(
    --exclude='/addons/windows/***'
    --include='/addons/***'
    --include='/cfg/***'
    --include='/*.txt'
    --exclude='/***'
)
SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
printf 'Instance ID: %s\nSource payload: %s\nRunner template: %s\nCommit: %s\nDestination: %s\n' "$INSTANCE_ID" "$SOURCE_CSGO" "$INSTANCE_TEMPLATE_DIR" "$SOURCE_COMMIT" "$FINAL_INSTANCE_ROOT"
printf 'Copies lifecycle helpers to the Instance root and allowlisted CS2 payload to %s/instance/.\n' "$FINAL_INSTANCE_ROOT"
printf 'Generated instance.env sets REPO_ROOT to this checkout and CUSTOM_FOLDER=instance.\n'

if [[ "$DRY_RUN" == "1" ]]; then
    DRY_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/fragcity-instance-dry-run.XXXXXX")"
    trap 'if [[ -n "${DRY_TMP_ROOT:-}" && -d "$DRY_TMP_ROOT" ]]; then rm -rf -- "$DRY_TMP_ROOT"; fi' EXIT
    mkdir -p "$DRY_TMP_ROOT/instance"
    rsync -a --safe-links --dry-run --itemize-changes "$INSTANCE_TEMPLATE_DIR/" "$DRY_TMP_ROOT/"
    rsync --recursive --links --times --perms --safe-links --chmod='Dg+rx,Do-rwx,Fg+r,Fo-rwx' --dry-run --itemize-changes "${RSYNC_FILTERS[@]}" "$SOURCE_CSGO/" "$DRY_TMP_ROOT/instance/"
    printf 'DRY RUN complete; no Instance files were created.\n'
    exit 0
fi

mkdir -p -- "$INSTANCE_STORAGE_ROOT"
# The parent is searchable by the steam group; only root can create/remove Instances.
chown root:steam "$INSTANCE_STORAGE_ROOT"
chmod 0750 "$INSTANCE_STORAGE_ROOT"
exec 9>>"$INSTANCE_STORAGE_ROOT/.create-instance.lock"
flock -x 9
[[ ! -e "$FINAL_INSTANCE_ROOT" && ! -L "$FINAL_INSTANCE_ROOT" ]] || die "Target appeared while waiting for lock; refusing overwrite."

STAGING_ROOT="$(mktemp -d "$INSTANCE_STORAGE_ROOT/.${INSTANCE_ID}.staging.XXXXXX")"
trap 'if [[ -n "${STAGING_ROOT:-}" && -d "$STAGING_ROOT" ]]; then rm -rf -- "$STAGING_ROOT"; fi' EXIT
mkdir -p "$STAGING_ROOT/instance"

# Copy every tracked file from the Linux Instance template, including hidden helper
# files such as .gitignore, then put only the allowlisted csgo payload inside ./instance/.
rsync -a --safe-links --human-readable --itemize-changes "$INSTANCE_TEMPLATE_DIR/" "$STAGING_ROOT/"
rsync --recursive --links --times --perms --safe-links --chmod='Dg+rx,Do-rwx,Fg+r,Fo-rwx' --human-readable --itemize-changes "${RSYNC_FILTERS[@]}" "$SOURCE_CSGO/" "$STAGING_ROOT/instance/"

# Create a real per-Instance config from the copied example. Preserve all template
# defaults, but set the actual checkout path and the relative custom payload folder.
{
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            REPO_ROOT=*) printf 'REPO_ROOT=%q\n' "$REPO_ROOT" ;;
            CUSTOM_FOLDER=*) printf 'CUSTOM_FOLDER=%q\n' "instance" ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < "$STAGING_ROOT/instance.example.env"
} > "$STAGING_ROOT/instance.env"
chmod 0600 "$STAGING_ROOT/instance.env"

cat > "$STAGING_ROOT/.fragcity-seed.json" <<EOF
{
  "schema_version": 2,
  "instance_id": "$INSTANCE_ID",
  "source_repository": "larnzs/cs2-kus-addons",
  "source_commit": "$SOURCE_COMMIT",
  "created_at_utc": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "custom_folder": "instance",
  "management_files": ["run.sh", "watchdog.sh", "stop.sh", "update.sh", "instance.env", "instance.example.env"],
  "payload": ["instance/addons", "instance/cfg", "instance/*.txt"],
  "base_game_copied": false,
  "gameinfo_gi_copied": false
}
EOF

# Control scripts/config are operated as steam. Optional owner/group applies only to
# the private payload folder intended for a future container mount.
chown -R -- steam:steam "$STAGING_ROOT"
if [[ -n "$INSTANCE_OWNER" || -n "$INSTANCE_GROUP" ]]; then
    if [[ -n "$INSTANCE_OWNER" && -n "$INSTANCE_GROUP" ]]; then
        OWNER_SPEC="$INSTANCE_OWNER:$INSTANCE_GROUP"
    elif [[ -n "$INSTANCE_OWNER" ]]; then
        OWNER_SPEC="$INSTANCE_OWNER"
    else
        OWNER_SPEC=":$INSTANCE_GROUP"
    fi
    chown -R -- "$OWNER_SPEC" "$STAGING_ROOT/instance"
fi
chmod 0750 "$STAGING_ROOT"

# Atomic finalization on the same filesystem; the final destination must not exist.
mv -T -- "$STAGING_ROOT" "$FINAL_INSTANCE_ROOT"
STAGING_ROOT=""
printf '\nSUCCESS: complete Linux Instance created at %s\n' "$FINAL_INSTANCE_ROOT"
printf 'Lifecycle scripts: run.sh, watchdog.sh, stop.sh, update.sh\n'
printf 'Private payload: %s/instance/ (CUSTOM_FOLDER=instance)\n' "$FINAL_INSTANCE_ROOT"
printf 'No Base Game, gameinfo.gi, Windows staging, SteamCMD, Panel API or server process was touched.\n'
