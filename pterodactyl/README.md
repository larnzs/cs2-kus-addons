# FragCity Pterodactyl addon payload and new-server provisioning

This integration connects the existing “Update CS2 Addons” GitHub Actions workflow to newly created servers using the custom K4ryuu/FragCity CS2 Egg. The Git checkout and updater credentials are never mounted into customer containers. The provisioner must not touch eligible servers that existed when its one-time baseline was recorded.

## Architecture at a glance

1. The existing GitHub Actions workflow remains the only source of truth for plugin updates on integration/kus-monorepo.
2. sync-addon-payload-host.sh fetches the branch and publishes an immutable deployable snapshot and inventory under /var/lib/pterodactyl/mounts/fragcity-addon-payload. It excludes only the seven exact K4ryuu-owned runtime paths listed below; every other repository file remains in the payload. Its systemd timer runs every five minutes.
3. One read-only Pterodactyl Mount exposes that host directory to eligible containers at /home/container/egg/fragcity-payload.
4. provision-addon-servers.php --watch checks the Panel database every minute. After the initial safety baseline, it processes only newly created servers that match the Mount's single eligible Egg and Node and have finished installation.
5. The tracked [modified FragCity Egg export](egg-kitsune-lab-c-s2-go--k4ryuu-m-o-d-i-f-i-e-d.json) includes the sync call in the Egg-level Startup template for new servers. The host-side provisioner also ensures eligible stopped server records have the prefix when it processes them; it recognizes an existing prefix and does not duplicate it.
6. If a Docker container already exists and is stopped, the provisioner verifies its exact name and /home/container volume mapping, then runs docker rm <container-id> without -v so the next Panel start creates a fresh container with the Mount. It never removes the server's volume. A running container is not changed.
7. At the next normal start, the Egg startup hook calls `sync-addon-payload-container.sh` before CS2. The script validates `P_SERVER_UUID` and reads the complete `.fragcity-game-files-v1.list` inventory. A volume with a registered `mode=pending` marker receives every deployable file under `game/` on that first sync, including `plugins/disabled/`, the exact customer config paths, platform overlays, and both `subscribed_*_ids.txt` files. Only the seven explicit K4ryuu runtime paths below are filtered. The synchronizer verifies copied files with SHA-256 and records `mode=completed`; later starts update non-config payload files while preserving server-specific configuration. The protected config paths are exactly `game/csgo/cfg/**`, `game/csgo/addons/counterstrikesharp/configs/**`, and these five files directly under `game/csgo/`: `gamemodes_server.txt`, `mapcycle.txt`, `mapcyclecustom.txt`, `subscribed_collection_ids.txt`, and `subscribed_file_ids.txt`. Other `.cfg` files or directories named `config(s)` elsewhere in the game tree are not automatically protected.

The host installer and Provisioner publish a one-way SHA-256 hash registry of the baseline UUIDs through the read-only Mount; raw server UUIDs are not exposed in that registry. If a server starts before the periodic Provisioner has registered it, the startup script recognizes the UUID as absent from the baseline and waits up to 90 seconds for the matching pending state file. The Provisioner can adopt an already-running server only after validating the exact read-only payload Mount, the matching `P_SERVER_UUID`, and the saved startup hook; it does not stop or replace that running container. If the marker is created during the wait, config seeding proceeds on that very first startup. If registration does not complete before timeout, synchronization fails closed and CS2 is not launched. Legacy volumes whose UUIDs are in the baseline and lack a state marker preserve existing config settings. The monitoring tools show the baseline registry state, baseline membership, processed UUID marker, and per-volume seed state so that a new, unregistered server is visible rather than silently classed as legacy.

## Egg startup hook (important)

The tracked export [egg-kitsune-lab-c-s2-go--k4ryuu-m-o-d-i-f-i-e-d.json](egg-kitsune-lab-c-s2-go--k4ryuu-m-o-d-i-f-i-e-d.json) is based on K4ryuu's current Go Egg export, with the FragCity sync hook added at the beginning of its `startup` template. Its startup begins exactly with:

```bash
bash /home/container/egg/fragcity-payload/sync-addon-payload-container.sh &&
```

For the live Panel, edit the existing custom FragCity/K4ryuu Egg's Startup command so this prefix appears once before the existing `./game/cs2.sh ...` command. Do not blindly import this export as a replacement if your current Egg has additional local changes; compare its variables/configuration first. The Go Egg runs the expanded startup command through `/bin/sh -c`, so the prefix launches the Bash synchronizer and only proceeds to CS2 if sync succeeds.

**Important:** changing the Egg's Startup template affects newly created servers; a server already created keeps its saved startup command. For an already-created server, the host provisioner must still attach/confirm the Mount and add the prefix to that server record, or the server-specific startup must be updated separately. A manually attached Mount without the prefix only exposes the files; it does not execute the synchronizer. The existing provisioner checks for the exact prefix and will not add it twice.

The host's volume path contains each server UUID, for example /var/lib/pterodactyl/volumes/<server-uuid>. Inside that container, /home/container is already bound to that exact volume. The container sync script writes every repository-relative path beneath /home/container/game/ and does not hardcode any host volume UUID.

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

The control center checks its own script for a newer version while waiting at the menu. When the payload-sync service fast-forwards this checkout, the open manager reloads the updated menu without needing to close and reopen the terminal. The manager's live update and the dashboard updater change only host-side control scripts; they do not change existing game-server volumes by themselves. The terminal dashboard presents a top-level system posture, resource capacity, service active/boot policy, payload revision and baseline health, mounted/running server tables, first-install attention rows, network listeners and latest automation events. It refreshes the host view every few seconds and performs the read-only Panel/Docker Mount scan on its own slower interval.

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

## Full game-tree payload deployment

The publisher stages the deployable repository `game/` tree into an immutable revision. The snapshot excludes only the seven exact K4ryuu-managed runtime paths listed below. Its generated `.fragcity-game-files-v1.list` records every remaining deployable file, and the publisher validates that every inventory entry exists, no paths are duplicated, and the inventory count matches the staged tree. An incomplete prior revision is rebuilt before publication.

The **only** runtime paths excluded from publication are:
- `game/csgo/addons/counterstrikesharp/api/**`
- `game/csgo/addons/counterstrikesharp/bin/**`
- `game/csgo/addons/counterstrikesharp/dotnet/**`
- `game/csgo/addons/counterstrikesharp/lang/**`
- `game/csgo/addons/metamod/bin/**`
- `game/csgo/addons/metamod/counterstrikesharp.vdf`
- `game/csgo/addons/metamod/metaplugins.ini`

All paths outside this explicit list remain included, including `plugins/disabled/` and customer configuration files. Both `game/csgo/subscribed_collection_ids.txt` and `game/csgo/subscribed_file_ids.txt` are mandatory first-install seed files; publication and first-install verification fail if either is missing.

At each normal server start, `sync-addon-payload-container.sh` validates the deployable inventory under repository `game/`. The host publisher already excludes only the seven exact K4ryuu-managed runtime paths. For a new UUID not in the hashed baseline registry, a missing state marker is not treated as a legacy server: the synchronizer waits up to 90 seconds for the host Provisioner to register it. Once `mode=pending` appears, the first sync copies and SHA-256 verifies every deployable file at matching relative paths under `/home/container/game`, including `plugins/disabled/`, `BotAI/`, `CS2UpdateMonitor/`, platform overlays and both subscribed-ID files. The sync fails if either subscribed-ID file is missing or its copied SHA-256 does not match. The exact config paths seeded once are `csgo/cfg/**`, `csgo/addons/counterstrikesharp/configs/**`, and five top-level files: `gamemodes_server.txt`, `mapcycle.txt`, `mapcyclecustom.txt`, `subscribed_collection_ids.txt`, and `subscribed_file_ids.txt`. On success the state becomes `mode=completed`.

On subsequent starts, only those exact config paths are protected from overwrite and stale cleanup. Other files ending in `.cfg` or directories called `config`/`configs` elsewhere remain normal repository-managed payload files. Legacy volumes whose UUIDs are present in the baseline registry but have no seed marker preserve their current configs. The deployable inventory contains every repository game file except the seven exact K4ryuu-managed runtime paths; customer configuration handling remains a separate per-server first-install policy. The two subscribed-ID files also have a create-if-absent safeguard: if either is missing on an already completed or legacy volume, sync restores and hash-verifies that missing file without replacing existing customer contents.

This is an **overlay**, not a request to replace the whole Steam-installed game directory with an exact mirror. Files present only in the upstream CS2 installation and absent from repository `game/` are retained. Stale cleanup is limited to previously recorded, non-config files that have disappeared from the repository.

The published Mount exposes only the filtered deployable `game/` payload, its inventory/commit metadata, a lock and the container sync script. K4ryuu-owned runtime paths are absent from the snapshot and are never removed from a live volume, even if an older manifest listed them. The mount does not expose the checkout, `.git` directory or host Git credentials inside a container.
 
## Host repository access

The publisher runs on the host and uses the checkout at /opt/fragcity/cs2-kus-addons. Keep it on a clean `integration/kus-monorepo` branch. If the repository is private, configure a host-only read-only GitHub deploy key or Git credential helper that works for root and the systemd service. Never put a token in the remote URL, repository, Egg variables, or container environment. The published Mount exposes only the filtered deployable `game/` snapshot, its inventory/commit metadata, lock and container sync script—not the checkout, `.git` directory, or Git credentials. Repository visibility is separate from this mount boundary: a public GitHub repository still exposes its tracked source publicly.

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

# Fetch/fast-forward to the current branch and publish the deployable game/ payload after exact runtime filters.
bash pterodactyl/sync-addon-payload-host.sh || exit 1
```

The publisher itself performs a fetch and a fast-forward-only update. If that update changes the publisher script, it restarts under the updated script before staging. It refuses a dirty/diverged checkout, and it leaves the last published revision available if publishing fails.

Verify that the active commit marker and complete game-file inventory agree:

```bash
M="/var/lib/pterodactyl/mounts/fragcity-addon-payload"
C="$(tr -d '\r\n' < "$M/CURRENT_COMMIT")" || exit 1
REV="$M/revisions/$C"
GAME="$REV/game"
INVENTORY="$REV/.fragcity-game-files-v1.list"
D="$GAME/csgo/addons/counterstrikesharp/plugins/disabled"

echo "Published commit: $C"
test "$(tr -d '\r\n' < "$REV/.source-commit")" = "$C" || exit 1
test -d "$GAME" && test -f "$INVENTORY" || exit 1
SOURCE_FILES="$(find "$GAME" -type f | wc -l)"
INVENTORY_FILES="$(wc -l < "$INVENTORY")"
test "$SOURCE_FILES" -gt 0 && test "$SOURCE_FILES" -eq "$INVENTORY_FILES" || exit 1
while IFS= read -r RELATIVE_PATH; do
    case "/$RELATIVE_PATH/" in *"/../"*) exit 1 ;; esac
    test -f "$GAME/$RELATIVE_PATH" || exit 1
done < "$INVENTORY"
test -d "$D" || exit 1
test -n "$(find "$D" -type f -print -quit)" || exit 1
printf 'Complete game/ files: %s; inventory entries: %s\n' "$SOURCE_FILES" "$INVENTORY_FILES"
printf 'Files in plugins/disabled/: '
find "$D" -type f | wc -l
```

Also run local syntax checks and confirm the GitHub Actions validation for the current `integration/kus-monorepo` HEAD has passed:

```bash
bash -n   pterodactyl/sync-addon-payload-host.sh   pterodactyl/sync-addon-payload-container.sh   pterodactyl/test-sync-payload.sh   pterodactyl/install-host-services.sh

php -l pterodactyl/provision-addon-servers.php
php -l pterodactyl/server-mount-status.php
```

CI validates shell syntax, PHP syntax/CLI argument handling, complete game-tree publication, inventory correctness, recovery of an incomplete read-only revision, full-tree transfer including disabled plugins, idempotency, per-file SHA-256, and stale cleanup limited to previously managed paths. CI does **not** connect to the real Panel database or Docker host; the dedicated live test below covers those integration points.

### 2. One-time live test before systemd

If the dedicated test server has not already been tested, create one in the Panel with a name beginning exactly `FragCity Payload Test`, using the configured Egg and Node. Keep it stopped while running the explicit provisioner command.

```bash
cd /opt/fragcity/cs2-kus-addons || exit 1
TEST_UUID="replace-with-the-test-server-uuid"

php pterodactyl/provision-addon-servers.php --server "$TEST_UUID"
```

Manual `--server` mode deliberately refuses names that do not begin with `FragCity Payload Test`. The provisioner validates the exact UUID-to-volume mapping, Mount definition, server image and any existing Docker container. If an exact stopped container exists, it removes that container without `-v`; it never removes the server volume. A running container is left alone.

Then start the server from the Panel. Its console must show a valid published revision, `Sync completed successfully`, and the complete repository `game/` file/hash counts. `plugins/disabled/` is copied exactly as stored in GitHub, but its contents remain under that directory; the synchronizer does not promote disabled plugins into the active plugin directory.

With the test server running, run the read-only verifier:

```bash
php pterodactyl/provision-addon-servers.php --verify-server "$TEST_UUID"
```

The verifier checks the Panel relation, UUID/volume mapping, running Docker container identity, Mount source/target/read-only flag, `P_SERVER_UUID`, startup prefix, published marker, config-seed state and required runtime commands. It compares update-managed non-config files against the published inventory by SHA-256, but intentionally does not compare customer config paths with repository defaults after the initial seed. Additional files from the Steam-installed game are allowed. It does not mutate the volume or copy files during verification. Verification does not change server files, startup settings, Mount relations or containers.

If the test server was already provisioned earlier, do not run `--server` again; the processed marker intentionally makes repeated provisioning a no-op. Publish the updated payload and restart the selected test server normally. On a freshly provisioned test server, the first start must copy and verify the complete deployable tree, including both subscribed-ID files while excluding only the seven exact K4ryuu runtime paths, and then change the seed state to `mode=completed`. Edit a config file and restart again: its custom contents must survive, while changing a non-config plugin file in the container should cause that file to be refreshed from the repository. The read-only verifier must then pass while explicitly preserving server-specific config paths. A legacy server without the seed state must likewise keep its configs untouched while still receiving the non-config plugin/runtime payload.

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

The timer refreshes the filtered deployable-game immutable snapshot from the current branch approximately every five minutes. A Payload update does not restart running CS2 servers; they sync the published files at their next normal startup.

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
- If a revision is missing any deployable game file, has an invalid filtered inventory, includes a forbidden K4ryuu runtime path, lacks `plugins/disabled/`, or has invalid permissions, rerun the publisher and inspect its output. It validates/rebuilds an incomplete current revision while holding the publisher lock. Do not manually delete revision directories or weaken the Mount's read-only flag.
- If the provisioner fails to find exactly one read-only, non-user-mountable Mount assigned to one Egg and one Node, fix the Panel Mount definition; do not weaken the checks.
- If an automatic provisioning pass fails, inspect `journalctl` first. The processed marker and baseline are safety barriers; do not remove them casually to force a retry.
- Upgrades to Pterodactyl Panel may change internal Laravel model behavior. Re-run the controlled test and verification before relying on this integration after a Panel upgrade.

## Live server monitoring and UUID reconciliation

The read-only status dashboard and Control Center render a separate block for every server that currently exists in the Panel database and matches the configured Egg/Node scope. Each block shows the full UUID and separately labels Panel Mount assignment, actual Docker container state, verified Docker Mount, processed marker, startup hook, baseline membership, and first-install seed state. The Mount inventory refreshes every five seconds by default, independently of the screen refresh interval.

The status probe also reports UUID-named Docker containers that no longer map to any Panel server, plus baseline UUIDs and processed markers that refer to servers no longer in the Panel database. These are shown in separate **orphan** and **historical/stale** sections, never mixed into the current server list. Baseline and marker files are not automatically deleted, and the monitor does not stop containers or remove volumes. If Docker inventory cannot be read, the monitor says the orphan count is unknown rather than claiming zero.

## Validation scope

The GitHub Actions workflow validates Bash/PHP syntax and CLI safety and runs the publisher/container synchronizer against a temporary volume. It covers filtered inventory creation and validation, all seven exact K4ryuu runtime exclusions, seeding and later preservation of both subscribed-ID files, preservation of Egg-owned runtime fixtures, recovery of an incomplete revision, deployment of `plugins/disabled/` and all other non-excluded subtrees, per-file SHA-256 verification, idempotency, safe legacy-manifest migration, preservation of untracked CS2 engine files, and stale cleanup restricted to previously managed non-excluded paths. It does not connect to the live Panel database, Docker daemon or a real game-server volume.
