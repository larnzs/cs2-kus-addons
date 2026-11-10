# CS2 KUS Addons — Larnz Unified Server

A maintained, single-repository Counter-Strike 2 dedicated-server distribution. This project combines the KUS-based server payload with the plugins, dependencies, game-mode configuration, deployment tooling, and multi-instance runners maintained in this repository.

This is an integrated downstream project, **not an official KUS release**. The original upstream KUS guide is not copied into this README; upstream source material retained for provenance lives under [docs/upstream/](docs/upstream/).

## What this repository owns

- The tracked CS2 runtime payload and its Windows-specific overlay.
- The unified plugin catalog, upstream version tracking, and updater adapters.
- Shared server configuration and game-mode plugin activation policy.
- Windows, Linux, and Docker installation/update workflows.
- Per-instance launch/watchdog templates for Windows and Linux.
- CI checks for payload layout, updater coverage, plugin lifecycle, and runtime integrity.

## Repository layout and sources of truth

| Path | Purpose |
| --- | --- |
| `game/csgo/` | Canonical tracked CS2 payload source. Shared/Linux files live here. |
| `game/csgo/addons/windows/` | Windows-only add-on overlay, flattened into the runtime during Windows deployment. |
| `game/csgo/cfg/` | Operator-managed shared game-mode configuration. Updaters protect this tree. |
| `DEPENDENCIES.json` | Manifest for release/source-built Larnz add-ons, dependencies, install mappings, and required runtime files. |
| `README.md` | Unified plugin catalog and displayed version/revision index. |
| `scripts/update/plugins/` | Per-plugin Bash adapters used by the scheduled catalog updater. |
| `scripts/Update-Addons.ps1` | PowerShell manifest updater used by Windows maintenance. |
| `server/` | Local Windows SteamCMD installation/runtime; ignored by Git and never part of the tracked payload. |
| `windows/` | Windows installation, repository update, maintenance, and external Instance templates. |
| `linux/` | Linux installation and repository update entrypoints plus per-instance templates. |
| `docker/` | Docker image, Compose deployment, and host-side volume update workflow. |
| `docs/` | Project documentation, lifecycle policy, and archived migration/upstream material. |

The tracked payload is the source used by deployment tools. It is not a copy of a locally installed server. Runtime files absent from the tracked payload are not deleted by normal overwrite-only deployment.

## Quick start

Choose one deployment method. The maintenance/install scripts **do not launch CS2**; launch is controlled by an Instance runner or the selected container deployment.

### Windows host

1. Clone this repository and check out `integration/kus-monorepo`.
2. Stop all running CS2 instances and watchdogs.
3. Run:

```bat
windows\install.bat
```

The installer fast-forwards the repository, runs the Windows add-on update/publish pipeline, installs or updates CS2 with SteamCMD, overlays the tracked payload, patches `gameinfo.gi`, and verifies the deployed files. It does not start the server.

To update only the repository, use `windows\update.bat`. To inspect or update Larnz manifest add-ons separately, use `windows\addons-inspect.bat` or `windows\addons-update.bat`.

For a server instance, copy the files from `windows/instance-template/` into an external Instance directory. Copy `instance.example.ini` to `instance.ini`, set `SERVER_DIR` to the absolute path of this repository's `server\` folder, configure a unique port and credentials, then start `watchdog.bat`. Keep the Instance directory and its secrets outside Git. See [the Windows entrypoint guide](windows/README.md) and [the Instance template guide](windows/instance-template/README.md).

### Linux host

Run from a clean clone owned by a non-root operator, with all CS2 processes stopped:

```bash
sudo -E bash ./linux/install.sh
```

The installer fast-forwards the active branch using the checkout owner's Git credentials, installs/updates Steam Linux Runtime and CS2, deploys the committed payload, and patches `gameinfo.gi`. It does not run upstream release discovery, push to GitHub, or launch CS2.

Create an Instance from the template and protect its configuration:

```bash
cp -a linux/instances/instance-template linux/instances/aim
cp linux/instances/aim/instance.example.env linux/instances/aim/instance.env
sudo chmod 600 linux/instances/aim/instance.env
sudo chown -R steam:steam linux/instances/aim
sudo -u steam bash linux/instances/aim/watchdog.sh
```

Only the Instance runner launches CS2. Use `linux/instances/aim/stop.sh` to stop that instance. See [Linux entrypoints](linux/README.md) and [Linux multi-instance setup](linux/instances/README.md).

### Docker

Create the local environment file, review every value, and keep real credentials out of Git:

```bash
cp .env.example .env
# Edit .env before starting the container.
docker compose -f docker/docker-compose.yml up --build
```

For maintenance, stop the running CS2 container and run:

```bash
bash ./docker/update.sh
```

The maintenance path updates the checkout/plugin payload, rebuilds the image, and runs a one-shot container to update the persistent game volume. It does not launch the game server. The Kubernetes manifest under `docker/kubernetes/` is retained as legacy reference and is not the maintained deployment path. See [Docker deployment notes](docker/README.md).

## Maintenance and update responsibilities

These commands intentionally have different scopes:

| Command | What it changes | Starts CS2? |
| --- | --- | --- |
| `windows/update.bat` | Git checkout only; fast-forward pull of `integration/kus-monorepo`. | No |
| `bash linux/update.sh` | Git checkout only; fast-forward pull of the currently checked-out branch. | No |
| `windows/install.bat` | Repository, managed add-ons, SteamCMD CS2 install, tracked runtime overlay, and `gameinfo.gi`. | No |
| `sudo -E bash linux/install.sh` | Repository, Steam Linux Runtime, CS2 install, tracked runtime overlay, and `gameinfo.gi`. | No |
| `windows/addons-update.bat` | Larnz manifest-managed upstream add-ons in the tracked payload. | No |
| `bash scripts/update/update.sh --dry-run` | Checks the README catalog and manifest updater plan without committing payload changes. | No |
| `bash docker/update.sh` | Docker checkout/plugin update, image rebuild, and persistent-volume maintenance. | No |

The plugin catalog has one combined table below. The updater keeps the two update domains separate internally:

- KUS-origin catalog entries are read from the unified table and handled by their per-plugin adapters under `scripts/update/plugins/`.
- Manifest-owned add-ons are processed from `DEPENDENCIES.json`; their release/source-build mapping and verification paths are not inferred from the KUS updater.
- `Metamod:Source` is the deliberate exception: its KUS-style updater also synchronizes its manifest version.
- Manifest-owned rows are excluded from the KUS catalog pass, preventing duplicate release checks and conflicting commits.

The full GitHub Actions updater checks the entire KUS catalog and all automation-enabled `DEPENDENCIES.json` add-ons every 5 minutes at UTC minutes 2, 7, 12, 17, 22, 27, 32, 37, 42, 47, 52, and 57. The manual priority workflow remains available for targeted checks and troubleshooting, but does not run on a competing schedule. GitHub may delay or drop scheduled workflows during busy periods, so five minutes is a target polling interval rather than a real-time guarantee. Successful updater commits are published to `integration/kus-monorepo`, after which node installers can deploy the committed payload using read-only Git access.

Useful maintainer commands:

```bash
# Preview catalog and manifest update work.
bash scripts/update/update.sh --dry-run

# List only the KUS-origin rows handled by the Bash catalog pass.
bash scripts/update/update.sh --list

# Preview/update the Windows PowerShell manifest updater.
windows\addons-update.bat -DryRun
windows\addons-update.bat
```

The Bash updater requires a clean working tree for an apply run because each successful add-on is committed separately. For full behavior, flags, adapter conventions, and rollback rules, see [scripts/update/README.md](scripts/update/README.md).

## Plugin activation and configuration ownership

### Mode-specific plugins

A plugin stored below `plugins/disabled/` is not abandoned or excluded from updates. That location prevents automatic loading by CounterStrikeSharp; the relevant game-mode CFG explicitly loads it when required. The updater refreshes the payload in place and does not rewrite the game's activation commands.

The lifecycle rules are documented in [MODE-PLUGIN-LIFECYCLE.md](docs/MODE-PLUGIN-LIFECYCLE.md). Every mode switch uses the central `unload_plugins.cfg` reset and mode-specific CFGs load only the DLLs required by that mode. Keep those exact DLL paths synchronized when adding or moving a mode plugin.

### Protected configuration

The updater and deployment workflows distinguish plugin binaries from operator-owned configuration:

- `game/csgo/cfg/` is manually managed and protected from upstream plugin release archives.
- `game/csgo/addons/counterstrikesharp/configs/` is manually managed, except for the narrowly allowlisted `cs2-tags` sample configuration.
- Plugin-local settings, language files, map profiles, and data are preserved by the relevant adapter where required.
- Deployment is an overwrite-only overlay. Files not present in the tracked payload are not purged from the runtime.

### Instance-local configuration

Windows `instance.ini` and Linux `instance.env` hold per-server ports, map settings, RCON passwords, GSLTs, and other secrets. Do not commit them. Instance `CUSTOM_FOLDER` content is copied into the shared runtime before launch. This is an additive file overlay, **not isolated per-instance storage**: if multiple instances target the same runtime path, the last copy can overwrite matching files for every instance using that runtime. Avoid conflicting custom files between simultaneously running instances.

## Validation and CI

The repository's GitHub Actions workflows validate more than shell syntax:

- Every README catalog entry must have a source link and an updater/bundle mapping, except the explicitly documented not-installed manual entry.
- Adapter scripts are sourced and their `PLUGIN_PATHS` are checked against real tracked payload paths.
- All automated `DEPENDENCIES.json` entries, the manual priority allowlist, and first-release adapters are checked independently.
- Windows and Linux payload layout, Windows overlay behavior, required runtime files, and protected configuration boundaries are checked.
- Plugin CFG load/unload paths and AFKManager mode policy are checked by `scripts/validate-plugin-lifecycle.py`.

Run the main catalog checks locally:

```bash
bash scripts/Test-AllUpdaters.sh
python3 scripts/Test-CatalogCoverage.py --strict
python3 scripts/validate-plugin-lifecycle.py
```

The current catalog contains **75 entries**: 74 are covered by an automatic updater or an owning bundle, and one is explicitly manual-only because it is not installed. Two components, `MenuManagerCS2` and `GG1MapChooser`, are updated as part of the GameModeManager bundle; they must not have competing standalone updaters.

## Plugin and runtime catalog

This is the unified inventory of plugins, libraries, native add-ons, and bundled components used by this distribution. Every name links to its upstream project. Paths are relative to `game/csgo/`. The version column is the displayed catalog value; source-built Manifest entries are shown as `branch@short-commit`. Updater links point to scripts tracked in this repository.

| Mod | Version / revision | Purpose | Payload placement / activation | Update automation |
| --- | --- | --- | --- | --- |
| [ABS_MapCycle](https://github.com/Austinbots/cs2-Change-Map-Rotation-Using-Text-File) | `main@7d71a7bf29bb` | Text-file map rotation; disabled for game-mode-specific activation | Mode-specific payload: `game/csgo/addons/counterstrikesharp/plugins/disabled/ABS_MapCycle` (kept disabled; game-mode CFG controls loading) | [`abs-mapcycle.sh`](scripts/update/plugins/abs-mapcycle.sh) |
| [AdvancedFriendlyFire](https://github.com/mister-keno/advanced-ff-cs2) | `main@ab332f0b5923` | Friendly-fire damage tracking and configured punishments; disabled for game-mode-specific activation | Mode-specific payload: `game/csgo/addons/counterstrikesharp/plugins/disabled/advanced_friendlyfire` (kept disabled; game-mode CFG controls loading) | [`advancedfriendlyfire.sh`](scripts/update/plugins/advancedfriendlyfire.sh) |
| [AFKManager](https://github.com/NiGHT757/AFKManager) | `0.2.8` | Stored under `plugins/disabled/`; selectively loaded by allowlisted public-mode CFGs | Mode-specific payload: `game/csgo/addons/counterstrikesharp/plugins/disabled/AFKManager` (kept disabled; game-mode CFG controls loading) | [`afkmanager.sh`](scripts/update/plugins/afkmanager.sh) |
| [AnnouncementBroadcaster](https://github.com/lengran/CS2AnnouncementBroadcaster) | `0.5` | Conditional messages, OnCommand, OnPlayerConnect, OnRoundStart, and TimerMsgs. | Default CounterStrikeSharp plugin | Script: [`announcementbroadcaster.sh`](scripts/update/plugins/announcementbroadcaster.sh) |
| [AnyBaseLibCS2](https://github.com/NickFox007/AnyBaseLibCS2) | `0.9.4` | Shared database/API library | Shared API payload: `game/csgo/addons/counterstrikesharp/shared/AnyBaseLib` | [`anybaselibcs2.sh`](scripts/update/plugins/anybaselibcs2.sh) |
| [CounterStrikeSharp](https://github.com/roflmuffin/CounterStrikeSharp) | `1.0.379` | Windows with-runtime files (including bundled .NET) are staged under `game/csgo/addons/windows/addons/counterstrikesharp/`; the shared/Linux payload remains under `game/csgo/addons/counterstrikesharp/`. | Shared CounterStrikeSharp runtime plus Windows with-runtime overlay | [`counterstrikesharp.sh`](scripts/update/plugins/counterstrikesharp.sh) |
| [CS2 Advertisement](https://github.com/partiusfabaa/cs2-advertisement) | `2.0.2` | Allows you to show ads in chat/center/panel. [How?](#enable-advertisements) | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-advertisement.sh`](scripts/update/plugins/cs2-advertisement.sh) |
| [CS2 Deathmatch](https://github.com/NockyCZ/CS2-Deathmatch) | `1.3.6` | Custom Deathmatch CS2 plugin (Includes custom spawnpoints, multicfg, gun selection, spawn protection, etc) | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-deathmatch.sh`](scripts/update/plugins/cs2-deathmatch.sh) |
| [CS2 Executes](https://github.com/zwolof/cs2-executes) | `1.1.1` | CS2 implementation of executes. Based on the version for CS:GO by Splewis. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-executes.sh`](scripts/update/plugins/cs2-executes.sh); selects the no-map-configs asset and preserves local map data |
| [CS2 Instadefuse](https://github.com/B3none/cs2-instadefuse) | `2.0.0` | Allows a CT to instantly defuse the bomb when nothing can prevent defusal. Written in C# for CounterStrikeSharp. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-instadefuse.sh`](scripts/update/plugins/cs2-instadefuse.sh); preserves local `lang/` |
| [CS2 Remove Map Weapons](https://github.com/kus/CS2-Remove-Map-Weapons) | `1.0.1` | Remove weapons from the map in CS2 as `mp_weapons_allow_map_placed 0` does not work. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-remove-map-weapons.sh`](scripts/update/plugins/cs2-remove-map-weapons.sh); updates the disabled plugin folder without changing mode activation. |
| [CS2 Retakes](https://github.com/B3none/cs2-retakes) | `3.1.1` | CS2 implementation of retakes. Based on the version for CS:GO by Splewis. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-retakes.sh`](scripts/update/plugins/cs2-retakes.sh) |
| [CS2 Retakes Allocator](https://github.com/yonilerner/cs2-retakes-allocator) | `2.4.2` | Advanced weapon allocation for B3none/cs2-retakes | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-retakes-allocator.sh`](scripts/update/plugins/cs2-retakes-allocator.sh); refreshes the plugin and bundled runtime dependencies while preserving local config, gamedata and translations. |
| [CS2 Whitelist](https://github.com/PhantomYopta/CS2_WhiteList) | `1.0.0` | Restricts access to the server for SteamID members/employees listed in the whitelist. [How?](#enable-whitelist-so-only-a-list-of-people-can-play) | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-whitelist.sh`](scripts/update/plugins/cs2-whitelist.sh); preserves operator-managed `whitelist.txt` |
| [CS2_ExecAfter](https://github.com/kus/CS2_ExecAfter) | `1.0.0` | Executes a command after server event (i.e. OnMapStart) or a delay. | Default CounterStrikeSharp plugin | Script: [`cs2-execafter.sh`](scripts/update/plugins/cs2-execafter.sh) |
| [cs2-advanced-weapon-system](https://github.com/CounterStrike2-Plugins-Archive/cs2-advanced-weapon-system) | `1.11` | An advanced weapon system that gives full control over weapon attributes, dynamic adjustments to weapon behaviour, restrictions and advanced customisation. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-advanced-weapon-system.sh`](scripts/update/plugins/cs2-advanced-weapon-system.sh); updates plugin runtime files without touching its external TOML config. |
| [CS2-Antibait](https://github.com/NeuTroNBZh/CS2-Antibait) | `main@825f83202bdb` | Retake highlight utility; disabled for game-mode-specific activation | Mode-specific payload: `game/csgo/addons/counterstrikesharp/plugins/disabled/Antibait` (kept disabled; game-mode CFG controls loading) | [`cs2-antibait.sh`](scripts/update/plugins/cs2-antibait.sh) |
| [CS2-CustomVotes](https://github.com/imi-tat0r/CS2-CustomVotes) | `1.1.4` | A plugin for Counter-Strike 2 to create custom votes for settings. | Default CounterStrikeSharp plugin | Script: [`cs2-customvotes.sh`](scripts/update/plugins/cs2-customvotes.sh); repairs the main DLL, Shared assembly, `CSSharpUtils.dll` and `.deps.json` as one set; preserves `lang/` |
| [CS2-FixRandomSpawn](https://github.com/qstage/CS2-FixRandomSpawn) | `1.2.0` | Fixes ConVar `mp_randomspawn` for any game mode. | Default CounterStrikeSharp plugin | Script: [`cs2-fixrandomspawn.sh`](scripts/update/plugins/cs2-fixrandomspawn.sh) |
| [CS2-GameModifiers](https://github.com/vinicius-trev/CS2-GameModifiers-Plugin) | `1.0.4` | CS2, but every round is a SURPRISE. Inspiration from [NadeKings video](https://www.youtube.com/watch?v=OQQBUFB56Iw). Fork from [Lewisscrivens](https://github.com/Lewisscrivens/CS2-GameModifiers-Plugin). | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-gamemodifiers.sh`](scripts/update/plugins/cs2-gamemodifiers.sh); preserves operator-owned `ModifierConfig/` and `ConVarModifiers/` presets. |
| [CS2-Gunsmenu](https://github.com/asapverneri/CS2-Gunsmenu) | `main@ec5dbdd99b23` | Player weapon-selection menus; staged under `plugins/disabled/` and automatically source-built; game-mode activation remains in its CFG. | Not installed; no payload staged | [`cs2-gunsmenu.sh`](scripts/update/plugins/cs2-gunsmenu.sh) |
| [CS2-Kill-Plugin](https://github.com/Quantor97/CS2-Kill-Plugin) | `0.2.0` | Player self-action command | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/Kill` | [`cs2-kill-plugin.sh`](scripts/update/plugins/cs2-kill-plugin.sh) |
| [CS2-KillFeedFilter](https://github.com/abnerfs/cs2-killfeed-filter) | `1.0.1` | Killfeed filtering; disabled for game-mode-specific activation | Mode-specific payload: `game/csgo/addons/counterstrikesharp/plugins/disabled/KillFeedFilter` (kept disabled; game-mode CFG controls loading) | [`cs2-killfeedfilter.sh`](scripts/update/plugins/cs2-killfeedfilter.sh) |
| [CS2-MutualScoringPlayers](https://github.com/qstage/CS2-MutualScoringPlayers) | `1.0.3` | Keeps score of kills between players. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-mutualscoringplayers.sh`](scripts/update/plugins/cs2-mutualscoringplayers.sh); preserves local `lang/` |
| [cs2-OneInTheChamber](https://github.com/ShookEagle/cs2-OneInTheChamber) | `1.0.0` | One in the Chamber game mode. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-oneinthechamber.sh`](scripts/update/plugins/cs2-oneinthechamber.sh); updates the disabled plugin folder while leaving game-mode loading unchanged. |
| [CS2-PlayerModelChanger](https://github.com/samyycX/CS2-PlayerModelChanger) | `1.8.6` | A lightweighted counterstrikesharp plugin to change player model. [How?](#model-changer) | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-playermodelchanger.sh`](scripts/update/plugins/cs2-playermodelchanger.sh); preserves local `lang/` and external config |
| [CS2-Playervotes](https://github.com/asapverneri/CS2-Playervotes) | `main@81b4a2bda817` | Player-initiated votes for kick, ban, mute, gag and silence; global plugin | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/Playervotes` | [`cs2-playervotes.sh`](scripts/update/plugins/cs2-playervotes.sh) |
| [CS2-Poor-MapPropAds](https://github.com/Letaryat/CS2-Poor-MapPropAds) | `main@2a1e4ce9e8af` | Wall-mounted prop billboard advertisements; global plugin | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/CS2-Poor-MapPropAds` | [`cs2-poor-mappropads.sh`](scripts/update/plugins/cs2-poor-mappropads.sh) |
| [cs2-quake-sounds](https://github.com/Kandru/cs2-quake-sounds) | `26.08.1` | Quake Sounds on multi kills. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-quake-sounds.sh`](scripts/update/plugins/cs2-quake-sounds.sh) |
| [cs2-ranks](https://github.com/partiusfabaa/cs2-ranks) | `2.0.5.5-recompile` | Persistent ranks and statistics | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/Ranks` | [`cs2-ranks.sh`](scripts/update/plugins/cs2-ranks.sh) |
| [cs2-showdamage](https://github.com/abnerfs/cs2-showdamage) | `1.1.0` | Damage display | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/ShowDamage` | [`cs2-showdamage.sh`](scripts/update/plugins/cs2-showdamage.sh) |
| [CS2-SimpleAdmin](https://github.com/daffyyyy/CS2-SimpleAdmin) | `1.9.1` | Additional administration features | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp` | [`cs2-simpleadmin.sh`](scripts/update/plugins/cs2-simpleadmin.sh) |
| [CS2-StaffList](https://github.com/asapverneri/CS2-StaffList) | `main@07fc28119686` | Lists online staff with hide-from-list controls; global plugin | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/CS2Stafflist` | [`cs2-stafflist.sh`](scripts/update/plugins/cs2-stafflist.sh) |
| [cs2-tags](https://github.com/CounterStrike2-Plugins-Archive/cs2-tags) | `1.15` | Player score/chat tags and the shared TagsApi required by SharpTimer. | Active plugin at `plugins/cs2-tags/`, API at `shared/TagsApi/`, and example config at `configs/plugins/cs2-tags/` | Manifest adapter: [`cs2-tags.sh`](scripts/update/plugins/cs2-tags.sh); only its sample-config folder is allowlisted |
| [CS2-TeamLimiter](https://github.com/Ferks-FK/CS2-TeamLimiter) | `development@b9be93940543` | Team-size limits | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/TeamLimiter` | [`cs2-teamlimiter.sh`](scripts/update/plugins/cs2-teamlimiter.sh) |
| [cs2-TeleportKill](https://github.com/rodopoulos1/cs2-TeleportKill) | `1.0.1` | Instantly teleport to the location of the enemy you kill. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-teleportkill.sh`](scripts/update/plugins/cs2-teleportkill.sh); preserves local `lang/` |
| [CS2-WeaponRestrict](https://github.com/TICHOJEBEC-SK/cs2-WeaponRestrict) | `WeaponRestrict1.5` | Configurable weapon restrictions; not installed and marked manual in the Manifest; not installed and marked manual in the Manifest; not installed and marked manual in the Manifest; not installed and marked manual in the Manifest; not installed and marked manual in the Manifest | Not installed; no payload staged | Manual-only — not installed; no updater by design |
| [CS2-WeaponSpeed](https://github.com/akanora/CS2-WeaponSpeed) | `1.3` | Gives players a speed boost when they fire specified weapons. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2-weaponspeed.sh`](scripts/update/plugins/cs2-weaponspeed.sh); updates the plugin while preserving external operator configuration. |
| [CS2FaceitLevels](https://github.com/Staaar0/cs2-FaceitLevels) | `1.1.5-124` | Native MetaMod plugin for FACEIT scoreboard levels, ELO lookup (`!elo` / `!elos`) and player badges. | Native MetaMod payload: `game/csgo/addons/CS2FaceitLevels/bin` | [`cs2faceitlevels.sh`](scripts/update/plugins/cs2faceitlevels.sh) |
| [CS2Fixes-RampbugFix](https://github.com/Interesting-exe/CS2Fixes-RampbugFix) | `5-1` | Minimizes rampbugs (needs to be enabled via `!settings` [How?](#i-run-a-surfkzbhop-server-and-want-movementunlocker-and-cs2fixes-rampbugfix-permanently-enabled)) | Base native add-on | [`cs2fixes-rampbugfix.sh`](scripts/update/plugins/cs2fixes-rampbugfix.sh) updates Linux/Windows binaries and shared gamedata |
| [CS2FunMatchPlugin](https://github.com/TitaniumLithium/CS2FunMatchPlugin) | `1.1.1` | Random fun mode every round | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2funmatchplugin.sh`](scripts/update/plugins/cs2funmatchplugin.sh); selects the Linux release asset |
| [CS2Rcon](https://github.com/LordFetznschaedl/CS2Rcon) | `1.2.0` | This is a rudimentary implementation of a RCON plugin for CS2 using CounterStrikeSharp as RCON does not work whilst connected to the server | Default CounterStrikeSharp plugin | Script: [`cs2rcon.sh`](scripts/update/plugins/cs2rcon.sh) |
| [CS2UpdateMonitor](https://github.com/beanman109/cs2-updatemonitor) | `1.1.0` | Disabled under `plugins/disabled/`; cs2node owns CS2 build detection and update lifecycle | Mode-specific payload: `game/csgo/addons/counterstrikesharp/plugins/disabled/CS2UpdateMonitor` (kept disabled; game-mode CFG controls loading) | [`cs2updatemonitor.sh`](scripts/update/plugins/cs2updatemonitor.sh) |
| [CS2WarcraftMod](https://github.com/Wngui/CS2WarcraftMod) | `3.3.5` | An open-source Warcraft mod for CS2 featuring a fully-fledged RPG system. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`cs2warcraftmod.sh`](scripts/update/plugins/cs2warcraftmod.sh); preserves local languages and the server-supplied CounterStrikeSharp API. |
| [deathrun-manager](https://github.com/leoskiline/cs2-deathrun-manager) | `0.5.1` | Deathrun Manager for CounterStrikeSharp Framework CS2. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`deathrun-manager.sh`](scripts/update/plugins/deathrun-manager.sh) |
| [GameModeManager](https://github.com/nickj609/GameModeManager) | `2.3.1` | Configurable game modes, settings, map groups and rotations; its release bundles GG1MapChooser, MenuManagerCore, PMM_GG1MapChooser and all three shared APIs. | Default CounterStrikeSharp plugin | Script: [`gamemodemanager.sh`](scripts/update/plugins/gamemodemanager.sh); owns all four bundled plugin folders and all three shared API folders from `addons/counterstrikesharp/`. Copies no `cfg/` or CounterStrikeSharp `configs/` content. |
| [GG1MapChooser](https://github.com/ssypchenko/GG1MapChooser) | `bundled` | `GG1MapChooser` and `ggmcAPI` are shipped and updated only through the GameModeManager bundle. | Default CounterStrikeSharp plugin for RTV and map selection | Bundled with GameModeManager; updated through [`gamemodemanager.sh`](scripts/update/plugins/gamemodemanager.sh). |
| [GunGame](https://github.com/ssypchenko/cs2-gungame) | `1.2.4` | GunGame mode on Counter Strike Sharp | Mode-specific plugin staged under `plugins/disabled/` | Script: [`gungame.sh`](scripts/update/plugins/gungame.sh) |
| [Inventory Simulator](https://github.com/ianlucas/cs2-css-inventory-simulator) | `3.8.1` | Use any Weapon, Knife, Gloves, Agent, Music Kit, Pin or Graffiti. [How?](#skin-changer) | Default CounterStrikeSharp plugin | Script: [`inventory-simulator.sh`](scripts/update/plugins/inventory-simulator.sh) |
| [jRandomSkills](https://github.com/Juzlus/jRandomSkills) | `1.2.4.b7` | CS2, but every round is a SURPRISE. Inspiration from [NadeKings video](https://www.youtube.com/watch?v=OQQBUFB56Iw). | Mode-specific plugin staged under `plugins/disabled/jRandomSkills` | Script: [`jrandomskills.sh`](scripts/update/plugins/jrandomskills.sh); preserves existing `configs/` and `languages/`, updates gamedata separately |
| [K4-Arenas](https://github.com/K4ryuu/K4-Arenas) | `2.0.8` | All in one arena plugin, that you can use to have a ladder type gameplay. Support all map, 2v2/3v3/etc [Database setup](#setup-mysql-database) | Mode-specific plugin staged under `plugins/disabled/` | Script: [`k4-arenas.sh`](scripts/update/plugins/k4-arenas.sh); updates both K4-Arenas and the separately packaged K4-Arenas-Bots companion. |
| [K4-DamageInfo](https://github.com/K4ryuu/K4-DamageInfo) | `2.4.0` | Displays the amount of damage players have inflicted on the victim's HP and Armor, as well as the hit groups they have hit. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`k4-damageinfo.sh`](scripts/update/plugins/k4-damageinfo.sh); preserves local translations and external operator configuration. |
| [MapConfigurator](https://github.com/ManifestManah/MapConfigurator) | `1.0.2` | Allows you to quick and easily create unique configuration files for each map on your server. | Default CounterStrikeSharp plugin | Script: [`mapconfigurator.sh`](scripts/update/plugins/mapconfigurator.sh); future-release adapter only because upstream currently has no GitHub Releases |
| [MatchZy](https://github.com/shobhit-pathak/MatchZy) | `0.9.2` | MatchZy is a plugin for CS2 for running and managing practice/pugs/scrims/matches with easy configuration! | Mode-specific plugin staged under `plugins/disabled/` | Script: [`matchzy.sh`](scripts/update/plugins/matchzy.sh) |
| [MenuManagerCS2](https://github.com/RRimmer/PanoramaMenuManagerCS2) | `bundled` | `MenuManagerCore` and `MenuManagerApi` are shipped and updated only through the GameModeManager bundle. | Bundled component: `MenuManagerCore`; shared API: `MenuManagerApi` | Bundled by GameModeManager; no standalone updater. [`gamemodemanager.sh`](scripts/update/plugins/gamemodemanager.sh) |
| [Metamod:Source](https://github.com/alliedmodders/metamod-source) | `2.0.0-1490` | Sits between the Game and the Engine, and allows plugins to intercept calls that flow between | Base native add-on | Script [`metamod-source.sh`](scripts/update/plugins/metamod-source.sh); manifest also tracks this version |
| [MovementUnlocker](https://github.com/Source2ZE/MovementUnlocker) | `2.0.1` | Removes max speed limitation from players on the ground, feels like CS:S [How?](#i-run-a-surfkzbhop-server-and-want-movementunlocker-and-cs2fixes-rampbugfix-permanently-enabled) | Base native add-on | Script: [`movementunlocker.sh`](scripts/update/plugins/movementunlocker.sh) |
| [MultiAddonManager](https://github.com/Source2ZE/MultiAddonManager) | `1.7.3` | Allows you to use multiple workshop addons at once and have clients download them [How?](#i-want-to-permanently-enable-multi-addon-manager) | Base native add-on | Script: [`multiaddonmanager.sh`](scripts/update/plugins/multiaddonmanager.sh); Pterodactyl Linux updates SteamRT3 `.so` and MetaMod VDF only. |
| [OpenPrefirePrac](https://github.com/lengran/OpenPrefirePrac) | `0.1.47` | Multiple prefire practices on competitive maps and support multiplayer practicing simultaneously. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`openprefireprac.sh`](scripts/update/plugins/openprefireprac.sh); preserves custom map profiles, resources and `default_cfg.json`. |
| [PlayerSettingsCS2](https://github.com/NickFox007/PlayerSettingsCS2) | `0.9.4` | Persistent player settings | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/PlayerSettings` | [`playersettingscs2.sh`](scripts/update/plugins/playersettingscs2.sh) |
| [RollTheDice](https://github.com/Kandru/cs2-roll-the-dice) | `26.10.12` | Roll the dice to get either a positive or negative effect for the current round. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`rollthedice.sh`](scripts/update/plugins/rollthedice.sh) |
| [ServerListPlayersFix](https://github.com/Source2ZE/ServerListPlayersFix) | `2.1` | Fixes players not showing up in the server browser | Base native add-on | Script: [`serverlistplayersfix.sh`](scripts/update/plugins/serverlistplayersfix.sh) |
| [SharpTimer](https://github.com/SharpTimer/SharpTimer) | `0.4.2` | Surf/Bhop/Deathrun timer; staged under `plugins/disabled/SharpTimer` by default. | Mode-specific plugin staged under `plugins/disabled/SharpTimer/` | Manifest adapter: [`sharptimer.sh`](scripts/update/plugins/sharptimer.sh); `cfg/SharpTimer/` remains operator-managed |
| [SimpleAdmin](https://github.com/connercsbn/SimpleAdmin/) | `0.1.2` | Adds basic administrator functions | Default CSS plugin; deliberately retained from KUS | Script: [`simpleadmin.sh`](scripts/update/plugins/simpleadmin.sh); this is separate from the manifest-managed CS2-SimpleAdmin set |
| [SimpleResetScore](https://github.com/stefanx111/cs2-SimpleResetScore) | `1.0.7` | Reset-score command | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/ResetScore` | [`simpleresetscore.sh`](scripts/update/plugins/simpleresetscore.sh) |
| [SLAYER_AntiCamp](https://github.com/zakriamansoor47/SLAYER_AntiCamp) | `1.2.5` | Anti-camp mode | Mode-specific payload: `game/csgo/addons/counterstrikesharp/plugins/disabled/SLAYER_AntiCamp` (kept disabled; game-mode CFG controls loading) | [`slayer-anticamp.sh`](scripts/update/plugins/slayer-anticamp.sh) |
| [SLAYER_Football](https://github.com/zakriamansoor47/SLAYER_Football) | `1.1` | Football in CS2. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`slayer-football.sh`](scripts/update/plugins/slayer-football.sh); updates only the plugin folder and preserves `lang/` |
| [SLAYER_HeadshotOnly](https://github.com/zakriamansoor47/SLAYER_HeadshotOnly) | `1.2.1` | Headshot-only mode | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/SLAYER_HeadshotOnly` | [`slayer-headshotonly.sh`](scripts/update/plugins/slayer-headshotonly.sh) |
| [SLAYER_Noscope](https://github.com/zakriamansoor47/SLAYER_Noscope) | `main@d0987f393485` | Noscope rules and commands; global plugin | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/SLAYER_Noscope` | [`slayer-noscope.sh`](scripts/update/plugins/slayer-noscope.sh) |
| [SLAYER_Revive](https://github.com/zakriamansoor47/SLAYER_Revive) | `1.3.2` | Revive Your Teammates. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`slayer-revive.sh`](scripts/update/plugins/slayer-revive.sh); preserves operator-managed `SLAYER_Revive.json` |
| [SpectatorList-CS2](https://github.com/srwiruwiru/SpectatorList-CS2) | `16` | Shows real-time spectators in on-screen display. | Mode-specific plugin staged under `plugins/disabled/` | Script: [`spectatorlist-cs2.sh`](scripts/update/plugins/spectatorlist-cs2.sh); preserves local `lang/` |
| [STFixes](https://github.com/rcnoob/STFixes) | `1.0.5` | A CounterStrikeSharp plugin with common fixes and features for SharpTimer servers | Mode-specific plugin staged under `plugins/disabled/` | Script: [`stfixes.sh`](scripts/update/plugins/stfixes.sh); upstream currently marks the project archived |
| [VIPCore](https://github.com/partiusfabaa/cs2-VIPCore) | `2.0.3` | VIP framework and shared API; local VIPCore configuration is preserved. | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/VIPCore` | [`vipcore.sh`](scripts/update/plugins/vipcore.sh) |
| [VIPCore Modules](https://github.com/partiusfabaa/cs2-VIPCore) | `2.0.3-modules-1` | VIP feature modules; tracks incremental module releases and repairs missing modules from a full package. | 45 module folders under `plugins/VIP_*` and `plugins/disabled/` | [`vipcore-modules.sh`](scripts/update/plugins/vipcore-modules.sh) |
| [WeaponPaints](https://github.com/Nereziel/cs2-WeaponPaints) | `472` | Player-side weapon customization | Plugin/runtime payload: `game/csgo/addons/counterstrikesharp/plugins/WeaponPaints` | [`weaponpaints.sh`](scripts/update/plugins/weaponpaints.sh) |

> [!NOTE]
> `CS2-WeaponRestrict` is intentionally not installed or staged, so it remains manual-only. `MenuManagerCS2` and `GG1MapChooser` are bundled with GameModeManager and are updated through its adapter. A plugin being stored under `plugins/disabled/` controls loading only; it does not disable update automation.

## Project provenance and license

The base server project is [kus/cs2-modded-server](https://github.com/kus/cs2-modded-server). This repository carries a downstream integrated payload and its own automation/configuration; it is not an official KUS release. The upstream KUS license is retained in [LICENSE](LICENSE), and each third-party plugin remains subject to its own license.
