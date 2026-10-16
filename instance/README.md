# FragCity Instance Payload Seeder

This is the **initial payload seeding** stage for the Pterodactyl-oriented `instancer`
branch. It is not yet the complete Pterodactyl provisioning integration.

## Setup

From the repository root on the trusted Debian Node:

```bash
cp instance/instance.example.env instance/instance.env
sudo nano instance/instance.env
sudo chmod 600 instance/instance.env
```

Set `INSTANCE_STORAGE_ROOT` to a host-side path outside the Git checkout. The script needs
write permission to that location. Do not source an `instance.env` supplied by a customer
or arbitrary API input.

## Preview and seed

```bash
sudo bash instance/create-instance.sh --dry-run aim-hs
sudo bash instance/create-instance.sh aim-hs
```

Output structure:

```text
<INSTANCE_STORAGE_ROOT>/aim-hs/
├── .fragcity-seed.json
└── game/
    └── csgo/
        ├── addons/
        ├── cfg/
        └── *.txt
```

## Inclusion rules

- Copy the full tracked `addons/` tree except `addons/windows/` (Windows-only staging).
- Copy the full tracked `cfg/` tree, including its initial configuration baseline.
- Copy all top-level `*.txt` files from `game/csgo/` (game-mode/map data).
- Do not copy `gameinfo.gi`, other root files, or the shared CS2 binaries/Base Game.
- Do not install/update CS2 or Steam Linux Runtime, start/stop a server, or call the Panel API.

The source payload must be committed and clean. Invalid IDs and existing destination folders
are rejected; existing Instances are never overwritten. Copy is non-destructive and has no
delete mode. A non-secret `.fragcity-seed.json` records the source commit.

The instance root is created with mode `0750`; payload paths are adjusted to be group-readable
but not world-readable. Optional `INSTANCE_OWNER` and `INSTANCE_GROUP` can set ownership for
a future mount, but only configure them after the Node UID/GID model is established. If either
is set, run the script as root.

This is a **one-time initial seed**, not a per-start updater. Subsequent managed plugin/runtime
updates must use a separate allowlisted flow that protects customer configuration paths.
Base Game updates are coordinated at Node level.

## Still to integrate

The next Pterodactyl PoC must decide how this private payload is connected to the shared
Base Game inside the server container (for example, a tested OverlayFS/mount design), then
automate Panel server creation, allocations, permissions, rollback and cleanup. This script
alone does not create a Pterodactyl server or mount the payload.
