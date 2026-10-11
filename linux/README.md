# Linux entrypoints

These scripts target a Linux VM/server. Google Cloud Compute Engine is a cloud hosting platform, not a separate operating system; `gcp.sh` belongs here because it bootstraps the repository on a Linux VM using the Google metadata service.

| File | Purpose |
| --- | --- |
| `install.sh` | Install/provision the Linux CS2 runtime and deploy the tracked `game/csgo/` payload. |
| `start.sh` | KUS-compatible Linux startup/provisioning path, including game update/start behavior. Review it before use; this path has not been live-tested against this unified private checkout. |
| `run.sh` | Linux server update/start helper based on the KUS runtime flow. |
| `stop.sh` | Process-stop helper. Review its broad process matching before running on a host that runs other workloads. |
| `gcp.sh` | Read Google Cloud instance metadata and invoke this checkout's `linux/install.sh`. |

Run from a clone of this repository, for example:

```bash
sudo bash ./linux/gcp.sh
sudo bash ./linux/install.sh
```

The Linux/GCP path is organized, but remains unvalidated on a live VM. Do not treat the folder move as evidence of a successful production deployment.
