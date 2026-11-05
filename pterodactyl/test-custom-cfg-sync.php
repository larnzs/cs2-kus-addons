<?php

declare(strict_types=1);

require_once __DIR__ . '/custom-cfg-sync.php';

function expect(bool $condition, string $message): void
{
    if (!$condition) {
        throw new RuntimeException('FAIL: ' . $message);
    }
}

function expectThrows(callable $callback, string $message): void
{
    try {
        $callback();
    } catch (Throwable $exception) {
        return;
    }
    throw new RuntimeException('FAIL: expected exception: ' . $message);
}

$root = sys_get_temp_dir() . '/fragcity-custom-cfg-test-' . bin2hex(random_bytes(6));
$templateRoot = $root . '/templates';
$cfgRoot = $root . '/volume/game/csgo/cfg';
if (!mkdir($templateRoot, 0700, true) || !mkdir($cfgRoot, 0700, true)) {
    throw new RuntimeException('Could not create test directories.');
}

try {
    $template = implode("\r\n", [
        '// template comment',
        'hostname "OLD NAME | Mode : Practice"',
        'sv_tags "128tick"',
        'sv_minrate 196608',
        'sv_maxrate 196608',
        'sv_server_graphic1 "sv_server_graphic1.png"',
        'sv_server_graphic2 "sv_server_graphic2.png"',
        'echo "custom practice"',
        '',
    ]);
    file_put_contents($templateRoot . '/custom_practice.cfg', $template);
    file_put_contents($templateRoot . '/custom_valve-deathmatch-freeforall.cfg', $template);
    file_put_contents($cfgRoot . '/server.cfg', "// mode fixture\n");

    $first = FragCityCustomCfgSynchronizer::sync($templateRoot, $cfgRoot, 'FragCity Test "North";exec echo BAD');
    expect($first['files'] === 2 && $first['created'] === 2 && $first['updated'] === 0,
        'initial render creates both custom CFG files');

    $practicePath = $cfgRoot . '/custom_practice.cfg';
    $practice = (string) file_get_contents($practicePath);
    expect(str_contains($practice, 'hostname "FragCity Test North exec echo BAD | Mode : Practice 🧪"'),
        'server name is safely rendered with practice mode suffix');
    expect(!str_contains($practice, '"North";'), 'quotes and command separators cannot escape the hostname string');
    expect(str_contains($practice, 'sv_tags "128tick"'), 'sv_tags is preserved');
    expect(str_contains($practice, 'sv_minrate 196608') && str_contains($practice, 'sv_maxrate 196608'),
        'server rates are preserved');
    expect(str_contains($practice, 'sv_server_graphic1 "sv_server_graphic1.png"')
        && str_contains($practice, 'sv_server_graphic2 "sv_server_graphic2.png"'),
        'server graphics are preserved');

    $second = FragCityCustomCfgSynchronizer::sync($templateRoot, $cfgRoot, 'FragCity Test "North";exec echo BAD');
    expect($second['created'] === 0 && $second['updated'] === 0 && $second['unchanged'] === 2,
        'repeated reconciliation is idempotent');

    // Non-hostname server settings survive a later Panel Server Name change.
    $customized = str_replace('sv_tags "128tick"', 'sv_tags "customer-tag"', $practice);
    file_put_contents($practicePath, $customized);
    $renamed = FragCityCustomCfgSynchronizer::sync($templateRoot, $cfgRoot, 'FragCity North-2');
    $renamedPractice = (string) file_get_contents($practicePath);
    expect($renamed['updated'] === 2, 'a Server Name change updates the custom CFG files');
    expect(str_contains($renamedPractice, 'hostname "FragCity North-2 | Mode : Practice 🧪"'),
        'renamed server hostname is rendered');
    expect(str_contains($renamedPractice, 'sv_tags "customer-tag"'),
        'rename does not overwrite server tags');
    expect(str_contains($renamedPractice, 'sv_minrate 196608') && str_contains($renamedPractice, 'sv_maxrate 196608'),
        'rename does not overwrite server rates');

    $ffa = (string) file_get_contents($cfgRoot . '/custom_valve-deathmatch-freeforall.cfg');
    expect(str_contains($ffa, 'Mode : Deathmatch FFA ☠'),
        'specific Valve FFA rule wins before generic Deathmatch rule');

    expectThrows(
        static fn () => FragCityCustomCfgSynchronizer::render("sv_tags \"fixture\"\n", 'Name', 'custom_missing.cfg'),
        'template without hostname must fail closed'
    );

    $outside = $root . '/outside.txt';
    file_put_contents($outside, 'untouched');
    @unlink($cfgRoot . '/custom_practice.cfg');
    if (!symlink($outside, $cfgRoot . '/custom_practice.cfg')) {
        throw new RuntimeException('Could not create symlink fixture.');
    }
    expectThrows(
        static fn () => FragCityCustomCfgSynchronizer::sync($templateRoot, $cfgRoot, 'Blocked Name'),
        'symlink target must be rejected'
    );
    expect((string) file_get_contents($outside) === 'untouched',
        'symlink target contents remain untouched');

    echo "PASS: custom CFG templates render per Panel Server Name; rename is idempotent; tags/rates/graphics are preserved; symlinks are rejected.\n";
} finally {
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
        RecursiveIteratorIterator::CHILD_FIRST
    );
    foreach ($iterator as $entry) {
        $path = $entry->getPathname();
        if ($entry->isDir() && !$entry->isLink()) {
            @rmdir($path);
        } else {
            @unlink($path);
        }
    }
    @rmdir($root);
}
