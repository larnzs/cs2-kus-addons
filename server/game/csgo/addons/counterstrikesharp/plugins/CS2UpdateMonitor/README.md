# CS2 Update Monitor

[![Build](https://github.com/beanman109/cs2-updatemonitor/actions/workflows/build.yml/badge.svg)](https://github.com/beanman109/cs2-updatemonitor/actions/workflows/build.yml)
[![Release](https://github.com/beanman109/cs2-updatemonitor/actions/workflows/release.yml/badge.svg)](https://github.com/beanman109/cs2-updatemonitor/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/beanman109/cs2-updatemonitor)](https://github.com/beanman109/cs2-updatemonitor/releases/latest)
[![License](https://img.shields.io/github/license/beanman109/cs2-updatemonitor)](LICENSE)

A CounterStrikeSharp plugin that detects Counter-Strike 2 updates, announces maintenance to players, counts down in chat/center text, and then either stops the server for an external supervisor or updates and restarts it itself.

Version 1.1.0 is hardened for unattended operation. It uses CounterStrikeSharp's pre-world-update listener for scheduling, which continues while an empty server is hibernating, and captures native values on the game thread before SteamCMD work moves to a background worker.

CounterStrikeSharp already runs through Metamod, so this is compatible with a server using both. It targets CounterStrikeSharp API `1.0.371` / .NET 10.

## Features

- Queries Valve metadata with SteamCMD and compares the public branch build ID to `appmanifest_730.acf`.
- Automatically generates `addons/counterstrikesharp/configs/plugins/CS2UpdateMonitor/CS2UpdateMonitor.json` on first load.
- Configurable polling, countdown, announcement times/messages/colors, maintenance window, and shutdown command.
- Optional wait-until-empty behavior.
- `NotifyOnly`, `ShutdownForSupervisor`, and `SelfUpdateAndRestart` action modes.
- Detached update helper waits for CS2 to exit, runs SteamCMD, logs the result, and launches the server again.
- Admin commands to check, manually schedule, cancel, and inspect status.
- Cancelling an automatically detected update persistently suppresses that build until Valve publishes a newer one.
- Persists pending countdowns across plugin hot reloads in `update-state.json`.
- Defers maintenance through map transitions and for a configurable post-map grace period.
- Uses a monotonic in-process countdown so system clock corrections cannot change the deadline.
- Limits automatic restart attempts per Valve build and applies a retry cooldown, preventing update/restart loops.
- Isolates chat/center-message failures so announcements can never block shutdown.

## Build

```text
dotnet build -c Release
```

The build output is in `bin/Release/net10.0`.

GitHub Actions builds and packages the plugin independently on Windows and Linux for every push and pull request. Tags matching `v*` publish both platform-labelled ZIP files to GitHub Releases.

## Install

1. Install current [Metamod:Source](https://www.sourcemm.net/downloads.php/?branch=master) and [CounterStrikeSharp](https://github.com/roflmuffin/CounterStrikeSharp/releases).
2. Download the ZIP for your server OS from [GitHub Releases](https://github.com/beanman109/cs2-updatemonitor/releases/latest).
3. Extract its `CS2UpdateMonitor` directory into `game/csgo/addons/counterstrikesharp/plugins`.
4. Confirm the resulting directory contains:
   - `CS2UpdateMonitor.dll`
   - `CS2UpdateMonitor.deps.json`
   - `CS2UpdateMonitor.runtimeconfig.json`
   - optionally `CS2UpdateMonitor.pdb`
5. Do **not** install a bundled `CounterStrikeSharp.API.dll`; the server must use its own matching API assembly.
6. Start the server once, then edit the generated JSON config.
7. Install SteamCMD on the same host and set `SteamCmdPath` if it is not on `PATH`.

The default `steamcmd` value also auto-detects common Linux locations, including Pterodactyl's `/home/container/steamcmd/steamcmd.sh`.

SteamCMD is only queried during normal operation. It does not touch the live game installation until the detached maintenance helper runs.

The plugin directory must remain named exactly `CS2UpdateMonitor`; do not append a version number to the directory name.

Verify the installation from the server console:

```text
css_plugins list
css_updatecheck
css_updatestatus
```

## Action modes

### ShutdownForSupervisor (recommended for Pterodactyl and other game panels)

After the countdown, the plugin runs `ShutdownCommand` (normally `quit`). If your Pterodactyl egg automatically restarts an exited server and runs SteamCMD during startup, no self-updater configuration is needed: leave `Action` as `ShutdownForSupervisor`. The server exits, Pterodactyl starts it again, and the egg installs the update during that startup. Ensure automatic restart/crash detection is enabled for the server.

The plugin cannot directly restart its own container unless you give it panel API credentials, which is unnecessary and less secure for this workflow.

### NotifyOnly

Only detects and announces the update. It never schedules a shutdown.

### SelfUpdateAndRestart

The plugin writes an update job, starts its own detached helper, then quits CS2. The helper waits for the process to exit, runs:

```text
steamcmd +force_install_dir <server> +login anonymous +app_update 730 [validate] +quit
```

It then launches `RestartExecutable` with `RestartArguments`.

For this mode configure:

- `DotnetHostPath`: a .NET 10 host. With the CounterStrikeSharp runtime this may be an absolute path such as `/server/game/csgo/addons/counterstrikesharp/dotnet/dotnet`.
- `ServerInstallDirectory`: the directory passed to SteamCMD, or `auto` to derive it from the app manifest.
- `RestartExecutable`: preferably a wrapper script or service-safe launcher. On Linux, make it executable.
- `RestartArguments` and `RestartWorkingDirectory`.

The helper log defaults to `update-helper.log` in the plugin directory. If SteamCMD fails, the helper logs the error and deliberately does not launch a potentially stale server.

## Important configuration

- `CheckIntervalSeconds`: minimum 60; default 300.
- `AppManifestPath`: `auto` searches upward from `game/csgo`, or specify the full path.
- `CountdownSeconds`: default 300.
- `OnlyStartCountdownWhenServerEmpty`: waits indefinitely for zero human players before starting the countdown.
- `MapChangeGraceSeconds`: default 15; shutdown and empty-server decisions are deferred while changing maps and during this grace period.
- `MaxAutomaticRestartsPerBuild`: default 2; set 0 to disable automatic restart scheduling while retaining detection.
- `AutomaticRestartRetryCooldownMinutes`: default 30 between attempts for the same build.
- `ShutdownCommandRetrySeconds`: delay before retrying if launching the helper or shutdown command throws.
- `StateFileName`: persistent safety state in the plugin directory; the default is `update-state.json`.
- `MaintenanceWindowStart` / `MaintenanceWindowEnd`: local 24-hour times such as `04:00` and `06:00`; leave either blank to disable the window. Overnight windows such as `23:00`–`05:00` work.
- `AnnounceAtSeconds`: thresholds such as `[300, 180, 60, 30, 10, 5, 4, 3, 2, 1]`.
- `Action`: one of the three modes above.
- `ValidateUpdate`: adds SteamCMD's expensive `validate` operation; normally leave false.
- `UpdateInstallTimeoutSeconds`: self-updater SteamCMD timeout; default 1800. This is separate from the shorter metadata-check timeout.

Message placeholders are `{time}`, `{seconds}`, `{installed_build}`, and `{remote_build}`. Supported color tokens are `{default}`, `{green}`, `{red}`, `{yellow}`, `{grey}`, and `{lightblue}`.

## Commands

- `css_updatestatus` / `!updatestatus`: available to everyone.
- `css_updatecheck` / `!updatecheck`: force a check now; requires `@css/root`.
- `css_updateschedule <seconds>` / `!updateschedule <seconds>`: manually begin a countdown; requires `@css/root`.
- `css_updatecancel` / `!updatecancel`: cancel maintenance; requires `@css/root`.

Server console can run the admin commands as well. CounterStrikeSharp permissions can be changed through its command override configuration if `@css/root` is too restrictive.

If detection appears inactive, run `css_updatecheck`, wait a few seconds, then run `css_updatestatus`. Status reports the last SteamCMD/path/manifest error directly instead of requiring log inspection.

## Operational notes

- Test the chosen shutdown/restart path with `css_updateschedule 30` during a maintenance period before relying on it unattended.
- The account running CS2 must be able to execute SteamCMD and, for self-update mode, write to the server installation.
- Avoid running two independent auto-updaters at once. Use either the plugin helper or the panel's updater.
- A process cannot update all of its own locked binaries safely. That is why the actual installation runs in a separate helper after CS2 exits.
- If Pterodactyl fails to install a detected build, the plugin waits for the configured cooldown before retrying and stops permanently for that build after the configured maximum. A newer Valve build resets the limit.
- Do not delete `update-state.json` merely to bypass a blocked build; inspect the panel's SteamCMD startup log first. Cancelling through `css_updatecancel` is the supported way to suppress a detected build.

## Contributing

Issues and pull requests are welcome. Please include your operating system, CounterStrikeSharp version, relevant plugin configuration, and the complete Update Monitor log section when reporting a problem.

## License

CS2 Update Monitor is available under the [MIT License](LICENSE).
