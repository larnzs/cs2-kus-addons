# CS2 KUS Addons — Larnz Unified Server

A private, single-repository Counter-Strike 2 dedicated-server distribution. It combines the KUS server setup, its bundled plugins and dependency files with the Larnz-managed add-ons and configuration layout.

**The repository's canonical runtime path is server/game/csgo/.** The old KUS staging path, game/csgo/, is not used as a second source tree. KUS runtime payloads—including its Windows-specific add-on payload—are imported directly into the canonical path. There is no second KUS checkout and no batch step that copies all plugins from a staging folder into the server.

The full original Larnz guide is preserved at [docs/Larnz-Addons-README.md](docs/Larnz-Addons-README.md). The complete KUS guide and its tables are included below for reference. When an older upstream section describes the old staging/copy workflow, use the unified installation commands in this introduction instead.

## Repository ownership and paths

| Path | Purpose |
| --- | --- |
| server/ | Canonical SteamCMD installation root. The large downloaded game binaries remain local and are not committed. |
| server/game/csgo/addons/ | KUS and Larnz plugin payloads in their final runtime locations. |
| server/game/csgo/cfg/ | Runtime configuration tree. Existing Larnz settings are preserved during KUS imports. |
| DEPENDENCIES.json | Larnz add-on updater manifest. |
| scripts/update/ | Upstream KUS update helpers, retained and path-normalized for the unified layout. |
| examples/run-template/ | Reusable Windows runner and VBS supervisor template. |
| docs/upstream/ | KUS source snapshot metadata and archived upstream entrypoints/workflows. |

The KUS root-level custom_files/ and custom_files_example/ trees are not imported or merged. Personal configuration generation and custom files remain under the Larnz-managed configuration workflow. Existing local secret folders and per-instance settings must stay private.

## Windows installation and operation

1. Clone this private repository to the server machine.
2. Run install.bat. It downloads SteamCMD if needed, installs CS2 into server/ only when the required game files are missing, and runs win.bat to validate the installation and ensure the Metamod entry is present.
3. In examples/run-template/, copy instance.example.ini to instance.ini and edit the instance settings and secrets. Then launch run.vbs.

win.bat does not copy or delete the addons/ directory, does not merge a second repository and does not run SteamCMD. update.bat only pulls this unified Git repository and validates the server. Neither script updates the CS2 game on an ordinary server restart.

To refresh Larnz-managed add-ons from the upstream releases, use addons-update.bat -DryRun to inspect the proposed changes, then run addons-update.bat when ready. This is separate from repository pulls and server restarts.

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

## Upstream attribution and license

The KUS source is [kus/cs2-modded-server](https://github.com/kus/cs2-modded-server). Its full guide, release table, game-mode documentation, dependency notes and troubleshooting material are preserved below. The upstream LGPL-3.0 license is retained in LICENSE; third-party plugins continue to be subject to their own licenses.

This is a private integrated distribution, not an official KUS release. The archived original KUS installer scripts and automation definitions are in docs/upstream/kus-original/ for reference; the unified scripts in this repository define the active one-repository path behavior.
