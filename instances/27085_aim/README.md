# CS2 Windows instance runner

This template runs a CS2 instance from the repository's canonical `server/` installation:

- `run.bat` reads local values from `instance.ini`, optionally overlays only the selected instance's `cfg/` and `addons/` folders, launches CS2, and restarts the server process after it exits.
- `run.vbs` starts the batch runner hidden and supervises it. It is intended to stay running until you stop it.
- `instance.example.ini` is a safe template. It contains no public IP address, Game Server Login Token, API key, or real password.

## Setup

1. Run `install.bat` from the repository root once.
2. Copy `instance.example.ini` to `instance.ini` in this folder.
3. Set `SERVER_DIR=..\..\server`, `PORT`, `MAP`, `MAPGROUP` and the public `IP` when applicable.
4. Set `STEAM_ACCOUNT` for an internet server and replace `RCON_PASSWORD` with a strong value. Keep `instance.ini` private; the folder's `.gitignore` excludes it.
5. Launch `run.vbs` for hidden operation or `run.bat` for a visible console.

## Behavior and maintenance

- The repository's runtime files live under `server\game\csgo\`; the runner does not use a second KUS checkout or staging tree.
- `CUSTOM_FOLDER` may be absolute or relative to this folder. Only its `cfg/` and `addons/` children are copied as optional per-instance overrides. This is an additive/overwrite overlay; the runner never deletes runtime files.
- `BIND_IP` controls the local listen address and defaults to `0.0.0.0`. `IP` is optional and, when set, is passed as `+net_public_adr`.
- `API_KEY`, `STEAM_ACCOUNT`, and `WORKSHOP_COLLECTION` are only passed when non-empty.
- The runner does not call SteamCMD, pull Git, or update add-on releases. Stop the server/supervisor before using `game-update.bat` or `update.bat`.
- `win.bat` only patches/validates the installed server; it never launches the game.
