# FragCity Backuper

Independent scheduled backup module for the FragCity/Pterodactyl host. It is separate from the addon Provisioner: it does not create servers, attach Mounts, modify UUID baselines, touch customer containers or change existing Provisioner timers.

## Backup contents

Each successful run publishes one verified archive containing:

- **MariaDB logical dump:** all actual databases returned by MariaDB, including mysql, panel, paymenter, sys and all GLOBAL_* databases. Runtime-only information_schema and performance_schema are excluded. Tables, routines, events, triggers and binary columns are included.
- **Redis RDB snapshot:** exported from the running Redis instance with redis-cli --rdb, including keyspaces across Redis databases.
- **Platform files:** /etc, all of /var/www, the complete /opt/fragcity/cs2-kus-addons checkout (including Git metadata), the Provisioner's safety-critical state at /var/lib/pterodactyl/fragcity-addon-provisioner (baseline UUIDs and processed markers), and /usr/local/bin, /usr/local/sbin, /usr/local/libexec.
- **Integrity metadata:** host/OS/kernel, repository commit, database list, SHA-256 checksums and an outer SHA-256 sidecar.

Transient Laravel logs, sessions, views, caches, Bootstrap cache and Node node_modules are excluded. Application code, Composer vendor directories, app storage data, .env files, TLS material and system configuration remain included.

## Deliberately excluded

The platform backup does not include /srv (re-downloadable CS2/Workshop assets), /var/lib/pterodactyl/volumes (customer game-server volumes), /var/lib/pterodactyl/mounts (the immutable addon payload can be re-published from Git), or /var/lib/docker (rebuildable Docker layers). Keep the existing full VMware clone as the complete-machine recovery image.

## Install

Run on the Debian host from the auto-updated checkout:

    cd /opt/fragcity/cs2-kus-addons
    sudo bash pterodactyl/backuper/install.sh

The installer creates /etc/fragcity/backuper.conf only if it does not already exist, installs one systemd service and timer, and enables only fragcity-backuper.timer. It does not call install-host-services.sh and does not change fragcity-addon-provision.timer or fragcity-addon-payload-sync.timer. An immediate backup is not started unless explicitly requested with FRAGCITY_BACKUP_RUN_NOW=1.

## First run

Review the root-only config:

    sudo nano /etc/fragcity/backuper.conf
    sudo chmod 600 /etc/fragcity/backuper.conf
    sudo bash pterodactyl/backuper/fragcity-backuper.sh --dry-run

The default uses local MariaDB root/socket authentication and the default local Redis CLI connection. Custom sockets can be set in MARIADB_ARGS and REDIS_CLI_ARGS. Optional REDIS_PASSWORD_FILE and GPG_PASSPHRASE_FILE must be root-owned, mode 0400 or 0600, and stored below /root/fragcity-backup-secrets/; the secret files are explicitly excluded from the archive. Keep a separate offline copy of the GPG passphrase.

Start a backup after dry-run passes:

    sudo systemctl start fragcity-backuper.service
    sudo journalctl -u fragcity-backuper.service -n 100 --no-pager

Verify a completed archive. Verification does not require MariaDB, Redis or the provisioner Git checkout to be running, so it can be used during disaster recovery:

    sudo bash pterodactyl/backuper/fragcity-backuper.sh --verify /var/backups/fragcity/fragcity-platform-YYYYMMDDTHHMMSSZ.tar.gz

Encrypted archives end in .tar.gz.gpg; configure the same passphrase file before verifying or restoring.

## Schedule, retention and status

- Daily at 03:30 host-local time, with up to 15 minutes randomized delay.
- Persistent timer; a missed run is triggered after the host returns.
- Default retention is 14 days.
- Requires at least 2 GiB free before starting.
- Uses a dedicated run lock. Retention pruning happens only after a complete archive has passed verification.
- Output archives and checksums are root-only.

    systemctl list-timers fragcity-backuper.timer --no-pager
    systemctl status fragcity-backuper.timer fragcity-backuper.service --no-pager
    journalctl -u fragcity-backuper.service -n 100 --no-pager
    ls -lah /var/backups/fragcity

## Destination and off-host safety

The default destination path is /var/backups/fragcity, but the installer does not mount storage there. The scheduled backup refuses to run until a separate physical disk or network volume is mounted at that path; this prevents silently filling the root VMDK and falsely treating a same-disk copy as disaster recovery.

For disaster recovery, mount a separate physical disk or network backup volume at exactly /var/backups/fragcity, then confirm with findmnt -T /var/backups/fragcity and df -h /var/backups/fragcity. The destination source must differ from the root filesystem. This is enforced by default through REQUIRE_SEPARATE_DESTINATION=1; set it to 0 only for an explicitly temporary local backup. Keep another copy off the machine.

Archives contain database contents, API keys, .env files, certificates and private config. Optional GPG symmetric encryption is supported by setting BACKUP_ENCRYPTION=1 and GPG_PASSPHRASE_FILE in the root-only config; keep an offline copy of that passphrase.

## Auto-update and Provisioner isolation

The host publisher fast-forwards the complete checkout from integration/kus-monorepo. The systemd unit points directly to pterodactyl/backuper/fragcity-backuper.sh in that checkout, so the next successful checkout update also updates Backuper code. No script copy under /usr/local becomes stale.

The Backuper obtains a shared lock on .git/fragcity-payload-stage.lock, while the existing publisher obtains it exclusively during fetch/fast-forward. If they overlap, the update waits until the repository archive is complete; the checkout cannot change halfway through the backup. A refresh may be delayed for the duration of the archive, but updater and provisioner logic are not changed.

The Backuper has its own service, timer and config. It does not modify Provisioner/Payload Sync scripts, Egg, Mount definitions, UUIDs, baseline registry, customer containers or game-server volumes.

## Restore outline

Do not restore over a live production database without a recovery plan. Preserve the current state first, stop application writers/queues, verify and extract the archive to a temporary location, then restore MariaDB and Redis using their documented procedures. Restore platform files with ownership and permissions preserved during a planned maintenance window. Before deploying onto different hardware, review hostname, IP, machine-id and SSH host keys.

Archive layout:
- databases/mariadb-all.sql.gz
- databases/redis.rdb
- files/platform-files.tar.gz
- metadata/manifest.txt
- metadata/SHA256SUMS

The full VMware clone remains the preferred one-step recovery for the exact original VM. This archive is the independent component-level recovery layer.
