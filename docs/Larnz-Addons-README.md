# CS2 KUS Addons

Additional plugins and libraries for [KUS/cs2-modded-server](https://github.com/kus/cs2-modded-server).

This repository is an **add-on layer** on top of KUS. KUS remains responsible for the base CS2 dedicated server, its own bundled mods/plugins, and its own update system. This repository manages the extra addon layer and our own files.

## How this repository works

The most important rule is simple:

> **The addon layer never deletes files from the destination. It only merges its files on top of the existing installation.**

When the layer is applied:

- Existing unrelated destination files are left untouched.
- A file supplied by this repository replaces the file at the same path.
- Files that exist only in the destination are not removed by the overlay.
- Our custom files are applied after the addon layer.

The repository's `server/game/csgo/` directory is the **canonical runtime tree**. The CS2 base game is installed into `server/`; plugin and config files tracked here already live at their final `server/game/csgo/` paths.

## KUS vs. cs2-kus-addons

| Part | Owner |
| --- | --- |
| Base CS2 dedicated server | KUS |
| KUS game modes and bundled plugins | KUS |
| KUS base updates | KUS |
| Extra plugins listed below | cs2-kus-addons |
| Extra plugin dependencies | cs2-kus-addons |
| Our custom configs/files | cs2-kus-addons |
| Addon installation/merge logic | cs2-kus-addons |

### Intentionally kept from KUS

KUS already includes its own **SimpleAdmin** ([connercsbn/SimpleAdmin](https://github.com/connercsbn/SimpleAdmin)). It stays installed.

We also install **Daffy CS2-SimpleAdmin** alongside it. These are intentionally kept as two separate plugins.

### Not managed by this repository

KUS already contains:

- [MultiAddonManager](https://github.com/Source2ZE/MultiAddonManager)
- [ServerListPlayersFix](https://github.com/Source2ZE/ServerListPlayersFix)

They are intentionally **not reinstalled or managed by this repository**.

## Add-ons installed

| Mod | Version | Why |
| --- | --- | --- |
| [CounterStrikeSharp](https://github.com/roflmuffin/CounterStrikeSharp) | 1.0.376 | The .NET scripting framework used by our CounterStrikeSharp plugins. Its runtime is required by this layer. |
| [CS2UpdateMonitor](https://github.com/beanman109/cs2-updatemonitor) | 1.1.0 | Detects new CS2 game builds and coordinates the restart handoff to the external supervisor. |
| [WeaponPaints](https://github.com/Nereziel/cs2-WeaponPaints) | `466` | Additional player-side game customization plugin. |
| [CS2-SimpleAdmin](https://github.com/daffyyyy/CS2-SimpleAdmin) | 1.9.0 | Provides extended server administration functionality. |
| [AFKManager](https://github.com/NiGHT757/AFKManager) | 0.2.8 | Detects AFK players and applies the configured AFK handling. |
| [CS2-Kill-Plugin](https://github.com/Quantor97/CS2-Kill-Plugin) | 0.2.0 | Adds a player self-action command. |
| [SimpleResetScore](https://github.com/stefanx111/cs2-SimpleResetScore) | 1.0.7 | Lets players reset their own score. |
| [cs2-showdamage](https://github.com/abnerfs/cs2-showdamage) | 1.1.0 | Shows damage information during gameplay. |
| [cs2-ranks](https://github.com/partiusfabaa/cs2-ranks) | v2.0.5.5-recompile | Persistent player ranks, statistics and progression backed by a database. |
| [VIPCore](https://github.com/partiusfabaa/cs2-VIPCore) | v1.3.4-recompile3 | Provides the VIP core/module used for VIP functionality. |
| [AnyBaseLibCS2](https://github.com/NickFox007/AnyBaseLibCS2) | 0.9.4 | Shared database/API library required by other add-ons. |
| [PlayerSettingsCS2](https://github.com/NickFox007/PlayerSettingsCS2) | 0.9.4 | Persistent player-settings library used by dependent plugins. |
| [MenuManagerCS2](https://github.com/NickFox007/MenuManagerCS2) | 1.4.1 | Menu/API library used by dependent plugins. |
| [SLAYER_AntiCamp](https://github.com/zakriamansoor47/SLAYER_AntiCamp) | `1.2.5` | Detects and handles excessive camping according to configuration. |
| [SLAYER_HeadshotOnly](https://github.com/zakriamansoor47/SLAYER_HeadshotOnly) | `1.2.1` | Provides a headshot-only gameplay mode. |
| [CS2-TeamLimiter](https://github.com/Ferks-FK/CS2-TeamLimiter) | — | Limits the maximum number of players on each team. |
| [CS2-WeaponRestrict](https://github.com/TICHOJEBEC-SK/CS2-WeaponRestrict) | WeaponRestrict1.5 | Applies configurable gameplay restrictions. |

> **Version note:** `cs2-showdamage` is intentionally pinned to `1.1.0`. `CS2-WeaponRestrict` is currently the only addon marked manual in `DEPENDENCIES.json`; `WeaponPaints` follows the latest stable GitHub release and is managed by the same updater as the other automated addons.

## Dependency order

Dependencies are explicit in [DEPENDENCIES.json](./DEPENDENCIES.json). The Windows manifest-driven updater verifies dependencies before installing an addon. Add-on release updates are separate from Git repository updates and SteamCMD game updates.

The core chain is:

```text
KUS / Metamod:Source
        |
CounterStrikeSharp + Runtime
        |
AnyBaseLibCS2
        |
PlayerSettingsCS2
        |
MenuManagerCS2
        |
+-------------------------------+
| dependent plugins             |
+-------------------------------+
```

Examples:

- CounterStrikeSharp requires KUS's Metamod:Source.
- PlayerSettingsCS2 requires CounterStrikeSharp and AnyBaseLibCS2.
- MenuManagerCS2 requires CounterStrikeSharp and PlayerSettingsCS2.
- CS2-SimpleAdmin requires CounterStrikeSharp, AnyBaseLibCS2, PlayerSettingsCS2 and MenuManagerCS2.

## Windows workflow

### 1. First install / update the addon layer

Run:

```bat
addons-update.bat -DryRun -Only CounterStrikeSharp
addons-update.bat -Only CounterStrikeSharp
```

The updater downloads the configured GitHub release, keeps the archive and extracted tree under:

```text
tmp/
└── releases/
    └── <addon>/
        └── <version>/
            ├── <release>.zip
            ├── extract-<release>/
            ├── layout-<release>.txt
            └── release-<release>.json
```

It then detects the release's real CS2 root and merges that tree directly into:

```text
server/game/csgo/
```

So the repository stores the **extracted runtime tree**, just like KUS does.

For example, when a CounterStrikeSharp Windows release has `addons/` at the archive root, that exact tree is placed at:

```text
<release>/addons/...  ->  server/game/csgo/addons/...
```

No extra `CounterStrikeSharp/` directory is inserted.

The updater never deletes files from that staging tree. It only creates/overwrites paths supplied by the upstream release. Release mappings support both full `game/csgo` roots and explicit plugin-directory destinations. The updater deliberately preserves `cfg/` and `addons/counterstrikesharp/configs/`; incoming release files cannot overwrite the static/user-managed settings in those locations.

The updater processes the manifest in dependency order, and the GitHub workflow validates required files across the full runtime tree after updating. The workflow also verifies that fixed configuration paths were not changed by release packages.
### CS2 Update Monitor

`CS2UpdateMonitor` is managed by the same `addons-update.bat` / `Update-Addons.ps1` pipeline as the other automated addons.

Its runtime directory is:

```text
server/game/csgo/addons/counterstrikesharp/plugins/CS2UpdateMonitor/
```

Its configuration is:

```text
server/game/csgo/addons/counterstrikesharp/configs/plugins/CS2UpdateMonitor/CS2UpdateMonitor.json
```

The upstream Windows release has a single top-level `CS2UpdateMonitor/` directory, so `DEPENDENCIES.json` uses an explicit `source_path` + `install_path` mapping instead of assuming the archive is a complete `game/csgo` tree.

The configured action is `ShutdownForSupervisor`: when a newer CS2 build is detected, the plugin announces a countdown and finally executes `quit`. The external VBS supervisor is responsible for starting the server again.

### 2. Initial installation

Run `install.bat` from this repository's Git checkout:

```bat
install.bat
```

The installer treats KUS as the raw base and this repository as the overlay. It clones KUS into `KUS_ROOT` from `win.ini` only when the checkout is missing, verifies the repository origin, and installs CS2 through SteamCMD only if the CS2 executable or `appmanifest_730.acf` is missing. If both are already present, it does not run `app_update` again.

It then calls `win.bat`, which rebuilds the KUS-managed server files and applies this repository's overlay plus optional custom-file layers. **`win.bat` does not download/update the game and never launches `cs2.exe`.**

The current `CS2UpdateMonitor` config uses `ShutdownForSupervisor`, which detects a new game build and shuts the server down, but does not install the update itself. Its game-update handoff must be wired into the VBS supervisor separately; do not add a second automatic SteamCMD updater.

### 3. Update both repositories and re-apply the layers

Run:

```bat
update.bat
```

This does:

1. `git pull --ff-only` for `cs2-kus-addons`, which receives the tracked plugin/library files published by this repository's addon updater.
2. `git pull --ff-only` for the KUS base repository.
3. Runs `win.bat` to rebuild the KUS-managed files and re-apply the addon overlay.

`update.bat` checks that both Git working trees are clean before pulling either repository. It does **not** run SteamCMD, update the game, or start the server. The plugin release-download/update pipeline remains separately available through `addons-update.bat` when updating the tracked addon layer from upstream releases.

The CS2 game-build checker and the VBS restart/update handoff will be configured as a separate step, so ordinary repository updates and server restarts do not become extra game-updater instances.

### 4. Update addon release files

To refresh the tracked plugins/libraries from their upstream releases in this local clone:

```bat
addons-update.bat -DryRun
addons-update.bat
```

These commands are separate from `update.bat`, which pulls already-published commits from both Git repositories.

## KUS base location

Edit [win.ini](./win.ini):

```ini
KUS_ROOT=..\\cs2-modded-server
```

The default assumes this layout:

```text
parent/
├── cs2-modded-server/
└── cs2-kus-addons/
```

The KUS repository is not copied into this repository and is not vendored here.

## Example: multi-instance runner template

The reusable template based on the supplied \`run.bat\` + VBS supervisor is in [\`examples/run-template/\`](./examples/run-template/). It includes a safe \`instance.example.ini\`; copy it to the ignored local file \`instance.ini\` and fill in machine-specific settings and credentials. The template starts/restarts an instance only; it does not run SteamCMD or update the CS2 game.

## File layout

```text
cs2-kus-addons/
├── DEPENDENCIES.json
├── README.md
├── win.ini
├── install.bat
├── win.bat
├── update.bat
├── addons-update.bat
├── addons-inspect.bat
├── examples/
│   └── run-template/
│       ├── run.bat
│       ├── run.vbs
│       ├── instance.example.ini
│       ├── .gitignore
│       └── README.md
├── scripts/
│   ├── Inspect-Releases.ps1
│   ├── Test-AddonOverlay.ps1
│   └── Update-Addons.ps1
└── server/
    └── game/
        └── csgo/  (runtime overlay)
```

## Updating addon versions

The release updater uses [DEPENDENCIES.json](./DEPENDENCIES.json) as the source of truth.

Useful commands:

```bat
addons-update.bat -DryRun
addons-update.bat -DryRun -Only CounterStrikeSharp
addons-update.bat -Only CounterStrikeSharp
addons-update.bat -Force -Only CounterStrikeSharp
```

The updater:

- checks the configured GitHub release/tag
- selects the exact asset pattern from the manifest
- downloads and extracts the archive
- verifies that a CS2 `addons/` tree can be found
- merges files into the staging tree without deleting unrelated files
- updates the version state in `DEPENDENCIES.json`
- updates the matching README table row
- supports source builds for addons that do not publish releases

The PowerShell updater commits each successful add-on update locally. A local run leaves those commits on your local branch, so review and push them yourself. The GitHub Actions workflow runs daily or by manual dispatch, validates the full managed runtime tree, and pushes successful update commits to `main`.

## Static configuration ownership

The addon updater intentionally does not copy incoming release files into either of these tracked paths:

- `server/game/csgo/cfg/`
- `server/game/csgo/addons/counterstrikesharp/configs/`

Those paths are reserved for fixed/user-managed settings. The workflow records their file list and SHA-256 hashes before updating, then fails if any file is added, removed, or changed. Edit those settings deliberately; upstream release archives cannot replace them. The normal `win.bat` overlay still merges the tracked staging tree into the KUS server installation.

The optional `custom_files/` directory remains available as a final KUS-compatible override layer, but it is not part of the addon release updater.

## License

Third-party plugins remain under their respective upstream licenses. This repository manages the installation/merge layer and our own configuration files.


## Private configuration and local overrides

This repository is intended to remain **private**. The tracked files under `server/game/csgo/cfg/` and `server/game/csgo/addons/counterstrikesharp/configs/` contain project-specific settings and are treated as user-managed configuration, not as upstream plugin payloads.

The addon updater never copies release ZIP files over those protected configuration paths. The GitHub workflow snapshots their file list and SHA-256 hashes before each update and verifies that the updater did not add, remove, or change them.

`custom_files/` and the ignored `custom_files_secret/` folder remain optional local override layers that are merged after the tracked addon overlay. For `custom_files_secret/`, mirror the path that the file should have inside `server/game/csgo/`; it is machine-local and must not be committed.

Keep this repository private while it contains personal configuration or credentials. Since previous versions may have been visible before the repository was made private, rotate any credentials that were exposed in earlier public commits.