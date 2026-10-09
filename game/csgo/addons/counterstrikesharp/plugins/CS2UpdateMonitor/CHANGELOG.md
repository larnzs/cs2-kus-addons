# Changelog

## 1.1.0

- Added persistent maintenance state across hot reloads.
- Added map-transition deferral and post-map grace periods.
- Added per-build automatic restart limits and retry cooldowns.
- Added monotonic countdown timing and schedule-race protection.
- Isolated chat and center-message failures from shutdown execution.
- Added atomic state persistence, corrupt-state recovery, and stricter config validation.
- Added separate SteamCMD metadata and update-install timeouts.
- Added Pterodactyl SteamCMD path auto-detection.

## 1.0.2

- Fixed CounterStrikeSharp native access from a background thread.
- Added update-check error reporting through `css_updatestatus`.

## 1.0.1

- Replaced hibernation-sensitive timers with a pre-world-update listener.
- Changed plugin author to `beanman109`.

## 1.0.0

- Initial release.
