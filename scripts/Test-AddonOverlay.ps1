[CmdletBinding()]
param(
    [switch]$SnapshotConfigs,
    [switch]$CompareConfigSnapshot,
    [switch]$VerifyAddons,
    [string]$SnapshotPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $RepoRoot "DEPENDENCIES.json"
$CsgoRoot = Join-Path $RepoRoot "server\game\csgo"

if (($SnapshotConfigs -or $CompareConfigSnapshot) -and [string]::IsNullOrWhiteSpace($SnapshotPath)) {
    throw "-SnapshotPath is required for configuration snapshot operations."
}
if (-not (Test-Path $CsgoRoot -PathType Container)) {
    throw "Missing runtime overlay root: $CsgoRoot"
}

function Get-ProtectedConfigSnapshot {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($relativeRoot in @("cfg", "addons\counterstrikesharp\configs")) {
        $absoluteRoot = Join-Path $CsgoRoot $relativeRoot
        if (-not (Test-Path $absoluteRoot -PathType Container)) {
            continue
        }

        Get-ChildItem -LiteralPath $absoluteRoot -Recurse -File -Force | ForEach-Object {
            if ($_.Name -in ".gitnote", ".gitkeep") { return }
            $relative = $_.FullName.Substring($CsgoRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            [void]$items.Add([pscustomobject]@{ path = $relative; sha256 = $hash })
        }
    }
    return @($items.ToArray() | Sort-Object -Property path)
}

if ($SnapshotConfigs) {
    $parent = Split-Path -Parent $SnapshotPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $items = @(Get-ProtectedConfigSnapshot)
    $json = ConvertTo-Json -InputObject $items -Depth 10
    [IO.File]::WriteAllText($SnapshotPath, ($json + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Snapshotted $($items.Count) protected config files." -ForegroundColor Cyan
}

if ($CompareConfigSnapshot) {
    if (-not (Test-Path $SnapshotPath -PathType Leaf)) {
        throw "Configuration snapshot was not found: $SnapshotPath"
    }
    $baseline = @(Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json)
    $current = @(Get-ProtectedConfigSnapshot)
    $baselineMap = @{}
    $currentMap = @{}
    foreach ($item in $baseline) { $baselineMap[[string]$item.path] = [string]$item.sha256 }
    foreach ($item in $current) { $currentMap[[string]$item.path] = [string]$item.sha256 }

    $problems = New-Object System.Collections.Generic.List[string]
    foreach ($path in $baselineMap.Keys) {
        if (-not $currentMap.ContainsKey($path)) { [void]$problems.Add("Removed config file: $path") }
        elseif ($currentMap[$path] -ne $baselineMap[$path]) { [void]$problems.Add("Changed config file: $path") }
    }
    foreach ($path in $currentMap.Keys) {
        if (-not $baselineMap.ContainsKey($path)) { [void]$problems.Add("New config file: $path") }
    }
    if ($problems.Count -gt 0) {
        throw ("Protected configuration changed during addon update:" + [Environment]::NewLine + ($problems -join [Environment]::NewLine))
    }
    Write-Host "Protected cfg/ and CounterStrikeSharp configs are unchanged ($($current.Count) files)." -ForegroundColor Green
}

if ($VerifyAddons) {
    if (-not (Test-Path $ManifestPath -PathType Leaf)) { throw "Missing manifest: $ManifestPath" }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $missing = New-Object System.Collections.Generic.List[string]
    $checked = 0

    foreach ($addon in @($manifest.addons | Sort-Object order)) {
        if (-not [bool]$addon.installed) {
            Write-Host "SKIP $($addon.name): installed=false" -ForegroundColor DarkGray
            continue
        }
        if ($addon.PSObject.Properties.Name -notcontains "verify_paths" -or @($addon.verify_paths).Count -eq 0) {
            throw "Installed addon '$($addon.name)' has no verify_paths in DEPENDENCIES.json."
        }

        foreach ($relativePathValue in @($addon.verify_paths)) {
            $relativePath = ([string]$relativePathValue).Replace('/', '\')
            if ([string]::IsNullOrWhiteSpace($relativePath) -or
                [IO.Path]::IsPathRooted($relativePath) -or
                $relativePath -match '(^|[\\/])\.\.([\\/]|$)') {
                throw "Unsafe verify_paths entry for '$($addon.name)': $relativePath"
            }
            $fullPath = [IO.Path]::GetFullPath((Join-Path $CsgoRoot $relativePath))
            $rootPrefix = [IO.Path]::GetFullPath($CsgoRoot).TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
            if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Verification path escaped the runtime root for '$($addon.name)': $relativePath"
            }
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                [void]$missing.Add("$($addon.name): server/game/csgo/$($relativePath.Replace('\', '/'))")
            }
            else { $checked++ }
        }

        if ($addon.PSObject.Properties.Name -contains "verify_globs") {
            foreach ($globValue in @($addon.verify_globs)) {
                $relativeGlob = ([string]$globValue).Replace('/', '\')
                if ([string]::IsNullOrWhiteSpace($relativeGlob) -or
                    [IO.Path]::IsPathRooted($relativeGlob) -or
                    $relativeGlob -match '(^|[\\/])\.\.([\\/]|$)') {
                    throw "Unsafe verify_globs entry for '$($addon.name)': $relativeGlob"
                }
                $guardRelative = $relativeGlob -replace '[*?]', 'wildcard'
                $guardFull = [IO.Path]::GetFullPath((Join-Path $CsgoRoot $guardRelative))
                $rootPrefix = [IO.Path]::GetFullPath($CsgoRoot).TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
                if (-not $guardFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Verification glob escaped the runtime root for '$($addon.name)': $relativeGlob"
                }
                $matches = @(Get-ChildItem -Path (Join-Path $CsgoRoot $relativeGlob) -File -ErrorAction SilentlyContinue)
                if ($matches.Count -eq 0) {
                    [void]$missing.Add("$($addon.name): server/game/csgo/$relativeGlob (no file matched runtime requirement)")
                }
                else {
                    $checked++
                    Write-Host "Runtime requirement matched $($matches.Count) file(s): $relativeGlob" -ForegroundColor DarkGray
                }
            }
        }
        Write-Host "Checked $($addon.name) $($addon.version)" -ForegroundColor Green
    }

    if ($missing.Count -gt 0) {
        throw ("Required runtime files are missing:" + [Environment]::NewLine + ($missing -join [Environment]::NewLine))
    }
    Write-Host "Verified $checked required files across installed addons." -ForegroundColor Green
}
