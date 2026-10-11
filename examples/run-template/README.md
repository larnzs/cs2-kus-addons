# CS2 Windows instance runner

Keep these five files together in each external Instance folder:

- `update.bat` — performs shared maintenance: checks/pulls the private repository, updates upstream add-ons, updates CS2 with SteamCMD, patches `gameinfo.gi`, applies the overwrite-only runtime overlay, and syncs optional overrides. It does not launch the server.
- `run.bat` — reads the private `instance.ini` and contains the CS2 launch arguments/command only. It waits for an active shared-maintenance lock, starts CS2, and returns when the process exits.
- `run.vbs` — the inner restart loop. It starts the runner batch through `cmd.exe`, waits for it to return, and retries after 100 ms when the runner reports a CS2 exit.
- `watchdog.bat` — the outer guardian. Launch this file instead of double-clicking `run.vbs`; it runs the VBS through `cscript.exe` and automatically relaunches the VBS host if that process exits or encounters an unhandled error.
- `instance.ini` — private per-instance settings. Create it from `instance.example.ini`; never commit credentials.

## Startup and update procedure

1. After install or when you deliberately need a shared update, stop **all** CS2 processes and all Instance watchdogs.
2. Run the Instance-local `update.bat` once and make sure it ends successfully. It skips shared maintenance if a CS2 process is already active. This template copy is distinct from the repository-root `update.bat`.
3. Start `watchdog.bat`. Keep its CMD window open; it is the independent guardian for the VBS host.
4. Do not start `run.vbs` directly for normal operation. The VBS loop never executes `update.bat`; it only invokes the launch batch and handles retries.
5. Keep the runner files and private `instance.ini` together. Give each Instance a unique port and point `SERVER_DIR` to the shared server runtime.

## Anti-crash behavior

The design intentionally has two layers:

- `watchdog.bat` stays in a visible CMD session and supervises the VBS host using `cscript.exe`. If the VBScript host terminates, the batch guardian waits one second and launches it again.
- `run.vbs` invokes `run.bat` via an explicit `cmd.exe /d /s /c` command, waits for completion, then retries after 100 ms when the batch returns exit code 100 (the launch runner's CS2-exited result). Launch errors and unexpected exit codes are written to `%TEMP%\\CS2-KUS-Watchdog.log`; repeat failures are rate-limited in the log.
- The VBS can use either the standard `run.bat` filename or, when there is no `run.bat`, a single unambiguous `*_run.bat` file such as `27085_run.bat`.
- Neither watchdog invokes `update.bat`, Git, release checks, SteamCMD, gameinfo patching, or payload deployment during crash recovery.
- `run.bat` waits while the shared maintenance lock exists so a server cannot start midway through runtime deployment. If an updater fails, fix the displayed error and run the instance-local `update.bat` again with all CS2 processes stopped.
- The updater is still overwrite-only; it does not delete runtime-only add-ons. The `addons/counterstrikesharp/configs/` and `cfg/settings/` trees remain protected from the runtime payload overlay.
- Since all Instances share one runtime, optional `CUSTOM_FOLDER` overrides are applied only while the shared runtime is idle. Different override files cannot be isolated across simultaneously running servers.

## Test

1. Stop all servers and all old VBS/CMD/PowerShell loops.
2. Copy the current `run.bat`, `run.vbs`, `watchdog.bat`, and instance-local `update.bat` beside your existing `instance.ini`. Do not replace private `instance.ini` or plugin configuration files.
3. Run the instance-local `update.bat` once while no CS2 process is active.
4. Double-click `watchdog.bat`; confirm the server launches and the guardian CMD remains open.
5. Use `quit` or terminate only CS2. The VBS should start the runner again after approximately 100 ms. If the VBS host itself exits, the guardian CMD should relaunch it after one second. The loop must never invoke `update.bat`.

Check `%TEMP%\\CS2-KUS-Watchdog.log` if the runner cannot be launched or repeatedly returns an unexpected exit code.
