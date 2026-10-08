# cs2-kus-addons

Addon layer for [KUS/cs2-modded-server](https://github.com/kus/cs2-modded-server).

## Ownership

- **KUS** owns the base server and its bundled mods/plugins.
- **cs2-kus-addons** owns the additional addon layer and custom files.
- **KUS SimpleAdmin** stays installed.
- **Daffy CS2-SimpleAdmin** is installed alongside KUS SimpleAdmin.
- **MultiAddonManager** and **ServerListPlayersFix** are intentionally not managed by this repository.

## Installed addons

See [DEPENDENCIES.json](./DEPENDENCIES.json) for the current tracked addon list.

## Installation architecture

1. Update the KUS base.
2. Install/update CounterStrikeSharp and its runtime.
3. Install addon dependencies in the required order.
4. Install the remaining addons.
5. Merge custom files last.
6. Start the server.

The repository should track upstream sources and installation logic rather than vendor third-party plugin binaries.
