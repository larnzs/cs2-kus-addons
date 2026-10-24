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
[[ "$ENABLE_TIMERS" == "0" || "$ENABLE_TIMERS" == "1" ]] || die "FRAGCITY_ENABLE_TIMERS must be 0 or 1."
if [[ -n "$BASELINE_EXCLUDE_UUID" ]]; then
  [[ "$BASELINE_EXCLUDE_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
    || die "FRAGCITY_BASELINE_EXCLUDE_UUID must be a canonical lowercase UUID."
  [[ ! -e "$BASELINE" && ! -L "$BASELINE" ]] \
    || die "A baseline already exists; an exclusion cannot be applied to it. Existing baseline was preserved."
fi
REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
EXPECTED_REPO_ROOT="/opt/fragcity/cs2-kus-addons"
PANEL_ROOT="${FRAGCITY_PANEL_ROOT:-/var/www/pterodactyl}"
PAYLOAD_ROOT="${FRAGCITY_PAYLOAD_SOURCE:-/var/lib/pterodactyl/mounts/fragcity-addon-payload}"
STATE_ROOT="${FRAGCITY_PROVISIONER_STATE:-/var/lib/pterodactyl/fragcity-addon-provisioner}"
BASELINE="$STATE_ROOT/baseline-uuids.txt"
BASELINE_EXCLUDE_UUID="${FRAGCITY_BASELINE_EXCLUDE_UUID:-}"
ENABLE_TIMERS="${FRAGCITY_ENABLE_TIMERS:-0}"

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
[[ -f "$REPO_ROOT/pterodactyl/systemd/fragcity-status-dashboard.sh" ]] \
  || die "Status dashboard script is missing."
[[ -f "$REPO_ROOT/pterodactyl/systemd/fragcity-systemd-status.desktop" ]] \
  || die "XFCE status dashboard autostart entry is missing."

install -d -o root -g root -m 0755 /etc/systemd/system
install -m 0644 "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-payload-sync.service" \
  /etc/systemd/system/fragcity-addon-payload-sync.service
install -m 0644 "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-payload-sync.timer" \
  /etc/systemd/system/fragcity-addon-payload-sync.timer
install -m 0644 "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-provision.service" \
  /etc/systemd/system/fragcity-addon-provision.service
install -m 0644 "$REPO_ROOT/pterodactyl/systemd/fragcity-addon-provision.timer" \
  /etc/systemd/system/fragcity-addon-provision.timer

log "Installed four systemd unit files."
systemctl daemon-reload

install -d -o root -g root -m 0755 /usr/local/libexec
install -m 0755 "$REPO_ROOT/pterodactyl/systemd/fragcity-status-dashboard.sh" \
  /usr/local/libexec/fragcity-status-dashboard.sh

if command -v xfce4-terminal >/dev/null 2>&1; then
  install -d -o root -g root -m 0755 /etc/xdg/autostart
  install -m 0644 "$REPO_ROOT/pterodactyl/systemd/fragcity-systemd-status.desktop" \
    /etc/xdg/autostart/fragcity-systemd-status.desktop
  log "Installed the XFCE status-window autostart entry; it opens at the next graphical login."
else
  log "xfce4-terminal was not found; the dashboard was installed but the automatic XFCE window was skipped."
fi

if [[ -L "$BASELINE" ]]; then
  die "Baseline path is a symlink: $BASELINE"
elif [[ -f "$BASELINE" ]]; then
  log "Existing baseline preserved; it was not overwritten."
elif [[ -e "$BASELINE" ]]; then
  die "Baseline path exists but is not a regular file: $BASELINE"
else
  log "Taking a one-time baseline of currently eligible servers. This does not modify any server."
  if [[ -n "$BASELINE_EXCLUDE_UUID" ]]; then
    php "$REPO_ROOT/pterodactyl/provision-addon-servers.php" --initialize-baseline --exclude "$BASELINE_EXCLUDE_UUID"
  else
    php "$REPO_ROOT/pterodactyl/provision-addon-servers.php" --initialize-baseline
  fi
fi

if [[ "$ENABLE_TIMERS" == "1" ]]; then
  log "Refreshing and validating the published payload before enabling timers."
  systemctl start fragcity-addon-payload-sync.service
  log "Enabling the payload refresh timer and automatic new-server provisioner."
  systemctl enable --now fragcity-addon-payload-sync.timer
  systemctl enable --now fragcity-addon-provision.timer
  if ! systemctl start fragcity-addon-provision.service; then
    log "WARNING: the immediate provisioning pass failed or skipped work; inspect the dashboard/journal. The timer remains enabled for retries."
  fi
  log "Both timers are enabled. The provisioner will retry servers that are still installing or currently running."
else
  log "Timers were not enabled by this installer invocation."
  log "To enable automation in a controlled first setup, run with FRAGCITY_ENABLE_TIMERS=1."
fi

log "Setup completed."
printf '\n'
printf 'Status dashboard: /usr/local/libexec/fragcity-status-dashboard.sh\n'
printf 'XFCE autostart: /etc/xdg/autostart/fragcity-systemd-status.desktop (opens at the next graphical login).\n'
printf 'Check status with: systemctl list-timers --all "fragcity-addon-*" --no-pager\n'
printf 'Logs: journalctl -u fragcity-addon-provision.service -n 100 --no-pager\n'
