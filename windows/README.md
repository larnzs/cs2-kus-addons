# Windows entrypoints

Run these scripts from the repository checkout; each resolves the repository root from its own location.

| File | Purpose |
| --- | --- |
| `install.bat` | Install/check SteamCMD and CS2, then deploy the tracked payload. Does not launch CS2. |
| `win.bat` | Deploy the local payload and patch/validate `gameinfo.gi`. This is the clean runtime add-on reset; stop every CS2 instance first. |
| `update.bat` | Require a clean Git checkout, pull the branch fast-forward-only, then run `win.bat`. |
| `game-update.bat` | Update CS2 through SteamCMD only when no `cs2.exe` is active, then redeploy the payload. |
| `addons-update.bat` | Check upstream releases and overlay managed add-ons into `game/csgo/`; does not remove stale files. |
| `addons-inspect.bat` | Inspect selected upstream release assets without installing them. |

Examples:

```bat
windows\install.bat
windows\addons-update.bat -DryRun -Only CounterStrikeSharp
windows\addons-inspect.bat -Only CounterStrikeSharp
```

## External Instance template

Copy the files in [`instance-template/`](instance-template/) into each external Instance folder beside its private `instance.ini`. The copied `run.bat`, `run.vbs`, `watchdog.bat`, and instance-local `update.bat` are deliberately separate from the repository maintenance scripts above. Keep credentials in the external `instance.ini`, never commit them.
