# CS2 Windows instance runner

Keep these four files together in each external Instance folder:

- `run.bat` — the normal runner. It validates `instance.ini`, performs shared maintenance only when no other `cs2.exe` is active, launches CS2 once, and returns to the supervisor when that process exits.
- `run_fast.bat` — a small wrapper around `run.bat --fast`. It uses the same per-instance settings and CS2 launch arguments but skips Git, upstream release checks, SteamCMD, gameinfo patching, and payload overlays.
- `run.vbs` — the simple WSH supervisor. It launches `run.bat` until the shared success marker exists; afterwards it launches `run_fast.bat`. It waits for each batch to return and then repeats after **100 milliseconds**.
- `instance.ini` — private per-instance settings. Create it from `instance.example.ini`; do not commit credentials.

The VBS resolves both batch paths beside itself, so these four active files can live outside `W:\\cs2-kus-addons`. All Instance supervisors must run under the same Windows account so they share the same `%TEMP%` marker.

## Setup

1. Run `install.bat` from the repository root once.
2. Copy `instance.example.ini` to `instance.ini` in each external Instance folder and configure it.
3. Set `SERVER_DIR` to the repository's shared `server` directory. Give each Instance a unique port, map/map group and its intended credentials.
4. Keep `instance.ini` private. It is excluded from Git.
5. Copy `run.bat`, `run_fast.bat`, `run.vbs`, and the private `instance.ini` side-by-side into each external Instance folder.
6. Launch `run.vbs` for hidden anti-crash supervision. Running `run.bat` directly opens the normal maintenance-and-launch path visibly.

## Update and anti-crash behavior

- On a cold start with no fast marker, `run.vbs` launches `run.bat`. If no other CS2 process is using the shared install, the batch runs the normal pipeline: pull the private repository, check upstream add-on releases, pull any newly published updater results, update CS2 with SteamCMD, patch `gameinfo.gi`, and apply the overwrite-only runtime overlay.
- Only after every maintenance stage succeeds, `run.bat` writes `%TEMP%\\CS2-KUS-FastLaunch.enabled`. This shared marker causes all Instance VBS supervisors to use `run_fast.bat` for future launches and crash recovery.
- If another `cs2.exe` is already active, `run.bat` skips shared maintenance but still launches this Instance. If another process starts between maintenance stages, it cancels the remaining update/deployment stages and releases the maintenance lock; it does not wait indefinitely while holding the lock.
- After the CS2 process exits or crashes, `run.bat` returns to VBS instead of starting another internal update loop. VBS checks the shared marker again: with the marker it runs `run_fast.bat`; without it, it retries `run.bat`. The delay between attempts is 100 ms.
- `run_fast.bat` does not update or deploy shared files and does not wait for other CS2 instances. Its per-Instance override sync is skipped if any CS2 process is active, to avoid changing shared files underneath a running server.
- The marker is intentionally persistent so long-running servers do not repeat the full update pipeline every time they crash. To deliberately perform a new full update cycle, stop the Instance supervisors and CS2 servers, delete `%TEMP%\\CS2-KUS-FastLaunch.enabled` and `%TEMP%\\CS2-KUS-Maintenance-success.marker`, then start one `run.vbs` while the shared install is idle. A successful maintenance pass recreates both markers.
- Runtime payload overlay is overwrite-only. It does not mirror, purge, move, or delete installed add-on files, and the full `addons/counterstrikesharp/configs/` and `cfg/settings/` trees remain protected.
- The updater does not call `win.bat`, `update.bat`, `game-update.bat`, or `install.bat`. Those have separate responsibilities; `win.bat` is a clean replacement/reset operation.

## Test

1. Ensure no Instance supervisor is already running.
2. Delete the two marker files from `%TEMP%` to test the full maintenance path.
3. Start `run.vbs`; verify the full update path completes and writes `CS2-KUS-FastLaunch.enabled`.
4. Start another Instance; its VBS should immediately select `run_fast.bat`.
5. Use `quit` in either server console. The same server should be launched again after about 100 milliseconds without rerunning the full update pipeline.
