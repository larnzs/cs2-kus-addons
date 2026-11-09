# Add-on updater and catalog automation

This documentation describes the updater maintained by **cs2-kus-addons**. It is not the upstream KUS installation guide.

The root [README.md](../../README.md) is the canonical, combined plugin catalog. Each row contains an upstream source link, displayed version/revision, payload location, activation behavior, and an updater or bundle link. The Bash catalog pass and the manifest pass share that table but do not process the same add-on twice.

## Update domains

| Domain | Source of truth | Updater |
| --- | --- | --- |
| KUS-origin plugins and native add-ons | Root README catalog rows not owned by `DEPENDENCIES.json` (except Metamod, which has special manifest synchronization) | `scripts/update/update.sh` and `scripts/update/plugins/*.sh` |
| Larnz release/source-build add-ons | `DEPENDENCIES.json` plus the corresponding row in root README | Manifest pass in `scripts/update/update.sh`, or `scripts/Update-Addons.ps1` on Windows |
| Bundled components | Parent bundle entry in `DEPENDENCIES.json` | Parent adapter only; no standalone release tracking |

The KUS parser reads the first `Mod | Version | Purpose` table in README. The combined catalog therefore keeps `Mod`, `Version / revision`, and `Purpose` as its first three columns. The orchestrator filters manifest-owned names out of the Bash catalog pass; the manifest pass processes them afterward. `Metamod:Source` remains in the Bash pass because its dedicated adapter also updates its manifest record.

## Running the updater

Run from a clean checkout of this repository:

```bash
# Inspect available changes without applying commits.
bash scripts/update/update.sh --dry-run

# List the KUS-origin rows handled by the Bash catalog pass.
bash scripts/update/update.sh --list

# Apply all available KUS catalog and automated manifest updates.
bash scripts/update/update.sh

# Restrict the run to one KUS catalog entry or manifest entry.
bash scripts/update/update.sh --only "K4-Arenas"
bash scripts/update/update.sh --only "CS2-Gunsmenu"

# Do not fast-forward from the remote first.
bash scripts/update/update.sh --dry-run --no-pull
```

A local apply run needs a clean working tree. Each successful plugin update is committed separately. If one adapter fails after changing files, only that plugin's uncommitted changes are rolled back; subsequent plugins continue where safe. Successful earlier commits remain available for publishing. Never run shared payload updates while a CS2 instance is active.

The script uses GitHub release metadata and configured source snapshots. Set `GITHUB_TOKEN` to avoid unauthenticated API rate limits. Source-built Manifest entries require the .NET SDK declared by the repository workflows (currently SDK 8 and 10 side-by-side).

## Windows manifest maintenance

```bat
windows\addons-update.bat -DryRun
windows\addons-update.bat
```

The PowerShell updater processes the Manifest entries and their release/source-build mappings. It verifies required files, preserves operator-managed configuration, and commits successful add-on changes. The Windows runtime updater can publish successful commits and then fast-forward the checkout before runtime deployment.

## Scheduled automation

- Full updater: the entire KUS catalog and all automation-enabled Manifest add-ons are checked every 5 minutes at UTC minutes 2, 7, 12, 17, 22, 27, 32, 37, 42, 47, 52, and 57.
- Manual priority allowlist: available through `workflow_dispatch` for targeted checks; it is not scheduled separately.
- Both workflows serialize writes to `integration/kus-monorepo` using the shared `addon-updater` concurrency group.
- GitHub may delay scheduled jobs; the cron schedule is not an exact execution-time guarantee.
- The workflows update the tracked repository payload. They do not modify files inside an already-running CS2 server process.

## Catalog coverage and exceptions

The root catalog currently has 75 rows:

- 74 entries are mapped to a dedicated updater or a documented owning bundle.
- 72 distinct adapter files are linked in the catalog; some adapters manage more than one row or bundle component.
- `MenuManagerCS2` and `GG1MapChooser` are bundled by GameModeManager and do not receive independent release adapters.
- `CS2-WeaponRestrict` is not installed or staged and is explicitly manual-only.
- Plugins under `plugins/disabled/` remain update-managed; only their runtime loading is controlled by game-mode CFGs.

The strict check is:

```bash
python3 scripts/Test-CatalogCoverage.py --strict
```

It checks that every catalog row has an upstream link, no duplicate plugin name exists, every updater link resolves to a real script, each script can be sourced, all declared payload paths exist, all automated Manifest entries are covered, and the updater's KUS/Manifest partition does not overlap. It also validates the manual priority and first-release adapter lists.

## Adapter rules

- Each script lives under `scripts/update/plugins/<slug>.sh`, where slug is the lower-case name with non-alphanumeric runs replaced by hyphens.
- A script declares every path it can write in `PLUGIN_PATHS`.
- Release adapters match exact upstream asset patterns and fail closed on missing or ambiguous archives.
- Source-built Manifest entries use the shared helper in `scripts/update/manifest-addon.sh` and record full commit SHA values in `DEPENDENCIES.json`; README displays `branch@12-character-SHA`.
- Preserve local configuration/data explicitly. Never widen a plugin's write scope merely to make an archive fit.
- Mode-specific payloads remain in their tracked disabled folders. Do not edit CFG activation commands as part of an update.

## Existing plugin scripts

The following are the adapter entrypoints currently tracked in this repository.

| Adapter path | |
| --- | --- |
| `plugins/abs-mapcycle.sh` | Tracked updater adapter |
| `plugins/advancedfriendlyfire.sh` | Tracked updater adapter |
| `plugins/afkmanager.sh` | Tracked updater adapter |
| `plugins/announcementbroadcaster.sh` | Tracked updater adapter |
| `plugins/anybaselibcs2.sh` | Tracked updater adapter |
| `plugins/counterstrikesharp.sh` | Tracked updater adapter |
| `plugins/cs2-advanced-weapon-system.sh` | Tracked updater adapter |
| `plugins/cs2-advertisement.sh` | Tracked updater adapter |
| `plugins/cs2-antibait.sh` | Tracked updater adapter |
| `plugins/cs2-customvotes.sh` | Tracked updater adapter |
| `plugins/cs2-deathmatch.sh` | Tracked updater adapter |
| `plugins/cs2-execafter.sh` | Tracked updater adapter |
| `plugins/cs2-executes.sh` | Tracked updater adapter |
| `plugins/cs2-fixrandomspawn.sh` | Tracked updater adapter |
| `plugins/cs2-gamemodifiers.sh` | Tracked updater adapter |
| `plugins/cs2-gunsmenu.sh` | Tracked updater adapter |
| `plugins/cs2-instadefuse.sh` | Tracked updater adapter |
| `plugins/cs2-kill-plugin.sh` | Tracked updater adapter |
| `plugins/cs2-killfeedfilter.sh` | Tracked updater adapter |
| `plugins/cs2-mutualscoringplayers.sh` | Tracked updater adapter |
| `plugins/cs2-oneinthechamber.sh` | Tracked updater adapter |
| `plugins/cs2-playermodelchanger.sh` | Tracked updater adapter |
| `plugins/cs2-playervotes.sh` | Tracked updater adapter |
| `plugins/cs2-poor-mappropads.sh` | Tracked updater adapter |
| `plugins/cs2-quake-sounds.sh` | Tracked updater adapter |
| `plugins/cs2-ranks.sh` | Tracked updater adapter |
| `plugins/cs2-remove-map-weapons.sh` | Tracked updater adapter |
| `plugins/cs2-retakes-allocator.sh` | Tracked updater adapter |
| `plugins/cs2-retakes.sh` | Tracked updater adapter |
| `plugins/cs2-showdamage.sh` | Tracked updater adapter |
| `plugins/cs2-simpleadmin.sh` | Tracked updater adapter |
| `plugins/cs2-stafflist.sh` | Tracked updater adapter |
| `plugins/cs2-tags.sh` | Tracked updater adapter |
| `plugins/cs2-teamlimiter.sh` | Tracked updater adapter |
| `plugins/cs2-teleportkill.sh` | Tracked updater adapter |
| `plugins/cs2-weaponspeed.sh` | Tracked updater adapter |
| `plugins/cs2-whitelist.sh` | Tracked updater adapter |
| `plugins/cs2faceitlevels.sh` | Tracked updater adapter |
| `plugins/cs2fixes-rampbugfix.sh` | Tracked updater adapter |
| `plugins/cs2funmatchplugin.sh` | Tracked updater adapter |
| `plugins/cs2rcon.sh` | Tracked updater adapter |
| `plugins/cs2updatemonitor.sh` | Tracked updater adapter |
| `plugins/cs2warcraftmod.sh` | Tracked updater adapter |
| `plugins/deathrun-manager.sh` | Tracked updater adapter |
| `plugins/game-mode-manager.sh` | Tracked updater adapter |
| `plugins/gamemodemanager.sh` | Tracked updater adapter |
| `plugins/gungame.sh` | Tracked updater adapter |
| `plugins/inventory-simulator.sh` | Tracked updater adapter |
| `plugins/jrandomskills.sh` | Tracked updater adapter |
| `plugins/k4-arenas.sh` | Tracked updater adapter |
| `plugins/k4-damageinfo.sh` | Tracked updater adapter |
| `plugins/mapconfigurator.sh` | Tracked updater adapter |
| `plugins/matchzy.sh` | Tracked updater adapter |
| `plugins/metamod-source.sh` | Tracked updater adapter |
| `plugins/movementunlocker.sh` | Tracked updater adapter |
| `plugins/multiaddonmanager.sh` | Tracked updater adapter |
| `plugins/openprefireprac.sh` | Tracked updater adapter |
| `plugins/playersettingscs2.sh` | Tracked updater adapter |
| `plugins/rollthedice.sh` | Tracked updater adapter |
| `plugins/serverlistplayersfix.sh` | Tracked updater adapter |
| `plugins/sharptimer.sh` | Tracked updater adapter |
| `plugins/simpleadmin.sh` | Tracked updater adapter |
| `plugins/simpleresetscore.sh` | Tracked updater adapter |
| `plugins/slayer-anticamp.sh` | Tracked updater adapter |
| `plugins/slayer-football.sh` | Tracked updater adapter |
| `plugins/slayer-headshotonly.sh` | Tracked updater adapter |
| `plugins/slayer-noscope.sh` | Tracked updater adapter |
| `plugins/slayer-revive.sh` | Tracked updater adapter |
| `plugins/spectatorlist-cs2.sh` | Tracked updater adapter |
| `plugins/stfixes.sh` | Tracked updater adapter |
| `plugins/vipcore-modules.sh` | Tracked updater adapter |
| `plugins/vipcore.sh` | Tracked updater adapter |
| `plugins/weaponpaints.sh` | Tracked updater adapter |

## Files

- `DEPENDENCIES.json` — Manifest source of truth.
- `README.md` — unified plugin version and updater table.
- `scripts/update/update.sh` — Bash orchestrator.
- `scripts/update/lib.sh` — shared updater helpers and safety boundaries.
- `scripts/update/manifest-addon.sh` — Manifest release/source-build helpers.
- `scripts/update/catalog-plugin.sh` — catalog ZIP extraction and overlay helpers.
- `scripts/Test-AllUpdaters.sh` — Bash updater hard checks.
- `scripts/Test-CatalogCoverage.py` — README/Manifest/path coverage audit.
