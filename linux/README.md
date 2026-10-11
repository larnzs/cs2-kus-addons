# Linux entrypoints

These scripts target a Linux VM/server. Google Cloud Compute Engine is a cloud hosting platform, not a separate operating system; `gcp.sh` belongs here because it bootstraps the repository on a Linux VM using the Google metadata service.

| File | Purpose |
| --- | --- |
| `install.sh` | Install/provision the Linux CS2 runtime, apply a non-destructive overlay of the tracked `game/csgo/` payload, then start CS2. Requires a strong `RCON_PASSWORD`; public hosting also needs a valid GSLT in `STEAM_ACCOUNT`. |
| `start.sh` | KUS-compatible existing-runtime startup path; updates the game and starts it **without redeploying add-ons**. Requires `RCON_PASSWORD` from environment or Google Cloud metadata. |
| `run.sh` | Update/start helper for an existing Linux runtime; does not deploy the tracked add-on payload. Set `RCON_PASSWORD` before use. |
| `stop.sh` | Gracefully stops CS2 processes only, then force-stops them if needed; it no longer kills unrelated installer, HTTP, or SCREEN processes. |
| `gcp.sh` | Read Google Cloud instance metadata and invoke this checkout's `linux/install.sh`. |

Run from a clone of this repository. For a direct install, configure a strong `RCON_PASSWORD` in the environment first; use `sudo -E` so it is preserved. Set `STEAM_ACCOUNT` (GSLT) for public hosting. On Google Cloud, put the RCON password in instance metadata and use `gcp.sh`.

```bash
sudo -E bash ./linux/install.sh
# Or on a Google Cloud VM:
sudo bash ./linux/gcp.sh
```

The Linux/GCP path is organized, but remains unvalidated on a live VM. Do not treat the folder move as evidence of a successful production deployment.
