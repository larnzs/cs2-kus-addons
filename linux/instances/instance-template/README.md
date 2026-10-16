# Linux instance template

**CS2 execution is Instance-only.** The repository's install/update scripts prepare the shared runtime but never launch a server. Use this template's `watchdog.sh` to start and supervise an instance.

Copy this directory to a unique name under `linux/instances/` and copy `instance.example.env` to `instance.env`.

- `run.sh` launches one CS2 process and returns status `100` when that process exits, allowing the supervisor to distinguish a crash/restart from a configuration error.
- `watchdog.sh` is the guardian/supervisor. Start this file, not `run.sh` directly, for automatic restart after a crash.
- `stop.sh` gracefully stops only this instance.
- `update.sh` is a separate, no-launch shared maintenance entrypoint. It skips maintenance when any CS2 process is active.

The scripts are intended to run as `CS2_USER` (default `steam`). Set ownership and secret permissions after copying:

```bash
sudo chown -R steam:steam /path/to/instance
sudo chmod 600 /path/to/instance/instance.env
```

`instance.env` is Bash assignment syntax and is sourced by the scripts, so quote values containing spaces or shell metacharacters. Never commit real Steam tokens, API keys, server passwords, or RCON passwords.

The default paths match the install flow in `linux/install.sh`: `SERVER_DIR=/home/steam/cs2`, `STEAMRT_DIR=/home/steam/steamrt`. That Linux installer/updater maintains this shared runtime. If you use a separate game installation, provision/update it separately rather than assuming `linux/install.sh` updates arbitrary custom directories.
