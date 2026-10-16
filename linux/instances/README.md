# Linux CS2 instances

This directory tracks the reusable `instance-template/` only. Real instance folders are intentionally ignored by Git so private server credentials, logs, PID files, and custom files do not get committed.

## Create an instance

From the repository root:

```bash
cp -a linux/instances/instance-template linux/instances/aim
cp linux/instances/aim/instance.example.env linux/instances/aim/instance.env
sudo chown -R steam:steam linux/instances/aim
sudo chmod 600 linux/instances/aim/instance.env
```

Edit `linux/instances/aim/instance.env`. The default runtime paths match this repository's Linux installer (`/home/steam/cs2`, `/home/steam/steamrt`, and `/steamcmd/steamcmd.sh`). Leave `REPO_ROOT=""` when the instance remains under this checkout; set an absolute path if it is moved outside the repository.

Start the watchdog as the CS2 service user:

```bash
sudo -u steam bash linux/instances/aim/watchdog.sh
```

The watchdog keeps restarting CS2 after a crash. Server output goes to `linux/instances/aim/logs/server.log`; follow it in another terminal with:

```bash
tail -F linux/instances/aim/logs/server.log
```

Stop only that instance:

```bash
sudo -u steam bash linux/instances/aim/stop.sh
```

Run shared maintenance separately, with all CS2 servers stopped:

```bash
sudo -E bash linux/instances/aim/update.sh
```

If any CS2 process is active, the instance updater safely skips shared maintenance instead of updating game/plugin files underneath a running server. For a real update, stop all instances and rerun the command.

## Shared runtime and custom files

Instances default to the shared runtime at `/home/steam/cs2`, matching the Linux installer. `CUSTOM_FOLDER` may point to a folder relative to the instance directory or to an absolute path. Before each launch, existing `CUSTOM_FOLDER/cfg/` and `CUSTOM_FOLDER/addons/` trees are copied additively into the shared runtime: matching files are overwritten, new files are added, and unrelated files are not deleted.

This is an overwrite-only file overlay, not isolated per-instance storage. If two instances use different custom files for the same runtime path, the last copy wins, and concurrently running servers may read the same shared file paths. Avoid conflicting overrides between active instances.

The shared maintenance lock coordinates this template with `linux/install.sh`. Keep instance folders and secret `instance.env` files out of commits; this directory's `.gitignore` does that automatically.
