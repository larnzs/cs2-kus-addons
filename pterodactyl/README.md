# FragCity Pterodactyl addon payload and new-server provisioning

This integration connects the existing scheduled “Update CS2 Addons” workflow to newly created servers using the custom K4ryuu/FragCity CS2 Egg. The private repository is never cloned into customer containers, and this automation must not touch servers that existed before the provisioner was installed.

## Architecture at a glance

1. The existing GitHub Actions workflow remains the only source of truth for plugin updates on integration/kus-monorepo.
2. sync-addon-payload-host.sh fetches the branch and publishes an immutable, allowlisted snapshot under /var/lib/pterodactyl/mounts/fragcity-addon-payload. Its systemd timer runs every five minutes.
3. One read-only Pterodactyl Mount exposes that host directory to eligible containers at /home/container/egg/fragcity-payload.
4. provision-addon-servers.php --watch checks the Panel database every minute. After the initial safety baseline, it processes only newly created servers that match the Mount's single eligible Egg and Node and have finished installation.
5. For each eligible new server, the provisioner validates the UUID and exact host volume, prepares the empty mount target under that server's own volume, attaches the Mount to that server through the installed Panel's Laravel models, and prefixes only that server's stored startup command with the sync script.
6. If a Docker container already exists and is stopped, the provisioner verifies its exact name and /home/container volume mapping, then runs docker rm <container-id> without -v so the next Panel start creates a fresh container with the Mount. It never removes the server's volume. A running container is not changed.
7. At the next normal start, K4ryuu's runtime update work runs first; the FragCity startup prefix then executes sync-addon-payload-container.sh before CS2 launches. The container script requires the runtime-provided P_SERVER_UUID, validates it as a UUID and logs the target identity before changing any game files. It copies and SHA-256 verifies only the managed addon payload into that same server's /home/container/game/csgo/ tree. If the UUID is missing or malformed, synchronization fails closed before creating or updating managed game paths.

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

Keep the Mount eligible for exactly one Egg and one Node. The provisioner deliberately fails closed if the definition is absent, not read-only, user-mountable, or assigned to multiple Eggs/Nodes.

## Payload files and exclusions

The immutable snapshot includes only these allowlisted paths:

- game/csgo/addons/counterstrikesharp/source/
- game/csgo/addons/counterstrikesharp/plugins/, excluding top-level BotAI/ and disabled/
- game/csgo/addons/counterstrikesharp/shared/
- game/csgo/addons/counterstrikesharp/gamedata/
- game/csgo/addons/MovementUnlocker/
- game/csgo/addons/serverlistplayersfix_mm/
- game/csgo/addons/surf/
- game/csgo/addons/scripts/
- game/csgo/addons/multiaddonmanager/
- game/csgo/addons/metamod/serverlistplayersfix_mm.vdf

The repository itself, .git, update scripts, updater credentials, game/csgo/cfg/, CounterStrikeSharp configs/, BotAI/, disabled/, and Egg-managed Metamod/CounterStrikeSharp runtime files are not staged or deployed. Managed payload paths must not contain symlinks. The container script copies files into the existing game tree; it never replaces the complete game directory.

## Host repository access

The publisher runs on the host and uses the checkout at /opt/fragcity/cs2-kus-addons. Keep it on a clean integration/kus-monorepo branch. Configure a host-only read-only GitHub deploy key or a Git credential helper that works for the service's root account. Do not put a token in the remote URL, repository, Egg variables, or container environment. The published Mount does not expose the .git directory or Git credentials.

The host publisher uses git fetch plus fast-forward-only updates. If GitHub access fails, the checkout is dirty/diverged, or the payload fails validation, the last published snapshot remains available.

## Install host services safely

After pulling the updated branch, first make sure the payload has already been published successfully and the one-time Mount above exists and is eligible for exactly one Egg and one Node.

Run the installer as root:

~~~bash
cd /opt/fragcity/cs2-kus-addons
bash pterodactyl/install-host-services.sh
~~~

The installer installs these four units and reloads systemd:

- fragcity-addon-payload-sync.service
- fragcity-addon-payload-sync.timer
- fragcity-addon-provision.service
- fragcity-addon-provision.timer

It then creates /var/lib/pterodactyl/fragcity-addon-provisioner/baseline-uuids.txt if one does not already exist. This one-time baseline records the UUIDs of all servers that are already eligible for the Mount. It does not change server files, Mount assignments, startup values, Docker containers, or volumes. An existing baseline is never overwritten automatically.

**The installer does not enable either timer.** Test one new server explicitly first.

### Explicitly provision a test server

Use the UUID of a newly created test server, not an existing production server. Do not put a UUID in the script or unit files; supply the test server's UUID only for this explicit one-shot test command.

~~~bash
cd /opt/fragcity/cs2-kus-addons
TEST_UUID="replace-with-the-new-test-server-uuid"
php pterodactyl/provision-addon-servers.php --server "$TEST_UUID"
~~~

This explicit mode may process a server that is in the baseline because it is intended only for the controlled first test. To reduce the chance of an accidental production UUID being supplied, the Panel server name must begin with `FragCity Payload Test`; it still enforces the configured Egg/Node, exact UUID volume, mount definition, startup command, and Docker safety checks. Normal newly-created servers are processed by `--watch` only if their UUID was not recorded in the one-time baseline. A per-server processed marker makes repeated invocation a no-op.

Expected behavior:

- Validates that the target is the Panel server with that UUID and that its volume is exactly /var/lib/pterodactyl/volumes/<UUID>.
- Creates the empty <volume>/egg/fragcity-payload target if absent. A symlink or non-empty target causes a hard stop instead of hiding existing files.
- Attaches the existing read-only Mount if not already attached.
- Prefixes only the server's stored startup command with bash /home/container/egg/fragcity-payload/sync-addon-payload-container.sh &&; the global Egg startup and other servers are not changed.
- If an exact server container exists in exited state, verifies that /home/container maps to this UUID's volume and removes only that Docker container without -v. If no container exists, no removal is needed. If it is running or in an unexpected state, the provisioner skips/refuses rather than interrupting it.
- Records completion under /var/lib/pterodactyl/fragcity-addon-provisioner/processed/<UUID>.json.

After the command reports success, inspect the Mount entry for this single test server in the Panel and then start it normally. The provisioner prepares the empty host-side mount target under that server's validated UUID volume. If an older stopped Docker container exists, it confirms that the container name and /home/container source match this UUID, then removes only that container without -v so Wings recreates it with the Mount; it does not remove or alter the volume. A running container is never removed or modified by the provisioner.

The new container should expose the Mount at /home/container/egg/fragcity-payload with ReadOnly=true and should have P_SERVER_UUID equal to the Panel server UUID. The console should report the target server UUID, Sync completed successfully and SHA-256 verification counts before the CS2 launch proceeds. If the UUID is missing/malformed, the sync script fails before touching managed paths; if the sync script or Mount fails, the && prefix prevents CS2 from launching with an incomplete payload.

After starting the test server, run the read-only verification mode on the host:

~~~bash
php pterodactyl/provision-addon-servers.php --verify-server "$TEST_UUID"
~~~

This verifies the Panel Mount relation, exact UUID-to-volume mapping, running Docker container identity, payload source and destination, read-only mount flag, P_SERVER_UUID, server-specific startup prefix, required runtime commands, and published snapshot metadata. It makes no changes. Do not enable the provisioning timer until this verification passes.

Do not manually copy the 243 MB snapshot into the server volume: the Mount exposes the payload read-only, and the container script deploys the managed files at startup.

## Enable automation only after the test passes

Once the test server has started successfully with a valid sync:

~~~bash
sudo systemctl enable --now fragcity-addon-payload-sync.timer
sudo systemctl start fragcity-addon-payload-sync.service
sudo systemctl status fragcity-addon-payload-sync.service --no-pager

sudo systemctl enable --now fragcity-addon-provision.timer
sudo systemctl start fragcity-addon-provision.service
sudo systemctl status fragcity-addon-provision.service --no-pager
~~~

Inspect service logs with:

~~~bash
sudo journalctl -u fragcity-addon-payload-sync.service -n 100 --no-pager
sudo journalctl -u fragcity-addon-provision.service -n 100 --no-pager
~~~

The publisher timer refreshes the payload about every five minutes. The provisioner timer scans about every minute. For each watch pass, the provisioner ignores UUIDs in the original baseline and UUIDs already marked processed. A new server is eligible only if its Egg and Node match the Mount; it is left alone while installation is incomplete. If its container is running, no changes are made and the watcher retries a later pass after it stops. The provisioner does not automatically start or restart servers.

This baseline is a critical safety barrier: **do not delete or regenerate it casually.** If you need to reset the provisioning state, first back up the state directory and explicitly review the impact on existing servers.

## Useful commands

~~~bash
# One-shot provisioning for a particular newly-created test server:
read -r -p "New test server UUID: " TEST_UUID
sudo php /opt/fragcity/cs2-kus-addons/pterodactyl/provision-addon-servers.php --server "$TEST_UUID"

# Verify that one running test server received the correct read-only Mount:
sudo php /opt/fragcity/cs2-kus-addons/pterodactyl/provision-addon-servers.php --verify-server "$TEST_UUID"

# Scan once for new eligible servers, without waiting for the timer:
sudo php /opt/fragcity/cs2-kus-addons/pterodactyl/provision-addon-servers.php --watch

# Publisher status:
sudo systemctl status fragcity-addon-payload-sync.timer --no-pager

# Provisioner status:
sudo systemctl status fragcity-addon-provision.timer --no-pager
~~~

## Validation

The .github/workflows/pterodactyl-sync-validation.yml workflow validates Bash syntax, PHP syntax, CLI argument safety, stages a real immutable payload snapshot in a temporary runner directory, and verifies container synchronization, SHA-256 checks, idempotency, stale-file cleanup, and preservation of the guarded user-owned configuration paths. CI does not connect to the production Panel or modify any real server volume.
