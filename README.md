# CS2 KUS Addons — Larnz Unified Server

A private, single-repository Counter-Strike 2 dedicated-server distribution. It combines the KUS server setup, its bundled plugins and dependency files with the Larnz-managed add-ons and configuration layout.

**The repository's canonical runtime path is server/game/csgo/.** The old KUS staging path, game/csgo/, is not used as a second source tree. KUS runtime payloads—including its Windows-specific add-on payload—are imported directly into the canonical path. There is no second KUS checkout and no batch step that copies all plugins from a staging folder into the server.

This README combines Larnz's manifest-managed add-ons with KUS's base plugins, game modes, configuration guidance, workshop-map catalog and troubleshooting notes. Historical source documents remain under `docs/upstream/`; where an archived guide differs from this file, the unified instructions here take precedence. The old dual-repository workflow in `docs/Larnz-Addons-README.md` is historical, not an active setup guide.

## Repository ownership and paths

| Path | Purpose |
| --- | --- |
| server/ | Canonical SteamCMD installation root. The large downloaded game binaries remain local and are not committed. |
| server/game/csgo/addons/ | KUS and Larnz plugin payloads in their final runtime locations. |
| server/game/csgo/cfg/ | Runtime configuration tree. Existing Larnz settings are preserved during KUS imports. |
| DEPENDENCIES.json | Larnz add-on updater manifest. |
| scripts/update/ | Imported upstream KUS helpers; treat as legacy until the Linux updater is migrated. |
| examples/run-template/ | Reusable Windows runner and VBS supervisor template. |
| docs/upstream/ | KUS source snapshot metadata and archived upstream entrypoints/workflows. |

The upstream `custom_files/` and `custom_files_example/` trees are intentionally not imported. On Windows, use the external per-instance override directory selected by `CUSTOM_FOLDER` in `examples/run-template/instance.ini`. Never store tokens, passwords or private database credentials in tracked files.

## Windows installation and operation

1. Clone this private repository to the Windows server machine with GitHub access.
2. Run `install.bat`. It downloads SteamCMD if needed, installs CS2 only when the required game files are missing, then calls `win.bat` to patch and validate the installation. It does not start the server.
3. Copy `examples/run-template/instance.example.ini` to `examples/run-template/instance.ini`, set the instance options and secrets, then start `run.vbs` (hidden) or `run.bat` (visible console).

**Windows command responsibilities are intentionally separate:**

- `win.bat` patches `gameinfo.gi` idempotently and verifies the managed files. It does not pull Git, run SteamCMD, copy a staging tree, or launch the server.
- `update.bat` only performs a fast-forward-only Git pull and then validates the installation. It refuses local/untracked changes.
- `game-update.bat` explicitly updates the CS2 game with SteamCMD. Stop every CS2 instance first.
- `addons-update.bat -DryRun` previews Larnz-managed release updates; `addons-update.bat` applies them. This updater preserves fixed config paths and commits each successful add-on update.
- A server restart through `run.bat`/`run.vbs` does not implicitly update Git, the CS2 game, or releases.

## Larnz-managed add-ons

These add-ons are maintained by the Larnz manifest/updater in addition to the KUS payloads. Some libraries are shared dependencies and remain separate from the KUS documentation's own plugin table.

| Add-on | Version | Purpose |
| --- | --- | --- |
| CounterStrikeSharp | 1.0.376 | Installed from the Windows **with-runtime** release; the bundled .NET runtime is kept under `addons/counterstrikesharp/dotnet/`. |
| CS2UpdateMonitor | 1.1.0 | Detects a new game build and signals the external supervisor |
| WeaponPaints | 466 | Player-side weapon customization |
| CS2-SimpleAdmin | 1.9.0 | Additional administration features |
| AFKManager | 0.2.8 | AFK handling |
| CS2-Kill-Plugin | 0.2.0 | Player self-action command |
| SimpleResetScore | 1.0.7 | Reset-score command |
| cs2-showdamage | 1.1.0 | Damage display |
| cs2-ranks | v2.0.5.5-recompile | Persistent ranks and statistics |
| VIPCore | v1.3.4-recompile3 | VIP core/module |
| AnyBaseLibCS2 | 0.9.4 | Shared database/API library |
| PlayerSettingsCS2 | 0.9.4 | Persistent player settings |
| MenuManagerCS2 | 1.4.1 | Menu/API library |
| SLAYER_AntiCamp | 1.2.5 | Anti-camp mode |
| SLAYER_HeadshotOnly | 1.2.1 | Headshot-only mode |
| CS2-TeamLimiter | — | Team-size limits |
| CS2-WeaponRestrict | WeaponRestrict1.5 | Configurable weapon restrictions; marked manual in the Larnz manifest |

## Larnz plugin dependencies

- CounterStrikeSharp provides the runtime required by the managed CounterStrikeSharp plugins.
- AnyBaseLibCS2, PlayerSettingsCS2 and MenuManagerCS2 provide shared APIs used by dependent plugins.
- The release updater keeps the manifest, versions and runtime file layout synchronized. Fixed configuration paths are deliberately protected from incoming add-on release archives.

## Project provenance

The base project is [kus/cs2-modded-server](https://github.com/kus/cs2-modded-server). This private integrated distribution is not an official KUS release. The upstream LGPL-3.0 license is retained in `LICENSE`; each third-party plugin remains subject to its own license. Original KUS notes and installer workflows are archived in `docs/upstream/` for provenance, not as active installation instructions.

## Quick navigation

- [Windows setup and maintenance](#running-on-windows)
- [Server capabilities and game modes](#server-capabilities-and-game-modes)
- [KUS bundled plugin catalog](#kus-bundled-and-optional-plugin-catalog)
- [Update responsibilities](#updating-the-integrated-repository-and-add-ons)
- [Configuration and per-instance overrides](#configuration-and-per-instance-overrides)
- [Online, LAN and server settings](#creating-an-online-server)
- [Workshop maps and map groups](#playing-workshop-mapscollections)
- [Deployment status for all platforms](#deployment-status)
- [FAQ and troubleshooting](#faq)

## Compatibility after CS2 updates

> [!IMPORTANT]
> **Are we broken?**
>
> If there has been a recent big CS2 update and your server is broken. We need to wait for the community to update their signatures and mods.
> This isn't a quick process. Valve gives no notice. People do this in their free time.
>
> If you go [here](https://github.com/ianlucas/cs2-signatures) and **CounterStrikeSharp** does not have two green ticks it's likely your server will not work and you need to wait for an update. Please do not make an issue, there is literally nothing I can do.

If you are looking for the CS:GO version you can still access that [here](https://github.com/kus/csgo-modded-server/tree/csgo).

## Server capabilities and game modes

A single modded Counter-Strike 2 (CS2) Modded Dedicated Server that you can [change the active mod](#changing-game-modes) on the server from chat or server console. [Maps are preconfigured per game mode](#what-maps-are-preconfigured-with-each-mode) and change when the game mode changes.

Each game mode has a hand full of maps preset so you are ready to go and it's [easy to add more](#setting-maps-for-different-game-modes).

- Competitive (using [MatchZy](https://github.com/shobhit-pathak/MatchZy#usage-commands))
- Practice (record grenade throws etc) (using [MatchZy](https://github.com/shobhit-pathak/MatchZy#usage-commands))
- Wingman (allows more than 4 players) ([Steam API key](#playing-workshop-mapscollections) required)
- GunGame ([Steam API key](#playing-workshop-mapscollections) required)
- Custom Deathmatch ([Steam API key](#playing-workshop-mapscollections) required)
- Prefire practice
- Retakes
- Executes
- [Capture The Flag](https://www.youtube.com/watch?v=d9Vo8waxBzA) ([Steam API key](#playing-workshop-mapscollections) required)
- One In The Chamber
- 1v1 (with arenas) ([Steam API key](#playing-workshop-mapscollections) required)
- ScoutzKnivez ([Steam API key](#playing-workshop-mapscollections) required)
- KZ ([Steam API key](#playing-workshop-mapscollections) required)
- BHop ([Steam API key](#playing-workshop-mapscollections) required)
- Surf ([Steam API key](#playing-workshop-mapscollections) required)
- Mini Games ([Steam API key](#playing-workshop-mapscollections) required)
- Deathrun ([Steam API key](#playing-workshop-mapscollections) required)
- Course format (tests players with different traps, kz, surf, bhop) ([Steam API key](#playing-workshop-mapscollections) required)
- Hide n Seek ([Steam API key](#playing-workshop-mapscollections) required)
- Battle Royale ([Steam API key](#playing-workshop-mapscollections) required)
- [Soccer](https://www.youtube.com/watch?v=yfltZoMH2Ts) ([Steam API key](#playing-workshop-mapscollections) required)
- Battle Ball ([Steam API key](#playing-workshop-mapscollections) required)

You can also enable modifiers in game modes from the `!settings` menu in chat i.e. Competitive with random rounds like [NadeKings video](https://www.youtube.com/watch?v=OQQBUFB56Iw).

- [Random Rounds](https://www.youtube.com/watch?v=OQQBUFB56Iw) - CS2, but every round is a SURPRISE.
- [WarcraftMod](https://www.youtube.com/watch?v=Z9HdF47zPss) - An open-source Warcraft mod for CS2 featuring a fully-fledged RPG system.
- Roll The Dice - Roll the dice to get either a positive or negative effect for the current round.
- Bunny hopping

> [!IMPORTANT]
> Using RCON whilst connected to the server does not work. See discussion [here](https://www.reddit.com/r/GlobalOffensive/comments/167spzi/cs2_rcon/).
> The current work arounds are:
>
> - I have included [CS2Rcon](https://github.com/LordFetznschaedl/CS2Rcon) which allows admins to use !rcon in chat.
> - You can disconnect from the server and use `rcon_address IP:PORT` in console and you can use rcon commands.
> - Use an external RCON program which has implemented the RCON protocol such as [this](https://github.com/fpaezf/CS2-RCON-Tool-V2).

## First-start verification

After the server is running, use the server console to check `meta list` for Metamod and the expected native plugins, then run `css_plugins list` to inspect CounterStrikeSharp plugins. CounterStrikeSharp should load with its bundled .NET runtime; the CI validation checks the runtime files but does not replace a real server-load smoke test.

The list below records the KUS catalog when this runtime snapshot was imported. These version labels are reference metadata, not a promise that every optional module is enabled or current. CounterStrikeSharp is intentionally documented only in the Larnz-managed table above: this branch installs the Windows **with-runtime** archive and rejects the no-runtime asset. The KUS SimpleAdmin and the Larnz-managed CS2-SimpleAdmin are distinct projects and are kept separately.

## KUS bundled and optional plugin catalog

Mod | Version in the upstream snapshot | Purpose
--- | --- | ---
[Metamod:Source](https://www.metamodsource.net/downloads.php?branch=dev) | `2.0.0-1473` | Sits between the Game and the Engine, and allows plugins to intercept calls that flow between
[MultiAddonManager](https://github.com/Source2ZE/MultiAddonManager) | `1.6.2` | Allows you to use multiple workshop addons at once and have clients download them [How?](#i-want-to-permanently-enable-multi-addon-manager)
[ServerListPlayersFix](https://github.com/Source2ZE/ServerListPlayersFix) | `2.0` | Fixes players not showing up in the server browser
[MovementUnlocker](https://github.com/Source2ZE/MovementUnlocker) | `2.0.1` | Removes max speed limitation from players on the ground, feels like CS:S [How?](#i-run-a-surfkzbhop-server-and-want-movementunlocker-and-cs2fixes-rampbugfix-permanently-enabled)
[CS2Fixes-RampbugFix](https://github.com/Interesting-exe/CS2Fixes-RampbugFix) | `5-1` | Minimizes rampbugs (needs to be enabled via `!settings` [How?](#i-run-a-surfkzbhop-server-and-want-movementunlocker-and-cs2fixes-rampbugfix-permanently-enabled))
[CS2_ExecAfter](https://github.com/kus/CS2_ExecAfter) | `1.0.0` | Executes a command after server event (i.e. OnMapStart) or a delay.
[CS2 Remove Map Weapons](https://github.com/kus/CS2-Remove-Map-Weapons) | `1.0.1` | Remove weapons from the map in CS2 as `mp_weapons_allow_map_placed 0` does not work.
[GameModeManager](https://github.com/nickj609/GameModeManager) | `1.0.62` | <div style="background-color: #fff3cd; padding: 8px; border-left: 4px solid #ffc107;">⚠️ Waiting for fix</div> A simple Counter-Strike 2 server plugin that helps admins manage game modes and map groups.
[Inventory Simulator](https://github.com/ianlucas/cs2-css-inventory-simulator) | `3.5.0` | Use any Weapon, Knife, Gloves, Agent, Music Kit, Pin or Graffiti. [How?](#skin-changer)
[CS2-PlayerModelChanger](https://github.com/samyycX/CS2-PlayerModelChanger) | `1.8.6` | A lightweighted counterstrikesharp plugin to change player model. [How?](#model-changer)
[MatchZy](https://github.com/shobhit-pathak/MatchZy) | `0.9.1` | MatchZy is a plugin for CS2 for running and managing practice/pugs/scrims/matches with easy configuration!
[MapConfigurator](https://github.com/ManifestManah/MapConfigurator) | `1.0.2` | Allows you to quick and easily create unique configuration files for each map on your server.
[K4-DamageInfo](https://github.com/KitsuneLab-Development/K4-DamageInfo) | `2.4.0` | Displays the amount of damage players have inflicted on the victim's HP and Armor, as well as the hit groups they have hit.
[SimpleAdmin](https://github.com/connercsbn/SimpleAdmin/) | `0.1.2` | Adds basic administrator functions
[CS2Rcon](https://github.com/LordFetznschaedl/CS2Rcon) | `1.2.0` | This is a rudimentary implementation of a RCON plugin for CS2 using CounterStrikeSharp as RCON does not work whilst connected to the server
[SharpTimer](https://github.com/Letaryat/poor-sharptimer) | `0.4.0` | SharpTimer is a simple Surf/KZ/Bhop/MG/Deathrun/etc CS2 Timer plugin
[STFixes](https://github.com/rcnoob/STFixes) | `1.0.5` | A CounterStrikeSharp plugin with common fixes and features for SharpTimer servers
[GunGame](https://github.com/ssypchenko/cs2-gungame) | `1.2.4` | GunGame mode on Counter Strike Sharp
[K4-Arenas](https://github.com/KitsuneLab-Development/K4-Arenas) | `2.0.8` | All in one arena plugin, that you can use to have a ladder type gameplay. Support all map, 2v2/3v3/etc [Database setup](#setup-mysql-database)
[CS2 Retakes](https://github.com/B3none/cs2-retakes) | `3.1.1` | CS2 implementation of retakes. Based on the version for CS:GO by Splewis.
[CS2 Instadefuse](https://github.com/B3none/cs2-instadefuse) | `2.0.0` | Allows a CT to instantly defuse the bomb when nothing can prevent defusal. Written in C# for CounterStrikeSharp.
[CS2 Retakes Allocator](https://github.com/yonilerner/cs2-retakes-allocator) | `2.4.2` | Advanced weapon allocation for B3none/cs2-retakes
[CS2 Whitelist](https://github.com/PhantomYopta/CS2_WhiteList) | `1.0.0`| Restricts access to the server for SteamID members/employees listed in the whitelist. [How?](#enable-whitelist-so-only-a-list-of-people-can-play)
[CS2 Executes](https://github.com/zwolof/cs2-executes) | `1.1.1` | CS2 implementation of executes. Based on the version for CS:GO by Splewis.
[CS2 Advertisement](https://github.com/partiusfabaa/cs2-advertisement) | `1.0.8-recompile` | Allows you to show ads in chat/center/panel. [How?](#enable-advertisements)
[CS2 Deathmatch](https://github.com/NockyCZ/CS2-Deathmatch) | `1.3.5` | Custom Deathmatch CS2 plugin (Includes custom spawnpoints, multicfg, gun selection, spawn protection, etc)
[OpenPrefirePrac](https://github.com/lengran/OpenPrefirePrac) | `0.1.47` | Multiple prefire practices on competitive maps and support multiplayer practicing simultaneously.
[CS2-CustomVotes](https://github.com/imi-tat0r/CS2-CustomVotes) | `1.1.3` | A plugin for Counter-Strike 2 to create custom votes for settings.
[deathrun-manager](https://github.com/leoskiline/cs2-deathrun-manager) | `0.5.1` | Deathrun Manager for CounterStrikeSharp Framework CS2.
[AnnouncementBroadcaster](https://github.com/lengran/CS2AnnouncementBroadcaster) | `0.5` | Conditional messages, OnCommand, OnPlayerConnect, OnRoundStart, and TimerMsgs.
[CS2-GameModifiers](https://github.com/vinicius-trev/CS2-GameModifiers-Plugin) | `1.0.4` | CS2, but every round is a SURPRISE. Inspiration from [NadeKings video](https://www.youtube.com/watch?v=OQQBUFB56Iw). Fork from [Lewisscrivens](https://github.com/Lewisscrivens/CS2-GameModifiers-Plugin).
[CS2FunMatchPlugin](https://github.com/TitaniumLithium/CS2FunMatchPlugin) | `1.1.1` | Random fun mode every round
[RollTheDice](https://github.com/Kandru/cs2-roll-the-dice) | `26.07.1` | Roll the dice to get either a positive or negative effect for the current round.
[CS2-FixRandomSpawn](https://github.com/qstage/CS2-FixRandomSpawn) | `1.1.4.1` | Fixes ConVar `mp_randomspawn` for any game mode.
[CS2-MutualScoringPlayers](https://github.com/qstage/CS2-MutualScoringPlayers) | `1.0.3` | Keeps score of kills between players.
[CS2WarcraftMod](https://github.com/Wngui/CS2WarcraftMod) | `3.3.5` | An open-source Warcraft mod for CS2 featuring a fully-fledged RPG system.
[cs2-advanced-weapon-system](https://github.com/schwarper/cs2-advanced-weapon-system) | `1.11` | An advanced weapon system that gives full control over weapon attributes, dynamic adjustments to weapon behaviour, restrictions and advanced customisation.
[cs2-OneInTheChamber](https://github.com/ShookEagle/cs2-OneInTheChamber) | `1.0.0` | One in the Chamber game mode.
[cs2-quake-sounds](https://github.com/Kandru/cs2-quake-sounds) | `26.08.1` | Quake Sounds on multi kills.
[CS2-WeaponSpeed](https://github.com/akanora/CS2-WeaponSpeed) | `1.3` | Gives players a speed boost when they fire specified weapons.
[SpectatorList-CS2](https://github.com/wiruwiru/SpectatorList-CS2) | `16` | Shows real-time spectators in on-screen display.
[SLAYER_Football](https://github.com/zakriamansoor47/SLAYER_Football) | `1.1` | Football in CS2.
[SLAYER_Revive](https://github.com/zakriamansoor47/SLAYER_Revive) | `1.3.2` | Revive Your Teammates.
[cs2-TeleportKill](https://github.com/rodopoulos1/cs2-TeleportKill) | `1.0.1` |  Instantly teleport to the location of the enemy you kill.
[CS2-BotAI](https://github.com/Austinbots/CS2-BotAI) | `1.0` | Improves the built in bots AI and also makes them run with a gun intead of a knife or nade.

## Updating the integrated repository and add-ons

There are three independent update operations. Keep them separate so a routine Git update cannot unexpectedly change the CS2 game build or download plugin releases.

| Operation | Command | What it changes |
| --- | --- | --- |
| Update tracked KUS + Larnz files | `update.bat` | Fast-forward-only pull of this private repository, followed by validation. It refuses a dirty working tree. |
| Update the CS2 game | `game-update.bat` | Runs SteamCMD for app 730. Stop all CS2 instances first. |
| Update Larnz-managed add-ons | `addons-update.bat -DryRun`, then `addons-update.bat` | Resolves release assets from `DEPENDENCIES.json`, maps files into `server/game/csgo/`, verifies required paths and commits successful add-on updates. |

Use `addons-inspect.bat -Only CounterStrikeSharp` to inspect an upstream release archive without installing it. The CounterStrikeSharp rule in `DEPENDENCIES.json` requires `counterstrikesharp-with-runtime-windows-{version}.zip`; the updater refuses a no-runtime asset. Its post-install verification checks both the API/plugin files and versioned .NET runtime files.

KUS base plugins that are not listed as automated add-ons remain tracked at their final runtime paths and arrive through Git updates. Do not run the old KUS Bash release updater on Windows or treat it as the authority for the Larnz manifest. Its historical notes remain available in `docs/upstream/KUS-README.md`.

A normal server start does not run Git, SteamCMD, or the add-on release updater. Stop the supervisor and server before changing runtime files.

## Share the love

If you appreciate the project then please take the time to star the repository 🙏

<img alt="Star the project" src="https://github.com/kus/cs2-modded-server/blob/assets/assets/star.png?raw=true&sanitize=true">

## Stay up to date

Subscribe to release notifications and stay up to date with the latest features and patches:

<img alt="Subscribe to updates" src="https://github.com/kus/cs2-modded-server/blob/assets/assets/watch.png?raw=true&sanitize=true">

## Configuration and per-instance overrides

This unified repository deliberately does **not** use the upstream KUS `custom_files/` or `custom_files_example/` overlay. Those directories and the old startup-time rebuild workflow were not imported.

### Shared configuration

The canonical shared files are already stored at their final runtime locations:

- `server/game/csgo/cfg/` — server and game-mode configuration.
- `server/game/csgo/addons/counterstrikesharp/configs/` — CounterStrikeSharp admins, groups and plugin configuration.
- `server/game/csgo/gamemodes_server.txt` and `server/game/csgo/subscribed_file_ids.txt` — shared map-group and Workshop subscription configuration when those files exist in the runtime tree.

Changes made directly to tracked files become local Git changes. Commit them intentionally if they should be part of this private repo. `update.bat` refuses to pull when local or untracked changes exist, rather than silently overwriting your work.

### Per-instance overrides on Windows

The Windows runner can apply optional `cfg/` and `addons/` overrides before it launches CS2. Set `CUSTOM_FOLDER` in `examples/run-template/instance.ini` to a directory containing these subfolders. For private settings, prefer an absolute path outside the repository, for example:

```text
D:\CS2-private\aim\
├── cfg\
│   └── custom_all.cfg
└── addons\
    └── counterstrikesharp\
        └── configs\
            └── admins.json
```

The runner copies the override folder's `cfg/` into `server/game/csgo/cfg/` and its `addons/` into `server/game/csgo/addons/`. This is an additive/overwrite copy: it does not delete runtime files. Because the override is applied at startup, it can be used to keep one instance's hostname, admins, RCON-related config, plugin settings or game-mode configuration separate from the shared tracked files.

For example, to add admins for one instance, copy the current `server/game/csgo/addons/counterstrikesharp/configs/admins.json` to:

```text
<CUSTOM_FOLDER>\addons\counterstrikesharp\configs\admins.json
```

Edit that private copy and restart the instance. For a shared admin list, edit the canonical runtime file and commit the change instead. A KUS example config may be helpful as a reference, but inspect it before using it because this unified branch's installed plugins and versions may differ.

To change settings for one game mode, put a relevant override in `<CUSTOM_FOLDER>/cfg/` (for example `custom_dm.cfg`) and ensure the mode's config executes it. Files such as `gamemodes_server.txt` and `subscribed_file_ids.txt` are root-level files, not children of `cfg/` or `addons/`; the current runner does not overlay root-level files, so edit those at their canonical path and track the change.

### Plugin-generated configuration files

The current unified Windows runner no longer rebuilds the entire `addons/` tree on every start. A file created by a plugin is not automatically deleted by that runner. For a persistent, instance-specific override, put a same-path file under `<CUSTOM_FOLDER>/addons/`; for a shared setting, use the canonical configuration path. The add-on updater also protects `cfg/` and CounterStrikeSharp's `configs/` from incoming release archives.

**Do not commit real secrets.** Keep `instance.ini`, API keys, Game Server Login Tokens, RCON passwords and database credentials out of tracked files.

## Creating an online server

For a public server, create a Steam [Game Server Login Token](https://steamcommunity.com/dev/managegameservers) and store it in the private `STEAM_ACCOUNT` field of `examples/run-template/instance.ini`. The Windows runner passes that value to CS2 only when non-empty.

Create a [Steam Web API key](https://steamcommunity.com/dev/apikey) and set `API_KEY` in the same private INI if the server needs to download Workshop content. Set `IP` to the reachable public address if the server needs an explicit advertised address; `BIND_IP=0.0.0.0` controls the local listen address.

Allow the selected game port (default `27085` in the current example INI) through Windows Firewall and your router/cloud firewall. Use the same port when connecting from the internet. Keep the Game Server Login Token, API key and RCON password private.

## Creating a LAN server

For a LAN-only Windows instance, set `LAN=1` in `examples/run-template/instance.ini`. You can leave `STEAM_ACCOUNT` empty for a private LAN server unless your intended server registration setup requires otherwise.

If the LAN server needs Workshop downloads, set `API_KEY` in the private INI. Ensure the host firewall allows the selected port from the local network.

## Windows runner settings

The active Windows runner reads `examples/run-template/instance.ini`, not environment variables and not `win.ini`. Copy `instance.example.ini` to `instance.ini`; the latter is excluded by Git.

| Setting | Example default | Purpose |
| --- | --- | --- |
| `SERVER_DIR` | `..\..\server` | Path to the SteamCMD game installation, relative to the template folder or absolute. |
| `IP` | empty | Optional public address passed as `+net_public_adr`. |
| `BIND_IP` | `0.0.0.0` | Local listen address. |
| `CUSTOM_FOLDER` | `aim` | Optional folder whose `cfg/` and `addons/` are overlaid before launch; use a private external path for secrets and local configs. |
| `PORT` | `27085` | Player connection port in the current example. |
| `TICKRATE` | `128` | Requested tickrate in the example; use a value supported by the installed server and plugins. |
| `MAXPLAYERS` | `64` | Maximum player count in the current example. |
| `LAN` | `0` | `0` for public/internet mode; `1` for LAN-only mode. |
| `STEAM_ACCOUNT` | empty | Game Server Login Token; required for normal public-server registration. |
| `API_KEY` | empty | Optional Steam Web API key for Workshop operations. |
| `SERVER_PASSWORD` | empty | Optional join password. |
| `RCON_PASSWORD` | placeholder | Replace with a strong private value before exposing the server. |
| `EXEC` | `aim.cfg` | Config file requested at launch. |
| `MAPGROUP` | `mg_aim` | Map group requested at launch. |
| `MAP` | `de_mirage` | Initial map requested at launch. |
| `WORKSHOP_COLLECTION` | empty | Optional Workshop collection ID. |

`run.bat` / `run.vbs` only starts and supervises the server process and applies per-instance `cfg/` and `addons/` overrides. These scripts do not pull Git, update the game or fetch new add-on releases. Linux and Google Cloud environment-variable settings have not yet been migrated to the unified layout; the old KUS `gcp.sh` and `install.sh` examples are not active instructions for this branch.

## Playing workshop maps/collections

To download maps from the Workshop, the server needs a Steam Web API key. Generate one [here](https://steamcommunity.com/dev/apikey) and put it in the private `API_KEY` field of `examples/run-template/instance.ini`. For a Workshop collection, set its ID in `WORKSHOP_COLLECTION`.

The console command for hosting a workshop map is `host_workshop_map fileid` where `fileid` is the number that comes after `?id=` in the workshop URL for example: [https://steamcommunity.com/sharedfiles/filedetails/?id=2433686680](https://steamcommunity.com/sharedfiles/filedetails/?id=2433686680)

The console command for hosting a workshop collection is `host_workshop_collection collectionid` where `collectionid` is the number that comes after `?id=` in the workshop URL for example: [https://steamcommunity.com/sharedfiles/filedetails/?id=1092904694](https://steamcommunity.com/sharedfiles/filedetails/?id=1092904694). This command will then download all maps in the collection and create a mapgroup out of them, then host it.

## Setting maps for different game modes

Add your maps by editing the tracked `server/game/csgo/gamemodes_server.txt` and selecting the relevant mode's map group. Most gamemodes fall under casual, but this distribution has unique groups so you can maintain each mode independently. The current Windows runner overlays only `cfg/` and `addons/`; it does not copy root-level files such as `gamemodes_server.txt`.

For Workshop maps, add their file IDs to the canonical `server/game/csgo/subscribed_file_ids.txt` when that file is used by your setup. Commit shared changes to this private repo so they can be reproduced on a clean checkout.

If you have python available, you can use our tool available to add a map to your custom game mode map groups: `python scripts/add-map.py <group_name> <map_name> [workshop_id] --custom`. Refer to `scripts/add-map.py` for more information.

## Deployment status

The unified and CI-verified deployment path currently targets Windows. The original KUS setup guide covered Linux, Google Cloud, Docker and Kubernetes, but those entrypoints have not yet been migrated to the single-repository runtime. The active runtime path is still `server/game/csgo/`; the limitation is the platform bootstrap/update scripts, not the tracked plugin tree.

### Running on Google Cloud

Provisioning and managing a Google Cloud VM is still possible, but the integrated repository's GCP bootstrap has not yet been completed. Do not use the archived startup command that downloads `gcp.sh` from the public KUS repository: that script belongs to the former separate-repository workflow and may not operate on this private tree.

When GCP support is migrated, this section will document the VM image, disk, firewall, metadata/secrets and game update handoff. For historical VM lifecycle commands, see [the archived KUS guide](docs/upstream/KUS-README.md#running-on-google-cloud); treat it as reference only.

### Running on Linux

The unified Linux install/start/update workflow has not yet been completed and verified. The imported `install.sh`, `gcp.sh` and shell updater helpers still originate from the KUS workflow and should not be treated as the active install path for this branch.

The canonical runtime directory remains `server/game/csgo/`. See [the archived Linux guide](docs/upstream/KUS-README.md#running-on-linux) for context only; do not run its raw-GitHub installer commands against this integrated checkout.

### Running in Docker

The upstream Docker examples still assume the original KUS image and override mount structure. The Docker build, persistent `server/` storage and update lifecycle have not yet been migrated and verified for this repo, so the old Docker command examples are not presented as working commands here.

The historical KUS container notes remain in [the archived Docker guide](docs/upstream/KUS-README.md#running-in-docker). The unified Docker instructions will be added when the image entrypoint consumes this repository's canonical runtime tree directly.

### Running in Kubernetes

Kubernetes deployment is not currently maintained for the unified distribution. The upstream manifest uses the previous container and `custom_files` layout; do not apply it directly to this branch. Consult [the archived Kubernetes notes](docs/upstream/KUS-README.md#running-in-kubernetes) for provenance only.

## Running on Windows

Use a Windows x64 server with Git installed and at least 60 GB of free disk space. This is a private repository, so authenticate to GitHub before cloning it.

### 1. Clone and install

```bat
git clone --branch integration/kus-monorepo https://github.com/larnzs/cs2-kus-addons.git
cd cs2-kus-addons
install.bat
```

`install.bat` downloads SteamCMD if needed and installs CS2 into `server/\` only when the game executable or Steam app manifest is missing. It then calls `win.bat` to patch `gameinfo.gi` and verify the managed runtime files. It does not start the server.

### 2. Configure and run an instance

Copy `examples/run-template/instance.example.ini` to `examples/run-template/instance.ini`. Edit the port, map/map group, reachable public IP (optional), Game Server Login Token, and a strong RCON password. Keep `instance.ini` private; it is excluded from Git.

Launch `examples/run-template/run.vbs` for hidden operation or `run.bat` for a visible console. The runner uses `server/game/csgo/` and can apply optional per-instance `cfg/` and `addons/` overrides from the configured local folder. It does not update anything automatically.

### Maintenance commands

| Command | Responsibility |
| --- | --- |
| `win.bat` | Idempotently adds the Metamod entry if needed and verifies installed files; does not start CS2. |
| `update.bat` | Fast-forward-only pull of the private Git repository, then validation. Requires a clean working tree. |
| `game-update.bat` | Explicit SteamCMD update of CS2; refuses to run while a `cs2.exe` process is detected. |
| `addons-update.bat -DryRun` | Preview Larnz-managed add-on release updates without writing files. |
| `addons-update.bat` | Apply add-on release updates; successful updates are committed separately. |
| `addons-inspect.bat` | Inspect upstream release assets and resolved archive layouts without installing them. |

These are separate operations by design: Git updates do not update the game, game updates do not update plugin releases, and a server start does not implicitly run any updater. Stop the supervisor and all server instances before updating the game.

Allow the selected game port through Windows Firewall and the router/cloud firewall. Use a valid Game Server Login Token for a public server. Keep API keys, login tokens, RCON passwords, and instance-specific settings out of tracked files.

## FAQ

### Player commands

#### !rtv

Players can start a vote to change the map in the current mod by typing `!rtv` in chat.

<img alt="Vote to change map" src="https://github.com/kus/cs2-modded-server/blob/assets/assets/rtv.png?raw=true&sanitize=true">

#### !gamemode

Players can start a vote to change the game mode by typing `!gamemode` in chat.

<img alt="Vote to change game mode" src="https://github.com/kus/cs2-modded-server/blob/assets/assets/vote-gamemode.png?raw=true&sanitize=true">

You can also start a specific game mode vote by typing `!comp`, `!wingman`, `!dm`, `!gg`, `!1v1`, `!awp`, `!aim`, `!prefire`, `!executes`, `!retake`, `!prac`, `!bhop`, `!kz`, `!surf`, `!minigames`, `!deathrun`, `!course`, `!scoutzknivez`, `!hns`, `!br`, `!soccer`, `!1.6`.

### I want MatchZy to record demos automatically

SourceTV is disabled by default for compatibility with a wider range of setups. To enable it on the current Windows runner, create `custom_all.cfg` under `<CUSTOM_FOLDER>/cfg/` in your external per-instance override directory and add:

```cfg
tv_enable 1
```

The runner overlays that `cfg/` directory before launching the server. You can review the available server commands in the [KUS server.cfg reference](https://github.com/kus/cs2-modded-server/blob/master/server/game/csgo/cfg/server.cfg). For MatchZy demos, leave `tv_autorecord 0` because MatchZy manages recording start and stop.

Check SourceTV with `tv_status` from the server console. You can also test with `tv_record <filename>` and stop with `tv_stoprecord`.

### What maps are preconfigured with each mode?

#### mg_active

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ancient.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_ancient<br><sup><sub>changelevel de_ancient</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_anubis.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_anubis<br><sup><sub>changelevel de_anubis</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_inferno<br><sup><sub>changelevel de_inferno</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_mirage<br><sup><sub>changelevel de_mirage</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_nuke<br><sup><sub>changelevel de_nuke</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust2.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_dust2<br><sup><sub>changelevel de_dust2</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_overpass<br><sup><sub>changelevel de_overpass</sub></sup></td></tr></table></td></tr></table>

#### mg_valve_competitive

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust2.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_dust2<br><sup><sub>changelevel de_dust2</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_mirage<br><sup><sub>changelevel de_mirage</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_inferno<br><sup><sub>changelevel de_inferno</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ancient_night.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_ancient_night<br><sup><sub>changelevel de_ancient_night</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_nuke<br><sup><sub>changelevel de_nuke</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_train.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_train<br><sup><sub>changelevel de_train</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_overpass<br><sup><sub>changelevel de_overpass</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_anubis.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_anubis<br><sup><sub>changelevel de_anubis</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_vertigo<br><sup><sub>changelevel de_vertigo</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_warden.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_warden<br><sup><sub>changelevel de_warden</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_stronghold.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_stronghold<br><sup><sub>changelevel de_stronghold</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_alpine.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_alpine<br><sup><sub>changelevel cs_alpine</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_office.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_office<br><sup><sub>changelevel cs_office</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_italy.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_italy<br><sup><sub>changelevel cs_italy</sub></sup></td></tr></table></td></tr></table>

#### mg_valve_wingman

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_sanctum.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_sanctum<br><sup><sub>changelevel de_sanctum</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_poseidon.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_poseidon<br><sup><sub>changelevel de_poseidon</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_overpass<br><sup><sub>changelevel de_overpass</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_vertigo<br><sup><sub>changelevel de_vertigo</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_nuke<br><sup><sub>changelevel de_nuke</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_inferno<br><sup><sub>changelevel de_inferno</sub></sup></td></tr></table></td></tr></table>

#### mg_valve_casual

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust2.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_dust2<br><sup><sub>changelevel de_dust2</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_mirage<br><sup><sub>changelevel de_mirage</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_inferno<br><sup><sub>changelevel de_inferno</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ancient_night.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_ancient_night<br><sup><sub>changelevel de_ancient_night</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_nuke<br><sup><sub>changelevel de_nuke</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_train.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_train<br><sup><sub>changelevel de_train</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_overpass<br><sup><sub>changelevel de_overpass</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_anubis.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_anubis<br><sup><sub>changelevel de_anubis</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_vertigo<br><sup><sub>changelevel de_vertigo</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_warden.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_warden<br><sup><sub>changelevel de_warden</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_stronghold.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_stronghold<br><sup><sub>changelevel de_stronghold</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_alpine.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_alpine<br><sup><sub>changelevel cs_alpine</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_office.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_office<br><sup><sub>changelevel cs_office</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_italy.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_italy<br><sup><sub>changelevel cs_italy</sub></sup></td></tr></table></td></tr></table>

#### mg_valve_deathmatch

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust2.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_dust2<br><sup><sub>changelevel de_dust2</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_mirage<br><sup><sub>changelevel de_mirage</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_inferno<br><sup><sub>changelevel de_inferno</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ancient_night.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_ancient_night<br><sup><sub>changelevel de_ancient_night</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_nuke<br><sup><sub>changelevel de_nuke</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_train.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_train<br><sup><sub>changelevel de_train</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_overpass<br><sup><sub>changelevel de_overpass</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_anubis.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_anubis<br><sup><sub>changelevel de_anubis</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_vertigo<br><sup><sub>changelevel de_vertigo</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_warden.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_warden<br><sup><sub>changelevel de_warden</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_stronghold.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_stronghold<br><sup><sub>changelevel de_stronghold</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_alpine.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_alpine<br><sup><sub>changelevel cs_alpine</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_office.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_office<br><sup><sub>changelevel cs_office</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_italy.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_italy<br><sup><sub>changelevel cs_italy</sub></sup></td></tr></table></td></tr></table>

#### mg_valve_arms_race

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_baggage.jpg?raw=true&sanitize=true"></td></tr><tr><td>ar_baggage<br><sup><sub>changelevel ar_baggage</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_shoots.jpg?raw=true&sanitize=true"></td></tr><tr><td>ar_shoots<br><sup><sub>changelevel ar_shoots</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_shoots_night.jpg?raw=true&sanitize=true"></td></tr><tr><td>ar_shoots_night<br><sup><sub>changelevel ar_shoots_night</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_pool_day.jpg?raw=true&sanitize=true"></td></tr><tr><td>ar_pool_day<br><sup><sub>changelevel ar_pool_day</sub></sup></td></tr></table></td></tr></table>

#### mg_valve_retakes

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust2.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_dust2<br><sup><sub>changelevel de_dust2</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_mirage<br><sup><sub>changelevel de_mirage</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_inferno<br><sup><sub>changelevel de_inferno</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ancient_night.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_ancient_night<br><sup><sub>changelevel de_ancient_night</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_nuke<br><sup><sub>changelevel de_nuke</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_train.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_train<br><sup><sub>changelevel de_train</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_overpass<br><sup><sub>changelevel de_overpass</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_anubis.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_anubis<br><sup><sub>changelevel de_anubis</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_vertigo<br><sup><sub>changelevel de_vertigo</sub></sup></td></tr></table></td></tr></table>

#### mg_comp

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust2.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_dust2<br><sup><sub>changelevel de_dust2</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_mirage<br><sup><sub>changelevel de_mirage</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_inferno<br><sup><sub>changelevel de_inferno</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ancient_night.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_ancient_night<br><sup><sub>changelevel de_ancient_night</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_nuke<br><sup><sub>changelevel de_nuke</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_train.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_train<br><sup><sub>changelevel de_train</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_overpass<br><sup><sub>changelevel de_overpass</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_anubis.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_anubis<br><sup><sub>changelevel de_anubis</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_vertigo<br><sup><sub>changelevel de_vertigo</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_warden.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_warden<br><sup><sub>changelevel de_warden</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_stronghold.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_stronghold<br><sup><sub>changelevel de_stronghold</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_alpine.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_alpine<br><sup><sub>changelevel cs_alpine</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_office.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_office<br><sup><sub>changelevel cs_office</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_italy.jpg?raw=true&sanitize=true"></td></tr><tr><td>cs_italy<br><sup><sub>changelevel cs_italy</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_golden.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3286163323">de_golden</a><br><sup><sub>host_workshop_map 3286163323</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_palacio.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3249860053">de_palacio</a><br><sup><sub>host_workshop_map 3249860053</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_agency.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3339983232">cs_agency</a><br><sup><sub>host_workshop_map 3339983232</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_basalt.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3329258290">de_basalt</a><br><sup><sub>host_workshop_map 3329258290</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_edin.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3328169568">de_edin</a><br><sup><sub>host_workshop_map 3328169568</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_assembly.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3071005299">de_assembly</a><br><sup><sub>host_workshop_map 3071005299</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_cbble.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3329387648">de_cbble</a><br><sup><sub>host_workshop_map 3329387648</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_cache.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3437809122">de_cache</a><br><sup><sub>host_workshop_map 3437809122</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_splinter.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3691046714">de_splinter</a><br><sup><sub>host_workshop_map 3691046714</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_biome.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3075706807">de_biome</a><br><sup><sub>host_workshop_map 3075706807</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mp_raid.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070346180">mp_raid</a><br><sup><sub>host_workshop_map 3070346180</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mutiny.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070766070">de_mutiny</a><br><sup><sub>host_workshop_map 3070766070</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_assault.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3694043544">cs_assault</a><br><sup><sub>host_workshop_map 3694043544</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ruins_d_prefab.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3072352643">de_ruins_d_prefab</a><br><sup><sub>host_workshop_map 3072352643</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_militia.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3089953774">cs_militia</a><br><sup><sub>host_workshop_map 3089953774</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_aztec_hr.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3079692971">de_aztec_hr</a><br><sup><sub>host_workshop_map 3079692971</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_akiba.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3108513658">de_akiba</a><br><sup><sub>host_workshop_map 3108513658</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/factory.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3681322159">factory</a><br><sup><sub>host_workshop_map 3681322159</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_insertion2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3236615060">cs_insertion2</a><br><sup><sub>host_workshop_map 3236615060</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mills.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3152430710">de_mills</a><br><sup><sub>host_workshop_map 3152430710</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_thera.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3121217565">de_thera</a><br><sup><sub>host_workshop_map 3121217565</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_season.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3073892687">de_season</a><br><sup><sub>host_workshop_map 3073892687</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ema.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3386116667">de_ema</a><br><sup><sub>host_workshop_map 3386116667</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/twofort_cs2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3345551391">twofort_cs2</a><br><sup><sub>host_workshop_map 3345551391</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_rats_remake.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3460962520">de_rats_remake</a><br><sup><sub>host_workshop_map 3460962520</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage_bricks.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3464733042">de_mirage_bricks</a><br><sup><sub>host_workshop_map 3464733042</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/project_phoenix.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3683699332">project_phoenix</a><br><sup><sub>host_workshop_map 3683699332</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ultimate_free_nuke.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3687298714">ultimate_free_nuke</a><br><sup><sub>host_workshop_map 3687298714</sub></sup></td></tr></table></td></tr></table>

#### mg_retake

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ancient.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_ancient<br><sup><sub>changelevel de_ancient</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_anubis.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_anubis<br><sup><sub>changelevel de_anubis</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_inferno<br><sup><sub>changelevel de_inferno</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_mirage<br><sup><sub>changelevel de_mirage</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_nuke<br><sup><sub>changelevel de_nuke</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust2.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_dust2<br><sup><sub>changelevel de_dust2</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_train.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_train<br><sup><sub>changelevel de_train</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_overpass<br><sup><sub>changelevel de_overpass</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_vertigo<br><sup><sub>changelevel de_vertigo</sub></sup></td></tr></table></td></tr></table>

#### mg_prefire

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ancient.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_ancient<br><sup><sub>changelevel de_ancient</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_anubis.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_anubis<br><sup><sub>changelevel de_anubis</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_inferno<br><sup><sub>changelevel de_inferno</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_mirage<br><sup><sub>changelevel de_mirage</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_nuke<br><sup><sub>changelevel de_nuke</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust2.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_dust2<br><sup><sub>changelevel de_dust2</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_train.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_train<br><sup><sub>changelevel de_train</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_overpass<br><sup><sub>changelevel de_overpass</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_vertigo<br><sup><sub>changelevel de_vertigo</sub></sup></td></tr></table></td></tr></table>

#### mg_executes

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_mirage<br><sup><sub>changelevel de_mirage</sub></sup></td></tr></table></td></tr></table>

#### mg_wingman

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_sanctum.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_sanctum<br><sup><sub>changelevel de_sanctum</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_poseidon.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_poseidon<br><sup><sub>changelevel de_poseidon</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_overpass<br><sup><sub>changelevel de_overpass</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_vertigo<br><sup><sub>changelevel de_vertigo</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_nuke<br><sup><sub>changelevel de_nuke</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_inferno<br><sup><sub>changelevel de_inferno</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_pool_day.jpg?raw=true&sanitize=true"></td></tr><tr><td>ar_pool_day<br><sup><sub>changelevel ar_pool_day</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_rooftop.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3536622725">de_rooftop</a><br><sup><sub>host_workshop_map 3536622725</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_splat.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3439120481">de_splat</a><br><sup><sub>host_workshop_map 3439120481</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust2_wingman.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3413800427">de_dust2_wingman</a><br><sup><sub>host_workshop_map 3413800427</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage_d.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3402437047">de_mirage_d</a><br><sup><sub>host_workshop_map 3402437047</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_palais.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3257582863">de_palais</a><br><sup><sub>host_workshop_map 3257582863</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_whistle.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3308613773">de_whistle</a><br><sup><sub>host_workshop_map 3308613773</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/gd_rialto.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3085490518">gd_rialto</a><br><sup><sub>host_workshop_map 3085490518</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_safehouse.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070550406">de_safehouse</a><br><sup><sub>host_workshop_map 3070550406</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_lake.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070563536">de_lake</a><br><sup><sub>host_workshop_map 3070563536</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_bank.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070581293">de_bank</a><br><sup><sub>host_workshop_map 3070581293</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_shortdust.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070612859">de_shortdust</a><br><sup><sub>host_workshop_map 3070612859</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_assembly.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3071005299">de_assembly</a><br><sup><sub>host_workshop_map 3071005299</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_cbble.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3329387648">de_cbble</a><br><sup><sub>host_workshop_map 3329387648</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_cache.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3437809122">de_cache</a><br><sup><sub>host_workshop_map 3437809122</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_biome.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3075706807">de_biome</a><br><sup><sub>host_workshop_map 3075706807</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mp_raid.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070346180">mp_raid</a><br><sup><sub>host_workshop_map 3070346180</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mutiny.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070766070">de_mutiny</a><br><sup><sub>host_workshop_map 3070766070</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_assault.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070594412">cs_assault</a><br><sup><sub>host_workshop_map 3070594412</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ruins_d_prefab.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3072352643">de_ruins_d_prefab</a><br><sup><sub>host_workshop_map 3072352643</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_sakura.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3082340867">de_sakura</a><br><sup><sub>host_workshop_map 3082340867</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_memento.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3165559377">de_memento</a><br><sup><sub>host_workshop_map 3165559377</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/skatepark.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3309665004">skatepark</a><br><sup><sub>host_workshop_map 3309665004</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ema.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3386116667">de_ema</a><br><sup><sub>host_workshop_map 3386116667</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/paintit.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3360723913">paintit</a><br><sup><sub>host_workshop_map 3360723913</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage_bricks.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3464733042">de_mirage_bricks</a><br><sup><sub>host_workshop_map 3464733042</sub></sup></td></tr></table></td></tr></table>

#### mg_dm

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_vertigo<br><sup><sub>changelevel de_vertigo</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust2.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_dust2<br><sup><sub>changelevel de_dust2</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_inferno<br><sup><sub>changelevel de_inferno</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage.jpg?raw=true&sanitize=true"></td></tr><tr><td>de_mirage<br><sup><sub>changelevel de_mirage</sub></sup></td></tr></table></td></tr></table>

#### mg_gg

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_shoots.jpg?raw=true&sanitize=true"></td></tr><tr><td>ar_shoots<br><sup><sub>changelevel ar_shoots</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_shoots_night.jpg?raw=true&sanitize=true"></td></tr><tr><td>ar_shoots_night<br><sup><sub>changelevel ar_shoots_night</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_baggage.jpg?raw=true&sanitize=true"></td></tr><tr><td>ar_baggage<br><sup><sub>changelevel ar_baggage</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_pool_day.jpg?raw=true&sanitize=true"></td></tr><tr><td>ar_pool_day<br><sup><sub>changelevel ar_pool_day</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/speedball.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3443206318">speedball</a><br><sup><sub>host_workshop_map 3443206318</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_plywood.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3118710028">aim_plywood</a><br><sup><sub>host_workshop_map 3118710028</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/gg_lego_arena.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3267768230">gg_lego_arena</a><br><sup><sub>host_workshop_map 3267768230</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_indoor.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3535917558">de_indoor</a><br><sup><sub>host_workshop_map 3535917558</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_assembly.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3071005299">de_assembly</a><br><sup><sub>host_workshop_map 3071005299</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/fy_iceworld.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070238628">fy_iceworld</a><br><sup><sub>host_workshop_map 3070238628</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/daymare.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3072640420">daymare</a><br><sup><sub>host_workshop_map 3072640420</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mcdonalds.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3134466699">mcdonalds</a><br><sup><sub>host_workshop_map 3134466699</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_theorem.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070348309">aim_theorem</a><br><sup><sub>host_workshop_map 3070348309</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_safehouse.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070550406">de_safehouse</a><br><sup><sub>host_workshop_map 3070550406</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_lake.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070563536">de_lake</a><br><sup><sub>host_workshop_map 3070563536</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_bank.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070581293">de_bank</a><br><sup><sub>host_workshop_map 3070581293</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/fun_bounce.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3088183343">fun_bounce</a><br><sup><sub>host_workshop_map 3088183343</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/1v1aim_map_longdustversion_d.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3082605693">1v1aim_map_longdustversion_d</a><br><sup><sub>host_workshop_map 3082605693</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_churches_s2r.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070291913">ar_churches_s2r</a><br><sup><sub>host_workshop_map 3070291913</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_ag_texture_city_advanced.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3082113929">aim_ag_texture_city_advanced</a><br><sup><sub>host_workshop_map 3082113929</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/trainingoutside.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3475270536">trainingoutside</a><br><sup><sub>host_workshop_map 3475270536</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/shipment_version_1_0.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3086555291">shipment_version_1_0</a><br><sup><sub>host_workshop_map 3086555291</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_ag_texture2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3074961197">aim_ag_texture2</a><br><sup><sub>host_workshop_map 3074961197</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_ag_texture_jungle.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3095778105">aim_ag_texture_jungle</a><br><sup><sub>host_workshop_map 3095778105</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs2_bloodstrike.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3071890065">cs2_bloodstrike</a><br><sup><sub>host_workshop_map 3071890065</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/gg_simpsons_vs_flanders_v2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3109232789">gg_simpsons_vs_flanders_v2</a><br><sup><sub>host_workshop_map 3109232789</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/school_d_environment_prefab.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3343693110">school_d_environment_prefab</a><br><sup><sub>host_workshop_map 3343693110</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_ema.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3386116667">de_ema</a><br><sup><sub>host_workshop_map 3386116667</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/twofort_cs2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3345551391">twofort_cs2</a><br><sup><sub>host_workshop_map 3345551391</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/paintit.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3360723913">paintit</a><br><sup><sub>host_workshop_map 3360723913</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kloce.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3248340515">kloce</a><br><sup><sub>host_workshop_map 3248340515</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/gulag.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3326465469">gulag</a><br><sup><sub>host_workshop_map 3326465469</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_rats_remake.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3460962520">de_rats_remake</a><br><sup><sub>host_workshop_map 3460962520</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage_bricks.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3464733042">de_mirage_bricks</a><br><sup><sub>host_workshop_map 3464733042</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_splat.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3439120481">de_splat</a><br><sup><sub>host_workshop_map 3439120481</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/1v1v1v1beta04.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3433012420">1v1v1v1beta04</a><br><sup><sub>host_workshop_map 3433012420</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/gg_festspeedball.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3111527644">gg_festspeedball</a><br><sup><sub>host_workshop_map 3111527644</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_blue_arena.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3361478861">ar_blue_arena</a><br><sup><sub>host_workshop_map 3361478861</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/gg_strafe_gg1.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3331570055">gg_strafe_gg1</a><br><sup><sub>host_workshop_map 3331570055</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_shotty2_gg1.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3360120483">aim_shotty2_gg1</a><br><sup><sub>host_workshop_map 3360120483</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/fy_hangemhigh.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3437226954">fy_hangemhigh</a><br><sup><sub>host_workshop_map 3437226954</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_combat_arena.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3455068243">ar_combat_arena</a><br><sup><sub>host_workshop_map 3455068243</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_ds_cornered_gg1.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3329405459">ar_ds_cornered_gg1</a><br><sup><sub>host_workshop_map 3329405459</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/awp_lego_2_destructible.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3706720942">awp_lego_2_destructible</a><br><sup><sub>host_workshop_map 3706720942</sub></sup></td></tr></table></td></tr></table>

#### mg_1v1

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_redline_fp.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070253400">aim_redline_fp</a><br><sup><sub>host_workshop_map 3070253400</sub></sup></td></tr></table></td></tr></table>

#### mg_bhop

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/bhop_at_night.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3077211069">bhop_at_night</a><br><sup><sub>host_workshop_map 3077211069</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/bhop_ragnarok.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3077153735">bhop_ragnarok</a><br><sup><sub>host_workshop_map 3077153735</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/bhop_zunron.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3077475505">bhop_zunron</a><br><sup><sub>host_workshop_map 3077475505</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/bhop_1derland.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3077596014">bhop_1derland</a><br><sup><sub>host_workshop_map 3077596014</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/bhop_whiteshit.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3078523849">bhop_whiteshit</a><br><sup><sub>host_workshop_map 3078523849</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/bhop_cherryblossom.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3082038560">bhop_cherryblossom</a><br><sup><sub>host_workshop_map 3082038560</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/bhop_arcturus.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3088973190">bhop_arcturus</a><br><sup><sub>host_workshop_map 3088973190</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/bhop_kiwi_cwfx.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3095219437">bhop_kiwi_cwfx</a><br><sup><sub>host_workshop_map 3095219437</sub></sup></td></tr></table></td></tr></table>

#### mg_kz

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/only_up.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3074758439">only_up</a><br><sup><sub>host_workshop_map 3074758439</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kz_dima.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3343029934">kz_dima</a><br><sup><sub>host_workshop_map 3343029934</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ewii_challenge.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3170668869">ewii_challenge</a><br><sup><sub>host_workshop_map 3170668869</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/hellcasecyrilchallenge.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3145779590">hellcasecyrilchallenge</a><br><sup><sub>host_workshop_map 3145779590</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kz_checkmate.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070194623">kz_checkmate</a><br><sup><sub>host_workshop_map 3070194623</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kz_victoria.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3086304337">kz_victoria</a><br><sup><sub>host_workshop_map 3086304337</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kz_rc_stonehenge.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3072219045">kz_rc_stonehenge</a><br><sup><sub>host_workshop_map 3072219045</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kz_sxb2_cxz.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3083714192">kz_sxb2_cxz</a><br><sup><sub>host_workshop_map 3083714192</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kz_rc_twotowers.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3083509404">kz_rc_twotowers</a><br><sup><sub>host_workshop_map 3083509404</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kz_simplyhard.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3078311932">kz_simplyhard</a><br><sup><sub>host_workshop_map 3078311932</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kz_nomibo.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3077122656">kz_nomibo</a><br><sup><sub>host_workshop_map 3077122656</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kz_sxb2_biewan.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3076000218">kz_sxb2_biewan</a><br><sup><sub>host_workshop_map 3076000218</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kz_ggsh.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3072744536">kz_ggsh</a><br><sup><sub>host_workshop_map 3072744536</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/kz_ltt.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3072699538">kz_ltt</a><br><sup><sub>host_workshop_map 3072699538</sub></sup></td></tr></table></td></tr></table>

#### mg_surf

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_kitsune.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3076153623">surf_kitsune</a><br><sup><sub>host_workshop_map 3076153623</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_utopia_njv.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3073875025">surf_utopia_njv</a><br><sup><sub>host_workshop_map 3073875025</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_beginner.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070321829">surf_beginner</a><br><sup><sub>host_workshop_map 3070321829</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_mesa_revo.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3076980482">surf_mesa_revo</a><br><sup><sub>host_workshop_map 3076980482</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_deathstar.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3080544577">surf_deathstar</a><br><sup><sub>host_workshop_map 3080544577</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_rookie.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3082548297">surf_rookie</a><br><sup><sub>host_workshop_map 3082548297</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_benevolent.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3098972556">surf_benevolent</a><br><sup><sub>host_workshop_map 3098972556</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_ace.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3088413071">surf_ace</a><br><sup><sub>host_workshop_map 3088413071</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_boreas.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3133346713">surf_boreas</a><br><sup><sub>host_workshop_map 3133346713</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_nyx.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3129698096">surf_nyx</a><br><sup><sub>host_workshop_map 3129698096</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_whiteout.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3296258256">surf_whiteout</a><br><sup><sub>host_workshop_map 3296258256</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/surf_ski_2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3079877518">surf_ski_2</a><br><sup><sub>host_workshop_map 3079877518</sub></sup></td></tr></table></td></tr></table>

#### mg_minigames

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_skeet_multigames_v7.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3082120895">mg_skeet_multigames_v7</a><br><sup><sub>host_workshop_map 3082120895</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_lego_course_2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3202752274">mg_lego_course_2</a><br><sup><sub>host_workshop_map 3202752274</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_warmcup_headshot.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3076765511">mg_warmcup_headshot</a><br><sup><sub>host_workshop_map 3076765511</sub></sup></td></tr></table></td></tr></table>

#### mg_battleroyale

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/br_t2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3462095803">br_t2</a><br><sup><sub>host_workshop_map 3462095803</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/br_electrified.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3330484099">br_electrified</a><br><sup><sub>host_workshop_map 3330484099</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/br_stacks.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3297489255">br_stacks</a><br><sup><sub>host_workshop_map 3297489255</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/br_flood.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3267454508">br_flood</a><br><sup><sub>host_workshop_map 3267454508</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/minecraft.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3186779271">minecraft</a><br><sup><sub>host_workshop_map 3186779271</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/minecraft_hungergame.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3240933254">minecraft_hungergame</a><br><sup><sub>host_workshop_map 3240933254</sub></sup></td></tr></table></td></tr></table>

#### mg_deathrun

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/deathrun_playground.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3164611860">deathrun_playground</a><br><sup><sub>host_workshop_map 3164611860</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/deathrun_egypt.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3311285877">deathrun_egypt</a><br><sup><sub>host_workshop_map 3311285877</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/deathrun_civilization.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3188021118">deathrun_civilization</a><br><sup><sub>host_workshop_map 3188021118</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/deathrun_iceworld_cs2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3083325292">deathrun_iceworld_cs2</a><br><sup><sub>host_workshop_map 3083325292</sub></sup></td></tr></table></td></tr></table>

#### mg_course

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cr_devisland_p1_v1.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3076483842">cr_devisland_p1_v1</a><br><sup><sub>host_workshop_map 3076483842</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_switch_course_v2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070439729">mg_switch_course_v2</a><br><sup><sub>host_workshop_map 3070439729</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cr_minecraft_jb_v2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070896876">cr_minecraft_jb_v2</a><br><sup><sub>host_workshop_map 3070896876</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_metro_course_v1.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070463151">mg_metro_course_v1</a><br><sup><sub>host_workshop_map 3070463151</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_alley_course_v2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070455802">mg_alley_course_v2</a><br><sup><sub>host_workshop_map 3070455802</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_glave_course_v2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070445185">mg_glave_course_v2</a><br><sup><sub>host_workshop_map 3070445185</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_office_course_v3.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070459211">mg_office_course_v3</a><br><sup><sub>host_workshop_map 3070459211</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_metal_course_v2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070464208">mg_metal_course_v2</a><br><sup><sub>host_workshop_map 3070464208</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_acrophobia_run_v2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070463620">mg_acrophobia_run_v2</a><br><sup><sub>host_workshop_map 3070463620</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_metro_course_s2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3071040020">mg_metro_course_s2</a><br><sup><sub>host_workshop_map 3071040020</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_circle_course_v3.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070434475">mg_circle_course_v3</a><br><sup><sub>host_workshop_map 3070434475</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_simpsons_course_v2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070447697">mg_simpsons_course_v2</a><br><sup><sub>host_workshop_map 3070447697</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_sonic_course_v2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070452642">mg_sonic_course_v2</a><br><sup><sub>host_workshop_map 3070452642</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/mg_sky_realm_v3.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070451616">mg_sky_realm_v3</a><br><sup><sub>host_workshop_map 3070451616</sub></sup></td></tr></table></td></tr></table>

#### mg_scoutzknivez

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/scoutzknivez_pure_cs2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3073929825">scoutzknivez_pure_cs2</a><br><sup><sub>host_workshop_map 3073929825</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_dizzy.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3070553020">ar_dizzy</a><br><sup><sub>host_workshop_map 3070553020</sub></sup></td></tr></table></td></tr></table>

#### mg_hns

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke_prophunt.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3366748499">de_nuke_prophunt</a><br><sup><sub>host_workshop_map 3366748499</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass_prophunt.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3382166635">de_overpass_prophunt</a><br><sup><sub>host_workshop_map 3382166635</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_inferno_prophunt.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3348038890">de_inferno_prophunt</a><br><sup><sub>host_workshop_map 3348038890</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo_prophunt.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3292648008">de_vertigo_prophunt</a><br><sup><sub>host_workshop_map 3292648008</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage_prophunt.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3287578956">de_mirage_prophunt</a><br><sup><sub>host_workshop_map 3287578956</sub></sup></td></tr></table></td></tr></table>

#### mg_soccer

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/field.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3238565662">field</a><br><sup><sub>host_workshop_map 3238565662</sub></sup></td></tr></table></td></tr></table>

#### mg_awp

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/awp_bhop_rocket.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3142070597">awp_bhop_rocket</a><br><sup><sub>host_workshop_map 3142070597</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/bump_arena.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3679420050">bump_arena</a><br><sup><sub>host_workshop_map 3679420050</sub></sup></td></tr></table></td></tr></table>

#### mg_battle

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/battleball.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3280650663">battleball</a><br><sup><sub>host_workshop_map 3280650663</sub></sup></td></tr></table></td></tr></table>

#### mg_aim

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_map.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3084291314">aim_map</a><br><sup><sub>host_workshop_map 3084291314</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/gg_festspeedball.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3111527644">gg_festspeedball</a><br><sup><sub>host_workshop_map 3111527644</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_plywood.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3118710028">aim_plywood</a><br><sup><sub>host_workshop_map 3118710028</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/freebet_aim_map.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3146122036">freebet_aim_map</a><br><sup><sub>host_workshop_map 3146122036</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_pool_day.jpg?raw=true&sanitize=true"></td></tr><tr><td>ar_pool_day<br><sup><sub>changelevel ar_pool_day</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_ak-colt_CS2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3078701726">aim_ak-colt_CS2</a><br><sup><sub>host_workshop_map 3078701726</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_usp.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3085962528">aim_usp</a><br><sup><sub>host_workshop_map 3085962528</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_deagle.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3075996446">aim_deagle</a><br><sup><sub>host_workshop_map 3075996446</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/1v1aim_map_longdustversion_d.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3082605693">1v1aim_map_longdustversion_d</a><br><sup><sub>host_workshop_map 3082605693</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_splat.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3439120481">de_splat</a><br><sup><sub>host_workshop_map 3439120481</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/1v1v1v1beta04.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3433012420">1v1v1v1beta04</a><br><sup><sub>host_workshop_map 3433012420</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_blue_arena.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3361478861">ar_blue_arena</a><br><sup><sub>host_workshop_map 3361478861</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/gg_strafe_gg1.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3331570055">gg_strafe_gg1</a><br><sup><sub>host_workshop_map 3331570055</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_shotty2_gg1.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3360120483">aim_shotty2_gg1</a><br><sup><sub>host_workshop_map 3360120483</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/fy_hangemhigh.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3437226954">fy_hangemhigh</a><br><sup><sub>host_workshop_map 3437226954</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_combat_arena.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3455068243">ar_combat_arena</a><br><sup><sub>host_workshop_map 3455068243</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ar_ds_cornered_gg1.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3329405459">ar_ds_cornered_gg1</a><br><sup><sub>host_workshop_map 3329405459</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/speedball.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3443206318">speedball</a><br><sup><sub>host_workshop_map 3443206318</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_indoor.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3535917558">de_indoor</a><br><sup><sub>host_workshop_map 3535917558</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/daymare.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3072640420">daymare</a><br><sup><sub>host_workshop_map 3072640420</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_ag_texture_city_advanced.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3082113929">aim_ag_texture_city_advanced</a><br><sup><sub>host_workshop_map 3082113929</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/trainingoutside.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3475270536">trainingoutside</a><br><sup><sub>host_workshop_map 3475270536</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/shipment_version_1_0.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3086555291">shipment_version_1_0</a><br><sup><sub>host_workshop_map 3086555291</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_ag_texture2.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3074961197">aim_ag_texture2</a><br><sup><sub>host_workshop_map 3074961197</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/aim_ag_texture_jungle.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3095778105">aim_ag_texture_jungle</a><br><sup><sub>host_workshop_map 3095778105</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs2_bloodstrike.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3071890065">cs2_bloodstrike</a><br><sup><sub>host_workshop_map 3071890065</sub></sup></td></tr></table></td></tr></table>

#### mg_casual16

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/as_oilrig.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3104677430">as_oilrig</a><br><sup><sub>host_workshop_map 3104677430</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_assult_classic.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3215705579">cs_assult_classic</a><br><sup><sub>host_workshop_map 3215705579</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_aztec_classic.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3213800338">de_aztec_classic</a><br><sup><sub>host_workshop_map 3213800338</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust_classic.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3078095785">de_dust_classic</a><br><sup><sub>host_workshop_map 3078095785</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_dust2_classic.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3201205818">de_dust2_classic</a><br><sup><sub>host_workshop_map 3201205818</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_italy_classic.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3212419403">cs_italy_classic</a><br><sup><sub>host_workshop_map 3212419403</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_militia_classic.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3144773563">cs_militia_classic</a><br><sup><sub>host_workshop_map 3144773563</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke_classic.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3205793205">de_nuke_classic</a><br><sup><sub>host_workshop_map 3205793205</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/cs_office_classic.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3216844784">cs_office_classic</a><br><sup><sub>host_workshop_map 3216844784</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_survivor_classic_m.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3217247541">de_survivor_classic_m</a><br><sup><sub>host_workshop_map 3217247541</sub></sup></td></tr></table></td></tr></table>

#### mg_45

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_vertigo_45.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3276886893">de_vertigo_45</a><br><sup><sub>host_workshop_map 3276886893</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_anubis_silly.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3245985233">de_anubis_silly</a><br><sup><sub>host_workshop_map 3245985233</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_overpass_45.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3270066070">de_overpass_45</a><br><sup><sub>host_workshop_map 3270066070</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_nuke_silly.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3245245780">de_nuke_silly</a><br><sup><sub>host_workshop_map 3245245780</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_mirage45.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3270516952">de_mirage45</a><br><sup><sub>host_workshop_map 3270516952</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/de_train_twyxe.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3406937162">de_train_twyxe</a><br><sup><sub>host_workshop_map 3406937162</sub></sup></td></tr></table></td></tr></table>

#### mg_ctf

<table><tr><td><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ctf_2fort.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3555531615">ctf_2fort</a><br><sup><sub>host_workshop_map 3555531615</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ctf_doublecross.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3555532817">ctf_doublecross</a><br><sup><sub>host_workshop_map 3555532817</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ctf_turbine.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3555534037">ctf_turbine</a><br><sup><sub>host_workshop_map 3555534037</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ctf_sawmill.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3611854449">ctf_sawmill</a><br><sup><sub>host_workshop_map 3611854449</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ctf_applejack.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3611844411">ctf_applejack</a><br><sup><sub>host_workshop_map 3611844411</sub></sup></td></tr></table><table align="left"><tr><td><img src="https://github.com/kus/cs2-modded-server/blob/assets/images/ctf_landfall.jpg?raw=true&sanitize=true"></td></tr><tr><td><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3611843310">ctf_landfall</a><br><sup><sub>host_workshop_map 3611843310</sub></sup></td></tr></table></td></tr></table>

### How do I connect to RCON remotely?

[Download SourceAdminTool](https://nightly.link/Drifter321/admintool/workflows/build/master) ([source](https://github.com/Drifter321/admintool)) for your OS (you can read about it [here](https://forums.alliedmods.net/showthread.php?t=289370)) and click `Servers > Add Servers` and put in the `<IP>:27015` and when you see the server show in the list, down the bottom left type in your RCON password and click `Login` and you should be able to execute commands from the bottom text box i.e. `exec dm.cfg`

**For a public server, connect to its reachable public IP and port. If autodetection or NAT is an issue, configure the advertised `IP` in the private Windows `instance.ini` and confirm that the router/cloud firewall forwards the selected port.**

### Accessing the admin menu

Admins are managed by CounterStrikeSharp's [Admin Framework](https://docs.cssharp.dev/docs/admin-framework/defining-admins.html). The canonical file is `server/game/csgo/addons/counterstrikesharp/configs/admins.json`.

For a per-instance admin list, copy the current file to `<CUSTOM_FOLDER>/addons/counterstrikesharp/configs/admins.json` in the external override folder and edit the private copy. For a shared admin list, edit the canonical tracked file and commit the change. The [KUS example admins.json](https://github.com/kus/cs2-modded-server/blob/master/custom_files_example/addons/counterstrikesharp/configs/admins.json) is a reference example only; review it before applying because the unified branch's plugin versions can differ.

Ensure JSON files are valid. On startup, look for the admin-loading message in the server log. If you modify admin settings while the server is running, use `css_admins_reload` and `css_groups_reload`; inspect the result with `css_admins_list` and `css_groups_list`.

### Use number keys to operate menu instead of typing !1 in chat

If you don't like having to type in chat !number every time you want to use a menu item; you can use this trick to bind the corresponding !number command to the number key. So when you press 1 it will select the 1 option:

_Note: This is assuming you are using the standard binds. You can change accordingly for your own setup._

```
bind "1" "slot1; css_1"
bind "2" "slot2; css_2"
bind "3" "slot3; css_3"
bind "4" "slot4; css_4"
bind "5" "slot5; css_5"
bind "6" "slot6; css_6"
bind "7" "slot7; css_7"
bind "8" "slot8; css_8"
bind "9" "slot9; css_9"
bind "0" "slot10; css_0"
```

### Changing maps

<img alt="Admin change map menu" src="https://github.com/kus/cs2-modded-server/blob/assets/assets/admin-maps.png?raw=true&sanitize=true">

Admins can type `!maps` in chat and it will bring up a menu of all the maps for the current mod. When a map is selected it will change the map straight away.

At the end of the map (if time runs out or win conditions are met) it a vote will show to choose a map from the current mod.

### Changing settings

Admins can type `!settings` in chat and it will bring up a menu of all the settings you can enable or disable. i.e.: Bunnyhopping, fun mode etc.

### Changing game modes

<img alt="Admin change game mode menu" src="https://github.com/kus/cs2-modded-server/blob/assets/assets/admin-modes.png?raw=true&sanitize=true">

Admins can type `!modes` in chat and it will bring up a menu of all the game modes. Simply choose one and it will switch to that game mode and change to a default map for that game mode.

The maps in `!maps` will also update to the new game mode when it has changed.

Changing between gamemodes multiple times is not recommended, and it is better if you restart the CS2 server in-between.

To view what other commands are available view the plugins documentation at the top of the page.

### RCON doesn't work

Using RCON whilst connected to the server does not work. See discussion [here](https://www.reddit.com/r/GlobalOffensive/comments/167spzi/cs2_rcon/).
The current work arounds are:

- I have included [CS2Rcon](https://github.com/LordFetznschaedl/CS2Rcon) which allows admins to use !rcon in chat.
- You can disconnect from the server and use `rcon_address IP:PORT` in console and you can use rcon commands.
- Use an external RCON program which has implemented the RCON protocol such as [this](https://github.com/fpaezf/CS2-RCON-Tool-V2).

If it still doesn't work, make sure you try connect from CS2 outside of a game via console:

**For a public server, connect to the reachable public IP and port. Configure the advertised `IP` in `instance.ini` if needed, and verify firewall/NAT forwarding.**

```bash
rcon_address ip:port
rcon_password "password"
rcon say "hi"
```

And check the ports cs2 is using on your OS i.e. on Ubuntu `sudo lsof -i -P -n | head -n 1; sudo lsof -i -P -n | grep cs2`.

### My server has run out of space!

Workshop maps take up a lot of space! If you want to delete all your workshop maps so the server can run again (it will download the maps you want to play). Stop the server, delete the `workshop` and start the server again:

Linux:

```
df -h -x tmpfs -x devtmpfs # Get total and free space (generally /dev/root)
cd /home/steam/cs2/game/bin/linuxsteamrt64/steamapps
ls -lah # You should see a workshop folder
du -sh workshop # To get the size of it
rm -rf workshop # Delete the workshop folder
```

Windows:

- Browse to where ever you are running your server from
- Open `game/bin/win64/steamapps/` and you should see a workshop folder
- Delete the workshop folder

### How do I add more bots?

By default, bots are enabled in deathmatch, gungame, gungame FFA, retakes, scoutsknives and wingman. The default behavior adds one bot when only one human is present and removes the need for bots when two or more humans join.

To override bot settings for one Windows instance, put a customized `custom_bots.cfg` in `<CUSTOM_FOLDER>/cfg/`; the runner overlays it into the runtime config tree before launch. The upstream starting point is [custom_bots.cfg](https://github.com/kus/cs2-modded-server/blob/master/server/game/csgo/cfg/custom_bots.cfg).

You can also manage bots through RCON with `bot_add_ct`, `bot_add_t` and `bot_kick`.

### Why can't I set the server to start automatically with a mod loaded

Because the way the server is setup with several mods it's not possible. You can't use `+exec` in the server launcher as that executes to quick before SourceMod is loaded. You can monitor the server once it's started (via RCON) and then load a mod i.e. `exec dm.cfg`.

### Updating Metamod:Source and CounterStrikeSharp

CounterStrikeSharp is managed by `DEPENDENCIES.json` and the Windows `addons-update.bat` workflow. Preview and update it with:

```bat
addons-update.bat -DryRun -Only CounterStrikeSharp
addons-update.bat -Only CounterStrikeSharp
```

The manifest requires the Windows **with-runtime** archive and CI checks that .NET runtime files are present. Do not manually copy a no-runtime CSS archive over this runtime tree.

Metamod:Source is a KUS base component, not a Larnz release-manifest entry. Keep its runtime files in the tracked repository and update them only through a reviewed integration change; do not manually overlay files into a separate `game/csgo/` staging directory. The legacy `scripts/check-updates.sh` and upstream Bash updater are not the active Windows update workflow.

### Quake Sounds

Quake Sounds is disabled by default and can be toggled by players with `!qs` when enabled. To enable it for a Windows instance:

1. In the external override folder, create or copy `<CUSTOM_FOLDER>/cfg/multiaddonmanager/multiaddonmanager.cfg` and add Workshop ID `3461824328` to `mm_extra_addons`.
2. Put `<CUSTOM_FOLDER>/cfg/settings/quake_sounds.cfg` in place and uncomment the `css_plugins load "plugins/disabled/QuakeSounds/QuakeSounds.dll"` line.
3. Ensure MultiAddonManager is enabled as described below, then restart that instance.

### Skin changer

On your server your players will have the ability to change the following:

- Weapon
  - Paint Kit, Wear, Seed, Name tag, StatTrak (with increment), and Stickers.
- Knife
  - Paint Kit, Wear, Seed, Name tag, and StatTrak (with increment).
- Gloves
  - Paint Kit, Wear, Seed.
- Agent
  - Patches.
- Music Kit
  - StatTrak (with increment). 
- Pin
- Graffiti

Go to [https://inventory.cstrike.app](https://inventory.cstrike.app/) and click `Sign-in to sync` and log in with Steam (this needs to be the same Steam account you are playing on).

Click `Craft Item` and create the items you want. You need to right click them and "Equip" them like you do in-game.

On the server type `!ws` and it should update your skins to what you have set.

> [!CAUTION]  
> Your server can be banned by Valve for using this plugin (see their [server guidelines](https://blog.counter-strike.net/index.php/server_guidelines)). Use at your own risk.

If you **DO NOT** want to use this plugin; change `FollowCS2ServerGuidelines` to `true` in `addons/counterstrikesharp/configs/core.json`. It is recommended to do this via [per-instance overrides](#configuration-and-per-instance-overrides).

### I want to permanently enable Multi Addon Manager

The KUS runtime includes MultiAddonManager, but its Metamod auto-load entry is optional. To enable it for one Windows instance, copy:

```text
server/game/csgo/addons/multiaddonmanager/multiaddonmanager.vdf
```

to:

```text
<CUSTOM_FOLDER>/addons/metamod/multiaddonmanager.vdf
```

The runner overlays that file at the Metamod configuration path on startup. To check whether it loaded, run `meta list` in the server console and look for MultiAddonManager.

### Model changer

Custom player models can be enabled in `!settings` under the custom player-model option. You also need a Workshop addon containing the model files; the KUS guide links [one example Workshop addon](https://steamcommunity.com/sharedfiles/filedetails/?id=3163629484).

Add the Workshop ID to the shared `server/game/csgo/cfg/multiaddonmanager/multiaddonmanager.cfg` or a per-instance override at `<CUSTOM_FOLDER>/cfg/multiaddonmanager/multiaddonmanager.cfg`. Configure model entries in `server/game/csgo/addons/counterstrikesharp/configs/plugins/PlayerModelChanger/PlayerModelChanger.json`, or create the same relative path below `<CUSTOM_FOLDER>/addons/` for a per-instance override.

To inspect assets in a Workshop addon, subscribe to it in the CS2 client and use [Source 2 Viewer](https://valveresourceformat.github.io/) to browse the downloaded content.

### I run a Surf/KZ/Bhop server and want MovementUnlocker and CS2Fixes-RampbugFix permanently enabled

The runtime tree includes Windows/Linux payloads for [MovementUnlocker](https://github.com/Source2ZE/MovementUnlocker) and [CS2Fixes-RampbugFix](https://github.com/Interesting-exe/CS2Fixes-RampbugFix). The corresponding Metamod VDF files are under `server/game/csgo/addons/surf/`.

For one Windows instance, copy the files from `server/game/csgo/addons/surf/windows/addons/metamod/` to `<CUSTOM_FOLDER>/addons/metamod/`. Confirm the exact filenames in the current tree, restart the server, and check `meta list` for the loaded plugins.

For an ad-hoc mode, the KUS game-mode menu can enable the surf settings using `!settings`; follow with `!maps` to select the desired map.

### Setup MySQL database

Database hosting is outside the scope of this repository. Plugin configuration files are generally under `server/game/csgo/addons/counterstrikesharp/configs/plugins/`.

For example, K4-Arenas configuration is typically at `server/game/csgo/addons/counterstrikesharp/configs/plugins/K4-Arenas/K4-Arenas.json`. For a per-instance database connection, place your private version at `<CUSTOM_FOLDER>/addons/counterstrikesharp/configs/plugins/K4-Arenas/K4-Arenas.json`; for a shared setting, edit the canonical file. If the real config does not exist, check for the plugin's `.example` template before creating one.

Never commit database passwords, connection strings or other credentials.

### Enable advertisements

The Advertisement plugin is disabled by default. To load it, add this command to the relevant mode config or to a per-instance `<CUSTOM_FOLDER>/cfg/custom_all.cfg`:

```cfg
css_plugins load "plugins/disabled/Advertisement/Advertisement.dll"
```

Its settings file is under `server/game/csgo/addons/counterstrikesharp/plugins/disabled/Advertisement/advertisement.json`. For a per-instance override, place your file at the same relative path below `<CUSTOM_FOLDER>/addons/`.

### Enable Whitelist so only a list of people can play

The Whitelist plugin is disabled by default. To load it, add this command to the relevant mode config or a per-instance `<CUSTOM_FOLDER>/cfg/custom_all.cfg`:

```cfg
css_plugins load "plugins/disabled/WhiteList/WhiteList.dll"
```

Its settings file is `server/game/csgo/addons/counterstrikesharp/plugins/disabled/WhiteList/whitelist.txt`. For a per-instance override, place your private file at the same relative path below `<CUSTOM_FOLDER>/addons/`.

### Failed to open libtier0.so

`Failed to open libtier0.so (/home/steam/cs2/bin/libgcc_s.so.1: version 'GCC_7.0.0' not found (required by /lib/i386-linux-gnu/libstdc++.so.6))`

This is because Valve ships their own copies of those libraries. As modern systems will have newer versions, you can safely delete the listed file from the server install. Do not delete the file in the system path (usually lib or lib32)[*](https://wiki.alliedmods.net/Installing_metamod:source).

`cd /home/steam/cs2/bin/` and `rm libgcc_s.so.1` and restart the server.

## License

See `LICENSE` for more details.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=kus/cs2-modded-server)](https://star-history.com/#kus/cs2-modded-server)
