# Linux entrypoints

The Linux entrypoints now follow the same naming contract as `windows/` wherever the roles match. Linux-only bootstrap and legacy runtime paths use descriptive names to distinguish them from repository maintenance and per-instance scripts.

| File | Purpose |
| --- | --- |
| `install.sh` | Unified no-launch install/update entrypoint, matching `windows/install.bat`. Requires root, a clean checkout, and stopped CS2 processes. Updates the branch, managed plugin payloads, Steam Linux Runtime and CS2, overlays tracked files without deleting unrelated runtime files, and patches `gameinfo.gi`. |
| `update.sh` | Repository-only update, matching `windows/update.bat`: switches to `integration/kus-monorepo` and pulls with `--ff-only`. It does not update plugins, CS2, or runtime files. |
| `setup-and-start.sh` | Linux-specific system/runtime setup worker. Installs required packages, SteamCMD, Steam Linux Runtime and CS2, overlays the tracked payload, and patches `gameinfo.gi`. When run directly it starts CS2; `install.sh` invokes it with `UPDATE_ONLY=1` so maintenance never launches the server. |
| `update-game-and-start.sh` | Existing-runtime helper: updates Steam Linux Runtime and CS2 through SteamCMD, then launches the runtime without deploying the tracked add-on payload. |
| `legacy-gcp-start.sh` | Legacy KUS-compatible startup path that reads Google Cloud metadata, prepares the OS/runtime, and starts CS2. It is separate from the unified managed-plugin update path. |
| `setup-and-start-from-gcp.sh` | Google Cloud metadata wrapper that loads instance attributes and invokes `setup-and-start.sh`. |
| `stop-all.sh` | Stops all matching CS2 processes for the configured service user; use the instance template's `stop.sh` when only one instance should be stopped. |
| `instances/instance-template/` | Reusable per-instance runner with `run.sh`, `watchdog.sh`, `stop.sh`, and instance-local `update.sh`. |

## Commands

Full install/update and safe payload deployment, without launching the server:

```bash
sudo -E bash ./linux/install.sh
```

Repository-only update (does not touch plugins or game files):

```bash
bash ./linux/update.sh
```

On Google Cloud Compute Engine, run the full no-launch maintenance path:

```bash
sudo -E bash ./google/update.sh
```

The full update entrypoints refuse to run while CS2 is active. Runtime overlays are overwrite-only: files absent from the repository payload are left in place, and existing CounterStrikeSharp configs are preserved.

## Multiple instances

See [`instances/README.md`](instances/README.md). Create each instance by copying `instances/instance-template/` and editing its private `instance.env`. The instance runner uses the Linux installer's default shared runtime (`/home/steam/cs2`) unless deliberately configured otherwise. Run it as `CS2_USER` (default `steam`); server output is isolated per instance in `logs/server.log`.

The GCP bootstrap wrapper respects caller-provided `PORT`, `TICKRATE`, `MAXPLAYERS`, `LAN`, and `EXEC` values before falling back to metadata/defaults.
