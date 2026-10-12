# Linux entrypoints

These scripts target a Linux VM/server. Google Cloud Compute Engine is a hosting platform, so its no-launch maintenance entrypoint is `google/update.sh`.

| File | Purpose |
| --- | --- |
| `update.sh` | Unified maintenance entrypoint: fast-forward the repository, update managed plugins, update Steam Linux Runtime and CS2 through SteamCMD, safely overlay the tracked payload, and patch `gameinfo.gi`. Requires root and a stopped CS2 server; does not launch the server. |
| `install.sh` | Provisioning worker used by `update.sh`; it can also be run directly for initial setup. Set `UPDATE_ONLY=1` to stop after installation/update and payload verification. |
| `start.sh` | Existing-runtime startup path; updates the game and launches it without redeploying add-ons. |
| `run.sh` | Update/start helper for an existing Linux runtime; does not deploy the tracked add-on payload. |
| `stop.sh` | Gracefully stops CS2 processes only. |
| `gcp.sh` | Reads Google Cloud instance metadata and invokes this checkout's Linux installer. |

Run the unified maintenance script from a clone of this repository:

```bash
sudo -E bash ./linux/update.sh
```

On Google Cloud Compute Engine, run:

```bash
sudo -E bash ./google/update.sh
```

The update entrypoints refuse to run while CS2 is active. They overlay updated paths only: files not present in the repository payload are left in place, and existing CounterStrikeSharp configs are preserved. No update entrypoint launches CS2. Runtime start scripts remain separate.
