# Pterodactyl payload sync (FragCity)

This flow connects the existing scheduled `Update CS2 Addons` workflow to new and existing Pterodactyl servers without cloning the private repository into customer containers.

## Flow

1. The existing GitHub Actions workflow checks and updates plugin sources/manifest in `integration/kus-monorepo`. It remains the single source of truth for plugin updates.
2. A host-side systemd timer fetches the newest commit from that branch every five minutes and publishes an immutable, allowlisted payload snapshot to `/var/lib/pterodactyl/mounts/fragcity-addon-payload`.
3. A **read-only Pterodactyl mount** exposes that host directory inside a game container at `/home/container/egg/fragcity-payload`.
4. K4ryuu's normal startup/update work runs first. The custom Egg startup string then runs `sync-addon-payload-container.sh`; it reads the published snapshot, hashes files, copies only changed files, verifies each copy, and removes stale files only from the managed roots.

The container never clones/pulls the private Git repository and receives no GitHub token. The host checkout contains the repo and credentials; the mount exposes only allowlisted game payload files plus the small sync script. New snapshots are staged fully before `CURRENT_COMMIT` changes, so containers do not read half-written payloads.

## Payload scope

Copied from the repo into each published snapshot:

- `game/csgo/addons/counterstrikesharp/source/`
- `game/csgo/addons/counterstrikesharp/plugins/` except its top-level `BotAI/` and `disabled/` directories
- `game/csgo/addons/counterstrikesharp/shared/`
- `game/csgo/addons/counterstrikesharp/gamedata/`
- `game/csgo/addons/MovementUnlocker/`
- `game/csgo/addons/serverlistplayersfix_mm/`
- `game/csgo/addons/surf/`
- `game/csgo/addons/scripts/`
- `game/csgo/addons/multiaddonmanager/`
- `game/csgo/addons/metamod/serverlistplayersfix_mm.vdf`

The flow never deploys the whole repo. It does not copy or prune `BotAI/`, `disabled/`, game `cfg/`, CounterStrikeSharp `configs/`, or Egg-managed Metamod/CounterStrikeSharp runtime directories. The payload source must not contain symlinks inside managed paths.

## Host setup

### 1. Give the host read-only access to the private repository

Use a **read-only deploy key for this repository**, stored on the host, or an already-configured host-level Git credential helper. Do not put a PAT in a URL, this repo, Egg variables, or a container environment.

The systemd service runs as root, so configure the deploy key/SSH host alias for root (or change the service user and directory ownership consistently). Clone a normal checkout—not a worktree—of the integration branch at:

```bash
sudo install -d -m 0750 /opt/fragcity
sudo git clone --single-branch --branch integration/kus-monorepo \\
  git@github-fragcity-kus:larnzs/cs2-kus-addons.git \\
  /opt/fragcity/cs2-kus-addons
```

The SSH alias `github-fragcity-kus` must be configured in the host's SSH config to use the read-only deploy key for GitHub. Add GitHub's host key to `known_hosts` using a trusted verification process; do not disable host-key checking. The checkout must be clean and remain on `integration/kus-monorepo`. The host publisher refuses dirty, detached, or different-branch checkouts.

### 2. Install the systemd units from this repository

```bash
sudo install -m 0644 \\
  /opt/fragcity/cs2-kus-addons/pterodactyl/systemd/fragcity-addon-payload-sync.service \\
  /etc/systemd/system/fragcity-addon-payload-sync.service
sudo install -m 0644 \\
  /opt/fragcity/cs2-kus-addons/pterodactyl/systemd/fragcity-addon-payload-sync.timer \\
  /etc/systemd/system/fragcity-addon-payload-sync.timer
sudo systemctl daemon-reload
sudo systemctl enable --now fragcity-addon-payload-sync.timer
sudo systemctl start fragcity-addon-payload-sync.service
sudo systemctl status fragcity-addon-payload-sync.service --no-pager
sudo cat /var/lib/pterodactyl/mounts/fragcity-addon-payload/CURRENT_COMMIT
```

The timer runs once shortly after boot and approximately every five minutes after that. If the central GitHub updater has just published a new commit, the next successful host sync stages it. Check the service journal on failure:

```bash
sudo journalctl -u fragcity-addon-payload-sync.service -n 100 --no-pager
```

The staging script uses `git fetch` and fast-forward-only updates. If GitHub is unreachable, authentication fails, or the checkout is dirty/diverged, it leaves the last published snapshot in place. It never passes credentials to the container.

## Pterodactyl mount requirement

Register a mount for the target node/Egg/server as appropriate in the existing FragCity mount mechanism:

| Setting | Value |
| --- | --- |
| Host source | `/var/lib/pterodactyl/mounts/fragcity-addon-payload` |
| Container destination | `/home/container/egg/fragcity-payload` |
| Access | **Read-only** |
| Applies to | The custom K4ryuu/FragCity CS2 Egg |

This is a new, dedicated mount source so it does not overwrite existing FragCity payload/config mounts. The host folder must exist before the mount is applied. After changing mount definitions, use the normal Pterodactyl/Wings procedure to apply them to each target server.

## Custom Egg startup command

Prefix the existing K4ryuu startup command with this exact check:

```bash
bash /home/container/egg/fragcity-payload/sync-addon-payload-container.sh &&
```

For the current custom Egg command, the complete resulting command is:

```text
bash /home/container/egg/fragcity-payload/sync-addon-payload-container.sh && ./game/cs2.sh {{CUSTOM_PARAMS}} -tickrate {{TICKRATE}} -dedicated +ip 0.0.0.0 -port {{SERVER_PORT}} +map {{SRCDS_MAP}} +mapgroup {{MAPGROUP}} -maxplayers {{SRCDS_MAXPLAYERS}} +sv_setsteamaccount {{STEAM_ACC}} +game_type {{GAME_TYPE}} +game_mode {{GAME_MODE}} -authkey {{AUTHKEY}} +sv_password {{PASSWORD}} +host_workshop_collection {{WORKSHOP}}
```

The sync script is deliberately first in the Egg's shell startup string. K4ryuu's `cs2egg` performs its own framework update work before it executes the provided `STARTUP` command; this means the FragCity payload is applied after that work and before CS2 launches. Confirm this ordering on the installed image before enabling it for production servers.

If the payload mount or `CURRENT_COMMIT` is missing, the custom sync script exits non-zero and CS2 will not start. This is a fail-closed behavior: it is safer than starting with a half-updated addon set. Fix the mount/staging service, then start the server again.

## Validation

The workflow `.github/workflows/pterodactyl-sync-validation.yml` runs when files under `pterodactyl/` change. It validates Bash syntax, runs the real host staging script against a temporary mount on the runner, then tests container syncing for:

- First-time file install and SHA-256 verification
- Idempotent second run (no file copies when payload is unchanged)
- Removal of stale files only inside managed roots
- Preservation of `BotAI/`, `disabled/`, and manually managed configuration files

The CI mount is temporary; it does not change a production node or server.
