# CS2 Windows instance runner

Each external Instance folder contains exactly these three active files:

- `run.bat` — validates the instance, attempts shared maintenance when safe and not recently completed, launches CS2 once, then returns when that CS2 process exits.
- `run.vbs` — the anti-crash supervisor. It uses the minimal known-good WSH loop: run the sibling batch hidden, wait for it to return, sleep 100 ms, and repeat. It does not inspect exit codes or change environment variables.
- `instance.ini` — private settings for this Instance. Create it from `instance.example.ini`; do not commit credentials.

The VBS resolves `run.bat` and `instance.ini` relative to its own directory, so the runner files may live outside `W:\\cs2-kus-addons`. Keep `run.bat`, `run.vbs`, and `instance.ini` side-by-side in the external Instance folder.

## Setup

1. Run `install.bat` from the repository root once.
2. Copy `instance.example.ini` to `instance.ini` in the external Instance folder and configure it.
3. Set `SERVER_DIR` to the repository's shared `server` directory. Set a unique port, map/map group, reachable public IP if needed, Game Server Login Token, and a strong RCON password.
4. Keep `instance.ini` private. It is excluded from Git in this template.
5. Copy only `run.bat`, `run.vbs`, and your private `instance.ini` into each external Instance folder. No separate fast-runner batch is needed.
6. Start `run.vbs` for hidden operation with anti-crash supervision. Run `run.bat` directly only when you intentionally want a visible maintenance-and-launch pass. Add `--pause` when you want the batch window to wait after exit.

## Anti-crash and maintenance behavior

- The VBS itself is deliberately just the simple loop. Maintenance policy, the shared update lock, the five-minute recent-success cooldown, and CS2 process checks remain in `run.bat`.
- Each `run.bat` launch uses the normal maintenance flow, except when the five-minute successful-maintenance marker suppresses duplicate work. It checks/pulls the private repository, checks configured upstream add-on releases, updates CS2 through SteamCMD only when safe, patches `gameinfo.gi`, and applies an overwrite-only runtime overlay.
- If **any other `cs2.exe` is already running**, startup maintenance is skipped and the new Instance continues to launch. If another process starts while this runner is waiting for the shared maintenance lock, the runner releases the lock, skips maintenance, and continues to launch. If a CS2 process becomes active between update stages, remaining update/deployment stages are abandoned. A busy shared install must not prevent anti-crash recovery.
- Shared updates are serialized by a machine-wide lock and are permitted only while no `cs2.exe` is active. If another Instance is already running or becomes active during maintenance, the remaining update/deployment stages are cancelled; this Instance can still launch without updates.
- Routine payload overlay copies overwrite matching files only. They do not mirror, purge, move, or delete installed add-on files, and they protect `addons/counterstrikesharp/configs/` and `cfg/settings/`.
- Per-Instance `cfg/` and `addons/` overrides are copied only when no CS2 process is active, because every Instance shares one runtime tree. If another server is active, those optional overrides are skipped instead of changing files underneath it.
- A machine-wide lock serializes maintenance. The lock and recent-success marker live under `%TEMP%\\`, outside the Git working tree. The recent-success marker avoids repeating a just-completed shared update during rapid Instance startups.
- The updater does not call `win.bat`, `update.bat`, `game-update.bat`, or `install.bat`. Those have separate responsibilities; `win.bat` is a clean replacement/reset operation, not part of the routine overwrite-only path.

## Diagnostics

The supervisor intentionally has no logging or additional control logic: it runs the sibling `run.bat`, waits for it to return, and repeats after 100 milliseconds. To test it, start `run.vbs`, issue `quit` in the CS2 server console, and confirm the same runner starts again.
