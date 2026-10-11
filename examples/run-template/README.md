# CS2 Windows instance runner

Keep these five files together in each external Instance folder:

- `run.bat` — normal runner. It validates `instance.ini`, performs shared maintenance only when no other `cs2.exe` is active, launches CS2 once, and returns when that process exits.
- `run_fast.bat` — wrapper around `run.bat --fast`; it reuses the same private settings and launch arguments but skips Git, release checks, SteamCMD, patching, and payload overlays.
- `run.vbs` — a lightweight watchdog. It **never waits for a batch or for CS2**; it polls WMI once per second and launches the PowerShell supervisor in a detached hidden process if that supervisor is missing.
- `supervisor.ps1` — the actual restart loop. It picks `run.bat` or `run_fast.bat` from the shared success marker, waits on a separate `cmd.exe` host, and retries after 100 ms. A named mutex prevents duplicate supervisors for the same Instance.
- `instance.ini` — private per-instance settings. Create it from `instance.example.ini`; never commit credentials.

The VBS watchdog is no longer connected to the lifetime of a batch or game process. If the PowerShell supervisor disappears when CS2 exits/crashes, VBS notices and starts it again. The supervisor writes a per-Instance diagnostic log named `CS2-KUS-Supervisor-<id>.log` in `%TEMP%`; the previous log is retained as `.previous` after rotation.

Both scripts resolve their paths beside themselves, so the Instance folder can stay outside `W:\\cs2-kus-addons`. Run all Instances under the same Windows account so they share `%TEMP%` and the maintenance marker.

## Setup

1. Run `install.bat` from the repository root once.
2. Copy `instance.example.ini` to `instance.ini` in each external Instance folder and configure it.
3. Set `SERVER_DIR` to the repository's shared `server` directory. Give each Instance a unique port, map/map group, and intended credentials.
4. Keep `instance.ini` private. It is excluded from Git.
5. Copy `run.bat`, `run_fast.bat`, `run.vbs`, `supervisor.ps1`, and your private `instance.ini` into each external Instance folder.
6. Launch `run.vbs`. The VBS process is only the watchdog; `supervisor.ps1` owns the restart loop.

## Update and anti-crash behavior

- When `%TEMP%\\CS2-KUS-Maintenance-success.marker` is absent, the supervisor starts `run.bat`. If no other CS2 process is using the shared install, the batch runs the full pipeline: pull the private repository, check upstream releases, update CS2 with SteamCMD, patch `gameinfo.gi`, and apply the overwrite-only runtime overlay.
- Only after all maintenance stages succeed does `run.bat` write the shared success marker. From then on, all Instance supervisors select `run_fast.bat` on every restart.
- If another `cs2.exe` is already active, `run.bat` skips shared maintenance but still launches this Instance. If another process starts mid-maintenance, remaining update/deployment stages are cancelled instead of touching shared runtime files.
- When CS2 or the runner exits/crashes, PowerShell starts the selected runner again after 100 ms. If PowerShell itself exits or crashes, the separate VBS watchdog notices the missing supervisor and relaunches it (typically within one second).
- `run_fast.bat` does not update or deploy shared files. Per-instance override sync is skipped if any CS2 process is active, so it does not change shared files underneath a running server.
- The success marker is intentionally persistent to prevent full update checks after routine crashes. To force one new full update cycle, stop all CS2 servers and both layers of supervisors, delete `%TEMP%\\CS2-KUS-Maintenance-success.marker`, then start one `run.vbs` while the shared install is idle.
- Runtime payload overlay is overwrite-only. It does not mirror, purge, move, or delete installed add-on files, and the full `addons/counterstrikesharp/configs/` and `cfg/settings/` trees remain protected.
- The runner does not call `win.bat`, `update.bat`, `game-update.bat`, or `install.bat`. Those have separate responsibilities; `win.bat` is a clean replacement/reset operation.

## Test

1. Ensure no old `run.vbs` / `supervisor.ps1` loops are still active.
2. To force a full update, delete `%TEMP%\\CS2-KUS-Maintenance-success.marker` before starting the watchdog.
3. Start `run.vbs`; confirm the hidden PowerShell process appears and the normal maintenance path completes.
4. Start another Instance. It should share the success marker and select `run_fast.bat`.
5. Use `quit` or terminate one CS2 process. The same Instance should return without repeating full update maintenance. If the PowerShell process is deliberately terminated, its VBS watchdog should relaunch it.
