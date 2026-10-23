#!/usr/bin/env bash
# Install FragCity's host-side Pterodactyl publisher/provisioner units.
#
# This is deliberately a setup-only command: it installs systemd unit files and
# takes a one-time baseline of servers already eligible for the FragCity Mount.
# It does NOT enable timers, attach a Mount, alter startup commands, remove Docker
# containers, or modify server volumes. Test one new server explicitly first.

set -Eeuo pipefail

log() { printf '[fragcity-install] %s\n' "$*"; }
die() { printf '[fragcity-install] ERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Run this installer as root."
REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
EXPECTED_REPO_ROOT="/opt/fragcity/cs2-kus-addons"
PANEL_ROOT="${FRAGCITY_PANEL_ROOT:-/var/www/pterodactyl}"
PAYLOAD_ROOT="${FRAGCITY_PAYLOAD_SOURCE:-/var/lib/pterodactyl/mounts/fragcity-addon-payload}"
STATE_ROOT="${FRAGCITY_PROVISIONER_STATE:-/var/lib/pterodactyl/fragcity-addon-provisioner}"
BASELINE="$STATE_ROOT/baseline-uuids.txt"

[[ "$REPO_ROOT" == "$EXPECTED_REPO_ROOT" ]] || die "Expected repository at $EXPECTED_REPO_ROOT, found $REPO_ROOT."
[[ -d "$REPO_ROOT/.git" ]] || die "Repository is not a normal Git checkout."
[[ "$(git -C "$REPO_ROOT" branch --show-current)" == "integration/kus-monorepo" ]] || die "Checkout must be on integration/kus-monorepo."
[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || die "Git checkout has local changes; refusing to install."

[[ -d "$PANEL_ROOT" && -f "$PANEL_ROOT/vendor/autoload.php" && -f "$PANEL_ROOT/bootstrap/app.php" ]] \
  || die "Pterodactyl Panel Laravel files were not found under $PANEL_ROOT."
[[ -f "$PAYLOAD_ROOT/CURRENT_COMMIT" && -f "$PAYLOAD_ROOT/.sync.lock" ]] \
  || die "The published payload is not ready at $PAYLOAD_ROOT."
[[ -f "$REPO_ROOT/pterodactyl/provision-addon-servers.php" ]] \
  || die "Provisioner PHP script is missing."
[[ -f "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-payload-sync.service" ]] \
  || die "Payload publisher service unit is missing."
[[ -f "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-payload-sync.timer" ]] \
  || die "Payload publisher timer unit is missing."
[[ -f "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-provision.service" ]] \
  || die "Provisioner service unit is missing."
[[ -f "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-provision.timer" ]] \
  || die "Provisioner timer unit is missing."

install -d -o root -g root -m 0755 /etc/systemd/system
install -m 0644 "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-payload-sync.service" \
  /etc/systemd/system/fragcity-addon-payload-sync.service
install -m 0644 "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-payload-sync.timer" \
  /etc/systemd/system/fragcity-addon-payload-sync.timer
install -m 0644 "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-provision.service" \
  /etc/systemd/system/fragcity-addon-provision.service
install -m 0644 "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-provision.timer" \
  /etc/systemd/system/fragcity-addon-provision.timer

log "Installed four systemd unit files. No timer has been enabled."
systemctl daemon-reload

if [[ -L "$BASELINE" ]]; then
  die "Baseline path is a symlink: $BASELINE"
elif [[ -f "$BASELINE" ]]; then
  log "Existing baseline preserved; it was not overwritten."
elif [[ -e "$BASELINE" ]]; then
  die "Baseline path exists but is not a regular file: $BASELINE"
else
  log "Taking a one-time baseline of currently eligible servers. This does not modify any server."
  php "$REPO_ROOT/pterodactyl/provision-addon-servers.php" --initialize-baseline
fi

log "Setup completed. Timers remain disabled for safety."
printf '\n'
printf 'Next, explicitly provision and test a NEW test server:\n'
printf '  php %s/pterodactyl/provision-addon-servers.php --server <test-server-uuid>\n' "$REPO_ROOT"
printf 'Start that server from the Panel and verify its payload sync before enabling either timer.\n'
printf 'After a successful test, enable automatic publisher/provisioning as documented in pterodactyl/README.md.\n'
