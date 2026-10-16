#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

# Initial seed only. This copies private per-Instance addon/config payload, not CS2
# binaries/Base Game. It never calls SteamCMD, Pterodactyl's API, or a server process.
# Copies: game/csgo/addons (except Windows staging), game/csgo/cfg, and root *.txt files.
# Does not copy gameinfo.gi or any other root files outside this allowlist.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
CONFIG_FILE="${INSTANCE_CONFIG_FILE:-$SCRIPT_DIR/instance.env}"

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
git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Run this from a Git checkout."
[[ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- game/csgo)" ]] || die "game/csgo has uncommitted or untracked files; review and commit them before seeding an Instance."

INSTANCE_ID=""
DRY_RUN=0
usage() {
    cat <<'USAGE'
Usage: bash instance/create-instance.sh [--dry-run] <instance-id>
ID: 1-64 letters, numbers, hyphens or underscores; first character must be a letter/number.
Creates: <INSTANCE_STORAGE_ROOT>/<instance-id>/game/csgo/
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

# First matching rsync rule wins. The allowlist is restricted to addons/, cfg/ and
# top-level *.txt files. There is deliberately no --delete option.
RSYNC_FILTERS=(
    --exclude='/addons/windows/***'
    --exclude='/gameinfo.gi'
    --include='/addons/***'
    --include='/cfg/***'
    --include='/*.txt'
    --exclude='/***'
)
SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
printf 'Instance ID: %s\nSource: %s\nCommit: %s\nDestination: %s/game/csgo\n' "$INSTANCE_ID" "$SOURCE_CSGO" "$SOURCE_COMMIT" "$FINAL_INSTANCE_ROOT"
printf 'Copies addons/, cfg/, top-level *.txt only; Base Game and gameinfo.gi are excluded.\n'

if [[ "$DRY_RUN" == "1" ]]; then
    DRY_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/fragcity-instance-dry-run.XXXXXX")"
    trap 'if [[ -n "${DRY_TMP_ROOT:-}" && -d "$DRY_TMP_ROOT" ]]; then rm -rf -- "$DRY_TMP_ROOT"; fi' EXIT
    mkdir -p "$DRY_TMP_ROOT/game/csgo"
    rsync --recursive --links --times --perms --safe-links --chmod='Dg+rx,Do-rwx,Fg+r,Fo-rwx' --dry-run --itemize-changes "${RSYNC_FILTERS[@]}" "$SOURCE_CSGO/" "$DRY_TMP_ROOT/game/csgo/"
    printf 'DRY RUN complete; no Instance files were created.\n'
    exit 0
fi

mkdir -p -- "$INSTANCE_STORAGE_ROOT"
exec 9>>"$INSTANCE_STORAGE_ROOT/.create-instance.lock"
flock -x 9
[[ ! -e "$FINAL_INSTANCE_ROOT" && ! -L "$FINAL_INSTANCE_ROOT" ]] || die "Target appeared while waiting for lock; refusing overwrite."

STAGING_ROOT="$(mktemp -d "$INSTANCE_STORAGE_ROOT/.${INSTANCE_ID}.staging.XXXXXX")"
trap 'if [[ -n "${STAGING_ROOT:-}" && -d "$STAGING_ROOT" ]]; then rm -rf -- "$STAGING_ROOT"; fi' EXIT
mkdir -p "$STAGING_ROOT/game/csgo"
rsync --recursive --links --times --perms --safe-links --chmod='Dg+rx,Do-rwx,Fg+r,Fo-rwx' --human-readable --itemize-changes "${RSYNC_FILTERS[@]}" "$SOURCE_CSGO/" "$STAGING_ROOT/game/csgo/"

cat > "$STAGING_ROOT/.fragcity-seed.json" <<EOF
{
  "schema_version": 1,
  "instance_id": "$INSTANCE_ID",
  "source_repository": "larnzs/cs2-kus-addons",
  "source_commit": "$SOURCE_COMMIT",
  "created_at_utc": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "payload": ["game/csgo/addons", "game/csgo/cfg", "game/csgo/*.txt"],
  "base_game_copied": false
}
EOF

# Optional owner/group lets the Node prepare read permissions for a future tested overlay.
# The default remains the user executing this trusted script. We never guess a Panel UID.
if [[ -n "$INSTANCE_OWNER" || -n "$INSTANCE_GROUP" ]]; then
    [[ "$EUID" -eq 0 ]] || die "Run as root when INSTANCE_OWNER or INSTANCE_GROUP is configured."
    if [[ -n "$INSTANCE_OWNER" && -n "$INSTANCE_GROUP" ]]; then
        OWNER_SPEC="$INSTANCE_OWNER:$INSTANCE_GROUP"
    elif [[ -n "$INSTANCE_OWNER" ]]; then
        OWNER_SPEC="$INSTANCE_OWNER"
    else
        OWNER_SPEC=":$INSTANCE_GROUP"
    fi
    chown -R -- "$OWNER_SPEC" "$STAGING_ROOT"
fi
# Keep payload private by default; rsync's chmod also strips world access from contents.
chmod 0750 "$STAGING_ROOT"

# Atomic finalization on the same filesystem; the final destination must not exist.
mv -T -- "$STAGING_ROOT" "$FINAL_INSTANCE_ROOT"
STAGING_ROOT=""
printf '\nSUCCESS: private payload seeded at %s\n' "$FINAL_INSTANCE_ROOT"
printf 'No Base Game, gameinfo.gi, Windows staging, SteamCMD, server process or Panel API was touched.\n'
