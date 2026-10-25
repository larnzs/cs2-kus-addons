#!/usr/bin/env php
<?php

declare(strict_types=1);

use Illuminate\Contracts\Console\Kernel;
use Pterodactyl\Models\Mount;
use Pterodactyl\Models\Server;
use Symfony\Component\Process\Process;

const DEFAULT_PANEL_ROOT = '/var/www/pterodactyl';
const DEFAULT_VOLUME_ROOT = '/var/lib/pterodactyl/volumes';
const DEFAULT_PAYLOAD_ROOT = '/var/lib/pterodactyl/mounts/fragcity-addon-payload';
const DEFAULT_MOUNT_TARGET = '/home/container/egg/fragcity-payload';
const DEFAULT_STATE_ROOT = '/var/lib/pterodactyl/fragcity-addon-provisioner';

function statusFail(string $message): never
{
    throw new RuntimeException($message);
}

function runReadOnlyCommand(array $arguments, int $timeout = 8): string
{
    $process = new Process($arguments);
    $process->setTimeout($timeout);
    $process->run();

    if (!$process->isSuccessful()) {
        $detail = trim($process->getErrorOutput() . "\n" . $process->getOutput());
        statusFail('Command failed: ' . implode(' ', $arguments) . ($detail === '' ? '' : ' — ' . $detail));
    }

    return trim($process->getOutput());
}

/** @return array{0:string,1:string} container state and actual mount state */
function initialSeedState(
    string $uuid,
    string $volumeRoot,
    bool $baselineKnown,
    bool $inBaseline
): string {
    if (is_link($volumeRoot) || !is_dir($volumeRoot)) {
        return 'UNKNOWN';
    }

    $volume = rtrim($volumeRoot, '/') . '/' . $uuid;
    if (is_link($volume)) {
        return 'UNSAFE';
    }
    if (!is_dir($volume)) {
        return $baselineKnown && $inBaseline ? 'LEGACY' : ($baselineKnown ? 'MISSING' : 'UNKNOWN');
    }

    $path = $volume . '/.fragcity-config-seed-v1.state';
    if (is_link($path)) {
        return 'UNSAFE';
    }
    if (!file_exists($path)) {
        return $baselineKnown && $inBaseline ? 'LEGACY' : ($baselineKnown ? 'MISSING' : 'UNKNOWN');
    }
    if (!is_file($path)) {
        return 'BAD';
    }

    $lines = file($path, FILE_IGNORE_NEW_LINES);
    if ($lines === false
        || !in_array('fragcity-config-seed-v1', $lines, true)
        || !in_array('server_uuid=' . $uuid, $lines, true)) {
        return 'BAD';
    }
    if (in_array('mode=completed', $lines, true)) {
        return 'DONE';
    }
    if (in_array('mode=pending', $lines, true)) {
        return 'PENDING';
    }
    return 'BAD';
}

function baselineRegistryStatus(string $baselinePath, string $registryPath): string
{
    if (is_link($baselinePath) || is_link($registryPath)) {
        return 'UNSAFE';
    }
    if (!is_file($baselinePath)) {
        return 'NO-BASELINE';
    }
    if (file_exists($registryPath) && !is_file($registryPath)) {
        return 'INVALID';
    }
    if (!is_file($registryPath)) {
        return 'MISSING';
    }

    $uuids = file($baselinePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    $published = file($registryPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($uuids === false || $published === false) {
        return 'INVALID';
    }

    $expected = [];
    foreach ($uuids as $uuid) {
        $uuid = trim($uuid);
        if (preg_match('/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/D', $uuid) !== 1) {
            return 'INVALID';
        }
        $expected[] = hash('sha256', $uuid);
    }
    foreach ($published as $digest) {
        if (preg_match('/^[0-9a-f]{64}$/D', trim($digest)) !== 1) {
            return 'INVALID';
        }
    }

    sort($expected, SORT_STRING);
    $published = array_map('trim', $published);
    sort($published, SORT_STRING);
    return $expected === $published ? 'READY' : 'STALE';
}

function inspectContainerMount(string $uuid, string $payloadRoot, string $mountTarget): array
{
    try {
        $idsOutput = runReadOnlyCommand(['docker', 'ps', '-aq', '--filter', 'name=^/' . $uuid . '$']);
        $ids = array_values(array_unique(array_filter(array_map('trim', preg_split('/\R/', $idsOutput) ?: []))));

        if ($ids === []) {
            return ['ABSENT', 'PENDING'];
        }
        if (count($ids) !== 1) {
            return ['ERROR', 'UNKNOWN'];
        }

        $decoded = json_decode(runReadOnlyCommand(['docker', 'inspect', $ids[0]]), true);
        if (!is_array($decoded) || count($decoded) !== 1 || !is_array($decoded[0])) {
            return ['ERROR', 'UNKNOWN'];
        }

        $container = $decoded[0];
        if (($container['Name'] ?? '') !== '/' . $uuid) {
            return ['ERROR', 'UNKNOWN'];
        }

        $state = strtoupper((string) ($container['State']['Status'] ?? 'UNKNOWN'));
        if (preg_match('/^[A-Z_]+$/D', $state) !== 1) {
            $state = 'UNKNOWN';
        }

        $targetMounts = array_values(array_filter(
            $container['Mounts'] ?? [],
            static fn (array $item): bool => rtrim((string) ($item['Destination'] ?? ''), '/') === $mountTarget
        ));

        if (count($targetMounts) !== 1) {
            return [$state, 'OFF'];
        }

        $item = $targetMounts[0];
        $source = rtrim((string) ($item['Source'] ?? ''), '/');
        $readOnly = array_key_exists('RW', $item) && $item['RW'] === false;

        return [$state, ($source === $payloadRoot && $readOnly) ? 'ON' : 'OFF'];
    } catch (Throwable $exception) {
        return ['ERROR', 'UNKNOWN'];
    }
}

try {
    if (!function_exists('posix_geteuid') || posix_geteuid() !== 0) {
        statusFail('Run this read-only status command as root.');
    }

    $panelRoot = rtrim((string) (getenv('FRAGCITY_PANEL_ROOT') ?: DEFAULT_PANEL_ROOT), '/');
    $volumeRoot = rtrim((string) (getenv('FRAGCITY_VOLUME_ROOT') ?: DEFAULT_VOLUME_ROOT), '/');
    $payloadRoot = rtrim((string) (getenv('FRAGCITY_PAYLOAD_SOURCE') ?: DEFAULT_PAYLOAD_ROOT), '/');
    $mountTarget = rtrim((string) (getenv('FRAGCITY_MOUNT_TARGET') ?: DEFAULT_MOUNT_TARGET), '/');
    $stateRoot = rtrim((string) (getenv('FRAGCITY_PROVISIONER_STATE') ?: DEFAULT_STATE_ROOT), '/');

    if (is_link($panelRoot) || !is_dir($panelRoot)) {
        statusFail('Pterodactyl Panel directory is missing or unsafe: ' . $panelRoot);
    }
    if (!is_file($panelRoot . '/vendor/autoload.php') || !is_file($panelRoot . '/bootstrap/app.php')) {
        statusFail('Pterodactyl Laravel bootstrap files are missing.');
    }

    require_once $panelRoot . '/vendor/autoload.php';
    $app = require $panelRoot . '/bootstrap/app.php';
    $app->make(Kernel::class)->bootstrap();

    $mounts = Mount::query()->where('source', $payloadRoot)->where('target', $mountTarget)->get();
    if ($mounts->count() !== 1) {
        statusFail('Expected exactly one FragCity Mount definition for the configured source/target; found ' . $mounts->count() . '.');
    }

    /** @var Mount $mount */
    $mount = $mounts->first();
    if (!$mount->read_only || $mount->user_mountable) {
        statusFail('FragCity Mount must be read-only and not user-mountable.');
    }

    $eggIds = $mount->eggs()->pluck('eggs.id')->map(static fn ($id) => (int) $id)->values()->all();
    $nodeIds = $mount->nodes()->pluck('nodes.id')->map(static fn ($id) => (int) $id)->values()->all();
    if (count($eggIds) !== 1 || count($nodeIds) !== 1) {
        statusFail('FragCity Mount must be assigned to exactly one Egg and one Node; found ' . count($eggIds) . ' Egg(s) and ' . count($nodeIds) . ' Node(s).');
    }

    $baselinePath = $stateRoot . '/baseline-uuids.txt';
    if (is_link($baselinePath)) {
        statusFail('Baseline file is a symlink; refusing to read it.');
    }
    $baselineKnown = is_file($baselinePath);
    $baseline = [];
    if ($baselineKnown) {
        $lines = file($baselinePath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        if ($lines === false) {
            statusFail('Could not read the server baseline.');
        }
        foreach ($lines as $line) {
            $uuid = trim($line);
            if (preg_match('/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/D', $uuid) !== 1) {
                statusFail('Invalid UUID found in baseline file.');
            }
            $baseline[$uuid] = true;
        }
    }

    // Keep the live Panel UUID inventory separate from the immutable first-install baseline.
    // A UUID absent from Panel must not remain in the current server list just because its
    // baseline row or provisioner marker still exists on disk.
    $allPanelUuidSet = [];
    foreach (Server::query()->pluck('uuid')->all() as $panelUuid) {
        $panelUuid = (string) $panelUuid;
        if (!validUuid($panelUuid)) {
            statusFail('Panel returned an invalid server UUID while reconciling the live inventory.');
        }
        $allPanelUuidSet[$panelUuid] = true;
    }

    $assignedIds = array_fill_keys(
        $mount->servers()->pluck('servers.id')->map(static fn ($id) => (int) $id)->values()->all(),
        true
    );
    $servers = Server::query()->whereIn('egg_id', $eggIds)->whereIn('node_id', $nodeIds)->orderBy('created_at')->get();

    // Detect UUID-named Docker containers whose server no longer exists in the Panel.
    // This is observational only: the monitor never removes a container or volume.
    $orphanContainers = [];
    $dockerScanStatus = 'OK';
    try {
        $dockerRows = runReadOnlyCommand(['docker', 'ps', '-a', '--format', '{{.Names}}|{{.State}}'], 10);
        foreach (preg_split('/\R/', $dockerRows) ?: [] as $dockerRow) {
            if ($dockerRow === '') {
                continue;
            }
            $parts = explode('|', $dockerRow, 2);
            $containerName = trim($parts[0] ?? '');
            $containerState = strtoupper(trim($parts[1] ?? 'UNKNOWN'));
            if (validUuid($containerName) && !isset($allPanelUuidSet[$containerName])) {
                $orphanContainers[$containerName] = $containerState;
            }
        }
    } catch (Throwable $exception) {
        $dockerScanStatus = 'ERROR';
    }

    $staleBaselineUuids = [];
    foreach (array_keys($baseline) as $baselineUuid) {
        if (!isset($allPanelUuidSet[$baselineUuid])) {
            $staleBaselineUuids[] = $baselineUuid;
        }
    }

    // Processed markers are historical state, not live servers. Report markers whose
    // UUID vanished from Panel instead of presenting them as current server rows.
    $staleProcessedUuids = [];
    $processedRoot = $stateRoot . '/processed';
    if (!is_link($processedRoot) && is_dir($processedRoot)) {
        foreach (glob($processedRoot . '/*.json') ?: [] as $markerPath) {
            $markerUuid = basename($markerPath, '.json');
            if (validUuid($markerUuid) && !isset($allPanelUuidSet[$markerUuid])) {
                $staleProcessedUuids[$markerUuid] = true;
            }
        }
    }

    $counts = [
        'eligible' => $servers->count(),
        'panel_on' => 0,
        'panel_off' => 0,
        'docker_on' => 0,
        'docker_off' => 0,
        'docker_pending' => 0,
        'docker_unknown' => 0,
        'processed_on' => 0,
        'startup_on' => 0,
        'seed_pending' => 0,
        'seed_missing' => 0,
        'seed_bad' => 0,
    ];

    $registryStatus = baselineRegistryStatus(
        $baselinePath,
        $payloadRoot . '/FRAGCITY_BASELINE_SHA256'
    );
    echo "META\tOK\t" . (int) $mount->id . "\t" . $payloadRoot . "\t" . $mountTarget . "\t" . $registryStatus . PHP_EOL;

    foreach ($servers as $server) {
        $uuid = (string) $server->uuid;
        if (preg_match('/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/D', $uuid) !== 1) {
            statusFail('Panel returned an invalid server UUID.');
        }

        $panelMount = isset($assignedIds[(int) $server->id]) ? 'ON' : 'OFF';
        $panelMount === 'ON' ? $counts['panel_on']++ : $counts['panel_off']++;

        [$containerState, $dockerMount] = inspectContainerMount($uuid, $payloadRoot, $mountTarget);
        if ($dockerMount === 'ON') {
            $counts['docker_on']++;
        } elseif ($dockerMount === 'OFF') {
            $counts['docker_off']++;
        } elseif ($dockerMount === 'PENDING') {
            $counts['docker_pending']++;
        } else {
            $counts['docker_unknown']++;
        }

        $markerPath = $stateRoot . '/processed/' . $uuid . '.json';
        $processed = is_link($markerPath) ? 'UNSAFE' : (is_file($markerPath) ? 'ON' : 'OFF');
        if ($processed === 'ON') {
            $counts['processed_on']++;
        }

        $expectedPrefix = 'bash ' . $mountTarget . '/sync-addon-payload-container.sh && ';
        $startup = str_starts_with((string) $server->startup, $expectedPrefix) ? 'ON' : 'OFF';
        if ($startup === 'ON') {
            $counts['startup_on']++;
        }

        $inBaseline = isset($baseline[$uuid]) ? 'ON' : ($baselineKnown ? 'OFF' : 'UNKNOWN');
        $seedState = initialSeedState($uuid, $volumeRoot, $baselineKnown, isset($baseline[$uuid]));
        if ($seedState === 'PENDING') {
            $counts['seed_pending']++;
        } elseif ($seedState === 'MISSING' && $inBaseline === 'OFF') {
            $counts['seed_missing']++;
        } elseif (in_array($seedState, ['BAD', 'UNSAFE'], true)) {
            $counts['seed_bad']++;
        }

        $name = trim(preg_replace('/[\x00-\x1F\x7F]+/', ' ', (string) $server->name) ?? '');
        echo implode("\t", [
            'SERVER', $uuid, $name, $panelMount, $containerState, $dockerMount,
            $processed, $startup, $inBaseline, $seedState,
        ]) . PHP_EOL;
    }

    echo "DOCKER_SCAN\t" . $dockerScanStatus . PHP_EOL;
    foreach ($orphanContainers as $orphanUuid => $containerState) {
        echo implode("\t", ['ORPHAN_CONTAINER', $orphanUuid, $containerState]) . PHP_EOL;
    }
    foreach ($staleBaselineUuids as $staleUuid) {
        echo implode("\t", ['STALE_BASELINE', $staleUuid]) . PHP_EOL;
    }
    foreach (array_keys($staleProcessedUuids) as $staleUuid) {
        echo implode("\t", ['STALE_MARKER', $staleUuid]) . PHP_EOL;
    }

    echo implode("\t", [
        'SUMMARY',
        (string) $counts['eligible'],
        (string) $counts['panel_on'],
        (string) $counts['panel_off'],
        (string) $counts['docker_on'],
        (string) $counts['docker_off'],
        (string) $counts['docker_pending'],
        (string) $counts['docker_unknown'],
        (string) $counts['processed_on'],
        (string) $counts['startup_on'],
        (string) $counts['seed_pending'],
        (string) $counts['seed_missing'],
        (string) $counts['seed_bad'],
        (string) count($allPanelUuidSet),
        $dockerScanStatus === 'OK' ? (string) count($orphanContainers) : 'UNKNOWN',
        (string) count($staleBaselineUuids),
        (string) count($staleProcessedUuids),
    ]) . PHP_EOL;
    exit(0);
} catch (Throwable $exception) {
    fwrite(STDERR, '[fragcity-mount-status] ERROR: ' . $exception->getMessage() . PHP_EOL);
    exit(1);
}
