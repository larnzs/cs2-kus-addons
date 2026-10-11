# CS2 Windows instance runner

Each external Instance folder contains exactly these three active files:

- `run.bat` — validates the instance, optionally performs shared startup maintenance, then launches CS2 and returns when the CS2 process exits.
- `run.vbs` — hidden anti-crash supervisor. It launches the sibling `run.bat` directly, waits for it to return, then launches the same file again after **5 seconds**. The first launch has no argument; every later launch passes `--no-update`. It does not use a second batch file or modify its own environment.
- `instance.ini` — private settings for this Instance. Create it from `instance.example.ini`; do not commit credentials.

The VBS resolves `run.bat` and `instance.ini` relative to its own directory, so the runner files may live outside `W:\\cs2-kus-addons`. Keep `run.bat`, `run.vbs`, and `instance.ini` side-by-side in the external Instance folder.

## Setup

1. Run `install.bat` from the repository root once.
2. Copy `instance.example.ini` to `instance.ini` in the external Instance folder and configure it.
3. Set `SERVER_DIR` to the repository's shared `server` directory. Set a unique port, map/map group, reachable public IP if needed, Game Server Login Token, and a strong RCON password.
4. Keep `instance.ini` private. It is excluded from Git in this template.
5. Copy only `run.bat`, `run.vbs`, and your private `instance.ini` into each external Instance folder. The old `run-fast.bat` is no longer used.
6. Start `run.vbs` for hidden operation with anti-crash supervision. Run `run.bat` directly only when you intentionally want a visible maintenance-and-launch pass. Add `--pause` when you want the batch window to wait after exit. The supervisor automatically passes `--no-update` on retries.

## Anti-crash and maintenance behavior

- `run.vbs` calls the same full path of `run.bat` forever, without depending on a specific exit code. The first attempt can run maintenance; after that, the VBS's own Boolean state causes each retry to pass `--no-update`. It waits 5 seconds between attempts and does not set environment variables after the batch exits.
- The first `run.bat` attempt may pull the private repository, check upstream add-on releases, update CS2 with SteamCMD where safe, patch `gameinfo.gi`, and apply overwrite-only payload files. Later attempts in the same VBS session pass `--no-update`, so the runner skips Git/release checks, SteamCMD, patching, and payload overlay before trying to launch CS2 again.
- If **any other `cs2.exe` is already running**, startup maintenance is skipped and the new Instance continues to launch. If another process starts while this runner is waiting for the shared maintenance lock, the runner releases the lock, skips maintenance, and continues to launch. A busy shared install must not prevent anti-crash recovery.
- SteamCMD can replace game binaries, so the updater never intentionally runs the game update while any `cs2.exe` is active. This only skips that maintenance work; it does not block launching or restarting the requested Instance.
- Routine payload overlay copies overwrite matching files only. They do not mirror, purge, move, or delete installed add-on files, and they protect `addons/counterstrikesharp/configs/` and `cfg/settings/`.
- Per-Instance `cfg/` and `addons/` overrides are copied only when no CS2 process is active, because every Instance shares one runtime tree. If another server is active, those optional overrides are skipped instead of changing files underneath it.
- A machine-wide lock serializes maintenance. The lock and recent-success marker live under `%TEMP%\\`, outside the Git working tree. The recent-success marker avoids repeating a just-completed shared update during rapid Instance startups.
- The updater does not call `win.bat`, `update.bat`, `game-update.bat`, or `install.bat`. Those have separate responsibilities; `win.bat` is a clean replacement/reset operation, not part of the routine overwrite-only path.

## Diagnostics

The supervisor intentionally has no per-loop logging or environment-variable mutation: it runs the sibling `run.bat`, waits for it to return, then retries after 5 seconds. To test it, start `run.vbs`, issue `quit` in the CS2 server console, and confirm a new runner launch occurs within roughly 5 seconds. For VBScript runtime diagnostics, run the VBS from a command prompt with `cscript //nologo run.vbs`; the runner is still launched hidden, but host-level script errors can be shown by the console host.
