# FragCity Pterodactyl addon payload and new-server provisioning

This integration connects the existing “Update CS2 Addons” GitHub Actions workflow to newly created servers using the custom K4ryuu/FragCity CS2 Egg. The Git checkout and updater credentials are never mounted into customer containers. The provisioner must not touch eligible servers that existed when its one-time baseline was recorded.

## Architecture at a glance

1. The existing GitHub Actions workflow remains the only source of truth for plugin updates on integration/kus-monorepo.
2. sync-addon-payload-host.sh fetches the branch and publishes an immutable, allowlisted snapshot under /var/lib/pterodactyl/mounts/fragcity-addon-payload. Its systemd timer runs every five minutes.
3. One read-only Pterodactyl Mount exposes that host directory to eligible containers at /home/container/egg/fragcity-payload.
4. provision-addon-servers.php --watch checks the Panel database every minute. After the initial safety baseline, it processes only newly created servers that match the Mount's single eligible Egg and Node and have finished installation.
5. For each eligible new server, the provisioner validates the UUID and exact host volume, prepares the empty mount target under that server's own volume, attaches the Mount to that server through the installed Panel's Laravel models, and prefixes only that server's stored startup command with the sync script.
6. If a Docker container already exists and is stopped, the provisioner verifies its exact name and /home/container volume mapping, then runs docker rm <container-id> without -v so the next Panel start creates a fresh container with the Mount. It never removes the server's volume. A running container is not changed.
7. At the next normal start, K4ryuu's runtime update work runs first; the FragCity startup prefix then executes sync-addon-payload-container.sh before CS2 launches. The container script requires the runtime-provided P_SERVER_UUID, validates it as a UUID and logs the target identity before changing any game files. It copies and SHA-256 verifies the managed addon payload into that same server's /home/container/game/csgo/ tree, including the complete CounterStrikeSharp configs/ tree, the complete cfg/ tree, and five top-level CS2 config/list files. If the UUID is missing or malformed, synchronization fails closed before creating or updating managed game paths.

The host's volume path contains each server UUID, for example /var/lib/pterodactyl/volumes/<server-uuid>. Inside that container, /home/container is already bound to that exact volume. The container sync script therefore writes to /home/container/game/csgo/ and does not hardcode any host volume UUID.

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
- game/csgo/cfg/ (the entire tree)
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

The full `game/csgo/addons/counterstrikesharp/configs/` tree and full `game/csgo/cfg/` tree are now managed and mirrored from the repository, together with `gamemodes_server.txt`, `mapcycle.txt`, `mapcyclecustom.txt`, `subscribed_collection_ids.txt` and `subscribed_file_ids.txt` at the top level of `game/csgo/`. These paths are authoritative repository payloads: local edits and extra files inside these two trees are replaced or removed during sync. Make lasting changes in Git and let the next published revision distribute them. The sync never replaces the whole `game/csgo/` directory.

Managed payload paths must not contain symlinks. The publisher validates the source trees and stages them into an immutable, read-only snapshot; the container synchronizer hashes each deployed file and performs stale-file cleanup only after all desired files have passed SHA-256 verification.

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

The verifier checks the Panel relation, UUID/volume mapping, running Docker container identity, Mount source/target/read-only flag, `P_SERVER_UUID`, startup prefix, published marker and required runtime commands. It also hashes each file in the published `plugins/disabled/` tree against the corresponding file in this server's volume. It does not change server files, startup settings, Mount relations or containers.

If this test has already passed and the current server successfully synchronized `disabled/`, do not provision it again just for the documentation. Continue to the baseline installation below.

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

The GitHub Actions workflow validates Bash/PHP syntax and CLI safety and runs the publisher/container synchronizer against a temporary directory tree. It covers incomplete-revision recovery (including failure without losing the previous revision), the `plugins/disabled/` payload, exact SHA-256 mirrors for CounterStrikeSharp configs and `cfg/`, the five top-level CS2 config/list files, idempotency, safe stale-file cleanup and preservation of excluded plugin paths. It does not connect to the live Panel database, Docker daemon or real game-server volume. Live verification on the dedicated test server is required before enabling automation.
