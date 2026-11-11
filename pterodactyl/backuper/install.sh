#!/usr/bin/env bash
# Installs only the independent Backuper timer; never alters Provisioner timers.
set -Eeuo pipefail
log() { printf '[fragcity-backuper-install] %s\n' "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Run this installer as root."
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
EXPECTED_ROOT="/opt/fragcity/cs2-kus-addons"
CONFIG_DIR="/etc/fragcity"
CONFIG_FILE="$CONFIG_DIR/backuper.conf"
RUN_NOW="${FRAGCITY_BACKUP_RUN_NOW:-0}"

[[ "$REPO_ROOT" == "$EXPECTED_ROOT" ]] || die "Expected checkout at $EXPECTED_ROOT; found $REPO_ROOT."
[[ -d "$REPO_ROOT/.git" ]] || die "Repository is not a normal Git checkout."
[[ "$(git -C "$REPO_ROOT" branch --show-current)" == "integration/kus-monorepo" ]] || die "Checkout must be on integration/kus-monorepo."
[[ "$RUN_NOW" == "0" || "$RUN_NOW" == "1" ]] || die "FRAGCITY_BACKUP_RUN_NOW must be 0 or 1."

for file in "$SCRIPT_DIR/fragcity-backuper.sh" "$SCRIPT_DIR/backuper.conf.example" \
            "$SCRIPT_DIR/fragcity-backuper.service" "$SCRIPT_DIR/fragcity-backuper.timer"; do
  [[ -f "$file" && ! -L "$file" ]] || die "Required file is missing or unsafe: $file"
done
command -v systemctl >/dev/null 2>&1 || die "systemd is required."
command -v flock >/dev/null 2>&1 || die "flock is required."

install -d -o root -g root -m 0755 "$CONFIG_DIR" /etc/systemd/system
install -d -o root -g root -m 0700 /var/backups/fragcity
touch "$REPO_ROOT/.git/fragcity-payload-stage.lock"
chmod 0600 "$REPO_ROOT/.git/fragcity-payload-stage.lock"

if [[ -L "$CONFIG_FILE" ]]; then
  die "Config path is a symlink: $CONFIG_FILE"
elif [[ -e "$CONFIG_FILE" ]]; then
  [[ -f "$CONFIG_FILE" && "$(stat -c '%u' "$CONFIG_FILE")" == "0" ]] || die "Existing config must be a root-owned regular file."
  chmod 0600 "$CONFIG_FILE"
  log "Existing config preserved."
else
  install -o root -g root -m 0600 "$SCRIPT_DIR/backuper.conf.example" "$CONFIG_FILE"
  log "Installed default config."
fi

# Validate the administrator config before installing/enabling any scheduler.
FRAGCITY_BACKUP_CONFIG="$CONFIG_FILE" /usr/bin/bash "$SCRIPT_DIR/fragcity-backuper.sh" --check-config
# shellcheck disable=SC1090
source "$CONFIG_FILE"
: "${REQUIRE_SEPARATE_DESTINATION:=1}"
[[ "$REQUIRE_SEPARATE_DESTINATION" == "0" || "$REQUIRE_SEPARATE_DESTINATION" == "1" ]] || die "REQUIRE_SEPARATE_DESTINATION must be 0 or 1."
install -d -o root -g root -m 0700 "$BACKUP_ROOT"
if [[ "$REQUIRE_SEPARATE_DESTINATION" == "1" ]]; then
  command -v findmnt >/dev/null 2>&1 || die "findmnt is required to validate the backup mount."
  root_source="$(findmnt -n -o SOURCE -T / 2>/dev/null || true)"
  backup_source="$(findmnt -n -o SOURCE -T "$BACKUP_ROOT" 2>/dev/null || true)"
  [[ -n "$root_source" && -n "$backup_source" && "$root_source" != "$backup_source" ]] || die "Refusing to enable the scheduler: mount a separate disk/NAS at $BACKUP_ROOT first."
fi

install -o root -g root -m 0644 "$SCRIPT_DIR/fragcity-backuper.service" /etc/systemd/system/fragcity-backuper.service
install -o root -g root -m 0644 "$SCRIPT_DIR/fragcity-backuper.timer" /etc/systemd/system/fragcity-backuper.timer
systemctl daemon-reload
systemctl enable --now fragcity-backuper.timer

if [[ "$RUN_NOW" == "1" ]]; then
  log "Immediate backup explicitly requested."
  systemctl start fragcity-backuper.service
else
  log "No immediate backup started; run --dry-run before the first scheduled run."
fi

log "Enabled only fragcity-backuper.timer; existing Provisioner and payload-sync timers were not changed."
printf '\nDry-run: sudo bash %s/fragcity-backuper.sh --dry-run\n' "$SCRIPT_DIR"
printf 'Run:     sudo systemctl start fragcity-backuper.service\n'
printf 'Logs:    sudo journalctl -u fragcity-backuper.service -n 100 --no-pager\n'
