# Linux entrypoints

**Install and update scripts never launch CS2.** Server processes are launched only by a configured Instance runner under `instances/<name>/run.sh`. For normal operation, start that Instance's `watchdog.sh` so it can restart CS2 after a crash.

| File | Purpose |
| --- | --- |
| `install.sh` | Unified install/update entrypoint, matching `windows/install.bat`. Requires root, a clean checkout owned by the non-root operator, and stopped CS2 processes. Fast-forwards the active branch using that operator's read-only Git credentials, installs/updates Steam Linux Runtime and CS2, overlays the committed plugin payload, and patches `gameinfo.gi`. Never pushes to GitHub or launches CS2. |
| `update.sh` | Repository-only update, matching `windows/update.bat`: fast-forwards the currently checked-out branch from its matching remote branch. It does not update plugins, CS2, or runtime files. |
| `setup.sh` | Root-only provisioning worker invoked by `install.sh`. Installs OS prerequisites, refreshes Steam app metadata before installing/updating Steam Linux Runtime (App ID `1628350`) and CS2 (App ID `730`), retries a stale/missing app-info cache once, deploys the committed payload, and patches `gameinfo.gi`. It logs SteamCMD diagnostics to `/var/log/cs2-kus-steamcmd/` and prepares Steam Runtime host settings; it never starts the server or pushes to GitHub. |
| `install-from-gcp.sh` | Google Cloud convenience wrapper for the same full install/update operation. It does not consume server secrets or launch CS2. |
| `stop-all.sh` | Emergency stop of running CS2 processes for the configured service user. When an Instance watchdog is active, use that Instance's `stop.sh` instead, or the watchdog may start the server again. |
| `instances/instance-template/` | Per-instance settings and lifecycle scripts: `run.sh`, `watchdog.sh`, `stop.sh`, and instance-local `update.sh`. Only `run.sh` launches CS2. |
| `setup-and-start.sh` | **Deprecated migration shim** kept for checkouts whose installer began before the rename. It delegates to `setup.sh` and never starts CS2. Use `install.sh` for normal operations. |

## Commands

Full install/update and safe payload deployment, without launching the server:

```bash
sudo -E bash ./linux/install.sh
```

Repository-only update (does not touch plugins or game files):

```bash
bash ./linux/update.sh
```

On Google Cloud Compute Engine, the same full no-launch maintenance workflow is available through:

```bash
sudo -E bash ./linux/install-from-gcp.sh
```

The full install/update entrypoints refuse to run while CS2 is active. They use the versions already committed to the active repository branch; they do not run the upstream-release updater or need GitHub write access. Keep plugin release discovery/commits in maintainer automation, then let node installs pull those committed updates using read-only Git access. Runtime overlays are overwrite-only: files absent from the repository payload are left in place, and existing CounterStrikeSharp configs are preserved.

## Multiple instances

See [`instances/README.md`](instances/README.md). Create each instance by copying `instances/instance-template/` and editing its private `instance.env`. The default shared runtime is `/home/steam/cs2`, and the Steam Linux Runtime is `/home/steam/steamrt`. Run the instance's `watchdog.sh` as `CS2_USER` (default `steam`); server output is isolated in that instance's `logs/server.log`.

All per-server settings, including port, map, RCON password, GSLT, and custom files, belong in the individual instance configuration. The host install/update workflow does not read them.
