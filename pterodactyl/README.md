# FragCity Pterodactyl addon payload and new-server provisioning

This integration connects the existing “Update CS2 Addons” GitHub Actions workflow to newly created servers using the custom K4ryuu/FragCity CS2 Egg. The Git checkout and updater credentials are never mounted into customer containers. The provisioner must not touch eligible servers that existed when its one-time baseline was recorded.

## Architecture at a glance

1. The existing GitHub Actions workflow remains the only source of truth for plugin updates on integration/kus-monorepo.
2. sync-addon-payload-host.sh fetches the branch and publishes an immutable, allowlisted snapshot under /var/lib/pterodactyl/mounts/fragcity-addon-payload. Its systemd timer runs every five minutes.
3. One read-only Pterodactyl Mount exposes that host directory to eligible containers at /home/container/egg/fragcity-payload.
4. provision-addon-servers.php --watch checks the Panel database every minute. After the initial safety baseline, it processes only newly created servers that match the Mount's single eligible Egg and Node and have finished installation.
5. For each eligible new server, the provisioner validates the UUID and exact host volume, prepares the empty mount target under that server's own volume, attaches the Mount to that server through the installed Panel's Laravel models, and prefixes only that server's stored startup command with the sync script.
6. If a Docker container already exists and is stopped, the provisioner verifies its exact name and /home/container volume mapping, then runs docker rm <container-id> without -v so the next Panel start creates a fresh container with the Mount. It never removes the server's volume. A running container is not changed.
7. At the next normal start, K4ryuu's runtime update work runs first; the FragCity startup prefix then executes sync-addon-payload-container.sh before CS2 launches. The container script requires the runtime-provided P_SERVER_UUID, validates it as a UUID and logs the target identity before changing any game files. Plugin code and its runtime support payload (source/, plugins/ including disabled/, shared/, gamedata/, and allowlisted addon/VDF files) continues to be hash-synced on every start. Configuration is a separate, one-time seed: only a newly provisioned volume carrying the provisioner's .fragcity-config-seed-v1.state marker receives the repository CounterStrikeSharp configs/, listed custom cfg/ files, and the five top-level CS2 config/list files. After verification, the same per-volume state file is appended with mode=completed; later starts never overwrite or stale-prune those configuration paths. The state file is pre-created by the host with permissions that let the isolated container record completion even when the volume root itself is not writable. An existing/legacy volume without a state marker is treated as legacy and its settings are preserved instead of being reseeded during rollout. The first seed still rejects symlinked targets and does not stale-prune unrelated game-owned cfg files. If the UUID is missing or malformed, synchronization fails closed before creating or updating managed game paths.

The host's volume path contains each server UUID, for example /var/lib/pterodactyl/volumes/<server-uuid>. Inside that container, /home/container is already bound to that exact volume. The container sync script therefore writes to /home/container/game/csgo/ and does not hardcode any host volume UUID.

## Visible XFCE status window and one-time automated bootstrap

The system services are intentionally headless: systemd cannot safely create an interactive GUI window from a recurring oneshot service. The installer therefore installs a read-only dashboard script and an XFCE autostart entry. The redesigned live monitor is organized into Host Health, Service Health, Automation/Publish Status, Active Mounted Servers, Network Snapshot, and Latest Automation Events. It refreshes host/service data every five seconds and rechecks the more expensive Panel/Docker Mount inventory every fifteen seconds. The Active Mounted count is intentionally strict: a server counts only when its Docker container is `RUNNING` and `docker inspect` confirms the expected FragCity source and target with read-only mode; a Panel assignment alone is not treated as an active mount. The dashboard shows the published payload/source revisions, marker consistency, timer next/last trigger times, baseline and processed-marker counts, real Docker-mounted server rows, host CPU load/RAM/swap/disk, service active/boot states, IP addresses, game UDP listeners, and the latest publisher/provisioner events. The mount inventory is root-only because it reads Panel's database and Docker metadata; if XFCE is running as a non-root user, the terminal may prompt for sudo authentication when opening the monitor. The root-owned payload publisher also updates `/usr/local/libexec/fragcity-status-dashboard.sh` from this branch after checking the new script's Bash syntax. The update is written atomically; an already-open dashboard detects its checksum changing and re-execs the new version, so UI changes arrive live without rerunning the installer or opening another window. This dashboard updater changes only the host-side status script, never game-server volumes.

For the first automated setup, if a specific server has already been created and should be handled by the watcher, pass its UUID as the one-time baseline exclusion. All other currently eligible servers are recorded in the baseline and remain untouched. The excluded UUID must genuinely match the configured Mount's Egg and Node; otherwise baseline initialization fails without creating the baseline.

Example for a deliberately selected new/test server:

```bash
cd /opt/fragcity/cs2-kus-addons || exit 1
NEW_SERVER_UUID='replace-with-the-new-server-uuid'
FRAGCITY_BASELINE_EXCLUDE_UUID="$NEW_SERVER_UUID" \
FRAGCITY_ENABLE_TIMERS=1 \
bash pterodactyl/install-host-services.sh
```

Use the exclusion only while the baseline file does not yet exist. An existing baseline is never overwritten, and an exclusion is refused if a baseline already exists. With `FRAGCITY_ENABLE_TIMERS=1`, the installer first runs the payload publisher, enables both timers, then triggers one immediate watcher pass. A server that is still installing or has a running container is deferred and retried by the provisioner timer. The dashboard is installed under `/usr/local/libexec/fragcity-status-dashboard.sh`; the XFCE autostart entry is `/etc/xdg/autostart/fragcity-systemd-status.desktop`. If XFCE is already logged in, the new window appears at the next graphical login; the dashboard can also be launched from an existing XFCE terminal.


### Clickable terminal control center (no separate dashboard window required)

The folder also contains a click-to-open XFCE launcher, FragCity-Control-Center.desktop, and its interactive manager, fragcity-manager.sh. This is the Linux equivalent of opening a small .exe-style utility: the launcher opens one terminal window and the manager keeps its menu in that same window. A .so is a shared library format, not the right format for this task.

The current menu has a separate details page for each major host component: Docker and its containers; Wings and its configuration; CS2Node and shared game files; PHP CLI/PHP-FPM; Nginx and HTTP listeners/config validation; the Pterodactyl Panel and queue worker; MariaDB; and Redis. The Control Center home screen also shows active/ON-OFF and enabled-at-boot states for core host services, plus a read-only inventory of every server eligible for the configured Mount. Each eligible server row separates the Panel Mount relation (ON/OFF) from the actual Docker container Mount (ON/OFF/PENDING/UNKNOWN), and shows provisioning-marker and startup-prefix state. PENDING means no UUID-named container exists yet; it is not reported as a confirmed Docker Mount. This inventory refreshes at most every 15 seconds to keep the two-second menu auto-update responsive without repeatedly querying the Panel database and Docker daemon. Each page shows the relevant systemd state, ON/OFF status, runtime/version or configuration checks, listeners or container/process details where relevant, and recent logs. There is also an all-services summary and a host resource page for RAM, storage, kernel and network interfaces.

The control center can:
- Toggle the payload auto-sync timer ON/OFF and persist that choice across reboots.
- Toggle the new-server provisioner timer ON/OFF. Turning it off pauses future automatic provisioning; it does not detach Mounts already assigned to servers.
- Run a payload refresh now, including fetching the newest branch and updating the host-side dashboard.
- Trigger one provisioning pass (requires typing YES because it may modify eligible stopped servers).
- Open a **Full First Install / Reinstall / Repair** wizard from menu option `I`. First-install mode can turn both timers on or keep the current timer settings unchanged (on a fresh setup, that leaves them off); it may optionally exclude one eligible server while creating a baseline that does not yet exist. Reinstall mode refreshes the service-unit/dashboard/autostart files and preserves each timer's existing enable/disable state.
- The wizard asks for an explicit `INSTALL` or `REINSTALL` confirmation. It does not delete the baseline, Mount relations, Docker volumes, or game-server data. If an existing baseline is present, it is never regenerated by this flow.
- Open the live dashboard in the same terminal, show recent logs, follow both services' logs, and show the next scheduled runs.

The manager requests root privileges with sudo when launched as a normal desktop user. To open it from Thunar/File Manager, allow launching the .desktop file once if XFCE asks or displays it as a text file, then double-click FragCity-Control-Center.desktop. The launcher expects this checkout path: /opt/fragcity/cs2-kus-addons.

The control center checks its own script for a newer version while waiting at the menu. When the payload-sync service fast-forwards this checkout, the open manager reloads the updated menu without needing to close and reopen the terminal. The manager's live update and the dashboard updater change only host-side control scripts; they do not change existing game-server volumes by themselves.

## What remains a one-time Panel setup

Pterodactyl 1.x has no documented public API for attaching a Mount definition to an individual server. For Panel 1.15.x, the provisioner uses the installed Panel's Laravel models to attach it. Recheck this internal model integration before upgrading Panel.

Create one Mount in Admin → Mounts with these exact properties:

| Setting | Value |
| --- | --- |
| Name | FragCity Addon Payload |
| Host source | /var/lib/pterodactyl/mounts/fragcity-addon-payload |
| Container target | /home/container/egg/fragcity-payload |
| Read Only | Enabled |
| User Mountable | Disabled |
| Eligible Egg | Exactly the custom Modified FragCity/K4ryuu CS2 Egg |
| Eligible Node | Exactly the node that should use this publisher, currently server1 |

The mount source must exist before it is attached. In /etc/pterodactyl/config.yml, the existing allowed_mounts entry for /var/lib/pterodactyl/mounts already permits this child path; do not modify Wings config or restart Wings just for this mount. The older mountplugins and mountconfigs paths are unrelated and are not used by this flow.

Keep the Mount eligible for exactly one Egg and one Node. The provisioner deliberately fails closed if the definition is absent, duplicated for the same source/target, not read-only, user-mountable, or assigned to multiple Eggs/Nodes.

## Payload files and exclusions

The immutable snapshot includes only these allowlisted paths:

- game/csgo/addons/counterstrikesharp/source/
- game/csgo/addons/counterstrikesharp/plugins/, including disabled/ but excluding top-level BotAI/ and CS2UpdateMonitor/
- game/csgo/addons/counterstrikesharp/shared/
- game/csgo/addons/counterstrikesharp/gamedata/
- game/csgo/addons/counterstrikesharp/configs/ (the entire tree)
- game/csgo/cfg/ (repository-owned custom config files only; deployment does not mirror or stale-prune the target cfg directory)
- game/csgo/gamemodes_server.txt
- game/csgo/mapcycle.txt
- game/csgo/mapcyclecustom.txt
- game/csgo/subscribed_collection_ids.txt
- game/csgo/subscribed_file_ids.txt
- game/csgo/addons/MovementUnlocker/
- game/csgo/addons/serverlistplayersfix_mm/
- game/csgo/addons/surf/
- game/csgo/addons/scripts/
- game/csgo/addons/multiaddonmanager/
- game/csgo/addons/metamod/serverlistplayersfix_mm.vdf

The repository checkout itself, `.git`, update scripts, updater credentials, the active plugin directories `BotAI/` and `CS2UpdateMonitor/`, and Egg-managed Metamod/CounterStrikeSharp runtime files are not staged or deployed. The `plugins/disabled/` tree is staged and synchronized like other managed CounterStrikeSharp plugin files, but remains under `disabled/`; disabled plugins are never promoted into the active `plugins/` root. A local plugin directory named `BotAI/` or `CS2UpdateMonitor/` is left untouched rather than copied or pruned.

Configuration files are first-install defaults, not continuously managed files. When the provisioner processes a newly created server, it writes `.fragcity-config-seed-v1.state` into that server's own volume with `mode=pending`. The next startup copies and verifies the repository's `game/csgo/addons/counterstrikesharp/configs/` tree, updates only the listed custom files under `game/csgo/cfg/`, and seeds the five top-level files `gamemodes_server.txt`, `mapcycle.txt`, `mapcyclecustom.txt`, `subscribed_collection_ids.txt` and `subscribed_file_ids.txt`. It then appends `mode=completed` to `.fragcity-config-seed-v1.state`; every subsequent start skips all three config groups entirely, including stale cleanup, so customer edits and newly created config files persist. Existing servers without a state marker are never overwritten during rollout. This deliberate migration default prioritizes protecting customer settings; a genuinely new server should be provisioned by the current watcher so it receives the state file with `mode=pending`. During the one-time seed, unrelated target-side cfg files and stock CS2 files such as `gamemode_*.cfg`, `machine_convars_default.vcfg`, `user_keys_default.vcfg` and `user_keys_dev_default.vcfg` are preserved. The plugin/source/shared/gamedata/addon payload remains hash-synced on every start. Symlink checks continue to prevent writes through symlinked paths during the seed and plugin synchronization.

A per-volume `.fragcity-managed-payload-v1.list` manifest tracks files previously deployed by the FragCity payload. File-level stale cleanup may remove a file only if it appears in that previous manifest and is absent from the current payload. The first sync after this feature is introduced has no prior manifest, so it skips manifest-based file deletion once. That safeguard does **not** disable plugin-directory reconciliation: every published snapshot also includes `.fragcity-plugin-inventory-v1.list`, generated from the top-level plugin directories actually staged from the current GitHub branch. At every server startup, the container synchronizer compares live CounterStrikeSharp plugin directories against this authoritative list, even for legacy servers with no old manifest. A directory no longer in the list—for example, a plugin deleted from GitHub—is moved out of `game/csgo/addons/counterstrikesharp/plugins/` into `.fragcity-retired-plugins/<commit-timestamp-batch>/<plugin-name>`. It can no longer be loaded by CounterStrikeSharp, while its files/data remain available for recovery. The `BotAI/` and `CS2UpdateMonitor/` directories remain excluded from file copying because they are handled separately, but their folder names are included in the authoritative GitHub inventory while their source folders still exist. If either source folder is removed from the branch, the same startup reconciliation quarantines the old active target folder. `disabled/` is a reserved directory included in the inventory. Plugin-generated/runtime data is never sourced from the repository or entered into the file manifest: this includes SQLite/database files such as `PlayerSettings/settings.sqlite` and `SimpleAdmin/bans.db`, `SimpleAdmin/data/`, and per-map JSON files under `CS2-Poor-MapPropAds/maps/`. Empty directories under plugin roots are left alone as well.

Managed payload paths must not contain symlinks. The publisher validates source trees and stages them into an immutable, read-only snapshot; the container synchronizer hashes each deployed file and stale-prunes only files recorded in the prior per-volume manifest after all desired files have passed SHA-256 verification. Files absent from that manifest—including plugin-generated databases and runtime data—are preserved.

## Host repository access

The publisher runs on the host and uses the checkout at /opt/fragcity/cs2-kus-addons. Keep it on a clean `integration/kus-monorepo` branch. If the repository is private, configure a host-only read-only GitHub deploy key or Git credential helper that works for root and the systemd service. Never put a token in the remote URL, repository, Egg variables, or container environment. The published Mount exposes only an allowlisted payload snapshot and the container sync script—not the checkout, `.git` directory, or Git credentials. Repository visibility is separate from this mount boundary: a public GitHub repository still exposes its tracked source publicly.

The host publisher uses git fetch plus fast-forward-only updates. If GitHub access fails, the checkout is dirty/diverged, or the payload fails validation, the last published snapshot remains available.

## Operational runbook: test first, then systemd

**Do not install or enable the timers until the manual payload test and read-only verification have passed.** The live test should be done on a dedicated server whose Panel name starts with `FragCity Payload Test`, using the one eligible Egg and Node assigned to the Mount.

### 1. Preflight the checkout and published payload

Run on the Debian/Pterodactyl host as root. The checkout must be clean; do not let the publisher overwrite uncommitted edits.

```bash
cd /opt/fragcity/cs2-kus-addons || exit 1

git branch --show-current
git status -sb

if test -n "$(git status --porcelain)"; then
    echo "STOP: commit or inspect local changes before continuing."
    exit 1
fi

test "$(git branch --show-current)" = "integration/kus-monorepo" || exit 1

# Fetch/fast-forward to the current branch and publish the allowlisted snapshot.
bash pterodactyl/sync-addon-payload-host.sh || exit 1
```

The publisher itself performs a fetch and a fast-forward-only update. If that update changes the publisher script, it restarts under the updated script before staging. It refuses a dirty/diverged checkout, and it leaves the last published revision available if publishing fails.

Verify that the active commit marker and disabled-plugin payload agree:

```bash
M="/var/lib/pterodactyl/mounts/fragcity-addon-payload"
C="$(tr -d '\r\n' < "$M/CURRENT_COMMIT")" || exit 1
REV="$M/revisions/$C"
D="$REV/game/csgo/addons/counterstrikesharp/plugins/disabled"

echo "Published commit: $C"
test "$(tr -d '\r\n' < "$REV/.source-commit")" = "$C" || exit 1
test -d "$D" || exit 1
test -n "$(find "$D" -type f -print -quit)" || exit 1
stat -c '%A (%a) %n' "$REV"
printf 'Files in disabled/: '
find "$D" -type f | wc -l
```

Also run local syntax checks and confirm the GitHub Actions validation for the current `integration/kus-monorepo` HEAD has passed:

```bash
bash -n   pterodactyl/sync-addon-payload-host.sh   pterodactyl/sync-addon-payload-container.sh   pterodactyl/test-sync-payload.sh   pterodactyl/install-host-services.sh

php -l pterodactyl/provision-addon-servers.php
php -l pterodactyl/server-mount-status.php
```

CI validates shell syntax, PHP syntax/CLI argument handling, publisher staging, recovery of an incomplete read-only revision, disabled-plugin transfer, idempotency, stale cleanup and protected-path exclusions. CI does **not** connect to the real Panel database or Docker host; the dedicated live test below covers those integration points.

### 2. One-time live test before systemd

If the dedicated test server has not already been tested, create one in the Panel with a name beginning exactly `FragCity Payload Test`, using the configured Egg and Node. Keep it stopped while running the explicit provisioner command.

```bash
cd /opt/fragcity/cs2-kus-addons || exit 1
TEST_UUID="replace-with-the-test-server-uuid"

php pterodactyl/provision-addon-servers.php --server "$TEST_UUID"
```

Manual `--server` mode deliberately refuses names that do not begin with `FragCity Payload Test`. The provisioner validates the exact UUID-to-volume mapping, Mount definition, server image and any existing Docker container. If an exact stopped container exists, it removes that container without `-v`; it never removes the server volume. A running container is left alone.

Then start the server from the Panel. Its console must show a valid published revision, `Sync completed successfully`, and the file/hash counts. The payload includes `plugins/disabled/` recursively; disabled plugins stay under that directory and are not promoted into the active plugin directory.

With the test server running, run the read-only verifier:

```bash
php pterodactyl/provision-addon-servers.php --verify-server "$TEST_UUID"
```

The verifier checks the Panel relation, UUID/volume mapping, running Docker container identity, Mount source/target/read-only flag, `P_SERVER_UUID`, startup prefix, published marker, config-seed state (if present), and required runtime commands. It compares every published `plugins/disabled/` file by SHA-256 and exact file count. It deliberately does not compare customer-owned `cfg/`, CounterStrikeSharp `configs/`, or the five top-level configuration/list files against repository defaults after first install, because those files are expected to diverge as customers customize their servers. A server without a config-seed state file is treated as legacy and preserved. Verification does not change server files, startup settings, Mount relations or containers.

If the test server was already provisioned earlier, do not run `--server` again; the processed marker intentionally makes repeated provisioning a no-op. Publish the updated payload and start/restart that server normally to verify that addon/plugin files still sync while its existing configs remain untouched. Legacy servers without `.fragcity-config-seed-v1.state` are deliberately never seeded during rollout. To test first-install config seeding end to end, create a fresh dedicated test server after deploying this change and let the current provisioner create its `mode=pending` state marker; its first start must seed the config files and record `mode=completed`, and its next start must preserve edits. Run `--verify-server` after the initial start. A verification from before the one-time seed support was added is not sufficient for this new behavior.

### 3. Install systemd unit files and take the one-time baseline

Only after the live test passes, run the installer as root:

```bash
cd /opt/fragcity/cs2-kus-addons || exit 1
bash pterodactyl/install-host-services.sh
```

The installer checks the repository path/branch/clean state, Panel Laravel files and a published Payload. It installs these four units and runs `systemctl daemon-reload`:

- `fragcity-addon-payload-sync.service`
- `fragcity-addon-payload-sync.timer`
- `fragcity-addon-provision.service`
- `fragcity-addon-provision.timer`

If no baseline exists, it creates `/var/lib/pterodactyl/fragcity-addon-provisioner/baseline-uuids.txt`. That file records every server UUID eligible for the configured Egg and Node at initialization time. This intentionally includes existing production servers and the already tested server, preventing the `--watch` mode from retroactively provisioning them. The baseline operation does not alter servers, Mount assignments, startup strings, containers or volumes.

An existing baseline is preserved and is never regenerated automatically. **Do not delete, empty or recreate it as a troubleshooting step.**

The installer does **not** enable either timer. Confirm that the unit files are installed and the timers remain disabled before going further:

```bash
systemctl list-unit-files 'fragcity-addon-*'

systemctl is-enabled fragcity-addon-payload-sync.timer || true
systemctl is-enabled fragcity-addon-provision.timer || true
systemctl is-active fragcity-addon-payload-sync.timer || true
systemctl is-active fragcity-addon-provision.timer || true

echo "=== Baseline ==="
cat /var/lib/pterodactyl/fragcity-addon-provisioner/baseline-uuids.txt
```

Immediately after a fresh installation, both timers are expected to be `disabled` and `inactive`. If either timer is already enabled or active, stop and inspect its state instead of assuming this is a fresh installation.

### 4. Run and enable the payload publisher first

Execute the oneshot service once, and inspect its status/log before enabling its timer:

```bash
systemctl start fragcity-addon-payload-sync.service
systemctl status fragcity-addon-payload-sync.service --no-pager --full
journalctl -u fragcity-addon-payload-sync.service -n 100 --no-pager

M="/var/lib/pterodactyl/mounts/fragcity-addon-payload"
C="$(tr -d '\r\n' < "$M/CURRENT_COMMIT")" || exit 1
D="$M/revisions/$C/game/csgo/addons/counterstrikesharp/plugins/disabled"
test "$(tr -d '\r\n' < "$M/revisions/$C/.source-commit")" = "$C" || exit 1
test -n "$(find "$D" -type f -print -quit)" || exit 1
```

A successful oneshot service may show `inactive (dead)` after it exits; inspect the recorded `Result`, `ExecMainStatus` and journal. Once successful, enable its five-minute timer:

```bash
systemctl enable --now fragcity-addon-payload-sync.timer
systemctl list-timers --all fragcity-addon-payload-sync.timer --no-pager
```

The timer refreshes the allowlisted immutable snapshot from the current branch approximately every five minutes. A Payload update does not restart running CS2 servers; they sync the published files at their next normal startup.

### 5. Enable automatic provisioning only when ready

Before enabling this timer, confirm that the baseline is correct and that **any eligible server created after the baseline is meant to be automatically configured**. The watcher has no dry-run mode: once enabled, it will attach the Mount and prefix the server-specific startup command for each eligible, post-baseline server it can safely process.

```bash
systemctl enable --now fragcity-addon-provision.timer
systemctl list-timers --all fragcity-addon-provision.timer --no-pager

systemctl status fragcity-addon-provision.timer --no-pager --full
journalctl -u fragcity-addon-provision.service -n 100 --no-pager
```

The provisioner timer checks approximately every minute (with a two-minute boot delay). It processes only servers that match the Mount's single eligible Egg and Node, are absent from the baseline and lack a processed marker. It skips incomplete/failed installations, active transfers, a node under maintenance, and running Docker containers. Skipped servers remain eligible for a later pass; the provisioner does not start or restart a game server.

For a new server, allow provisioning to finish before its first start. If a new server is already running, the watcher will not mutate its container/startup; stop it normally and allow a later watcher pass to retry.

### How to operate and troubleshoot

**Run a publish immediately:**

```bash
bash /opt/fragcity/cs2-kus-addons/pterodactyl/sync-addon-payload-host.sh
```

**Check timers and recent service logs:**

```bash
systemctl status fragcity-addon-payload-sync.timer fragcity-addon-provision.timer --no-pager
journalctl -u fragcity-addon-payload-sync.service -n 100 --no-pager
journalctl -u fragcity-addon-provision.service -n 100 --no-pager
```

**Inspect the current published revision:**

```bash
M="/var/lib/pterodactyl/mounts/fragcity-addon-payload"
C="$(tr -d '\r\n' < "$M/CURRENT_COMMIT")"
D="$M/revisions/$C/game/csgo/addons/counterstrikesharp/plugins/disabled"
printf 'Commit: %s\n' "$C"
cat "$M/revisions/$C/.source-commit"
find "$D" -type f | wc -l
```

**Re-check a running test server without changing it:**

```bash
php /opt/fragcity/cs2-kus-addons/pterodactyl/provision-addon-servers.php --verify-server "$TEST_UUID"
```

**Pause automatic actions** (this leaves the installed unit files, baseline, Mount relations and per-server startup prefixes intact):

```bash
systemctl disable --now fragcity-addon-provision.timer
systemctl disable --now fragcity-addon-payload-sync.timer
```

Troubleshooting guardrails:

- If the publisher reports a dirty checkout, inspect `git status -sb`; do not discard unknown edits to make the command pass.
- If a revision is missing `plugins/disabled/` or has invalid permissions, rerun the publisher and inspect its output. It validates/rebuilds an incomplete current revision while holding the publisher lock. Do not manually delete revision directories or weaken the Mount's read-only flag.
- If the provisioner fails to find exactly one read-only, non-user-mountable Mount assigned to one Egg and one Node, fix the Panel Mount definition; do not weaken the checks.
- If an automatic provisioning pass fails, inspect `journalctl` first. The processed marker and baseline are safety barriers; do not remove them casually to force a retry.
- Upgrades to Pterodactyl Panel may change internal Laravel model behavior. Re-run the controlled test and verification before relying on this integration after a Panel upgrade.

## Validation scope

The GitHub Actions workflow validates Bash/PHP syntax and CLI safety and runs the publisher/container synchronizer against a temporary directory tree. It covers incomplete-revision recovery, the `plugins/disabled/` payload, one-time initial config seeding, persistence of customized `cfg/`, CounterStrikeSharp `configs/` and top-level list files across subsequent starts, legacy-volume preservation, preservation of stock game-owned cfg files, plugin runtime database/data/map JSON preservation, manifest-based stale cleanup, idempotency and excluded plugin paths. It does not connect to the live Panel database, Docker daemon or a real game-server volume.
