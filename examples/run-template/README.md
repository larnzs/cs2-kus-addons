# CS2 Windows instance runner

Keep these four files together in each external Instance folder:

- `update.bat` — runs the one-shot shared maintenance pipeline: repository pull, upstream add-on update, SteamCMD, gameinfo patch, overwrite-only runtime overlay, and optional override sync. It never launches CS2 and contains no server launch command.
- `run.bat` — reads private `instance.ini` and contains the CS2 launch configuration/command only. It waits while shared maintenance is running, then starts one CS2 process and returns when it exits.
- `run.vbs` — invokes `update.bat` once when the watchdog starts, then runs the classic anti-crash loop over `run.bat`: wait for the batch/server to exit, sleep 100 ms, repeat. The loop never calls the updater.
- `instance.ini` — private per-instance settings. Create it from `instance.example.ini`; never commit credentials.

Copy `run.bat`, `run.vbs`, `update.bat`, and your private `instance.ini` into each external Instance folder. Keep all Instances under the same Windows account so they share `%TEMP%\CS2-KUS-Maintenance.lock` and the five-minute success marker.

## Setup

1. Run `install.bat` from the repository root once.
2. Copy `instance.example.ini` to `instance.ini` in the external Instance folder and configure it.
3. Set `SERVER_DIR` to the shared `server` directory in the private repository. Give each Instance a unique port.
4. Copy the four files listed above into the Instance folder. Keep the real `instance.ini` private.
5. Start `run.vbs`. It runs maintenance once, then restarts only `run.bat`.

## Update and anti-crash behavior

- At watchdog startup, `run.vbs` runs `update.bat` once and waits for it to finish. The updater does not modify shared files if any `cs2.exe` is active; it exits successfully so another Instance can start.
- Successful full maintenance writes `%TEMP%\CS2-KUS-Maintenance-success.marker`. Other Instances started within five minutes skip duplicate Git/release/SteamCMD/deploy work. This marker is only a cooldown; it does not select a different runner.
- After maintenance returns, VBS loops only over `run.bat`. When CS2 exits or crashes, the batch returns and VBS retries it after **100 milliseconds**. This loop does not check Git, query releases, run SteamCMD, patch `gameinfo.gi`, or overlay add-ons.
- If an updater is deploying the shared runtime, `run.bat` waits for the lock to clear. If an updater crashed and left a stale lock, the runner checks the owner PID and removes the lock only when its owner is gone or the lock has been incomplete for over 30 seconds.
- If a real maintenance error occurs, `update.bat` returns a nonzero code and VBS stops rather than launching against a potentially partial deployment. Fix the error, then restart `run.vbs`.
- Runtime overlay is overwrite-only. It does not delete installed add-ons/runtime-only files; `addons/counterstrikesharp/configs/` and `cfg/settings/` remain protected.
- Optional `CUSTOM_FOLDER` overrides are copied by `update.bat` only while no CS2 process is active, because all Instances share one runtime. Different overrides cannot be isolated between simultaneous servers using that same shared runtime.
- For an intentional manual update, stop every CS2 process and all Instance watchdogs first, then run the Instance-local `update.bat`. This copied file is distinct from the repository-root `update.bat`.

## Test

1. Stop all CS2 servers and old VBS/PowerShell supervisors.
2. Copy the new `run.bat`, `run.vbs`, and instance-local `update.bat` beside your existing private `instance.ini`. Do not overwrite `instance.ini` or plugin configuration files.
3. Start one `run.vbs`. Its visible first window should run one-shot maintenance; then the server runner begins.
4. With CS2 running, confirm VBS stays alive. Use `quit` or terminate only the CS2 process; VBS should restart `run.bat` after about 100 ms without running `update.bat` again.
5. Start another Instance while the first CS2 is running. Its updater should skip shared maintenance, then its `run.bat` should start without waiting for the other server to stop.
