# CS2 KUS Addons — Larnz Unified Server

A private, single-repository Counter-Strike 2 dedicated-server distribution. It combines the KUS server setup, its bundled plugins and dependency files with the Larnz-managed add-ons and configuration layout.

**The repository follows KUS's staged payload model.** `game/csgo/` is the tracked source payload; `server/` is the local Windows SteamCMD install ignored by Git. Windows deploys the payload into `server/game/csgo/` and flattens `game/csgo/addons/windows/` only at deployment time.

The full original Larnz guide is preserved at [docs/Larnz-Addons-README.md](docs/Larnz-Addons-README.md). The complete KUS guide and its tables are included below for reference. When an older upstream section describes the old staging/copy workflow, use the unified installation commands in this introduction instead.

## Repository ownership and paths

| Path | Purpose |
| --- | --- |
| `server/` | Local SteamCMD installation root; downloaded game binaries remain local and are not committed. |
| `windows/` | Windows BAT entrypoints and the external Instance runner template. |
| `linux/` | Linux install/start/stop helpers and the Google Cloud VM bootstrap. |
| `docker/` | Dockerfile, Compose file, Docker installer, and legacy Kubernetes manifest. |
| `.dockerignore` | Intentionally remains at repo root for the repo-root Docker build context. |
| `game/csgo/addons/` | Tracked KUS and Larnz plugin payload source. |
| `game/csgo/cfg/` | Tracked shared configuration source, deployed into the installed runtime. |
| DEPENDENCIES.json | Larnz add-on updater manifest. |
| scripts/update/ | Upstream KUS update helpers, retained and path-normalized for the unified layout. |
| windows/instance-template/ | Reusable Windows runner and VBS supervisor template. |
| docs/upstream/ | Archived KUS source/docs and historical entrypoints. The completed one-time payload-migration workflow is archived here, not registered as an executable GitHub Actions workflow. |

The KUS root-level custom_files/ and custom_files_example/ trees are not imported or merged. Personal configuration generation and custom files remain under the Larnz-managed configuration workflow. Existing local secret folders and per-instance settings must stay private.

## Windows installation and operation

1. Clone this private repository to the server machine.
2. Run `windows/install.bat`. It downloads SteamCMD if needed and runs KUS-style `app_update 730` against `server/`, then calls `windows/win.bat` to deploy `game/csgo/`, patch installed `gameinfo.gi`, and verify the runtime. It does not start the server.
3. In windows/instance-template/, copy instance.example.ini to instance.ini and edit the instance settings and secrets. Then launch run.vbs.

`windows/win.bat` deploys tracked `game/csgo/` to `server/game/csgo/` and flattens the Windows overlay; it does not run SteamCMD or start CS2. `windows/update.bat` pulls the private repository and redeploys the payload. Regular server starts do not run an updater.

To refresh Larnz-managed add-ons from the upstream releases, use windows/addons-update.bat -DryRun to inspect the proposed changes, then run windows/addons-update.bat when ready. This is separate from repository pulls and server restarts.

## Larnz-managed add-ons

These add-ons are maintained by the Larnz manifest/updater in addition to the KUS payloads. Some libraries are shared dependencies and remain separate from the KUS documentation's own plugin table.

| Add-on | Version | Purpose |
| --- | --- | --- |
| CounterStrikeSharp | 1.0.376 | Windows with-runtime files are staged under `game/csgo/addons/windows/addons/counterstrikesharp/`; shared/Linux payload remains under `game/csgo/addons/counterstrikesharp/`. |
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
