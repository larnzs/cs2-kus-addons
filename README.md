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

The repository's \`server/game/csgo/\` directory is a **staging/overlay tree**, not a second CS2 installation.

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
| [WeaponPaints](https://github.com/Nereziel/cs2-WeaponPaints) | build-466 | Additional player-side game customization plugin. |
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
| [SLAYER_AntiCamp](https://github.com/zakriamansoor47/SLAYER_AntiCamp) | v1.2.5 | Detects and handles excessive camping according to configuration. |
| [SLAYER_HeadshotOnly](https://github.com/zakriamansoor47/SLAYER_HeadshotOnly) | v1.2.1 | Provides a headshot-only gameplay mode. |
| [CS2-TeamLimiter](https://github.com/Ferks-FK/CS2-TeamLimiter) | — | Limits the maximum number of players on each team. |
| [CS2-WeaponRestrict](https://github.com/TICHOJEBEC-SK/CS2-WeaponRestrict) | WeaponRestrict1.5 | Applies configurable gameplay restrictions. |

> **Version note:** \`cs2-showdamage\` is intentionally pinned to \`1.1.0\`. The two addons marked as manual in \`DEPENDENCIES.json\` remain tracked but are not processed by the automated Windows updater.

## Dependency order

Dependencies are explicit in [DEPENDENCIES.json](./DEPENDENCIES.json). The Windows updater verifies dependencies before installing an addon.

The core chain is:

\`\`\`text
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
\`\`\`

Examples:

- CounterStrikeSharp requires KUS's Metamod:Source.
- PlayerSettingsCS2 requires CounterStrikeSharp and AnyBaseLibCS2.
- MenuManagerCS2 requires CounterStrikeSharp and PlayerSettingsCS2.
- CS2-SimpleAdmin requires CounterStrikeSharp, AnyBaseLibCS2, PlayerSettingsCS2 and MenuManagerCS2.

## Windows workflow

### 1. First install / update the addon layer

Run:

\`\`\`bat
addons-update.bat -DryRun -Only CounterStrikeSharp
addons-update.bat -Only CounterStrikeSharp
\`\`\`

The updater downloads the configured GitHub release, keeps the archive and extracted tree under:

\`\`\`text
tmp/
└── releases/
    └── <addon>/
        └── <version>/
            ├── <release>.zip
            ├── extract-<release>/
            ├── layout-<release>.txt
            └── release-<release>.json
\`\`\`

It then detects the release's real CS2 root and merges that tree directly into:

\`\`\`text
server/game/csgo/
\`\`\`

So the repository stores the **extracted runtime tree**, just like KUS does.

For example, when a CounterStrikeSharp Windows release has \`addons/\` at the archive root, that exact tree is placed at:

\`\`\`text
<release>/addons/...  ->  server/game/csgo/addons/...
\`\`\`

No extra \`CounterStrikeSharp/\` directory is inserted.

The updater never deletes files from that staging tree. It only creates/overwrites paths supplied by the upstream release.

Run the next addon only after the previous layer is verified.

### 2. Start the server

Run:

\`\`\`bat
win.bat
\`\`\`

\`win.bat\` uses the KUS repository as the base, applies the same KUS Metamod gameinfo patch, rebuilds KUS's generated server areas, then applies this repository's overlay.

The KUS base cleanup is intentionally performed **before** our overlay is copied. That prevents old KUS-managed files from surviving a KUS update while ensuring our layer is restored immediately afterwards.

### 3. Full update + start

Run:

\`\`\`bat
update.bat
\`\`\`

This does:

1. \`git pull\` for \`cs2-kus-addons\`
2. \`git pull --ff-only\` for the KUS base repository
3. Runs \`win.bat\`

Addon release updates are intentionally a separate operation:

\`\`\`bat
addons-update.bat
\`\`\`

This keeps normal server startup predictable and avoids downloading third-party releases every time the server starts.

## KUS base location

Edit [win.ini](./win.ini):

\`\`\`ini
KUS_ROOT=..\\cs2-modded-server
\`\`\`

The default assumes this layout:

\`\`\`text
parent/
├── cs2-modded-server/
└── cs2-kus-addons/
\`\`\`

The KUS repository is not copied into this repository and is not vendored here.

## File layout

\`\`\`text
cs2-kus-addons/
├── DEPENDENCIES.json
├── README.md
├── win.ini
├── win.bat
├── update.bat
├── addons-update.bat
├── server/
│   └── game/
│       └── csgo/
└── scripts/
    └── Update-Addons.ps1
\`\`\`

## Updating addon versions

The release updater uses [DEPENDENCIES.json](./DEPENDENCIES.json) as the source of truth.

Useful commands:

\`\`\`bat
addons-update.bat -DryRun
addons-update.bat -DryRun -Only CounterStrikeSharp
addons-update.bat -Only CounterStrikeSharp
addons-update.bat -Force -Only CounterStrikeSharp
\`\`\`

The updater:

- checks the configured GitHub release/tag
- selects the exact asset pattern from the manifest
- downloads and extracts the archive
- verifies that a CS2 \`addons/\` tree can be found
- merges files into the staging tree without deleting unrelated files
- updates the version state in \`DEPENDENCIES.json\`
- updates the matching README table row
- supports source builds for addons that do not publish releases

It does **not** push or commit automatically. Review with \`git status\` and commit/push the resulting changes yourself.

## Custom files

Our custom configuration belongs in the repository's \`custom_files/\` directory and is applied after both the KUS base and the addon overlay.

This follows the same general layering model as KUS while keeping ownership separate:

**KUS owns the base.**  
**cs2-kus-addons owns the extra layer.**

## License

Third-party plugins remain under their respective upstream licenses. This repository manages the installation/merge layer and our own configuration files.
