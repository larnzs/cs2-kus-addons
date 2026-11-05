<?php

declare(strict_types=1);

/**
 * Render per-server custom CFG files from the checked-in templates.
 *
 * Existing per-server files are authoritative for every setting except hostname:
 * reconciliation changes only that directive, preserving sv_tags, rates, graphics,
 * and any other server-specific edits. Missing files are created from the templates.
 */
final class FragCityCustomCfgSynchronizer
{
    private const MODE_RULES = [
        ['valve-deathmatch-freeforall', 'Deathmatch FFA', '☠'],
        ['deathmatch-freeforall', 'Deathmatch FFA', '☠'],
        ['valve-deathmatch', 'Deathmatch', '☠'],
        ['deathmatch', 'Deathmatch', '☠'],
        ['valve-competitive', 'Competitive', '⚔'],
        ['competitive', 'Competitive', '⚔'],
        ['comp', 'Competitive', '⚔'],
        ['retake', 'Retake', '🔄'],
        ['wingman', 'Wingman', '👥'],
        ['scoutzknivez', 'Scoutzknivez', '🎯'],
        ['minigames', 'Minigames', '🎮'],
        ['deathrun', 'Deathrun', '🏃'],
        ['surf', 'Surf', '🏄'],
        ['bhop', 'Bhop', '🐇'],
        ['kz', 'KZ', '🧗'],
        ['aim', 'Aim', '🚧'],
        ['awp', 'AWP', '🎯'],
        ['hs', 'Headshot', '💥'],
        ['gg', 'Gun Game', '🔫'],
        ['ctf', 'CTF', '🚩'],
        ['br', 'Battle Royale', '👑'],
        ['battle', 'Battle', '🛡'],
        ['practice', 'Practice', '🧪'],
        ['prefire', 'Prefire', '🔥'],
        ['oitc', 'OITC', '🔪'],
        ['course', 'Course', '🧭'],
        ['executes', 'Executes', '⚙'],
        ['soccer', 'Soccer', '⚽'],
        ['war', 'War', '⚔'],
        ['casual-1.6', 'Casual1.6', ''],
        ['1v1', '1v1', '🥊'],
    ];

    public static function modeLabelFromFilename(string $filename): string
    {
        $stem = pathinfo($filename, PATHINFO_FILENAME);
        if (strncasecmp($stem, 'custom_', 7) !== 0) {
            throw new RuntimeException('Custom CFG filename must begin with custom_: ' . $filename);
        }
        $normalized = str_replace('_', '-', strtolower(substr($stem, 7)));
        foreach (self::MODE_RULES as [$needle, $label, $emoji]) {
            if (str_contains($normalized, $needle)) {
                return trim($label . ' ' . $emoji);
            }
        }
        $fallback = str_replace('-', ' ', $normalized);
        $fallback = preg_replace('/\s+/', ' ', trim($fallback));
        return ucwords((string) $fallback);
    }

    public static function sanitizeServerName(string $serverName): string
    {
        if (preg_match('//u', $serverName) !== 1) {
            throw new RuntimeException('Pterodactyl Server Name is not valid UTF-8.');
        }
        $safe = preg_replace('/[\x00-\x1F\x7F;"\\\\]+/u', ' ', trim($serverName));
        if ($safe === null) {
            throw new RuntimeException('Could not sanitize the Pterodactyl Server Name.');
        }
        $safe = preg_replace('/\s+/u', ' ', trim($safe));
        if ($safe === null || $safe === '') {
            throw new RuntimeException('Pterodactyl Server Name cannot be empty after sanitization.');
        }
        if (function_exists('mb_substr')) {
            $safe = mb_substr($safe, 0, 96, 'UTF-8');
        } else {
            preg_match_all('/./us', $safe, $characters);
            $safe = implode('', array_slice($characters[0] ?? [], 0, 96));
        }
        if ($safe === '') {
            throw new RuntimeException('Pterodactyl Server Name became empty after length validation.');
        }
        return $safe;
    }

    public static function render(string $contents, string $serverName, string $filename): string
    {
        $hostname = self::sanitizeServerName($serverName)
            . ' | Mode : ' . self::modeLabelFromFilename($filename);
        $lines = preg_split('/(?<=\n)/', $contents);
        if ($lines === false) {
            throw new RuntimeException('Could not split custom CFG contents: ' . $filename);
        }

        $output = '';
        $hostnameCount = 0;
        $pattern = '/^(\s*hostname\s+)(?:"(?:\\\\.|[^"\\\\])*"|[^;\s]+)(.*)$/i';
        foreach ($lines as $line) {
            $body = $line;
            $newline = '';
            if (preg_match('/(\r\n|\n|\r)$/', $line, $ending) === 1) {
                $newline = $ending[1];
                $body = substr($line, 0, -strlen($newline));
            }
            if (preg_match('/^\s*(?:\/\/|;|#)/', $body) === 1) {
                $output .= $line;
                continue;
            }
            if (preg_match($pattern, $body, $matches) === 1) {
                $hostnameCount++;
                $output .= $matches[1] . '"' . $hostname . '"' . $matches[2] . $newline;
                continue;
            }
            $output .= $line;
        }

        if ($hostnameCount !== 1) {
            throw new RuntimeException(
                'Expected exactly one active hostname directive in ' . $filename .
                '; found ' . $hostnameCount . '.'
            );
        }
        return $output;
    }

    /**
     * Existing target files keep every setting except hostname. Missing targets
     * are seeded from their template. No server files are ever deleted.
     *
     * @return array{files:int,created:int,updated:int,unchanged:int}
     */
    public static function sync(string $templateRoot, string $cfgDirectory, string $serverName): array
    {
        if (is_link($templateRoot) || !is_dir($templateRoot)) {
            throw new RuntimeException('Custom CFG template directory is missing or unsafe: ' . $templateRoot);
        }
        $realTemplates = realpath($templateRoot);
        if ($realTemplates === false || $realTemplates !== rtrim($templateRoot, '/')) {
            throw new RuntimeException('Custom CFG template directory must be canonical: ' . $templateRoot);
        }
        if (is_link($cfgDirectory) || !is_dir($cfgDirectory)) {
            throw new RuntimeException('Server cfg directory is missing or unsafe: ' . $cfgDirectory);
        }
        $realCfg = realpath($cfgDirectory);
        if ($realCfg === false || $realCfg !== rtrim($cfgDirectory, '/')) {
            throw new RuntimeException('Server cfg directory must be canonical: ' . $cfgDirectory);
        }

        $templates = glob($realTemplates . '/custom_*.cfg', GLOB_NOSORT);
        if ($templates === false || $templates === []) {
            throw new RuntimeException('No custom_*.cfg templates were found in ' . $realTemplates);
        }
        sort($templates, SORT_STRING);

        $created = 0;
        $updated = 0;
        $unchanged = 0;
        foreach ($templates as $templatePath) {
            if (is_link($templatePath) || !is_file($templatePath)) {
                throw new RuntimeException('Custom CFG template is not a regular file: ' . $templatePath);
            }
            $realTemplate = realpath($templatePath);
            if ($realTemplate === false || dirname($realTemplate) !== $realTemplates) {
                throw new RuntimeException('Custom CFG template escaped its template directory: ' . $templatePath);
            }

            $filename = basename($realTemplate);
            if (preg_match('/^custom_[A-Za-z0-9._-]+\.cfg$/D', $filename) !== 1) {
                throw new RuntimeException('Unexpected custom CFG template filename: ' . $filename);
            }
            $targetPath = $realCfg . '/' . $filename;
            if (is_link($targetPath)) {
                throw new RuntimeException('Refusing to write through a custom CFG symlink: ' . $targetPath);
            }
            if (file_exists($targetPath) && !is_file($targetPath)) {
                throw new RuntimeException('Custom CFG target exists but is not a regular file: ' . $targetPath);
            }

            $isNew = !is_file($targetPath);
            $sourceContents = file_get_contents($isNew ? $realTemplate : $targetPath);
            if ($sourceContents === false) {
                throw new RuntimeException('Could not read custom CFG file: ' . ($isNew ? $realTemplate : $targetPath));
            }
            $rendered = self::render($sourceContents, $serverName, $filename);
            if ($rendered === $sourceContents) {
                $unchanged++;
                continue;
            }
            self::writeAtomically($targetPath, $rendered, $realCfg);
            if ($isNew) {
                $created++;
            } else {
                $updated++;
            }
        }

        return ['files' => count($templates), 'created' => $created, 'updated' => $updated, 'unchanged' => $unchanged];
    }

    private static function writeAtomically(string $targetPath, string $contents, string $cfgDirectory): void
    {
        if (is_link($targetPath)) {
            throw new RuntimeException('Refusing to replace a custom CFG symlink: ' . $targetPath);
        }
        $metadataPath = is_file($targetPath)
            ? $targetPath
            : (is_file($cfgDirectory . '/server.cfg') ? $cfgDirectory . '/server.cfg' : $cfgDirectory);
        $metadata = stat($metadataPath);
        if ($metadata === false) {
            throw new RuntimeException('Could not read ownership/mode metadata from ' . $metadataPath);
        }
        $mode = ($metadata['mode'] & 0777);
        if ($mode === 0) {
            $mode = 0644;
        }

        $temporaryPath = $cfgDirectory . '/.' . basename($targetPath) . '.fragcity-' . bin2hex(random_bytes(8));
        $handle = @fopen($temporaryPath, 'xb');
        if ($handle === false) {
            throw new RuntimeException('Could not create temporary custom CFG file: ' . $temporaryPath);
        }
        $written = 0;
        $length = strlen($contents);
        try {
            while ($written < $length) {
                $count = fwrite($handle, substr($contents, $written));
                if ($count === false || $count === 0) {
                    throw new RuntimeException('Could not write temporary custom CFG file: ' . $temporaryPath);
                }
                $written += $count;
            }
            if (!fflush($handle)) {
                throw new RuntimeException('Could not flush temporary custom CFG file: ' . $temporaryPath);
            }
        } catch (Throwable $exception) {
            fclose($handle);
            @unlink($temporaryPath);
            throw $exception;
        }
        fclose($handle);

        if (function_exists('posix_geteuid') && posix_geteuid() === 0) {
            if (!chown($temporaryPath, (int) $metadata['uid'])
                || !chgrp($temporaryPath, (int) $metadata['gid'])) {
                @unlink($temporaryPath);
                throw new RuntimeException('Could not preserve custom CFG file ownership: ' . $targetPath);
            }
        }
        if (!chmod($temporaryPath, $mode)) {
            @unlink($temporaryPath);
            throw new RuntimeException('Could not preserve custom CFG file permissions: ' . $targetPath);
        }
        if (is_link($targetPath) || !rename($temporaryPath, $targetPath)) {
            @unlink($temporaryPath);
            throw new RuntimeException('Could not atomically publish custom CFG file: ' . $targetPath);
        }
    }
}
