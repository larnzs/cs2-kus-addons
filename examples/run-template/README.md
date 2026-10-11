# CS2 Windows instance runner

Keep these four files together in each external Instance folder:

- `update.bat` — performs shared maintenance: checks/pulls the private repository, updates upstream add-ons, updates CS2 with SteamCMD, patches `gameinfo.gi`, applies the overwrite-only runtime overlay, and syncs optional overrides. It does not launch the server.
- `run.bat` — reads the private `instance.ini` and contains the CS2 launch arguments/command only. It waits for an active shared-maintenance lock, starts CS2, and returns when the process exits.
- `run.vbs` — the classic watchdog loop only. It runs `run.bat`, waits for the batch to return, sleeps 100 ms, and runs it again. It never calls `update.bat`.
- `instance.ini` — private per-instance settings. Create it from `instance.example.ini`; never commit credentials.

## Startup and update procedure

1. After install or when you deliberately need a shared update, stop **all** CS2 processes and all Instance watchdogs.
2. Run the Instance-local `update.bat` once and make sure it ends successfully. It skips shared maintenance if a CS2 process is already active. This template copy is distinct from the repository-root `update.bat`.
3. Start `run.vbs` for each Instance. The VBS now launches only `run.bat`; it does not execute update checks at startup or after a crash.
4. Keep each Instance's `run.bat`, `run.vbs`, `update.bat`, and private `instance.ini` together. Give each Instance a unique port and point `SERVER_DIR` to the shared server runtime.

## Anti-crash behavior

The VBS file intentionally uses the classic minimal loop:

```vbscript
Option Explicit

Dim shell, fso, root, batPath
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
batPath = root & "\run.bat"

Do
    shell.Run Chr(34) & batPath & Chr(34), 0, True
    WScript.Sleep 100
Loop
```

- `shell.Run` uses `wait=True`; VBS waits until `run.bat` and the CS2 process it starts return, sleeps 100 milliseconds, then retries `run.bat`.
- The loop contains no updater invocation, marker logic, PowerShell supervisor, WMI polling, or alternative runner. A routine crash therefore does not repeat Git, release, SteamCMD, patching, or deployment work.
- `run.bat` waits while the shared maintenance lock exists so a server cannot start midway through runtime deployment. If the updater fails, fix the displayed error and run `update.bat` again with all CS2 processes stopped.
- The updater is still overwrite-only; it does not delete runtime-only add-ons. The `addons/counterstrikesharp/configs/` and `cfg/settings/` trees remain protected from the runtime payload overlay.
- Since all Instances share one runtime, optional `CUSTOM_FOLDER` overrides are applied only while the shared runtime is idle. Different override files cannot be isolated across simultaneously running servers.

## Test

1. Stop all servers and old VBS/PowerShell loops.
2. Copy the current `run.bat`, `run.vbs`, and instance-local `update.bat` beside your existing `instance.ini`. Do not replace private `instance.ini` or plugin configuration files.
3. Run the instance-local `update.bat` once while no CS2 process is active.
4. Start `run.vbs`; confirm the server launches.
5. Use `quit` or terminate only CS2. VBS should start `run.bat` again after approximately 100 ms. It should not invoke `update.bat` at any point in this loop.