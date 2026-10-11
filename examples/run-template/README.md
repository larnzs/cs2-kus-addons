# CS2 Windows instance runner

This template uses the repository's canonical `server/` installation. Keep `run.bat`, `run-fast.bat`, `run.vbs`, and `instance.ini` together in each external Instance folder.

- **`run.bat`** performs a shared maintenance pass on launch, then starts CS2 once. It checks the private repository and upstream add-on releases, applies overwrite-only payload files, and starts the game.
- **`run-fast.bat`** starts the same configured server without Git, upstream release checks, SteamCMD, gameinfo patching, or payload overlays. It delegates shared argument/configuration and launch logic to `run.bat --no-update`.
- **`run.vbs`** is the hidden supervisor. It launches each batch file using `%ComSpec% /d /c call` and sets the inherited `CS2_RUNNER_NO_PAUSE=1` environment flag, so a child runner does not wait for keyboard input even if argument quoting changes. It logs each returned exit code to `%TEMP%\CS2-KUS-runner-launcher.log`. Its first attempt uses `run.bat`; after the runner returns `100` (CS2 exited), it switches to `run-fast.bat` and relaunches immediately, with no maintenance cooldown or intentional sleep. It stays in fast mode until the VBS supervisor is restarted.
- `instance.example.ini` is a safe template with no real public IP, Game Server Login Token, API key, or password.

## Setup

1. Run `install.bat` from the repository root once.
2. Copy `instance.example.ini` to `instance.ini` in the Instance folder and configure it.
3. Set `SERVER_DIR` to the repository's shared `server` directory. Set the unique port, map/map group, reachable public IP (optional), Game Server Login Token, and a strong RCON password.
4. Keep `instance.ini` private. It is excluded from Git in this template.
5. Copy **all three** runner files (`run.bat`, `run-fast.bat`, and `run.vbs`) plus `instance.ini` into each actual external Instance directory; do not copy only the old `run.bat` and `run.vbs`.
6. Launch `run.vbs` for hidden operation with anti-crash supervision. Launch `run.bat` directly only when you want a visible console and an update pass. Launch `run-fast.bat` to start a server immediately without update work. To test anti-crash, start **`run.vbs` itself** (not `run.bat`), then use `quit` in the CS2 server console. The runner banner and `Press any key to close this window` should not appear in a visible launcher window; if they do, you are likely running a batch file directly or using stale Instance copies. Check `%TEMP%\CS2-KUS-runner-launcher.log` for a `Runner returned exit code 100` entry followed by a `switching to run-fast.bat` entry.

## Maintenance and multi-instance safety

- A machine-wide lock serializes shared maintenance so two maintenance runners do not pull, update and overlay the same repository/runtime at the same time.
- The former machine-wide `cs2.exe` gate no longer blocks add-on updates or the runtime overlay. The live overlay uses overwrite-only file copies: it never mirrors, purges, moves or deletes installed add-on files, and it protects the full `addons/counterstrikesharp/configs/` and `cfg/settings/` trees.
- SteamCMD updates CS2 game binaries, not just plugin files. Therefore, the runner skips only the SteamCMD game update while **any** `cs2.exe` process is active; add-on release checks, gameinfo patching and overwrite-only payload copies can continue. A later maintenance launch can update the game when all CS2 processes are stopped.
- Windows can reject an overwrite if a DLL is currently locked by a running process. If the overlay reports such an error, the VBS supervisor switches to the fast runner so a failed update cannot prevent the server from restarting. Restart VBS or run `run.bat` again later to retry maintenance.
- Per-Instance `cfg/` and `addons/` overrides are copied only when no CS2 process is active, because all Instances share one runtime tree. When another server is already running, override sync is skipped rather than changing files underneath that server.
- The updater never calls `win.bat`, `update.bat`, `game-update.bat`, or `install.bat`. Those operations have different responsibilities, and `win.bat` is a clean replacement/reset workflow rather than the routine overwrite-only path.
- The machine-wide maintenance lock and recent-success marker are stored under `%TEMP%\`, outside the Git working tree. A stale lock can be cleared after the owning runner process has exited.

## Common launch arguments

`run.bat` accepts `--no-pause` for use by VBS and `--no-update` for the fast launch path. `run-fast.bat` forwards arguments to this shared runner.
