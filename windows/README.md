# Windows entrypoints

Run these scripts from the repository checkout. Shared maintenance refuses to run while any `cs2.exe` process is active.

| File | Purpose |
| --- | --- |
| `update.bat` | Repository-only update: switches to `integration/kus-monorepo` and runs `git pull --ff-only origin integration/kus-monorepo`. It does not touch game files, SteamCMD, plugins, or the server runtime. Pauses before closing when run directly. |
| `install.bat` | Unified install/update: updates the repo, checks and publishes managed add-on releases, installs or updates CS2 through SteamCMD, safely overlays the Windows/shared payload, patches `gameinfo.gi`, and verifies required add-on files. It never launches the server and pauses before closing when run directly. |
| `addons-update.bat` | Optional stand-alone managed add-on update helper; waits for a keypress after success or failure. |
| `addons-inspect.bat` | Inspect selected upstream release assets without installing them; waits for a keypress after success or failure. |

Examples:

```bat
windows\update.bat
windows\install.bat
windows\addons-update.bat -DryRun -Only CounterStrikeSharp
windows\addons-inspect.bat -Only CounterStrikeSharp
```

## External Instance template

The public Windows maintenance scripts wait at the end and display `Please press any key to exit . . .` when run directly. `install.bat` passes `--no-pause` when calling `update.bat` internally, avoiding a nested pause.


Files in `instance-template/` are intentionally separate and instance-local. The unified shared updater does not edit or synchronize any Instance files; keep each Instance folder and its `instance.ini` outside the shared repository/runtime update process.
