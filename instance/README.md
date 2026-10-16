# FragCity Linux Instance Seeder

This script creates a complete Linux Instance bundle from the committed CS2-KUS payload
and the tracked Linux Instance template. It is still a host-side payload/runner seeding step,
not complete Pterodactyl server provisioning.

## Setup

From the repository root on the trusted Debian Node:

~~~bash
cp instance/instance.example.env instance/instance.env
sudo nano instance/instance.env
sudo chmod 600 instance/instance.env
~~~

Set INSTANCE_STORAGE_ROOT to a host-side absolute path outside the Git checkout. The script
requires root and the steam service account because the generated Linux lifecycle scripts run
as steam. For the default path, it prepares /var/lib/fragcity and /var/lib/fragcity/instances
for steam to traverse. If you configure a custom root, its parent directories must already be
traversable by steam; the script validates this instead of changing arbitrary parent paths.
Do not source an instance config supplied by a customer or arbitrary API input.

## Preview and create

~~~bash
sudo bash instance/create-instance.sh --dry-run 29001-aim_hs
sudo bash instance/create-instance.sh 29001-aim_hs
~~~

The ID may contain 1-64 letters, numbers, hyphens, or underscores and must start with a
letter or number. Existing target directories are never overwritten. Use a new ID or safely
move an older test directory aside before recreating it.

## Output structure

~~~text
<INSTANCE_STORAGE_ROOT>/29001-aim_hs/
├── .fragcity-seed.json
├── .gitignore
├── README.md
├── instance.example.env
├── instance.env
├── run.sh
├── stop.sh
├── update.sh
├── watchdog.sh
└── instance/
    ├── addons/
    ├── cfg/
    └── *.txt
~~~

Every file from linux/instances/instance-template is copied to the Instance root, including
the runner, watchdog, stop/update helpers, documentation, example environment, and hidden
.gitignore. A separate instance.env is generated from the example; it sets REPO_ROOT to the
current checkout and CUSTOM_FOLDER to the relative path instance. That matches the directory
created for the payload and is what run.sh uses for the launch-time custom-file overlay.

## Payload inclusion rules

- Copy the tracked addons/ tree except addons/windows/ (Windows-only staging).
- Copy the tracked cfg/ tree and top-level *.txt files directly into the private instance/ folder.
- Do not preserve the source game/csgo/ wrapper path.
- Do not copy gameinfo.gi, the shared CS2 binaries/Base Game, or other files outside the allowlist.
- Do not install/update CS2 or Steam Linux Runtime, start/stop a server, or call the Panel API.

The source payload and Linux template must be committed and clean. The script uses a staging
directory and atomic final rename, and does not overwrite an existing Instance. The generated
Instance root and control scripts are owned by steam:steam; instance.env is mode 0600. Optional
INSTANCE_OWNER and INSTANCE_GROUP only change ownership of the private instance/ payload
folder, for a future container-mount model. Leave them empty until the Node UID/GID design is
validated.

Before the first launch, edit the generated instance.env and set a strong, unique
RCON_PASSWORD. The current Linux run.sh copies instance/cfg and instance/addons additively to
the shared game runtime when launching; it does not delete existing runtime files.

## Still to integrate

The next Pterodactyl PoC must decide how the private instance/ payload is connected to the
shared Base Game inside the server container (for example, a tested OverlayFS/mount design),
then automate Panel server creation, allocations, permissions, rollback and cleanup. This
script alone does not create a Pterodactyl server or mount the payload.
