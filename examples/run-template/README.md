# CS2 Windows instance runner

This template runs a CS2 instance from the repository's canonical server/ installation.

- run.bat reads instance.ini, launches CS2, and owns restart plus maintenance after the game process exits.
- run.vbs is only a hidden launcher/supervisor. It does not run SteamCMD, Git, or deployment scripts.
- instance.example.ini is a safe template. It contains no public IP, Game Server Login Token, API key, or real password.

## Setup

1. Run install.bat from the repository root once.
2. Copy instance.example.ini to instance.ini in this folder.
3. Set SERVER_DIR to the repository's server directory, and configure PORT, MAP, MAPGROUP, and the public IP when applicable.
4. Set STEAM_ACCOUNT for an internet server and use a strong RCON_PASSWORD. Keep instance.ini private; the folder's .gitignore excludes it.
5. Copy run.bat and run.vbs to the actual Instance directory outside the repository if you want Instance files kept separate from the checkout. Keep instance.ini beside them.
6. Launch run.vbs for hidden operation or run.bat for a visible console.

## Maintenance behavior

- Every maintenance cycle uses a machine-wide lock so multiple Instances cannot update the shared installation at the same time.
- Before it updates the game or overlays payload files, the runner ensures no cs2.exe process is using the shared installation. On initial startup, if another Instance is already running, it skips shared-file updates and starts without applying this Instance's shared cfg/ and addons/ overrides. After a server exits and an update is due, that Instance waits for the other server processes to stop before touching the shared installation.
- Game files are checked/updated directly through SteamCMD. The runner does not call game-update.bat, update.bat, win.bat, or the installer.
- The runner pulls the latest integration/kus-monorepo commit from the private repository. The repository's remote updater workflow checks upstream add-on releases and publishes payload updates; the runner does not run addons-update.bat locally, because that script creates local commits and could make later fast-forward pulls fail.
- Runtime payload deployment is overwrite-only. It uses direct file-level copies, never mirrors or deletes the runtime addons/ directory, and retains files that are no longer present in the payload. This intentionally means removed or renamed add-on files are not automatically deleted.
- Existing addons/counterstrikesharp/configs/ and cfg/settings/ files are protected from the shared payload overlay. Per-Instance overrides are copied only while no CS2 server process is active.
- BIND_IP controls the local listen address and defaults to 0.0.0.0. IP is optional and, when set, is passed as +net_public_adr.
- API_KEY, STEAM_ACCOUNT, and WORKSHOP_COLLECTION are only passed when non-empty.

The maintenance lock and last-success marker are stored under %TEMP%, outside the Git working tree. If a runner is forcibly killed in the middle of maintenance, other runner instances detect and clear a stale lock once its owner process is gone.
