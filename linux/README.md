# Linux entrypoints

These scripts include the Linux VM/GCP provisioning path and a reusable per-instance runner. Google Cloud Compute Engine remains a hosting platform; its no-launch maintenance entrypoint is `google/update.sh`.

| File | Purpose |
| --- | --- |
| `update.sh` | Unified maintenance entrypoint: fast-forward the repository, update managed plugins, update Steam Linux Runtime and CS2 through SteamCMD, safely overlay the tracked payload, and patch `gameinfo.gi`. Requires root and a stopped CS2 server; does not launch the server. |
| `install.sh` | Provisioning worker used by `update.sh`; it can also be run directly for initial setup. Set `UPDATE_ONLY=1` to stop after installation/update and payload verification. |
| `start.sh` | Existing-runtime startup path; updates the game and launches it without redeploying add-ons. |
| `run.sh` | Update/start helper for an existing Linux runtime; does not deploy the tracked add-on payload. |
| `stop.sh` | Gracefully stops CS2 processes only. |
| `gcp.sh` | Reads Google Cloud instance metadata and invokes this checkout's Linux installer. |
| `instances/instance-template/` | Per-instance runner with private config, custom-folder overlay, automatic crash restart, per-instance stop, and separate no-launch maintenance. |

Run the unified maintenance script from a clone of this repository:

```bash
sudo -E bash ./linux/update.sh
```

On Google Cloud Compute Engine, run:

```bash
sudo -E bash ./google/update.sh
```

The update entrypoints refuse to run while CS2 is active. They overlay updated paths only: files not present in the repository payload are left in place, and existing CounterStrikeSharp configs are preserved. No update entrypoint launches CS2. Runtime start scripts remain separate.


## Multiple instances

See [`instances/README.md`](instances/README.md). Create each instance by copying `instances/instance-template/` and editing its private `instance.env`. Instances use the Linux installer's default shared runtime (`/home/steam/cs2`) unless deliberately configured otherwise. The runner must run as `CS2_USER` (default `steam`), and server output is isolated per instance in `logs/server.log`.

The GCP launcher now respects caller-provided `PORT`, `TICKRATE`, `MAXPLAYERS`, `LAN`, and `EXEC` values before falling back to metadata/defaults.
