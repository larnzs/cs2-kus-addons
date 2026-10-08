# CS2 KUS Addons

Additional plugins and libraries for [KUS/cs2-modded-server](https://github.com/kus/cs2-modded-server).

This repository is an **add-on layer** on top of KUS. KUS remains responsible for the base CS2 dedicated server, its own bundled mods/plugins, and its own update system. This repository only adds the extra plugins and files we choose to run.

## How this repository works

The most important rule is simple:

> **This repository never deletes files from the server. It only merges/adds its files on top of the existing installation.**

When the installer/update process runs, files from this repository are copied/extracted into the existing server paths.

- Existing unrelated files are left untouched.
- If an add-on provides a file at a path that already exists, that file is overwritten by the add-on's copy.
- Nothing is removed just because it is not present in this repository.
- Custom files are applied after the add-ons, so they can override add-on defaults.

This makes the repository a persistent, non-destructive add-on layer over the KUS base rather than a replacement for it.

## KUS vs. cs2-kus-addons

| Part | Owner |
| --- | --- |
| Base CS2 dedicated server | KUS |
| KUS game modes and bundled plugins | KUS |
| KUS base updates | KUS |
| Extra plugins listed below | cs2-kus-addons |
| Extra plugin dependencies | cs2-kus-addons |
| Our custom configs/files | cs2-kus-addons |
| Installation/merge logic for these add-ons | cs2-kus-addons |

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
| [CounterStrikeSharp](https://github.com/roflmuffin/CounterStrikeSharp) | 1.0.376 | The .NET scripting framework used by our CounterStrikeSharp plugins. Its runtime is required by the server-side plugins in this layer. |
| [WeaponPaints](https://github.com/Nereziel/cs2-WeaponPaints) | build-466 | Provides player weapon, knife, glove and agent cosmetic/inventory features. |
| [CS2-SimpleAdmin](https://github.com/daffyyyy/CS2-SimpleAdmin) | 1.9.0 | Provides extended administration functionality for the server. |
| [AFKManager](https://github.com/NiGHT757/AFKManager) | 0.2.8 | Detects AFK players and applies the configured AFK handling. |
| [CS2-Kill-Plugin](https://github.com/Quantor97/CS2-Kill-Plugin) | 0.2.0 | Adds player suicide commands such as !suicide and /suicide. |
| [SimpleResetScore](https://github.com/stefanx111/cs2-SimpleResetScore) | 1.0.7 | Lets players reset their own score. |
| [cs2-showdamage](https://github.com/abnerfs/cs2-showdamage) | 1.1.0 | Shows damage information to players during gameplay. |
| [cs2-ranks](https://github.com/partiusfabaa/cs2-ranks) | v2.0.5.5-recompile | Provides persistent player ranks, statistics and progression backed by a database. |
| [VIPCore](https://github.com/partiusfabaa/cs2-VIPCore) | v1.3.4-recompile3 | Provides the VIP core/module used for VIP functionality. |
| [AnyBaseLibCS2](https://github.com/NickFox007/AnyBaseLibCS2) | 0.9.4 | Shared database/API library required by other add-ons in this layer. |
| [PlayerSettingsCS2](https://github.com/NickFox007/PlayerSettingsCS2) | 0.9.4 | Provides persistent player settings used by dependent plugins. |
| [MenuManagerCS2](https://github.com/NickFox007/MenuManagerCS2) | 1.4.1 | Provides menu/API functionality used by dependent plugins. |
| [SLAYER_AntiCamp](https://github.com/zakriamansoor47/SLAYER_AntiCamp) | v1.2.5 | Detects and handles excessive camping according to the configured rules. |
| [SLAYER_HeadshotOnly](https://github.com/zakriamansoor47/SLAYER_HeadshotOnly) | v1.2.1 | Provides a headshot-only gameplay mode. |
| [CS2-TeamLimiter](https://github.com/Ferks-FK/CS2-TeamLimiter) | — | Limits the maximum number of players on each team. |
| [CS2-WeaponRestrict](https://github.com/TICHOJEBEC-SK/cs2-WeaponRestrict) | WeaponRestrict1.5 | Restricts selected weapons according to the server configuration. |

> **Version note:** Versions above are the releases currently tracked for this repository. cs2-showdamage is intentionally pinned to 1.1.0.

## Installation order

The table above is the addon catalog. The installer will use a **dependency-safe installation order** instead of blindly following the table order.

The first layer is always:

1. CounterStrikeSharp + runtime
2. AnyBaseLibCS2
3. PlayerSettingsCS2
4. MenuManagerCS2
5. Plugins that depend on those libraries
6. Remaining plugins
7. Custom files last

The exact order may be adjusted as individual release packages and dependencies are verified.

## Updating

The intended flow is:

1. KUS updates the base server.
2. This repository installs/updates CounterStrikeSharp and its runtime.
3. This repository merges required libraries/dependencies.
4. This repository merges the selected add-ons.
5. Custom files are merged last.
6. The server starts.

Running the add-on installer again should be safe: it can overwrite files it owns, but it does not delete unrelated server files.

## Custom files

Our custom configuration will live in the repository's custom-file layer and will be applied after third-party add-ons.

This follows the same general idea as KUS's custom_files system while keeping the ownership boundary clear:

**KUS owns the base.**  
**cs2-kus-addons owns the extra layer.**

## License

Third-party plugins remain under their respective upstream licenses. This repository manages the installation/merge layer and our own configuration files.
