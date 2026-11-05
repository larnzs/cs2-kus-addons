# CounterStrikeSharp mode plugin lifecycle

## One reset point per mode switch

Every primary game-mode CFG contains exactly one:

```cfg
exec unload_plugins.cfg
```

It must appear before any `css_plugins` command in that mode CFG. The central file unloads each manually loadable plugin DLL by its exact relative DLL path. A mode CFG then loads only the plugins required for that mode.

This is an explicit reset list, not `css_plugins unload all`: CounterStrikeSharp core and plugins intended to remain universal must not be disabled by a mode switch. The list does not include every DLL under `plugins/disabled/`; plugin dependencies and modules that are never manually loaded by mode CFGs are not entry points and are intentionally excluded.

## Rules for plugin commands

- Every manual `css_plugins load` must use one quoted, relative path such as `plugins/disabled/AFKManager/AFKManager.dll`.
- Every DLL path used by `load`, `unload`, or `reload` must exist and appear in `unload_plugins.cfg`.
- Do not load plugins by display name/module name. Explicit DLL paths make unload matching deterministic and avoid ambiguity.
- Do not put plugin loads in `custom_*.cfg`, `*_settings.cfg`, or warmup snippets unless the lifecycle policy and reset behavior are deliberately updated.
- `CS2Rcon` is the only module-name exception: Competitive/Practice-style modes may unload it while MatchZy owns the mode; the central reset reloads it once for the next mode transition.
- When adding a plugin load, add the exact DLL path to `unload_plugins.cfg`. When adding a primary game mode, add it to the AFK policy and explicitly decide whether AFKManager should be enabled.

## AFKManager policy

AFKManager is stored under:

`addons/counterstrikesharp/plugins/disabled/AFKManager/AFKManager.dll`

Every primary mode transition unloads it through the central reset. It is then loaded only by the explicit allowlist below. AFKManager must not be loaded from a custom, settings, warmup, or other nested CFG.

**Enabled modes:** Casual, Casual 1.6, Casual Active, Casual Workshop, Aim, AWP, AWP Aim, Battle Ball, Battle Royale, CTF, Deathmatch, Gun Game, Minigames, One in the Chamber, ScoutzKnivez, Soccer, Valve Arms Race, Valve Deathmatch FFA, Valve Deathmatch, and VIP.

**Disabled modes:** 1v1 Arenas, Competitive 45°, Bhop, Competitive, Course, Deathrun, Executes, Hide N Seek, KZ, Practice, Prefire, Retakes, Surf, Valve Competitive, Valve Retake, Valve Wingman, and Wingman.

The machine-readable allowlist lives in `scripts/plugin-mode-policy.json`.

## Automated hardcheck

`scripts/validate-plugin-lifecycle.py` recursively scans every CFG and checks:

- all `css_plugins` commands are syntactically recognized and use one target argument;
- every manually loaded plugin uses an explicit DLL path, exists on disk, and is present in the central unload list;
- central unload entries exist and are not duplicated;
- every primary mode CFG contains exactly one central reset before its plugin commands;
- `CS2Rcon` follows its single documented unload/reload exception;
- the AFK policy covers every primary mode CFG, with exactly one load in each enabled mode and no loads elsewhere.

The `KUS payload layout checks` GitHub Actions workflow runs this validator whenever the CFG tree, lifecycle policy, validator, or lifecycle documentation changes.
