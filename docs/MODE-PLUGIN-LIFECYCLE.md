# CounterStrikeSharp mode plugin lifecycle

## One reset point per mode switch

Every primary game-mode CFG starts with:

```cfg
exec unload_plugins.cfg
```

That file is the central reset list for every plugin DLL that can be manually loaded by a CFG. It uses the exact DLL path, not a display name. The plugin-specific CFG then loads only the plugins required by that mode.

The reset list intentionally does **not** contain every DLL stored below `plugins/disabled/`. Most DLLs in plugin folders are dependencies, and some plugins (for example `Ranks_Tag`, `VIP_NightVip`, and `VIP_Random`) are intentionally never loaded by a game-mode CFG. Only actual plugin entry points that can be manually loaded need a matching central unload command.

`CS2Rcon` is a special case: Competitive/Practice CFGs unload it while MatchZy owns the mode, and the central reset reloads it for the next mode transition.

## AFKManager policy

AFKManager is stored under:

`addons/counterstrikesharp/plugins/disabled/AFKManager/AFKManager.dll`

Every mode transition unloads it first. Only the allowlisted game-mode CFGs load it again. This prevents it leaking from Deathmatch or Casual into a mode where anti-camp is inappropriate.

**Enabled modes:** Casual, Casual 1.6, Casual Active, Casual Workshop, Aim, AWP, AWP Aim, Battle Ball, Battle Royale, CTF, Deathmatch, Gun Game, Minigames, One in the Chamber, ScoutzKnivez, Soccer, Valve Arms Race, Valve Deathmatch FFA, Valve Deathmatch, and VIP.

**Disabled modes:** 1v1 Arenas, Competitive 45°, Bhop, Competitive, Course, Deathrun, Executes, Hide N Seek, KZ, Practice, Prefire, Retakes, Surf, Valve Competitive, Valve Retake, Valve Wingman, and Wingman.

The machine-readable allowlist lives in `scripts/plugin-mode-policy.json`.

## Validation rule

`scripts/validate-plugin-lifecycle.py` scans every CFG recursively and checks that:

- every path-based `css_plugins load` points to an existing DLL;
- every path-based load has the same exact path in `unload_plugins.cfg`;
- a mode CFG resets plugins before loading its mode-specific set;
- the AFKManager policy covers every primary mode CFG and matches its load command exactly.

The payload-layout GitHub Actions workflow runs this validator on changes to the CFG tree, lifecycle policy, or validator itself. When introducing a new manually loaded plugin, add its exact DLL path to `unload_plugins.cfg`; when adding a new game mode, add it to the AFK policy and decide explicitly whether AFKManager should run there.
