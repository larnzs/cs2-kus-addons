#!/usr/bin/env php
<?php
declare(strict_types=1);

use Illuminate\Contracts\Console\Kernel;
use Illuminate\Support\Facades\DB;
use Symfony\Component\Process\Process;

const DEFAULT_PANEL_ROOT = '/var/www/pterodactyl';
const DEFAULT_VOLUME_ROOT = '/var/lib/pterodactyl/volumes';
const DEFAULT_STATE_ROOT = '/var/lib/pterodactyl/fragcity-addon-provisioner';
const PROVISIONER_LOCK = '/run/lock/fragcity-addon-provisioner.lock';
const STARTUP_HOOK_PATH = '/home/container/egg/fragcity-payload/sync-addon-payload-container.sh';
const STARTUP_HOOK_PREFIX = 'bash ' . STARTUP_HOOK_PATH . ' && ';
const STATE_FILENAME = 'plugin-conflict-toggle-v1.json';

function logLine(string $message): void { fwrite(STDOUT, '[fragcity-plugin-emergency] ' . $message . PHP_EOL); }
function fail(string $message): never { throw new RuntimeException($message); }
function validUuid(string $uuid): bool { return preg_match('/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/D', $uuid) === 1; }

function startupSyncHookPrefix(string $startup): ?string
{
    if (preg_match('~^\s*(?:bash[ \t]+)?' . preg_quote(STARTUP_HOOK_PATH, '~') . '[ \t]*&&[ \t]*~', $startup, $matches) !== 1) {
        return null;
    }
    return $matches[0];
}

function startupHasSyncHook(string $startup): bool
{
    return startupSyncHookPrefix($startup) !== null;
}

/** Remove only the exact leading FragCity container-side sync hook and return the bytes removed. */
function removeStartupSyncHook(string $startup): string
{
    $prefix = startupSyncHookPrefix($startup);
    if ($prefix === null) {
        return $startup;
    }
    return substr($startup, strlen($prefix));
}

/** Restore the exact per-server prefix captured before emergency mode; do not normalize it. */
function restoreStartupSyncHook(string $startup, string $originalPrefix): string
{
    if (startupHasSyncHook($startup)) { return $startup; }
    if ($originalPrefix === '' || trim($startup) === '') {
        fail('Refusing to restore the payload hook because its original prefix or Startup Command is empty.');
    }
    return $originalPrefix . $startup;
}

function safeVolumePath(string $uuid, string $volumeRoot): string
{
    if (!validUuid($uuid)) { fail('Invalid server UUID: ' . $uuid); }
    if (is_link($volumeRoot) || !is_dir($volumeRoot)) { fail('Pterodactyl volume root is missing or unsafe: ' . $volumeRoot); }
    $realRoot = realpath($volumeRoot);
    if ($realRoot === false || $realRoot !== rtrim($volumeRoot, '/')) { fail('Volume root is not a canonical non-symlink directory: ' . $volumeRoot); }
    $expected = $realRoot . '/' . $uuid;
    if (is_link($expected) || !is_dir($expected)) { fail('Server volume is missing or unsafe for UUID ' . $uuid . ': ' . $expected); }
    $realVolume = realpath($expected);
    if ($realVolume === false || $realVolume !== $expected || dirname($realVolume) !== $realRoot || basename($realVolume) !== $uuid) {
        fail('Server volume failed UUID/path containment validation: ' . $expected);
    }
    return $realVolume;
}

/** Return active, already_disabled, conflict or missing; refuse unsafe paths and symlinks. */
function addonDirectoryState(string $volumePath): string
{
    $cursor = $volumePath;
    foreach (['game', 'csgo'] as $part) {
        $cursor .= '/' . $part;
        if (is_link($cursor)) { fail('Refusing symlink in CS2 addon path: ' . $cursor); }
        if (file_exists($cursor) && !is_dir($cursor)) { fail('CS2 addon parent is not a directory: ' . $cursor); }
        if (!is_dir($cursor)) { return 'missing'; }
    }
    $active = $cursor . '/addons';
    $disabled = $cursor . '/DISABLED_addons';
    if (is_link($active) || is_link($disabled)) { fail('Refusing symlinked addons directory under: ' . $cursor); }
    if ((file_exists($active) && !is_dir($active)) || (file_exists($disabled) && !is_dir($disabled))) {
        fail('addons or DISABLED_addons exists but is not a directory under: ' . $cursor);
    }
    if (is_dir($active) && is_dir($disabled)) { return 'conflict'; }
    if (is_dir($active)) { return 'active'; }
    if (is_dir($disabled)) { return 'already_disabled'; }
    return 'missing';
}

/**
 * Move a recreated addons directory to a unique sibling name without touching its contents.
 * Both directories are known to be real directories under the validated UUID volume.
 */
function quarantineRecreatedAddonDirectory(string $volumePath): string
{
    if (addonDirectoryState($volumePath) !== 'conflict') {
        fail('A recoverable addons conflict is no longer present for UUID ' . basename($volumePath));
    }
    $cs2 = $volumePath . '/game/csgo';
    $source = $cs2 . '/addons';
    for ($attempt = 0; $attempt < 20; $attempt++) {
        $name = 'RECOVERED_addons_' . gmdate('Ymd_His') . '_' . bin2hex(random_bytes(4));
        $destination = $cs2 . '/' . $name;
        clearstatcache(true, $destination);
        if (file_exists($destination) || is_link($destination)) { continue; }
        if (!rename($source, $destination)) {
            fail('Could not quarantine the newly-created addons directory for UUID ' . basename($volumePath));
        }
        logLine('UUID ' . basename($volumePath) . ': preserved conflicting addons as ' . $name . '.');
        return $name;
    }
    fail('Could not allocate a unique RECOVERED_addons directory name for UUID ' . basename($volumePath));
}

/** A directory rename only; no files are removed and no Docker Mount is changed. */
function disableAddonDirectory(string $volumePath, string $beforeState): string
{
    $current = addonDirectoryState($volumePath);
    $cs2 = $volumePath . '/game/csgo';

    if ($current === 'conflict') {
        if (!in_array($beforeState, ['active', 'already_disabled', 'conflict'], true)) {
            fail('Both addons directories appeared unexpectedly for UUID ' . basename($volumePath) . '; preserving both for manual review.');
        }
        return 'quarantined_conflict_' . quarantineRecreatedAddonDirectory($volumePath);
    }

    if ($beforeState === 'active') {
        if ($current === 'active') {
            if (!rename($cs2 . '/addons', $cs2 . '/DISABLED_addons')) { fail('Could not rename addons for UUID ' . basename($volumePath)); }
            return 'renamed';
        }
        if ($current === 'already_disabled') { return 'renamed'; } // interrupted immediately after rename()
        fail('addons disappeared during emergency disable for UUID ' . basename($volumePath));
    }
    if ($beforeState === 'already_disabled') {
        if ($current !== 'already_disabled') { fail('Pre-disabled directory changed unexpectedly for UUID ' . basename($volumePath)); }
        return 'pre_existing_disabled';
    }
    if ($beforeState === 'missing') {
        if ($current !== 'missing') { fail('addons path appeared after the emergency plan for UUID ' . basename($volumePath)); }
        return 'missing';
    }
    if ($beforeState === 'conflict') {
        if ($current === 'already_disabled') { return 'kept_pre_existing_disabled'; }
        fail('The pre-existing addons conflict changed unexpectedly for UUID ' . basename($volumePath));
    }
    fail('Invalid recorded addons state for UUID ' . basename($volumePath));
}

/**
 * Remove only the Egg's per-container MetaMod/CounterStrikeSharp version cache.
 * The UUID volume has already passed safeVolumePath() validation; no shared Mount path is used.
 */
function removeEggVersionsCache(string $volumePath): string
{
    $eggDirectory = $volumePath . '/egg';
    if (is_link($eggDirectory)) {
        fail('Refusing symlinked Egg directory for UUID ' . basename($volumePath));
    }
    clearstatcache(true, $eggDirectory);
    if (!file_exists($eggDirectory)) {
        return 'egg_directory_missing';
    }
    if (!is_dir($eggDirectory)) {
        fail('Egg path exists but is not a directory for UUID ' . basename($volumePath));
    }

    $versionsFile = $eggDirectory . '/versions.txt';
    clearstatcache(true, $versionsFile);
    if (is_link($versionsFile)) {
        fail('Refusing symlinked egg/versions.txt for UUID ' . basename($volumePath));
    }
    if (!file_exists($versionsFile)) {
        return 'already_missing';
    }
    if (!is_file($versionsFile)) {
        fail('egg/versions.txt exists but is not a regular file for UUID ' . basename($volumePath));
    }
    if (!unlink($versionsFile)) {
        fail('Could not remove only egg/versions.txt for UUID ' . basename($volumePath));
    }
    logLine('UUID ' . basename($volumePath) . ': removed only egg/versions.txt so the next normal start can refresh the MetaMod/CounterStrikeSharp version cache.');
    return 'deleted';
}

/** Restore only directories that were active before this tool renamed them. */
function enableAddonDirectory(string $volumePath, string $beforeState): string
{
    $current = addonDirectoryState($volumePath);
    $cs2 = $volumePath . '/game/csgo';

    if ($current === 'conflict') {
        if ($beforeState === 'active') {
            $recovered = quarantineRecreatedAddonDirectory($volumePath);
            if (addonDirectoryState($volumePath) !== 'already_disabled') {
                fail('The original DISABLED_addons directory was not available after conflict quarantine for UUID ' . basename($volumePath));
            }
            if (!rename($cs2 . '/DISABLED_addons', $cs2 . '/addons')) {
                fail('Could not restore the original addons directory after conflict quarantine for UUID ' . basename($volumePath));
            }
            return 'recovered_conflict_and_restored_' . $recovered;
        }
        if (in_array($beforeState, ['already_disabled', 'conflict'], true)) {
            return 'quarantined_conflict_kept_disabled_' . quarantineRecreatedAddonDirectory($volumePath);
        }
        fail('Both addons directories appeared unexpectedly for UUID ' . basename($volumePath) . '; preserving both for manual review.');
    }

    if ($beforeState === 'active') {
        if ($current === 'already_disabled') {
            if (!rename($cs2 . '/DISABLED_addons', $cs2 . '/addons')) { fail('Could not restore addons for UUID ' . basename($volumePath)); }
            return 'restored';
        }
        if ($current === 'active') { return 'already_restored'; } // interrupted immediately after restore rename()
        fail('Neither addons nor DISABLED_addons exists for UUID ' . basename($volumePath));
    }
    if ($beforeState === 'already_disabled') {
        if ($current !== 'already_disabled') { fail('Pre-disabled directory changed unexpectedly for UUID ' . basename($volumePath)); }
        return 'left_pre_existing_disabled';
    }
    if ($beforeState === 'missing') {
        if ($current !== 'missing') { fail('addons path changed while emergency mode was active for UUID ' . basename($volumePath)); }
        return 'left_missing';
    }
    fail('Invalid recorded addons state for UUID ' . basename($volumePath));
}

function ensureStateDirectory(string $path): void
{
    if (is_link($path)) { fail('Emergency state directory must not be a symlink: ' . $path); }
    if (!is_dir($path) && !mkdir($path, 0700, true) && !is_dir($path)) { fail('Could not create emergency state directory: ' . $path); }
    if (!chmod($path, 0700)) { fail('Could not restrict emergency state directory permissions: ' . $path); }
}

function writeStateAtomically(string $path, array $state): void
{
    if (is_link($path) || (file_exists($path) && !is_file($path))) { fail('Emergency state path is unsafe: ' . $path); }
    $json = json_encode($state, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . PHP_EOL;
    $tmp = $path . '.tmp.' . getmypid();
    if (is_link($tmp) || file_exists($tmp)) { fail('Emergency state temporary path exists or is unsafe: ' . $tmp); }
    if (file_put_contents($tmp, $json, LOCK_EX) === false || !chmod($tmp, 0600)) { @unlink($tmp); fail('Could not write emergency state: ' . $path); }
    if (!rename($tmp, $path)) { @unlink($tmp); fail('Could not atomically publish emergency state: ' . $path); }
}

function readState(string $path): ?array
{
    if (is_link($path)) { fail('Emergency state file must not be a symlink: ' . $path); }
    if (!file_exists($path)) { return null; }
    if (!is_file($path)) { fail('Emergency state path is not a regular file: ' . $path); }
    $state = json_decode((string) file_get_contents($path), true);
    if (!is_array($state) || ($state['version'] ?? null) !== 1 || !is_string($state['state'] ?? null) || !is_array($state['servers'] ?? null)) {
        fail('Emergency state file is malformed or has an unsupported version.');
    }
    foreach ($state['servers'] as $uuid => $entry) {
        if (!validUuid((string) $uuid) || !is_array($entry)
            || !in_array($entry['addons_before'] ?? null, ['active', 'already_disabled', 'missing', 'conflict'], true)
            || !is_bool($entry['hook_before'] ?? null)
            || (isset($entry['hook_prefix_before']) && !is_string($entry['hook_prefix_before']))
            || (isset($entry['versions_cache_done']) && !is_bool($entry['versions_cache_done']))) {
            fail('Emergency state file contains an invalid server entry.');
        }
    }
    return $state;
}

function runCommand(array $arguments, int $timeout = 30): string
{
    $process = new Process($arguments);
    $process->setTimeout($timeout);
    $process->run();
    if (!$process->isSuccessful()) {
        $detail = trim($process->getErrorOutput() . "\n" . $process->getOutput());
        fail('Command failed (' . ($process->getExitCode() ?? 1) . '): ' . implode(' ', $arguments) . ($detail === '' ? '' : "\n" . $detail));
    }
    return trim($process->getOutput());
}

function safeContainerMount(string $uuid, string $volumePath): array
{
    $decoded = json_decode(runCommand(['docker', 'inspect', $uuid]), true);
    if (!is_array($decoded) || count($decoded) !== 1 || !is_array($decoded[0])) { fail('Could not decode Docker inspect for UUID ' . $uuid); }
    $container = $decoded[0];
    if (($container['Name'] ?? '') !== '/' . $uuid) { fail('Docker container name does not exactly match UUID ' . $uuid); }
    $mounts = array_values(array_filter($container['Mounts'] ?? [], static fn (array $m): bool => ($m['Destination'] ?? '') === '/home/container'));
    if (count($mounts) !== 1 || rtrim((string) ($mounts[0]['Source'] ?? ''), '/') !== $volumePath) {
        fail('Docker /home/container mapping does not match the UUID volume for ' . $uuid);
    }
    return ['state' => (string) ($container['State']['Status'] ?? 'unknown')];
}

function bootPanel(string $panelRoot): void
{
    if (is_link($panelRoot) || !is_dir($panelRoot)) { fail('Pterodactyl Panel root is missing or unsafe: ' . $panelRoot); }
    if (!is_file($panelRoot . '/vendor/autoload.php') || !is_file($panelRoot . '/bootstrap/app.php')) { fail('Pterodactyl Laravel bootstrap files are missing under: ' . $panelRoot); }
    require_once $panelRoot . '/vendor/autoload.php';
    $app = require $panelRoot . '/bootstrap/app.php';
    $app->make(Kernel::class)->bootstrap();
}

function acquireProvisionerLock()
{
    $handle = fopen(PROVISIONER_LOCK, 'c');
    if ($handle === false || !flock($handle, LOCK_EX)) { if (is_resource($handle)) fclose($handle); fail('Could not acquire the shared Provisioner lock.'); }
    return $handle;
}

/** Block concurrent startup synchronization while the folder and Startup Command are changed. */
function acquirePayloadLock(string $payloadRoot)
{
    $path = rtrim($payloadRoot, '/') . '/.sync.lock';
    if (is_link($path)) { fail('Payload lock is a symlink: ' . $path); }
    if (!is_file($path)) { logLine('Payload .sync.lock is absent; the server Startup Command will still be fixed before any directory change.'); return null; }
    $handle = fopen($path, 'c');
    if ($handle === false || !flock($handle, LOCK_EX)) { if (is_resource($handle)) fclose($handle); fail('Could not acquire exclusive payload sync lock.'); }
    return $handle;
}

function collectLocalUuidContainers(string $volumeRoot): array
{
    $names = runCommand(['docker', 'ps', '-a', '--format', '{{.Names}}']);
    $uuids = [];
    foreach (preg_split('/\R/', $names) ?: [] as $name) {
        $name = trim($name);
        if (validUuid($name)) { $uuids[$name] = true; }
    }
    if ($uuids === []) { return []; }
    $rows = DB::table('servers')->whereIn('uuid', array_keys($uuids))->get(['uuid', 'startup']);
    $servers = [];
    foreach ($rows as $row) { $servers[(string) $row->uuid] = $row; }

    $targets = [];
    foreach (array_keys($uuids) as $uuid) {
        if (!isset($servers[$uuid])) { logLine('Skipping orphan UUID Docker container without a Panel record: ' . $uuid); continue; }
        $volume = safeVolumePath($uuid, $volumeRoot);
        $container = safeContainerMount($uuid, $volume);
        $addonsBefore = addonDirectoryState($volume);
        $startupBefore = (string) ($servers[$uuid]->startup ?? '');
        $hookPrefixBefore = startupSyncHookPrefix($startupBefore) ?? '';
        $hookBefore = $hookPrefixBefore !== '';
        // Non-CS2 UUID containers without a FragCity startup hook are outside this operation.
        if (!$hookBefore && $addonsBefore === 'missing') { continue; }
        $targets[$uuid] = [
            'addons_before' => $addonsBefore,
            'hook_before' => $hookBefore,
            'hook_prefix_before' => $hookPrefixBefore,
            'container_state' => $container['state'],
            'hook_done' => false,
            'addons_done' => false,
            'versions_cache_done' => false,
        ];
    }
    logLine('Discovered ' . count($uuids) . ' UUID containers; selected ' . count($targets) . ' CS2 target(s).');
    return $targets;
}

function updateServerStartup(string $uuid, string $startup): void
{
    if (DB::table('servers')->where('uuid', $uuid)->update(['startup' => $startup]) !== 1) {
        fail('Could not update only the server-specific Startup Command for UUID ' . $uuid);
    }
}

function executeDisable(array &$state, string $path, string $volumeRoot): int
{
    $state['state'] = 'disabling';
    $state['updated_at'] = gmdate('c');
    writeStateAtomically($path, $state);
    $failed = [];

    foreach ($state['servers'] as $uuid => &$entry) {
        try {
            logLine('Disabling plugins for UUID ' . $uuid . '...');
            $row = DB::table('servers')->where('uuid', $uuid)->first(['uuid', 'startup']);
            if ($row === null) { fail('Panel server record disappeared during disable: ' . $uuid); }
            if ($entry['hook_before']) {
                $startup = (string) ($row->startup ?? '');
                $currentPrefix = startupSyncHookPrefix($startup);
                $originalPrefix = (string) ($entry['hook_prefix_before'] ?? STARTUP_HOOK_PREFIX);
                if ($currentPrefix !== null) {
                    if ($currentPrefix !== $originalPrefix) {
                        fail('The server Startup Command hook changed after the emergency plan was recorded; refusing to rewrite it.');
                    }
                    updateServerStartup($uuid, removeStartupSyncHook($startup));
                    logLine('Removed only the exact original payload-sync prefix from the server Startup Command.');
                }
            }
            $entry['hook_done'] = true;
            writeStateAtomically($path, $state);

            $volume = safeVolumePath($uuid, $volumeRoot);
            $result = disableAddonDirectory($volume, $entry['addons_before']);
            $entry['addons_done'] = true;
            unset($entry['last_error'], $entry['last_error_at']);
            $entry['last_successful_action'] = 'disable';
            $entry['last_attempt_at'] = gmdate('c');
            writeStateAtomically($path, $state);
            logLine('UUID ' . $uuid . ': directory=' . $result . ', container=' . ($entry['container_state'] ?? 'unknown'));
        } catch (Throwable $exception) {
            $entry['last_error'] = $exception->getMessage();
            $entry['last_error_at'] = gmdate('c');
            $failed[] = $uuid;
            writeStateAtomically($path, $state);
            logLine('UUID ' . $uuid . ' failed: ' . $exception->getMessage() . ' Continuing with the remaining UUID containers.');
        }
    }
    unset($entry);

    $state['state'] = $failed === [] ? 'disabled' : 'disable_partial';
    $state['updated_at'] = gmdate('c');
    $state['failed_uuids'] = $failed;
    writeStateAtomically($path, $state);

    if ($failed === []) {
        logLine('Emergency disable completed for every target. No plugin files were deleted and no Docker Mount was detached.');
        return 0;
    }
    logLine('Emergency disable partially completed. Successful UUIDs were kept; retry or restore the failed UUIDs from the Control Center. Failed count: ' . count($failed));
    return 1;
}

function executeEnable(array &$state, string $path, string $volumeRoot): int
{
    $state['state'] = 'enabling';
    $state['updated_at'] = gmdate('c');
    writeStateAtomically($path, $state);
    $failed = [];

    foreach ($state['servers'] as $uuid => &$entry) {
        try {
            logLine('Restoring plugins for UUID ' . $uuid . '...');
            $volume = safeVolumePath($uuid, $volumeRoot);
            $result = enableAddonDirectory($volume, $entry['addons_before']);
            $entry['addons_done'] = true;
            writeStateAtomically($path, $state);

            $row = DB::table('servers')->where('uuid', $uuid)->first(['uuid', 'startup']);
            if ($row === null) { fail('Panel server record disappeared during restore: ' . $uuid); }
            if ($entry['hook_before']) {
                $startup = (string) ($row->startup ?? '');
                $originalPrefix = (string) ($entry['hook_prefix_before'] ?? STARTUP_HOOK_PREFIX);
                $restored = restoreStartupSyncHook($startup, $originalPrefix);
                if ($restored !== $startup) {
                    updateServerStartup($uuid, $restored);
                    logLine('Restored the exact original payload-sync prefix in the server Startup Command.');
                }
            }
            $entry['hook_done'] = true;

            if ($entry['addons_before'] === 'active') {
                $versionsCacheResult = removeEggVersionsCache($volume);
                $entry['versions_cache_done'] = true;
                $entry['versions_cache_action'] = $versionsCacheResult;
            } else {
                // Respect servers that were already disabled or had no addons directory before emergency mode.
                $versionsCacheResult = 'preserved_pre_existing_non_active_state';
                $entry['versions_cache_done'] = true;
                $entry['versions_cache_action'] = $versionsCacheResult;
            }

            unset($entry['last_error'], $entry['last_error_at']);
            $entry['last_successful_action'] = 'enable';
            $entry['last_attempt_at'] = gmdate('c');
            writeStateAtomically($path, $state);
            logLine('UUID ' . $uuid . ': directory=' . $result . ', egg_versions_cache=' . $versionsCacheResult);
        } catch (Throwable $exception) {
            $entry['last_error'] = $exception->getMessage();
            $entry['last_error_at'] = gmdate('c');
            $failed[] = $uuid;
            writeStateAtomically($path, $state);
            logLine('UUID ' . $uuid . ' failed: ' . $exception->getMessage() . ' Continuing with the remaining UUID containers.');
        }
    }
    unset($entry);

    $state['state'] = $failed === [] ? 'enabled' : 'enable_partial';
    $state['updated_at'] = gmdate('c');
    $state['failed_uuids'] = $failed;
    writeStateAtomically($path, $state);

    if ($failed === []) {
        logLine('Emergency mode is disabled for every target. Pre-disabled addons directories remain untouched.');
        return 0;
    }
    logLine('Emergency restore partially completed. Successful UUIDs were kept; retry the failed UUIDs from the Control Center. Failed count: ' . count($failed));
    return 1;
}

function statePath(string $root): string { return rtrim($root, '/') . '/' . STATE_FILENAME; }

function printStatus(string $path): int
{
    $state = readState($path);
    if ($state === null || ($state['state'] ?? '') === 'enabled') {
        echo "STATE=enabled\nTARGETS=" . (is_array($state['servers'] ?? null) ? count($state['servers']) : 0) . "\n";
    } else {
        echo 'STATE=' . $state['state'] . "\nTARGETS=" . count($state['servers']) . "\n";
    }
    return 0;
}

function removeTestTree(string $path): void
{
    if (!file_exists($path) && !is_link($path)) { return; }
    if (is_dir($path) && !is_link($path)) {
        $items = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($path, FilesystemIterator::SKIP_DOTS), RecursiveIteratorIterator::CHILD_FIRST);
        foreach ($items as $item) {
            if ($item->isDir() && !$item->isLink()) { rmdir($item->getPathname()); }
            else { unlink($item->getPathname()); }
        }
        rmdir($path);
    } else { unlink($path); }
}

function runSelfTest(): int
{
    $tail = './game/cs2.sh {{CUSTOM_PARAMS}} -tickrate {{TICKRATE}}';
    $hooked = STARTUP_HOOK_PREFIX . $tail;
    $barePrefix = STARTUP_HOOK_PATH . ' && ';
    $bareHooked = $barePrefix . $tail;
    $spacedPrefix = "  bash " . STARTUP_HOOK_PATH . " &&  ";
    $spacedHooked = $spacedPrefix . $tail;
    if (!startupHasSyncHook($hooked) || removeStartupSyncHook($hooked) !== $tail
        || restoreStartupSyncHook($tail, STARTUP_HOOK_PREFIX) !== $hooked
        || restoreStartupSyncHook($hooked, STARTUP_HOOK_PREFIX) !== $hooked
        || removeStartupSyncHook($bareHooked) !== $tail
        || restoreStartupSyncHook($tail, $barePrefix) !== $bareHooked
        || removeStartupSyncHook($spacedHooked) !== $tail
        || restoreStartupSyncHook($tail, $spacedPrefix) !== $spacedHooked) {
        fail('Self-test failed: exact Startup Command prefix removal/restoration/idempotency.');
    }
    $unrelated = 'bash /some/other/script.sh && ' . $tail;
    if (removeStartupSyncHook($unrelated) !== $unrelated) { fail('Self-test failed: unrelated Startup Command was changed.'); }

    $root = sys_get_temp_dir() . '/fragcity-plugin-toggle-test-' . bin2hex(random_bytes(6));
    $cs2 = $root . '/game/csgo';
    if (!mkdir($cs2, 0700, true) || !mkdir($root . '/egg', 0700)) { fail('Self-test could not create temporary fixture.'); }
    try {
        file_put_contents($root . '/egg/versions.txt', "metamod=old\ncss=old\n");
        file_put_contents($root . '/egg/keep-this-file.txt', 'unrelated-egg-data');
        mkdir($cs2 . '/addons', 0700);
        mkdir($cs2 . '/addons/sample-plugin', 0700);
        file_put_contents($cs2 . '/addons/sample-plugin/keep-me.txt', 'original-plugin-files');
        $before = addonDirectoryState($root);
        if ($before !== 'active' || disableAddonDirectory($root, $before) !== 'renamed'
            || !is_file($cs2 . '/DISABLED_addons/sample-plugin/keep-me.txt') || is_dir($cs2 . '/addons')
            || !is_file($root . '/egg/versions.txt')) {
            fail('Self-test failed: disable rename must preserve plugin data and egg/versions.txt.');
        }
        if (enableAddonDirectory($root, 'active') !== 'restored'
            || file_get_contents($cs2 . '/addons/sample-plugin/keep-me.txt') !== 'original-plugin-files'
            || addonDirectoryState($root) !== 'active') {
            fail('Self-test failed: normal reverse rename or content preservation.');
        }
        $cacheRemoval = removeEggVersionsCache($root);
        if ($cacheRemoval !== 'deleted' || file_exists($root . '/egg/versions.txt')
            || file_get_contents($root . '/egg/keep-this-file.txt') !== 'unrelated-egg-data') {
            fail('Self-test failed: Enable must remove only egg/versions.txt and preserve other Egg files.');
        }
        if (removeEggVersionsCache($root) !== 'already_missing'
            || file_get_contents($root . '/egg/keep-this-file.txt') !== 'unrelated-egg-data') {
            fail('Self-test failed: versions cache removal is not idempotent or changed unrelated files.');
        }

        // Reproduce the reported incident: a new addons folder appears while the original is disabled.
        if (!rename($cs2 . '/addons', $cs2 . '/DISABLED_addons')) {
            fail('Self-test could not prepare the disabled original directory.');
        }
        mkdir($cs2 . '/addons', 0700);
        mkdir($cs2 . '/addons/newly-created', 0700);
        file_put_contents($cs2 . '/addons/newly-created/preserve-this.txt', 'recreated-addon-data');
        if (addonDirectoryState($root) !== 'conflict') {
            fail('Self-test failed: simultaneous addons and DISABLED_addons must be detected as a recoverable conflict.');
        }
        $recovery = enableAddonDirectory($root, 'active');
        $recovered = glob($cs2 . '/RECOVERED_addons_*', GLOB_ONLYDIR) ?: [];
        if (!str_starts_with($recovery, 'recovered_conflict_and_restored_')
            || count($recovered) !== 1
            || file_get_contents($cs2 . '/addons/sample-plugin/keep-me.txt') !== 'original-plugin-files'
            || file_get_contents($recovered[0] . '/newly-created/preserve-this.txt') !== 'recreated-addon-data'
            || addonDirectoryState($root) !== 'active') {
            fail('Self-test failed: conflict quarantine did not preserve both folders and restore the original plugin directory.');
        }
        if (enableAddonDirectory($root, 'active') !== 'already_restored'
            || count(glob($cs2 . '/RECOVERED_addons_*', GLOB_ONLYDIR) ?: []) !== 1) {
            fail('Self-test failed: conflict recovery is not idempotent.');
        }

        // A server that was already disabled before emergency mode must remain disabled.
        if (!rename($cs2 . '/addons', $cs2 . '/DISABLED_addons')) {
            fail('Self-test could not prepare a pre-disabled fixture.');
        }
        mkdir($cs2 . '/addons', 0700);
        file_put_contents($cs2 . '/addons/unexpected-file.txt', 'keep-separate');
        file_put_contents($root . '/egg/versions.txt', "leave-pre-disabled-cache\n");
        $preDisabledResult = enableAddonDirectory($root, 'already_disabled');
        $recovered = glob($cs2 . '/RECOVERED_addons_*', GLOB_ONLYDIR) ?: [];
        $unexpectedDataPreserved = false;
        foreach ($recovered as $recoveredDirectory) {
            $unexpectedPath = $recoveredDirectory . '/unexpected-file.txt';
            if (is_file($unexpectedPath) && file_get_contents($unexpectedPath) === 'keep-separate') {
                $unexpectedDataPreserved = true;
                break;
            }
        }
        if (!str_starts_with($preDisabledResult, 'quarantined_conflict_kept_disabled_')
            || count($recovered) !== 2
            || !$unexpectedDataPreserved
            || file_get_contents($cs2 . '/DISABLED_addons/sample-plugin/keep-me.txt') !== 'original-plugin-files'
            || !is_file($root . '/egg/versions.txt')
            || addonDirectoryState($root) !== 'already_disabled') {
            fail('Self-test failed: pre-disabled state was not preserved while quarantining the recreated addons directory.');
        }

        echo "PASS: Startup Command hook removal/restoration and idempotency.\n";
        echo "PASS: addons directory disable/enable renames preserve all original files.\n";
        echo "PASS: recreated addons conflict is quarantined with a unique RECOVERED_addons_* name; original DISABLED_addons is restored.\n";
        echo "PASS: pre-disabled servers remain disabled; recreated addons data is preserved separately.\n";
        echo "PASS: repeated recovery is idempotent and unrelated Startup Commands are unchanged.\n";
        echo "PASS: Disable preserves egg/versions.txt; Enable removes only that cache file and preserves other Egg files.\n";
        echo "PASS: pre-disabled addon directories and their Egg version cache remain untouched.\n";
    } finally { removeTestTree($root); }
    return 0;
}

function main(array $argv): int
{
    $mode = $argv[1] ?? '--help';
    $panel = rtrim((string) (getenv('FRAGCITY_PANEL_ROOT') ?: DEFAULT_PANEL_ROOT), '/');
    $volumes = rtrim((string) (getenv('FRAGCITY_VOLUME_ROOT') ?: DEFAULT_VOLUME_ROOT), '/');
    $payload = rtrim((string) (getenv('FRAGCITY_PAYLOAD_SOURCE') ?: '/var/lib/pterodactyl/mounts/fragcity-addon-payload'), '/');
    $stateRoot = rtrim((string) (getenv('FRAGCITY_PROVISIONER_STATE') ?: DEFAULT_STATE_ROOT), '/');
    $stateFile = statePath($stateRoot);

    if ($mode === '--help' || $mode === '-h') {
        echo "Usage: php plugin-conflict-toggle.php --status|--disable|--enable|--self-test\n";
        return 0;
    }
    if (isset($argv[2])) { fail('Unexpected extra arguments.'); }
    if ($mode === '--self-test') { return runSelfTest(); }
    if ($mode === '--status') { return printStatus($stateFile); }
    if (!in_array($mode, ['--disable', '--enable'], true)) { fail('Unknown action: ' . $mode); }
    if (!function_exists('posix_geteuid') || posix_geteuid() !== 0) { fail('Emergency toggle must run as root.'); }

    ensureStateDirectory($stateRoot);
    $provisionerLock = acquireProvisionerLock();
    $payloadLock = null;
    try {
        bootPanel($panel);
        $payloadLock = acquirePayloadLock($payload);
        $state = readState($stateFile);

        if ($mode === '--disable') {
            if ($state !== null && ($state['state'] ?? '') === 'disabled') {
                logLine('Emergency plugin disable is already active; no changes made.');
                return 0;
            }
            if ($state === null || ($state['state'] ?? '') === 'enabled') {
                $targets = collectLocalUuidContainers($volumes);
                if ($targets === []) { fail('No local UUID-named CS2 containers with an addons directory or FragCity payload Startup hook were found.'); }
                $state = [
                    'version' => 1, 'state' => 'disabling',
                    'created_at' => gmdate('c'), 'updated_at' => gmdate('c'),
                    'servers' => $targets,
                ];
                writeStateAtomically($stateFile, $state);
            }
            return executeDisable($state, $stateFile, $volumes);
        }

        if ($state === null || ($state['state'] ?? '') === 'enabled') {
            logLine('Emergency disable is not active; no changes made.');
            return 0;
        }
        return executeEnable($state, $stateFile, $volumes);
    } finally {
        if (is_resource($payloadLock)) { flock($payloadLock, LOCK_UN); fclose($payloadLock); }
        if (is_resource($provisionerLock)) { flock($provisionerLock, LOCK_UN); fclose($provisionerLock); }
    }
}

try { exit(main($argv)); }
catch (Throwable $exception) {
    fwrite(STDERR, '[fragcity-plugin-emergency] ERROR: ' . $exception->getMessage() . PHP_EOL);
    exit(1);
}
