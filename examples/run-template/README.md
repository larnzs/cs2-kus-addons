# CS2 Windows instance runner

Keep these three files together in each external Instance folder:

- `run.bat` — owns the normal maintenance and CS2 lifecycle loop.
- `run.vbs` — the minimal outer watchdog, matching the known-good WSH pattern: run the sibling `run.bat` hidden, wait for it to return, then try again after 100 ms.
- `instance.ini` — private per-instance settings. Create it from `instance.example.ini`; do not commit credentials.

The VBS resolves `run.bat` beside itself, so the active runner can live outside `W:\\cs2-kus-addons`. There is no `run-fast.bat`.

## Setup

1. Run `install.bat` from the repository root once.
2. Copy `instance.example.ini` to `instance.ini` in the external Instance folder and configure it.
3. Set `SERVER_DIR` to the repository's shared `server` directory. Choose a unique port, map/map group, and valid credentials.
4. Keep `instance.ini` private. It is excluded from Git.
5. Copy `run.bat`, `run.vbs`, and `instance.ini` side-by-side into each external Instance folder.
6. Start `run.vbs` for hidden supervision. You can also run `run.bat` directly to see its console, but the batch owns the loop and will restart CS2 after an exit.

## Update and anti-crash behavior

- On ordinary startup, `run.bat` uses the shared maintenance lock and five-minute successful-maintenance cooldown. If another `cs2.exe` is already running, it skips maintenance and attempts to launch this Instance without changing shared runtime files.
- After this Instance's CS2 process exits or crashes, `run.bat` enters post-exit maintenance mode. It waits until **all** `cs2.exe` processes have exited, then checks/pulls the private repository, checks upstream add-on releases, pulls newly published changes, updates CS2 through SteamCMD, patches `gameinfo.gi`, and applies the overwrite-only payload overlay before restarting.
- A machine-wide lock serializes update attempts. If another `cs2.exe` becomes active between update stages, the remaining update/deployment stages are cancelled; the runner does not patch or overlay the live runtime under that process.
- If a maintenance step fails, `run.bat` waits 60 seconds and retries the maintenance loop. A normal CS2 crash does not end the batch process: it is handled internally by the maintenance/restart loop.
- `run.vbs` is deliberately only the small outer watchdog. Normally it remains waiting inside `shell.Run(..., 0, True)` while `run.bat` handles CS2 exits. It retries the batch after 100 ms only if the batch process itself returns or terminates.
- The runtime overlay overwrites matching paths only. It does not mirror, purge, move, or delete installed add-on files. The full `addons/counterstrikesharp/configs/` and `cfg/settings/` trees are protected.
- Per-instance `cfg/` and `addons/` overrides are synced only when no CS2 process is active, because every Instance shares one runtime tree.
- The updater does not call `win.bat`, `update.bat`, `game-update.bat`, or `install.bat`. Those have separate responsibilities; `win.bat` is a clean replacement/reset operation.

## Test

Start `run.vbs`, then use `quit` in the CS2 server console. The expected path is: the batch sees CS2 exit, waits for every other CS2 process to stop, runs the guarded maintenance cycle, and starts CS2 again. If the batch process itself exits unexpectedly, the VBS relaunches the sibling `run.bat` after 100 ms.
