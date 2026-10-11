# CS2 Windows instance runner

This template uses the repository's canonical `server/` installation. Keep `run.bat`, `run-fast.bat`, `run.vbs`, and `instance.ini` together in each external Instance folder.

- **`run.bat`** performs a shared maintenance pass on launch, then starts CS2 once. It checks the private repository and upstream add-on releases, applies overwrite-only payload files, and starts the game.
- **`run-fast.bat`** starts the same configured server without Git, upstream release checks, SteamCMD, gameinfo patching, or payload overlays. It delegates shared argument/configuration and launch logic to `run.bat --no-update`.
- **`run.vbs`** is the hidden supervisor. Like the known-working simple WSH loop, it launches the full path of a sibling batch file directly with `shell.Run(..., 0, True)`, waits for it to finish, and logs the returned exit code. It resolves `run.bat`, `run-fast.bat`, and `instance.ini` relative to the VBS file, not the current working directory or repository. The inherited `CS2_RUNNER_NO_PAUSE=1` flag prevents a child runner from waiting for keyboard input. The first attempt uses `run.bat`; once that attempt returns for any reason, every subsequent attempt uses `run-fast.bat`, so recovery does not depend on the batch exit code being passed through in a particular format. Launch paths and exit codes are logged to `%TEMP%\\CS2-KUS-runner-launcher.log`, with a 5-second delay between attempts to avoid a tight crash loop.
- `instance.example.ini` is a safe template with no real public IP, Game Server Login Token, API key, or password.

## Setup

1. Run `install.bat` from the repository root once.
2. Copy `instance.example.ini` to `instance.ini` in the Instance folder and configure it.
3. Set `SERVER_DIR` to the repository's shared `server` directory. Set the unique port, map/map group, reachable public IP (optional), Game Server Login Token, and a strong RCON password.
4. Keep `instance.ini` private. It is excluded from Git in this template.
5. Copy **all three** runner files (`run.bat`, `run-fast.bat`, and `run.vbs`) plus `instance.ini` into each actual external Instance directory; do not copy only the old `run.bat` and `run.vbs`.
6. Launch `run.vbs` for hidden operation with anti-crash supervision. Launch `run.bat` directly only when you want a visible console and an update pass. Launch `run-fast.bat` to start a server immediately without update work. To test anti-crash, start **`run.vbs` itself** (not `run.bat`), then use `quit` in the CS2 server console. The supervised batch window is hidden, so its normal runner banner should not be visible. Check `%TEMP%\CS2-KUS-runner-launcher.log` for `Launching: ...\run.bat`, `Initial runner returned; all subsequent restarts use run-fast.bat`, and then `Launching: ...\run-fast.bat`.

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
