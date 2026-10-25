#!/usr/bin/env php
<?php

declare(strict_types=1);

use Illuminate\Contracts\Console\Kernel;
use Illuminate\Support\Facades\DB;
use Pterodactyl\Models\Mount;
use Pterodactyl\Models\Server;
use Symfony\Component\Process\Process;

/**
 * FragCity's Pterodactyl 1.x server provisioner.
 *
 * This process is intended to run on the Wings/Panel host as root. It uses the
 * installed Panel's own Laravel models because Pterodactyl 1.x does not expose a
 * documented public API for assigning Mount definitions to individual servers.
 *
 * Modes:
 *   --initialize-baseline  Record existing eligible server UUIDs without changing them.
 *   --server <uuid>         Explicitly provision one server (for controlled tests).
 *   --watch                 Provision only eligible servers created after the baseline.
 *   --help                  Print this help.
 */

const DEFAULT_PANEL_ROOT = '/var/www/pterodactyl';
const DEFAULT_VOLUME_ROOT = '/var/lib/pterodactyl/volumes';
const DEFAULT_PAYLOAD_ROOT = '/var/lib/pterodactyl/mounts/fragcity-addon-payload';
const DEFAULT_MOUNT_TARGET = '/home/container/egg/fragcity-payload';
const DEFAULT_STATE_ROOT = '/var/lib/pterodactyl/fragcity-addon-provisioner';
const SYNC_SCRIPT_NAME = 'sync-addon-payload-container.sh';
const EXPECTED_STARTUP_MARKER = './game/cs2.sh';

function logLine(string $message): void
{
    fwrite(STDOUT, '[fragcity-provision] ' . $message . PHP_EOL);
}

function fail(string $message, int $code = 1): never
{
    throw new RuntimeException($message, $code);
}

function usage(): void
{
    echo <<<TEXT
FragCity Pterodactyl addon provisioner

Usage:
  php provision-addon-servers.php --initialize-baseline [--exclude <server-uuid>]
  php provision-addon-servers.php --server <server-uuid>
  php provision-addon-servers.php --verify-server <server-uuid>
  php provision-addon-servers.php --watch
  php provision-addon-servers.php --help

Safety model:
  * --initialize-baseline only records currently eligible servers; it does not modify them.
  * --watch only processes servers not present in that baseline and not already provisioned.
  * --server is a one-shot test override and requires a Panel name beginning "FragCity Payload Test".
  * --verify-server is read-only with respect to server files, mounts, startup settings, and Docker containers.
  * Only stopped Docker containers named exactly after the server UUID may be removed.
  * Docker container removal never uses -v; the server volume is preserved.

Configuration overrides:
  FRAGCITY_PANEL_ROOT
  FRAGCITY_VOLUME_ROOT
  FRAGCITY_PAYLOAD_SOURCE
  FRAGCITY_MOUNT_TARGET
  FRAGCITY_PROVISIONER_STATE

TEXT;
}

function validUuid(string $uuid): bool
{
    return preg_match('/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/D', $uuid) === 1;
}

/** Run a command without a shell; arguments cannot be interpreted as shell syntax. */
function runCommand(array $arguments, int $timeout = 60): string
{
    $process = new Process($arguments);
    $process->setTimeout($timeout);
    $process->run();

    if (!$process->isSuccessful()) {
        $detail = trim($process->getErrorOutput() . "\n" . $process->getOutput());
        fail(sprintf(
            'Command failed (exit %d): %s%s',
            $process->getExitCode() ?? 1,
            implode(' ', $arguments),
            $detail === '' ? '' : "\n" . $detail
        ));
    }

    return trim($process->getOutput());
}

function ensureStateDirectory(string $path): void
{
    if (is_link($path)) {
        fail('State directory must not be a symlink: ' . $path);
    }

    if (!is_dir($path) && !mkdir($path, 0700, true) && !is_dir($path)) {
        fail('Could not create state directory: ' . $path);
    }

    if (is_link($path) || !is_dir($path)) {
        fail('State directory is not a safe directory: ' . $path);
    }

    if (!chmod($path, 0700)) {
        fail('Could not restrict state directory permissions: ' . $path);
    }
}

function writeAtomically(string $path, string $contents, int $mode = 0600): void
{
    if (is_link($path)) {
        fail('Refusing to replace a symlink: ' . $path);
    }

    $temporary = $path . '.tmp.' . getmypid();
    if (is_link($temporary)) {
        fail('Temporary state path is a symlink: ' . $temporary);
    }

    if (file_put_contents($temporary, $contents, LOCK_EX) === false) {
        fail('Could not write temporary state file: ' . $temporary);
    }

    if (!chmod($temporary, $mode)) {
        @unlink($temporary);
        fail('Could not set state file permissions: ' . $temporary);
    }

    if (!rename($temporary, $path)) {
        @unlink($temporary);
        fail('Could not publish state file: ' . $path);
    }
}

function readUuidList(string $path): array
{
    if (is_link($path) || !is_file($path)) {
        fail('Baseline file is missing or unsafe: ' . $path);
    }

    $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($lines === false) {
        fail('Could not read baseline file: ' . $path);
    }

    $uuids = [];
    foreach ($lines as $line) {
        $uuid = trim($line);
        if (!validUuid($uuid)) {
            fail('Invalid UUID in baseline file: ' . $uuid);
        }
        $uuids[$uuid] = true;
    }

    return $uuids;
}

function bootPanel(string $panelRoot): void
{
    if (is_link($panelRoot) || !is_dir($panelRoot)) {
        fail('Panel root is missing or is a symlink: ' . $panelRoot);
    }

    $autoload = $panelRoot . '/vendor/autoload.php';
    $bootstrap = $panelRoot . '/bootstrap/app.php';
    if (!is_file($autoload) || !is_file($bootstrap)) {
        fail('Panel Laravel bootstrap files are missing under: ' . $panelRoot);
    }

    require_once $autoload;
    $app = require $bootstrap;
    $kernel = $app->make(Kernel::class);
    $kernel->bootstrap();
}

function validatedPayloadCommit(string $payloadRoot): string
{
    if (is_link($payloadRoot) || !is_dir($payloadRoot)) {
        fail('Payload source is missing or is a symlink: ' . $payloadRoot);
    }

    $realRoot = realpath($payloadRoot);
    if ($realRoot === false || $realRoot !== rtrim($payloadRoot, '/')) {
        fail('Payload source must be a canonical, non-symlink path: ' . $payloadRoot);
    }

    foreach ([$payloadRoot . '/CURRENT_COMMIT', $payloadRoot . '/.sync.lock',
        $payloadRoot . '/' . SYNC_SCRIPT_NAME] as $required) {
        if (is_link($required) || !is_file($required)) {
            fail('Required payload publisher file is missing or unsafe: ' . $required);
        }
    }

    $commit = trim((string) file_get_contents($payloadRoot . '/CURRENT_COMMIT'));
    if (preg_match('/^[0-9a-f]{40}$/D', $commit) !== 1) {
        fail('CURRENT_COMMIT is not a full lowercase Git commit SHA.');
    }

    $revision = $payloadRoot . '/revisions/' . $commit;
    if (is_link($revision) || !is_dir($revision)) {
        fail('Published revision directory is missing or unsafe: ' . $revision);
    }

    $marker = $revision . '/.source-commit';
    if (is_link($marker) || !is_file($marker) || trim((string) file_get_contents($marker)) !== $commit) {
        fail('Published revision marker does not match CURRENT_COMMIT.');
    }

    foreach ([
        $revision . '/game/csgo/addons/counterstrikesharp/plugins',
        $revision . '/game/csgo/addons/counterstrikesharp/plugins/disabled',
        $revision . '/game/csgo/addons/counterstrikesharp/source',
        $revision . '/game/csgo/addons/counterstrikesharp/shared',
        $revision . '/game/csgo/addons/counterstrikesharp/gamedata',
        $revision . '/game/csgo/addons/counterstrikesharp/configs',
        $revision . '/game/csgo/cfg',
    ] as $requiredDirectory) {
        if (is_link($requiredDirectory) || !is_dir($requiredDirectory)) {
            fail('Published revision is incomplete or unsafe: ' . $requiredDirectory);
        }
    }

    foreach ([
        'gamemodes_server.txt',
        'mapcycle.txt',
        'mapcyclecustom.txt',
        'subscribed_collection_ids.txt',
        'subscribed_file_ids.txt',
    ] as $requiredConfigFile) {
        $path = $revision . '/game/csgo/' . $requiredConfigFile;
        if (is_link($path) || !is_file($path)) {
            fail('Published revision is missing a required top-level CS2 config file: ' . $path);
        }
    }

    $disabledRoot = $revision . '/game/csgo/addons/counterstrikesharp/plugins/disabled';
    if (is_link($disabledRoot)) {
        fail('Published disabled-plugin folder must not be a symlink.');
    }

    $disabledHasFile = false;
    $disabledIterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($disabledRoot, FilesystemIterator::SKIP_DOTS)
    );
    foreach ($disabledIterator as $entry) {
        if ($entry->isFile() && !$entry->isLink()) {
            $disabledHasFile = true;
            break;
        }
    }
    if (!$disabledHasFile) {
        fail('Published payload has no files under CounterStrikeSharp plugins/disabled/.');
    }

    // Validate the complete repository game/ tree against the publisher's inventory.
    $gameRoot = $revision . '/game';
    $gameInventory = $revision . '/.fragcity-game-files-v1.list';
    if (is_link($gameRoot) || !is_dir($gameRoot)
        || is_link($gameInventory) || !is_file($gameInventory)) {
        fail('Published revision is missing the complete game/ tree or its file inventory.');
    }

    $gameFiles = file($gameInventory, FILE_IGNORE_NEW_LINES);
    if ($gameFiles === false || count($gameFiles) === 0 || count(array_unique($gameFiles)) !== count($gameFiles)) {
        fail('Published full-game inventory is empty, unreadable or contains duplicate paths.');
    }

    foreach ($gameFiles as $relativePath) {
        if ($relativePath === '' || str_starts_with($relativePath, '/')
            || str_contains($relativePath, '..') || str_contains($relativePath, '//')) {
            fail('Published full-game inventory contains an unsafe path.');
        }
        $path = $gameRoot . '/' . $relativePath;
        if (is_link($path) || !is_file($path)) {
            fail('Published full-game inventory references a missing or unsafe file: ' . $relativePath);
        }
    }

    $actualGameFileCount = 0;
    $gameIterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($gameRoot, FilesystemIterator::SKIP_DOTS)
    );
    foreach ($gameIterator as $entry) {
        if ($entry->isLink()) {
            fail('Published game/ tree contains a symlink: ' . $entry->getPathname());
        }
        if ($entry->isFile()) {
            $actualGameFileCount++;
        }
    }
    if ($actualGameFileCount !== count($gameFiles)) {
        fail(
            'Published full-game file count does not match its inventory. Inventory: ' .
            count($gameFiles) . '; actual: ' . $actualGameFileCount . '.'
        );
    }

    return $commit;
}

/**
 * Return the one, intentionally narrow mount definition configured for FragCity.
 * It must be eligible for exactly one Egg and one Node so this automation cannot
 * silently expand to unrelated game servers.
 */
function getConfiguredMount(string $payloadRoot, string $target): Mount
{
    // Count every definition using this source/target pair, not only valid flags.
    // Otherwise a valid mount plus a conflicting writable duplicate could be missed.
    $mounts = Mount::query()
        ->where('source', $payloadRoot)
        ->where('target', $target)
        ->get();

    if ($mounts->count() !== 1) {
        fail(
            'Expected exactly one Mount definition with source ' .
            $payloadRoot . ' and target ' . $target . '; found ' . $mounts->count() . '.'
        );
    }

    /** @var Mount $mount */
    $mount = $mounts->first();
    if (!$mount->read_only || $mount->user_mountable) {
        fail('The unique FragCity Mount must be read-only and not user-mountable.');
    }
    $eggIds = $mount->eggs()->pluck('eggs.id')->map(static fn ($id) => (int) $id)->values()->all();
    $nodeIds = $mount->nodes()->pluck('nodes.id')->map(static fn ($id) => (int) $id)->values()->all();

    if (count($eggIds) !== 1 || count($nodeIds) !== 1) {
        fail(
            'FragCity automatic provisioning requires the Mount to be assigned to exactly one Egg ' .
            'and exactly one Node. Current eligible Egg count: ' . count($eggIds) .
            '; Node count: ' . count($nodeIds) . '.'
        );
    }

    return $mount;
}

function eligibleServers(Mount $mount): array
{
    $eggIds = $mount->eggs()->pluck('eggs.id')->map(static fn ($id) => (int) $id)->values()->all();
    $nodeIds = $mount->nodes()->pluck('nodes.id')->map(static fn ($id) => (int) $id)->values()->all();

    return Server::query()
        ->whereIn('egg_id', $eggIds)
        ->whereIn('node_id', $nodeIds)
        ->orderBy('created_at')
        ->get()
        ->all();
}

function serverIsEligible(Server $server, Mount $mount): bool
{
    return $mount->eggs()->where('eggs.id', (int) $server->egg_id)->exists()
        && $mount->nodes()->where('nodes.id', (int) $server->node_id)->exists();
}

/**
 * Resolve the server's own volume without permitting a UUID to escape the configured
 * Pterodactyl volume root or redirect through a symlink.
 */
function serverVolumePath(Server $server, string $volumeRoot): string
{
    if (!validUuid((string) $server->uuid)) {
        fail('Panel returned an invalid server UUID.');
    }

    if (is_link($volumeRoot) || !is_dir($volumeRoot)) {
        fail('Pterodactyl volume root is missing or is a symlink: ' . $volumeRoot);
    }

    $realRoot = realpath($volumeRoot);
    if ($realRoot === false || $realRoot !== rtrim($volumeRoot, '/')) {
        fail('Pterodactyl volume root must be a canonical, non-symlink path: ' . $volumeRoot);
    }

    $expected = $realRoot . '/' . $server->uuid;
    if (is_link($expected) || !is_dir($expected)) {
        fail('The server volume does not exist as a direct directory under the volume root: ' . $expected);
    }

    $realVolume = realpath($expected);
    if ($realVolume === false || $realVolume !== $expected || dirname($realVolume) !== $realRoot
        || basename($realVolume) !== $server->uuid) {
        fail('Server volume path failed containment validation: ' . $expected);
    }

    return $realVolume;
}

/**
 * Prepare target directories one component at a time. Do not follow symlinks, do
 * not create a volume, and refuse to hide any pre-existing files under a new mount.
 */
function prepareMountTarget(string $volumePath, string $mountTarget): string
{
    $prefix = '/home/container/';
    if (!str_starts_with($mountTarget, $prefix)) {
        fail('Mount target must be below /home/container/: ' . $mountTarget);
    }

    $relative = substr($mountTarget, strlen($prefix));
    $parts = explode('/', $relative);
    if ($relative === '' || in_array('', $parts, true) || in_array('.', $parts, true)
        || in_array('..', $parts, true)) {
        fail('Mount target has unsafe path components: ' . $mountTarget);
    }

    $cursor = $volumePath;
    $pterodactylUser = function_exists('posix_getpwnam') ? posix_getpwnam('pterodactyl') : false;
    $pterodactylGroup = function_exists('posix_getgrnam') ? posix_getgrnam('pterodactyl') : false;

    foreach ($parts as $index => $part) {
        $cursor .= '/' . $part;

        if (is_link($cursor)) {
            fail('Mount destination contains a symlink: ' . $cursor);
        }

        if (file_exists($cursor)) {
            if (!is_dir($cursor)) {
                fail('Mount destination path exists but is not a directory: ' . $cursor);
            }
        } else {
            if (!mkdir($cursor, 0755) && !is_dir($cursor)) {
                fail('Could not create mount destination directory: ' . $cursor);
            }

            if ($pterodactylUser !== false && !chown($cursor, (int) $pterodactylUser['uid'])) {
                fail('Could not assign mount destination to the pterodactyl user: ' . $cursor);
            }

            $gid = $pterodactylGroup !== false
                ? (int) $pterodactylGroup['gid']
                : ($pterodactylUser !== false ? (int) $pterodactylUser['gid'] : null);
            if ($gid !== null && !chgrp($cursor, $gid)) {
                fail('Could not assign mount destination group: ' . $cursor);
            }
        }

        if ($index === count($parts) - 1) {
            $entries = scandir($cursor);
            if ($entries === false) {
                fail('Could not inspect mount destination directory: ' . $cursor);
            }
            $entries = array_values(array_diff($entries, ['.', '..']));
            if (count($entries) > 0) {
                fail('Mount target is not empty; refusing to hide existing files: ' . $cursor);
            }
        }
    }

    return $cursor;
}

/**
 * Find and validate the exact Docker container that belongs to this server.
 * A running container is returned as-is so the caller can defer without changes.
 */
function inspectServerContainer(string $uuid, string $volumePath, string $expectedImage): ?array
{
    $rawIds = runCommand(['docker', 'ps', '-aq', '--filter', 'name=^/' . $uuid . '$']);
    $ids = array_values(array_unique(array_filter(array_map('trim', preg_split('/\R/', $rawIds) ?: []))));

    if (count($ids) === 0) {
        return null;
    }
    if (count($ids) !== 1) {
        fail('Expected one Docker container for server UUID ' . $uuid . ', found ' . count($ids) . '.');
    }

    $containerId = $ids[0];
    $json = runCommand(['docker', 'inspect', $containerId]);
    $decoded = json_decode($json, true);
    if (!is_array($decoded) || count($decoded) !== 1 || !is_array($decoded[0])) {
        fail('Could not decode docker inspect output for ' . $containerId . '.');
    }

    $container = $decoded[0];
    if (($container['Name'] ?? '') !== '/' . $uuid) {
        fail('Docker container name does not exactly match server UUID ' . $uuid . '.');
    }

    $homeMounts = array_values(array_filter(
        $container['Mounts'] ?? [],
        static fn (array $mount): bool => ($mount['Destination'] ?? '') === '/home/container'
    ));
    if (count($homeMounts) !== 1 || rtrim((string) ($homeMounts[0]['Source'] ?? ''), '/') !== $volumePath) {
        fail('Docker container /home/container mount does not match the server volume; refusing to remove it.');
    }

    $actualImage = (string) ($container['Config']['Image'] ?? '');
    if ($actualImage !== $expectedImage) {
        fail(
            'Docker image mismatch for server ' . $uuid . '. Expected ' .
            $expectedImage . ', got ' . $actualImage . '; refusing to alter this container.'
        );
    }

    $status = (string) ($container['State']['Status'] ?? '');
    if ($status !== 'running' && $status !== 'exited') {
        fail('Docker container state is unexpected (' . $status . '); refusing to alter it.');
    }

    return [
        'id' => $containerId,
        'state' => $status,
    ];
}

function isServerReady(Server $server): bool
{
    if (!$server->isInstalled()
        || in_array((string) $server->status, [
            Server::STATUS_INSTALLING,
            Server::STATUS_INSTALL_FAILED,
            Server::STATUS_REINSTALL_FAILED,
            Server::STATUS_RESTORING_BACKUP,
            Server::STATUS_SUSPENDED,
        ], true)) {
        logLine('Skipping ' . $server->uuid . ': server is not in a completed, runnable installation state.');
        return false;
    }

    if (!is_null($server->transfer)) {
        logLine('Skipping ' . $server->uuid . ': a server transfer is pending or in progress.');
        return false;
    }

    if ($server->node->isUnderMaintenance()) {
        logLine('Skipping ' . $server->uuid . ': the node is under maintenance.');
        return false;
    }

    return true;
}

function processedMarkerPath(string $stateRoot, string $uuid): string
{
    return rtrim($stateRoot, '/') . '/processed/' . $uuid . '.json';
}

function serverStartupPrefix(string $mountTarget): string
{
    return 'bash ' . rtrim($mountTarget, '/') . '/' . SYNC_SCRIPT_NAME . ' && ';
}

/**
 * Record that a newly provisioned volume must complete its first full game/ sync.
 * Keep the legacy state filename/identifier so already provisioned volumes remain readable;
 * this marker no longer gates the copying of configs or other repository game files.
 */
function prepareConfigSeedMarker(string $volumePath, string $uuid, int $mountId, string $payloadCommit): void
{
    $state = $volumePath . '/.fragcity-config-seed-v1.state';

    if (is_link($state)) {
        fail('Initial-sync state path is a symlink: ' . $state);
    }
    if (file_exists($state) && !is_file($state)) {
        fail('Initial-sync state path is not a regular file: ' . $state);
    }

    if (is_file($state)) {
        $lines = file($state, FILE_IGNORE_NEW_LINES);
        if ($lines === false
            || !in_array('fragcity-config-seed-v1', $lines, true)
            || !in_array('server_uuid=' . $uuid, $lines, true)) {
            fail('Initial-sync state does not match server UUID ' . $uuid . '.');
        }
        if (in_array('mode=completed', $lines, true)) {
            logLine('Initial full game/ sync is marked complete for ' . $uuid . '; all repository files still sync on every start.');
        } elseif (in_array('mode=pending', $lines, true)) {
            logLine('Initial full game/ payload sync is pending for ' . $uuid . '.');
        } else {
            fail('Initial-sync state has no recognized pending/completed mode for ' . $uuid . '.');
        }
        return;
    }

    $contents = "fragcity-config-seed-v1\n"
        . 'server_uuid=' . $uuid . "\n"
        . "mode=pending\n"
        . 'mount_id=' . $mountId . "\n"
        . 'payload_commit=' . $payloadCommit . "\n"
        . 'created_at_utc=' . gmdate('c') . "\n";

    // The container cannot always create files in the root of its bind-mounted
    // volume, so make this isolated per-server state file writable for its own
    // container user. It is not an authority boundary and contains no secrets.
    writeAtomically($state, $contents, 0666);
    logLine('Created initial-sync state for ' . $uuid . '; the complete repository game/ tree will be copied and verified on next start.');
}

/**
 * Process exactly one server. Returns false when it is not ready or is currently
 * running, leaving it unmarked so a later watcher pass can retry.
 */
function provisionOne(
    Server $server,
    Mount $mount,
    string $volumeRoot,
    string $payloadRoot,
    string $mountTarget,
    string $stateRoot,
    string $payloadCommit
): bool {
    if (!serverIsEligible($server, $mount)) {
        fail('Server ' . $server->uuid . ' is not eligible for the configured FragCity Mount.');
    }

    if (!isServerReady($server)) {
        return false;
    }

    if ($server->isSuspended()) {
        logLine('Skipping suspended server ' . $server->uuid . '.');
        return false;
    }

    $uuid = (string) $server->uuid;
    $volumePath = serverVolumePath($server, $volumeRoot);
    $container = inspectServerContainer($uuid, $volumePath, (string) $server->image);

    if ($container !== null && $container['state'] === 'running') {
        logLine('Skipping ' . $uuid . ': its Docker container is running; no changes were made.');
        return false;
    }

    $startup = (string) $server->startup;
    if (!str_contains($startup, EXPECTED_STARTUP_MARKER)) {
        fail('Server startup does not contain the expected CS2 launch command; refusing to modify it.');
    }

    $syncScriptPath = rtrim($mountTarget, '/') . '/' . SYNC_SCRIPT_NAME;
    $prefix = serverStartupPrefix($mountTarget);

    if (!str_starts_with($startup, $prefix) && str_contains($startup, $syncScriptPath)) {
        fail('The sync script is already present but not as a safe startup prefix; manual review required.');
    }

    $targetPath = prepareMountTarget($volumePath, $mountTarget);

    DB::transaction(function () use ($mount, $server, $startup, $prefix): void {
        $mount->servers()->syncWithoutDetaching([(int) $server->id]);

        if (!str_starts_with($startup, $prefix)) {
            $server->startup = $prefix . $startup;
            $server->saveOrFail();
        }
    });

    logLine('Mount relation is attached and the server-specific startup is configured for ' . $uuid . '.');

    if ($container !== null) {
        // Never use -v here. The host volume contains the customer's game files.
        runCommand(['docker', 'rm', $container['id']]);
        logLine('Removed stopped Docker container ' . $container['id'] . ' without deleting its volume.');
    } else {
        logLine('No existing Docker container needs recreation; Wings will create it with the Mount on next start.');
    }

    prepareConfigSeedMarker($volumePath, $uuid, (int) $mount->id, $payloadCommit);

    $markerPath = processedMarkerPath($stateRoot, $uuid);
    if (is_link($markerPath)) {
        fail('Provisioned marker is a symlink: ' . $markerPath);
    }

    $marker = [
        'server_uuid' => $uuid,
        'server_id' => (int) $server->id,
        'mount_id' => (int) $mount->id,
        'node_id' => (int) $server->node_id,
        'egg_id' => (int) $server->egg_id,
        'payload_commit_at_provision' => $payloadCommit,
        'processed_at_utc' => gmdate('c'),
        'startup_prefix' => $prefix,
        'container_recreated' => $container !== null,
        'target_path' => $targetPath,
    ];

    writeAtomically($markerPath, json_encode($marker, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);

    logLine('Provisioning completed for ' . $uuid . '. Start this server from the Panel to sync its addon files.');
    return true;
}


/**
 * Read-only post-start verification for a single explicitly selected server.
 * Confirms that the Panel relation, server UUID, volume mapping, read-only
 * payload mount, startup prefix, and runtime prerequisites all agree.
 */
function verifyOne(
    Server $server,
    Mount $mount,
    string $volumeRoot,
    string $payloadRoot,
    string $mountTarget
): void {
    if (!serverIsEligible($server, $mount)) {
        fail('Server ' . $server->uuid . ' is not eligible for the configured FragCity Mount.');
    }
    if (!isServerReady($server) || $server->isSuspended()) {
        fail('Server is not in a runnable installed state; start/finish installation before verification.');
    }

    $uuid = (string) $server->uuid;
    $volumePath = serverVolumePath($server, $volumeRoot);
    $container = inspectServerContainer($uuid, $volumePath, (string) $server->image);
    if ($container === null) {
        fail('No Docker container exists for ' . $uuid . '; start the server from the Panel first.');
    }
    if ($container['state'] !== 'running') {
        fail('Docker container is not running; start the server from the Panel before verification.');
    }

    $prefix = serverStartupPrefix($mountTarget);
    if (!str_starts_with((string) $server->startup, $prefix)) {
        fail('The expected FragCity sync prefix is not present at the start of the server startup command.');
    }
    if (!$mount->servers()->where('servers.id', (int) $server->id)->exists()) {
        fail('The FragCity Mount is not attached to this server in the Panel database.');
    }

    $decoded = json_decode(runCommand(['docker', 'inspect', $container['id']]), true);
    if (!is_array($decoded) || count($decoded) !== 1 || !is_array($decoded[0])) {
        fail('Could not decode Docker inspection while verifying the payload Mount.');
    }
    $docker = $decoded[0];
    $payloadMounts = array_values(array_filter(
        $docker['Mounts'] ?? [],
        static fn (array $entry): bool => ($entry['Destination'] ?? '') === $mountTarget
    ));
    if (count($payloadMounts) !== 1) {
        fail('Expected exactly one Docker Mount at ' . $mountTarget . '; found ' . count($payloadMounts) . '.');
    }
    $actualSource = rtrim((string) ($payloadMounts[0]['Source'] ?? ''), '/');
    if ($actualSource !== $payloadRoot) {
        fail('Payload Mount source mismatch. Expected ' . $payloadRoot . ', got ' . $actualSource . '.');
    }
    if (($payloadMounts[0]['RW'] ?? true) !== false) {
        fail('Payload Mount is not read-only inside Docker.');
    }

    $environment = $docker['Config']['Env'] ?? [];
    $serverUuidValues = [];
    foreach ($environment as $value) {
        if (str_starts_with((string) $value, 'P_SERVER_UUID=')) {
            $serverUuidValues[] = substr((string) $value, strlen('P_SERVER_UUID='));
        }
    }
    if (count($serverUuidValues) !== 1 || $serverUuidValues[0] !== $uuid) {
        fail('Docker P_SERVER_UUID does not uniquely match the Panel server UUID ' . $uuid . '.');
    }

    $preflight = <<<'BASH'
set -Eeuo pipefail
for command_name in bash sha256sum find cp mkdir rm awk flock tr chmod dirname grep mv sort wc; do
    command -v "$command_name" >/dev/null 2>&1 || {
        printf 'MISSING required command: %s\n' "$command_name" >&2
        exit 21
    }
done
base="${FRAGCITY_VERIFY_PAYLOAD_BASE:?missing payload base}"
test -d "$base" && test ! -L "$base"
test -r "$base/CURRENT_COMMIT"
test -r "$base/.sync.lock"
test -r "$base/sync-addon-payload-container.sh"
commit="$(tr -d '\r\n' < "$base/CURRENT_COMMIT")"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]]
revision="$base/revisions/$commit"
test -d "$revision" && test ! -L "$revision"
test -f "$revision/.source-commit" && test ! -L "$revision/.source-commit"
marker="$(tr -d '\r\n' < "$revision/.source-commit")"
test "$marker" = "$commit"

payload_game="$revision/game"
target_game="/home/container/game"
game_inventory="$revision/.fragcity-game-files-v1.list"
test -d "$payload_game" && test ! -L "$payload_game"
test -d "$target_game" && test ! -L "$target_game"
test -f "$game_inventory" && test ! -L "$game_inventory"
test -z "$(find "$payload_game" -type l -print -quit)"
expected_game_files="$(wc -l < "$game_inventory")"
test "$expected_game_files" -gt 0
test "$(LC_ALL=C sort -u "$game_inventory" | wc -l)" -eq "$expected_game_files"
test "$(find "$payload_game" -type f | wc -l)" -eq "$expected_game_files"
verified_game_files=0
while IFS= read -r relative_file || [[ -n "$relative_file" ]]; do
    [[ -n "$relative_file" && "$relative_file" != /* && "$relative_file" != *".."* && "$relative_file" != *"//"* ]] || {
        printf 'Unsafe full-game inventory path: %s\n' "$relative_file" >&2
        exit 22
    }
    payload_file="$payload_game/$relative_file"
    target_file="$target_game/$relative_file"
    test ! -L "$payload_file" && test -f "$payload_file"
    test ! -L "$target_file" && test -f "$target_file"
    IFS='/' read -r -a path_parts <<< "$relative_file"
    parent="$target_game"
    for ((index = 0; index < ${#path_parts[@]} - 1; index++)); do
        parent="$parent/${path_parts[$index]}"
        if [[ -L "$parent" ]]; then
            printf 'Target path contains a symlink: %s\n' "$parent" >&2
            exit 23
        fi
    done
    payload_hash="$(sha256sum -- "$payload_file" | awk '{print $1}')"
    target_hash="$(sha256sum -- "$target_file" | awk '{print $1}')"
    if [[ "$payload_hash" != "$target_hash" ]]; then
        printf 'Game payload SHA-256 mismatch: %s\n' "$relative_file" >&2
        exit 24
    fi
    verified_game_files=$((verified_game_files + 1))
done < "$game_inventory"
test "$verified_game_files" -eq "$expected_game_files"
printf 'PASS: verified all %d tracked file(s) from the complete repository game/ tree; no payload path exclusions.\n' "$verified_game_files"

seed_state="/home/container/.fragcity-config-seed-v1.state"
test ! -L "$seed_state" || {
    printf 'Config-seed state file is a symlink: %s\n' "$seed_state" >&2
    exit 29
}
if [[ -f "$seed_state" ]]; then
    grep -Fxq 'fragcity-config-seed-v1' "$seed_state"
    grep -Fxq "server_uuid=$P_SERVER_UUID" "$seed_state"
    if grep -Fxq 'mode=completed' "$seed_state"; then
        printf 'PASS: initial full game/ payload sync completed; every repository file was verified above.\n'
    elif grep -Fxq 'mode=pending' "$seed_state"; then
        printf 'Initial full game/ sync state is still pending; startup synchronization did not complete.\n' >&2
        exit 30
    else
        printf 'Initial-sync state has no recognized mode.\n' >&2
        exit 31
    fi
else
    printf 'PASS: legacy server has no first-sync marker; the complete repository game/ tree was verified above.\n'
fi

bash -n "$base/sync-addon-payload-container.sh"
printf 'PASS: required commands available; read-only payload revision %s is valid.\n' "$commit"
BASH;

    $runtimeOutput = runCommand([
        'docker', 'exec',
        '-e', 'FRAGCITY_VERIFY_PAYLOAD_BASE=' . $mountTarget,
        $container['id'],
        '/bin/bash', '-lc', $preflight,
    ]);
    logLine('Verified server UUID and host volume mapping: ' . $uuid . ' -> ' . $volumePath . '.');
    logLine('Verified Docker payload mount source, target, and read-only mode.');
    logLine('Verified P_SERVER_UUID and server-specific startup prefix.');
    logLine($runtimeOutput);
    logLine('Read-only verification completed. No server files, startup settings, mounts, or containers were changed.');
}

function main(array $argv): int
{
    $mode = $argv[1] ?? '--help';

    if ($mode === '--help' || $mode === '-h') {
        usage();
        return 0;
    }

    $serverUuid = null;
    $baselineExcludeUuid = null;
    if (in_array($mode, ['--server', '--verify-server'], true)) {
        $serverUuid = $argv[2] ?? '';
        if (!validUuid($serverUuid)) {
            fwrite(STDERR, "ERROR: {$mode} requires a canonical lowercase UUID.\n");
            usage();
            return 2;
        }
        if (isset($argv[3])) {
            fwrite(STDERR, "ERROR: unexpected extra arguments.\n");
            usage();
            return 2;
        }
    } elseif ($mode === '--initialize-baseline') {
        if (isset($argv[2])) {
            if (($argv[2] ?? '') !== '--exclude'
                || !isset($argv[3])
                || isset($argv[4])
                || !validUuid((string) $argv[3])) {
                fwrite(STDERR, "ERROR: --initialize-baseline accepts only --exclude followed by one canonical lowercase UUID.\n");
                usage();
                return 2;
            }
            $baselineExcludeUuid = (string) $argv[3];
        }
    } elseif ($mode !== '--watch' || isset($argv[2])) {
        fwrite(STDERR, "ERROR: invalid arguments.\n");
        usage();
        return 2;
    }

    if (!function_exists('posix_geteuid') || posix_geteuid() !== 0) {
        fail('This host-side provisioner must run as root.');
    }

    $config = [
        'panelRoot' => rtrim((string) (getenv('FRAGCITY_PANEL_ROOT') ?: DEFAULT_PANEL_ROOT), '/'),
        'volumeRoot' => rtrim((string) (getenv('FRAGCITY_VOLUME_ROOT') ?: DEFAULT_VOLUME_ROOT), '/'),
        'payloadRoot' => rtrim((string) (getenv('FRAGCITY_PAYLOAD_SOURCE') ?: DEFAULT_PAYLOAD_ROOT), '/'),
        'mountTarget' => (string) (getenv('FRAGCITY_MOUNT_TARGET') ?: DEFAULT_MOUNT_TARGET),
        'stateRoot' => rtrim((string) (getenv('FRAGCITY_PROVISIONER_STATE') ?: DEFAULT_STATE_ROOT), '/'),
    ];

    // Post-start verification must not create or chmod provisioner state directories.
    // Mutating modes create their protected state roots as needed.
    if ($mode !== '--verify-server') {
        ensureStateDirectory($config['stateRoot']);
        $processedDir = $config['stateRoot'] . '/processed';
        ensureStateDirectory($processedDir);
    }

    $lockPath = '/run/lock/fragcity-addon-provisioner.lock';
    $lock = fopen($lockPath, 'c');
    if ($lock === false) {
        fail('Could not open provisioner lock file: ' . $lockPath);
    }
    if (!flock($lock, LOCK_EX | LOCK_NB)) {
        logLine('Another provisioner run is active; this pass will exit without changes.');
        return 0;
    }

    $payloadCommit = validatedPayloadCommit($config['payloadRoot']);
    bootPanel($config['panelRoot']);

    $mount = getConfiguredMount($config['payloadRoot'], $config['mountTarget']);
    $baselinePath = $config['stateRoot'] . '/baseline-uuids.txt';

    if ($mode === '--initialize-baseline') {
        if (is_link($baselinePath) || file_exists($baselinePath)) {
            fail('Baseline already exists; refusing to overwrite it. Review it manually before any reset.');
        }

        $servers = eligibleServers($mount);
        $eligibleUuids = [];
        foreach ($servers as $server) {
            $uuid = (string) $server->uuid;
            if (!validUuid($uuid)) {
                fail('Panel returned an invalid UUID while creating the baseline.');
            }
            $eligibleUuids[$uuid] = $uuid;
        }

        if ($baselineExcludeUuid !== null) {
            if (!isset($eligibleUuids[$baselineExcludeUuid])) {
                fail(
                    'The explicitly excluded UUID is not currently eligible for the configured Mount/Egg/Node: ' .
                    $baselineExcludeUuid
                );
            }
            unset($eligibleUuids[$baselineExcludeUuid]);
            logLine(
                'Explicitly excluded ' . $baselineExcludeUuid .
                ' from the one-time baseline; it remains eligible for the watcher.'
            );
        }

        $uuids = array_values($eligibleUuids);
        sort($uuids, SORT_STRING);
        writeAtomically($baselinePath, implode(PHP_EOL, $uuids) . ($uuids === [] ? '' : PHP_EOL));
        logLine('Baseline initialized with ' . count($uuids) . ' currently eligible server(s).');
        if ($baselineExcludeUuid !== null) {
            logLine('One explicitly excluded eligible server will be picked up by --watch when it is ready.');
        }
        logLine('No server volumes, Mount assignments, Docker containers, or startup commands were changed.');
        return 0;
    }

    if ($mode === '--watch') {
        $baseline = readUuidList($baselinePath);
        $servers = eligibleServers($mount);
        $successes = 0;
        $failures = 0;

        foreach ($servers as $server) {
            $uuid = (string) $server->uuid;
            if (isset($baseline[$uuid]) || is_file(processedMarkerPath($config['stateRoot'], $uuid))) {
                continue;
            }

            try {
                if (provisionOne(
                    $server, $mount, $config['volumeRoot'], $config['payloadRoot'],
                    $config['mountTarget'], $config['stateRoot'], $payloadCommit
                )) {
                    $successes++;
                }
            } catch (Throwable $exception) {
                $failures++;
                fwrite(STDERR, '[fragcity-provision] ERROR for ' . $uuid . ': ' . $exception->getMessage() . PHP_EOL);
            }
        }

        logLine('Watch pass finished. Provisioned: ' . $successes . '; errors: ' . $failures . '.');
        return $failures === 0 ? 0 : 1;
    }

    /** @var Server|null $server */
    $server = Server::query()->where('uuid', $serverUuid)->first();
    if ($server === null) {
        fail('No Panel server was found with UUID ' . $serverUuid . '.');
    }

    // Explicit provisioning is reserved for an intentionally named test server.
    // Normal newly-created production/test servers are handled by --watch after
    // the one-time baseline, so a mistyped UUID cannot provision an ordinary server.
    if ($mode === '--server'
        && preg_match('/^FragCity Payload Test(?:\\b|$)/i', (string) $server->name) !== 1) {
        fail(
            'Manual --server mode is restricted to Panel server names beginning with ' .
            '"FragCity Payload Test". Normal new servers are handled by --watch after the baseline.'
        );
    }

    if ($mode === '--verify-server') {
        verifyOne(
            $server, $mount, $config['volumeRoot'], $config['payloadRoot'], $config['mountTarget']
        );
        return 0;
    }

    $markerPath = processedMarkerPath($config['stateRoot'], $serverUuid);
    if (is_link($markerPath)) {
        fail('Provisioned marker is a symlink: ' . $markerPath);
    }
    if (is_file($markerPath)) {
        logLine('Server ' . $serverUuid . ' is already marked provisioned; no changes were made.');
        return 0;
    }

    $success = provisionOne(
        $server, $mount, $config['volumeRoot'], $config['payloadRoot'],
        $config['mountTarget'], $config['stateRoot'], $payloadCommit
    );

    if (!$success) {
        logLine('Server was not provisioned on this pass; it will remain eligible for a later retry.');
    }

    return 0;
}

try {
    exit(main($argv));
} catch (Throwable $exception) {
    fwrite(STDERR, '[fragcity-provision] ERROR: ' . $exception->getMessage() . PHP_EOL);
    exit(1);
}
