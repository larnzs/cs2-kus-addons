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
    $repoTemplateRoot = __DIR__ . '/custom-cfg';
    $repoCfgRoot = dirname(__DIR__) . '/game/csgo/cfg';
    $actualTemplates = glob($repoTemplateRoot . '/custom_*.cfg', GLOB_NOSORT);
    expect(is_array($actualTemplates) && count($actualTemplates) === 37,
        'repository contains exactly 37 active custom CFG templates');
    expect(FragCityCustomCfgSynchronizer::modeEmojiFromFilename('custom_casual-1.6.cfg') === '🕹️',
        'Casual 1.6 receives an emoji-only hostname suffix');
    expect(FragCityCustomCfgSynchronizer::modeEmojiFromFilename('custom_casualw.cfg') === '🧰',
        'Casual Workshop receives its own emoji-only hostname suffix');
    $casualWorkshopTemplate = file_get_contents($repoTemplateRoot . '/custom_casualw.cfg');
    expect($casualWorkshopTemplate !== false
        && !str_contains((string) $casualWorkshopTemplate, 'exec settings/alltalk_on.cfg'),
        'Casual Workshop template does not inherit Casual-only gameplay settings');
    expect(str_contains((string) $casualWorkshopTemplate, '// Executed after casualw.cfg'),
        'Casual Workshop template documents its actual CFG entry point');
    expect(FragCityCustomCfgSynchronizer::modeEmojiFromFilename('custom_deathmatch-valve.cfg') === '🎯',
        'Valve Deathmatch template retains the matching active CFG filename and emoji');
    expect(FragCityCustomCfgSynchronizer::modeEmojiFromFilename('custom_valve-deathmatch.cfg') === '🎯',
        'Valve Deathmatch Map Start settings keep their own matching custom CFG alias and emoji');
    $templateNames = [];
    foreach ($actualTemplates as $actualTemplate) {
        $filename = basename($actualTemplate);
        $templateNames[$filename] = true;
        $contents = file_get_contents($actualTemplate);
        expect($contents !== false, 'repository template is readable: ' . $filename);
        $emoji = FragCityCustomCfgSynchronizer::modeEmojiFromFilename($filename);
        expect($emoji !== '' && preg_match('//u', $emoji) === 1 && !str_contains($emoji, '�')
            && preg_match('/U\\+[0-9A-F]{4,6}/i', $emoji) !== 1,
            $filename . ' maps to a real UTF-8 emoji character, not a replacement glyph or code-point text');
        $renderedTemplate = FragCityCustomCfgSynchronizer::render((string) $contents, 'FragCity Template Check', $filename);
        $expectedHostnamePattern = '/^\\s*hostname\\s+"FragCity Template Check - '
            . preg_quote($emoji, '/') . '"\\s*$/mi';
        expect(preg_match($expectedHostnamePattern, $renderedTemplate) === 1,
            $filename . ' renders the exact server-name / hyphen / emoji hostname format');
        expect(!str_contains($renderedTemplate, 'Mode :') && !str_contains($renderedTemplate, ' | '),
            $filename . ' does not render the legacy label or pipe separator');
        foreach (['sv_tags', 'sv_minrate', 'sv_maxrate', 'sv_server_graphic1', 'sv_server_graphic2'] as $directive) {
            expect(preg_match_all('/^\s*' . preg_quote($directive, '/') . '\b/mi', (string) $contents) === 1,
                $filename . ' has exactly one ' . $directive . ' directive');
        }
    }
    expect(glob($repoCfgRoot . '/custom_*.cfg') === [],
        'no static custom CFG files remain in the deployable game/csgo/cfg tree');

    $referencedCustomConfigs = [];
    foreach (glob($repoCfgRoot . '/*.cfg') ?: [] as $modeCfg) {
        $modeContents = file_get_contents($modeCfg);
        if ($modeContents === false) {
            throw new RuntimeException('Could not read game CFG: ' . $modeCfg);
        }
        if (preg_match_all('/^\s*exec\s+"?(custom_[A-Za-z0-9._-]+\.cfg)\b/im', $modeContents, $matches) > 0) {
            foreach ($matches[1] as $name) {
                $referencedCustomConfigs[$name][] = basename($modeCfg);
            }
        }
    }
    foreach ($referencedCustomConfigs as $referencedName => $sourceCfgs) {
        expect(isset($templateNames[$referencedName]),
            'every active exec custom_*.cfg reference has a template: ' . $referencedName .
            ' (referenced by: ' . implode(', ', array_unique($sourceCfgs)) . ')');
    }

    $actualOutputRoot = $root . '/actual-repo-template-render';
    if (!mkdir($actualOutputRoot, 0700, true)) {
        throw new RuntimeException('Could not create actual-template render directory.');
    }
    $actualRender = FragCityCustomCfgSynchronizer::sync(
        $repoTemplateRoot,
        $actualOutputRoot,
        'FragCity Template Check'
    );
    expect($actualRender['files'] === 37 && $actualRender['created'] === 37,
        'all 37 repository templates render successfully into a fresh server cfg folder; stats=' . json_encode($actualRender));

    $template = implode("\r\n", [
        '// template comment',
        'hostname "OLD NAME - 🧪"',
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
    expect(str_contains($practice, 'hostname "FragCity Test North exec echo BAD - 🧪"'),
        'server name is safely rendered with the practice emoji suffix');
    expect(!str_contains($practice, 'Mode :') && !str_contains($practice, ' | '),
        'rendered hostname contains neither the legacy text label nor the pipe separator');
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
    expect(str_contains($renamedPractice, 'hostname "FragCity North-2 - 🧪"'),
        'renamed server hostname is rendered with the hyphen and emoji');
    expect(str_contains($renamedPractice, 'sv_tags "customer-tag"'),
        'rename does not overwrite server tags');
    expect(str_contains($renamedPractice, 'sv_minrate 196608') && str_contains($renamedPractice, 'sv_maxrate 196608'),
        'rename does not overwrite server rates');

    $ffa = (string) file_get_contents($cfgRoot . '/custom_valve-deathmatch-freeforall.cfg');
    expect(str_contains($ffa, 'hostname "FragCity North-2 - 🎯"'),
        'specific Valve FFA rule wins before generic Deathmatch rule and renders its emoji');

    expectThrows(
        static fn () => FragCityCustomCfgSynchronizer::render("sv_tags \"fixture\"\n", 'Name', 'custom_missing.cfg'),
        'template without hostname must fail closed'
    );

    expectThrows(
        static fn () => FragCityCustomCfgSynchronizer::render("hostname \"old\"\n", 'Name', 'custom_unmapped.cfg'),
        'template without an explicit game-mode emoji must fail closed'
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
