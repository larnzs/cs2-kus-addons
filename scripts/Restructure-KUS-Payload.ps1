param([Parameter(Mandatory=$true)][string]$KusRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
function Copy-TreeContent([string]$Source, [string]$Destination, [string]$Relative = "") {
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Missing source tree: $Source" }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        $rel = if ($Relative) { "$Relative/$($item.Name)" } else { $item.Name }
        if (
            $rel -ceq "cfg/settings/MatchZy/lang/pt-pt.json" -or
            $rel -ceq "addons/counterstrikesharp/plugins/disabled/MatchZy/lang/pt-pt.json"
        ) {
            $archive = Join-Path $script:RepoRoot "docs/upstream/runtime-case-collisions/MatchZy/lang/pt-pt.json"
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $archive) | Out-Null
            Copy-Item -LiteralPath $item.FullName -Destination $archive -Force
            Write-Host "Archived case-colliding MatchZy locale outside runtime."
            continue
        }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            Copy-TreeContent -Source $item.FullName -Destination $target -Relative $rel
        } else {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}
function Get-RelativePayloadPath([string]$RuntimeRelative, [string]$PayloadRoot) {
    $normalized = $RuntimeRelative.Replace("\", "/")
    $windowsOnly = (
        $normalized -match '^(?i:addons/counterstrikesharp/api/)' -or
        $normalized -match '^(?i:addons/counterstrikesharp/bin/win64/)' -or
        $normalized -match '^(?i:addons/counterstrikesharp/dotnet/)' -or
        $normalized -match '^(?i:addons/.+/bin/win64/)' -or
        $normalized -match '^(?i:cfg/settings/)'
    )
    $overlayPath = Join-Path (Join-Path $PayloadRoot "addons/windows") ($normalized.Replace("/", [IO.Path]::DirectorySeparatorChar))
    if ($windowsOnly -or (Test-Path -LiteralPath $overlayPath -PathType Leaf)) { return "addons/windows/$normalized" }
    return $normalized
}

$repoOutput = (& git rev-parse --show-toplevel 2>$null)
if (-not $repoOutput) { throw "Run this script inside the unified repository." }
$script:RepoRoot = [IO.Path]::GetFullPath($repoOutput.Trim())
$RepoRoot = $script:RepoRoot
$branchName = (& git -C $RepoRoot branch --show-current).Trim()
if ($branchName -ne "integration/kus-monorepo") { throw "Migration is allowed only on integration/kus-monorepo." }

$KusRoot = [IO.Path]::GetFullPath((Join-Path $RepoRoot $KusRoot))
$KusPayload = Join-Path $KusRoot "game/csgo"
$LegacyRuntime = Join-Path $RepoRoot "server/game/csgo"
$PayloadRoot = Join-Path $RepoRoot "game/csgo"
$OverlayManifest = Join-Path $RepoRoot "docs/upstream/LARNZ-RUNTIME-FILES.txt"
$ManifestPath = Join-Path $RepoRoot "DEPENDENCIES.json"

if (-not (Test-Path -LiteralPath (Join-Path $KusRoot ".git"))) { throw "Pinned KUS checkout is missing: $KusRoot" }
if (-not (Test-Path -LiteralPath $KusPayload -PathType Container)) { throw "Pinned KUS game/csgo payload is missing." }
if (-not (Test-Path -LiteralPath $LegacyRuntime -PathType Container)) { throw "Current tracked runtime is missing; refusing to replace an unknown payload." }
if (-not (Test-Path -LiteralPath $OverlayManifest -PathType Leaf)) { throw "Larnz preservation manifest is missing." }
if (Test-Path -LiteralPath $PayloadRoot -PathType Container) {
    if (@(Get-ChildItem -LiteralPath $PayloadRoot -Recurse -File -Force -ErrorAction SilentlyContinue).Count -gt 100) {
        throw "game/csgo already contains a payload. This migration is one-shot and will not overwrite it."
    }
}

$kusCommit = (& git -C $KusRoot rev-parse HEAD).Trim()
Write-Host "KUS source commit: $kusCommit"
Write-Host "Building tracked game/csgo payload from the pinned KUS source tree..."
Copy-TreeContent -Source $KusPayload -Destination $PayloadRoot

$larnzPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in Get-Content -LiteralPath $OverlayManifest) {
    $entry = $entry.Trim()
    if ($entry.StartsWith("server/game/csgo/", [StringComparison]::OrdinalIgnoreCase)) {
        [void]$larnzPaths.Add($entry.Substring("server/game/csgo/".Length).Replace("\", "/"))
    }
}
$baseFiles = @{}
Get-ChildItem -LiteralPath $PayloadRoot -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($PayloadRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
    $baseFiles[$rel] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
}

$currentFiles = @(Get-ChildItem -LiteralPath $LegacyRuntime -Recurse -File -Force)
$preservedPayloadPaths = New-Object 'System.Collections.Generic.List[string]'
foreach ($file in $currentFiles) {
    $rel = $file.FullName.Substring($LegacyRuntime.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
    $existsInKus = $baseFiles.ContainsKey($rel)
    $currentHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    $isListedLarnz = $larnzPaths.Contains($rel)
    $differsFromKus = (-not $existsInKus) -or ($currentHash -ne $baseFiles[$rel])
    if (-not $isListedLarnz -and -not $differsFromKus) { continue }

    $targetRel = Get-RelativePayloadPath -RuntimeRelative $rel -PayloadRoot $PayloadRoot
    $target = Join-Path $PayloadRoot ($targetRel.Replace("/", [IO.Path]::DirectorySeparatorChar))
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    [void]$preservedPayloadPaths.Add("game/csgo/$targetRel")
}
Write-Host "Preserved $($preservedPayloadPaths.Count) Larnz/local files and platform overrides."
Write-Utf8 -Path $OverlayManifest -Text (($preservedPayloadPaths | Sort-Object -Unique) -join [Environment]::NewLine)

# CSS's Windows with-runtime archive belongs in the Windows overlay, never over the shared Linux binary.
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$manifest.architecture.target_root = "game/csgo"
$manifest.architecture | Add-Member -NotePropertyName platform_overlay_root -NotePropertyValue "game/csgo/addons/windows" -Force
$manifest.architecture | Add-Member -NotePropertyName runtime_roots -NotePropertyValue ([ordered]@{
    windows = "server/game/csgo"
    linux = "<SteamCMD install root>/game/csgo"
}) -Force
$css = @($manifest.addons | Where-Object name -eq "CounterStrikeSharp") | Select-Object -First 1
if (-not $css) { throw "CounterStrikeSharp entry is missing from DEPENDENCIES.json." }
$css.merge = "release_plugin_directory"
$css | Add-Member -NotePropertyName source_path -NotePropertyValue "addons/counterstrikesharp" -Force
$css | Add-Member -NotePropertyName install_path -NotePropertyValue "addons/windows/addons/counterstrikesharp" -Force
$assetMappings = [ordered]@{
    "counterstrikesharp-with-runtime-windows-{version}.zip" = @([ordered]@{
        merge = "release_plugin_directory"
        source_path = "addons/counterstrikesharp"
        install_path = "addons/windows/addons/counterstrikesharp"
    })
}
$css | Add-Member -NotePropertyName asset_mappings -NotePropertyValue $assetMappings -Force
$css.verify_paths = @(
    "addons/windows/addons/counterstrikesharp/api/CounterStrikeSharp.API.dll",
    "addons/windows/addons/counterstrikesharp/bin/win64/counterstrikesharp.dll",
    "addons/windows/addons/counterstrikesharp/dotnet/dotnet.exe"
)
$css.verify_globs = @(
    "addons/windows/addons/counterstrikesharp/dotnet/shared/Microsoft.NETCore.App/*/System.Private.CoreLib.dll",
    "addons/windows/addons/counterstrikesharp/dotnet/host/fxr/*/hostfxr.dll"
)
Write-Utf8 -Path $ManifestPath -Text (($manifest | ConvertTo-Json -Depth 30) + [Environment]::NewLine)

# SteamCMD output is local; game/csgo is the tracked source payload.
$ignorePath = Join-Path $RepoRoot ".gitignore"
$ignore = Get-Content -LiteralPath $ignorePath -Raw
$marker = "# Unified KUS/Larnz server: only the managed payload trees are tracked."
$markerIndex = $ignore.IndexOf($marker, [StringComparison]::Ordinal)
if ($markerIndex -lt 0) { throw "Could not find the unified .gitignore marker." }
$ignore = $ignore.Substring(0, $markerIndex).TrimEnd()
$ignore += @'

# KUS-style architecture: tracked source payload and local SteamCMD install are separate.
.env
/steamcmd/
/server/
/game/*
!/game/csgo/
'@ + [Environment]::NewLine
Write-Utf8 -Path $ignorePath -Text $ignore

# Redirect the release updater and archive inspector to the tracked payload tree.
$updaterPath = Join-Path $RepoRoot "scripts/Update-Addons.ps1"
$updater = Get-Content -LiteralPath $updaterPath -Raw
$oldRootLine = '$ServerRoot = Join-Path $RepoRoot "server\game\csgo"'
if (-not $updater.Contains($oldRootLine)) { throw "Update-Addons.ps1 root was not found." }
$updater = $updater.Replace($oldRootLine, '$PayloadRoot = Join-Path $RepoRoot "game\csgo"')
$updater = $updater.Replace('$ServerRoot', '$PayloadRoot').Replace('$serverRootFull', '$payloadRootFull').Replace('$serverFull', '$payloadFull')
$updater = $updater.Replace('server/game/csgo', 'game/csgo').Replace('server\game\csgo', 'game\csgo').Replace('server/game', 'game')
$updater = $updater.Replace('^(?i:addons/counterstrikesharp/configs)', '^(?i:addons/(windows/addons/)?counterstrikesharp/configs)')
Write-Utf8 -Path $updaterPath -Text $updater

$inspectPath = Join-Path $RepoRoot "scripts/Inspect-Releases.ps1"
$inspect = Get-Content -LiteralPath $inspectPath -Raw
if (-not $inspect.Contains($oldRootLine)) { throw "Inspect-Releases.ps1 root was not found." }
$inspect = $inspect.Replace($oldRootLine, '$PayloadRoot = Join-Path $RepoRoot "game\csgo"')
$inspect = $inspect.Replace('$ServerRoot', '$PayloadRoot').Replace('$serverFull', '$payloadFull')
$inspect = $inspect.Replace('server/game/csgo', 'game/csgo').Replace('server\game\csgo', 'game\csgo')
Write-Utf8 -Path $inspectPath -Text $inspect

# Verification runs against the staged source by default; -VerifyRuntime maps overlay paths after flattening.
$verifyPath = Join-Path $RepoRoot "scripts/Test-AddonOverlay.ps1"
$verify = @'
[CmdletBinding()]
param(
    [switch]$SnapshotConfigs,
    [switch]$CompareConfigSnapshot,
    [switch]$VerifyAddons,
    [switch]$VerifyRuntime,
    [string]$SnapshotPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $RepoRoot "DEPENDENCIES.json"
$PayloadRoot = Join-Path $RepoRoot "game\csgo"
$RuntimeRoot = Join-Path $RepoRoot "server\game\csgo"
$CsgoRoot = if ($VerifyRuntime) { $RuntimeRoot } else { $PayloadRoot }
if (($SnapshotConfigs -or $CompareConfigSnapshot) -and [string]::IsNullOrWhiteSpace($SnapshotPath)) { throw "-SnapshotPath is required." }
if (-not (Test-Path -LiteralPath $CsgoRoot -PathType Container)) { throw "Missing payload/runtime root: $CsgoRoot" }

function Resolve-VerificationPath([string]$RelativePath) {
    if ($VerifyRuntime -and $RelativePath.StartsWith("addons\windows\", [StringComparison]::OrdinalIgnoreCase)) {
        return $RelativePath.Substring("addons\windows\".Length)
    }
    return $RelativePath
}
function Get-ProtectedConfigSnapshot {
    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($relativeRoot in @("cfg", "addons\counterstrikesharp\configs")) {
        $absoluteRoot = Join-Path $CsgoRoot $relativeRoot
        if (-not (Test-Path -LiteralPath $absoluteRoot -PathType Container)) { continue }
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
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $json = ConvertTo-Json -InputObject @(Get-ProtectedConfigSnapshot) -Depth 10
    [IO.File]::WriteAllText($SnapshotPath, ($json + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    Write-Host "Configuration snapshot written."
}
if ($CompareConfigSnapshot) {
    if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) { throw "Snapshot missing: $SnapshotPath" }
    $baseline = @(Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json)
    $current = @(Get-ProtectedConfigSnapshot)
    $before = @{}; $after = @{}
    foreach ($x in $baseline) { $before[[string]$x.path] = [string]$x.sha256 }
    foreach ($x in $current) { $after[[string]$x.path] = [string]$x.sha256 }
    $problems = New-Object 'System.Collections.Generic.List[string]'
    foreach ($path in $before.Keys) {
        if (-not $after.ContainsKey($path)) { [void]$problems.Add("Removed config: $path") }
        elseif ($after[$path] -ne $before[$path]) { [void]$problems.Add("Changed config: $path") }
    }
    foreach ($path in $after.Keys) { if (-not $before.ContainsKey($path)) { [void]$problems.Add("New config: $path") } }
    if ($problems.Count) { throw ($problems -join [Environment]::NewLine) }
    Write-Host "Protected configs unchanged ($($current.Count) files)." -ForegroundColor Green
}
if ($VerifyAddons) {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Missing manifest: $ManifestPath" }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $missing = New-Object 'System.Collections.Generic.List[string]'
    $checked = 0
    foreach ($addon in @($manifest.addons | Sort-Object order)) {
        if (-not [bool]$addon.installed) { Write-Host "SKIP $($addon.name): installed=false"; continue }
        if ($addon.PSObject.Properties.Name -notcontains "verify_paths" -or @($addon.verify_paths).Count -eq 0) {
            throw "Installed addon '$($addon.name)' has no verify_paths."
        }
        foreach ($pathValue in @($addon.verify_paths)) {
            $relative = Resolve-VerificationPath (([string]$pathValue).Replace('/', '\'))
            if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)') {
                throw "Unsafe verify_paths entry for '$($addon.name)': $relative"
            }
            $full = [IO.Path]::GetFullPath((Join-Path $CsgoRoot $relative))
            $prefix = [IO.Path]::GetFullPath($CsgoRoot).TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
            if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Verification path escaped root: $relative" }
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { [void]$missing.Add("$($addon.name): $relative") } else { $checked++ }
        }
        if ($addon.PSObject.Properties.Name -contains "verify_globs") {
            foreach ($globValue in @($addon.verify_globs)) {
                $glob = Resolve-VerificationPath (([string]$globValue).Replace('/', '\'))
                if ([string]::IsNullOrWhiteSpace($glob) -or [IO.Path]::IsPathRooted($glob) -or $glob -match '(^|[\\/])\.\.([\\/]|$)') {
                    throw "Unsafe verify_globs entry for '$($addon.name)': $glob"
                }
                $guard = [IO.Path]::GetFullPath((Join-Path $CsgoRoot ($glob -replace '[*?]', 'wildcard')))
                $prefix = [IO.Path]::GetFullPath($CsgoRoot).TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
                if (-not $guard.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Verification glob escaped root: $glob" }
                if (@(Get-ChildItem -Path (Join-Path $CsgoRoot $glob) -File -ErrorAction SilentlyContinue).Count -eq 0) {
                    [void]$missing.Add("$($addon.name): $glob (no glob match)")
                }
            }
        }
    }
    if ($missing.Count) { throw ("Missing required files:" + [Environment]::NewLine + ($missing -join [Environment]::NewLine)) }
    Write-Host "Verified $checked required paths/globs in $CsgoRoot." -ForegroundColor Green
}
'@
Write-Utf8 -Path $verifyPath -Text $verify

# KUS-style Windows deployment script.
$deployPath = Join-Path $RepoRoot "scripts/Deploy-Runtime.ps1"
$deploy = @'
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$PayloadRoot = Join-Path $RepoRoot "game\csgo"
$RuntimeRoot = Join-Path $RepoRoot "server\game\csgo"
$GameInfoPath = Join-Path $RuntimeRoot "gameinfo.gi"
if (-not (Test-Path -LiteralPath (Join-Path $PayloadRoot "addons") -PathType Container)) { throw "Tracked payload is missing: $PayloadRoot\addons" }
if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) { throw "SteamCMD runtime is missing: $RuntimeRoot" }
if (-not (Test-Path -LiteralPath $GameInfoPath -PathType Leaf)) { throw "gameinfo.gi is missing. Run install.bat first." }

function Copy-TreeContent {
    param([string]$Source, [string]$Destination, [string]$RelativePath = "", [switch]$SkipWindowsOverlay)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        $relative = if ($RelativePath) { "$RelativePath/$($item.Name)" } else { $item.Name }
        $normalized = $relative.Replace("\", "/")
        if ($SkipWindowsOverlay -and ($normalized.Equals("addons/windows", [StringComparison]::OrdinalIgnoreCase) -or $normalized.StartsWith("addons/windows/", [StringComparison]::OrdinalIgnoreCase))) { continue }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) { Copy-TreeContent -Source $item.FullName -Destination $target -RelativePath $relative -SkipWindowsOverlay:$SkipWindowsOverlay }
        else {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}
function Copy-PayloadFiles {
    param([string]$Source, [string]$Destination, [string]$RelativePath = "")
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        $relative = if ($RelativePath) { "$RelativePath/$($item.Name)" } else { $item.Name }
        $normalized = $relative.Replace("\", "/")
        if ($normalized.Equals("addons", [StringComparison]::OrdinalIgnoreCase) -or $normalized.Equals("cfg/settings", [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($normalized.Equals("gameinfo.gi", [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to replace SteamCMD-owned gameinfo.gi." }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            Copy-PayloadFiles -Source $item.FullName -Destination $target -RelativePath $relative
        } else {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}
$WorkRoot = Join-Path $RepoRoot ("tmp\deploy-runtime-" + [guid]::NewGuid().ToString("N"))
$IncomingRoot = Join-Path $WorkRoot "csgo"
$WindowsOverlay = Join-Path $PayloadRoot "addons\windows"
$RuntimeAddons = Join-Path $RuntimeRoot "addons"
$IncomingAddons = Join-Path $IncomingRoot "addons"
$RuntimeSettings = Join-Path $RuntimeRoot "cfg\settings"
$IncomingSettings = Join-Path $IncomingRoot "cfg\settings"
$BackupAddons = Join-Path $WorkRoot "addons.previous"
$BackupSettings = Join-Path $WorkRoot "settings.previous"
$BackupConfig = Join-Path $WorkRoot "css-configs.previous"
$ConfigDestination = Join-Path $RuntimeRoot "addons\counterstrikesharp\configs"
$addonsBackupCreated = $false
$settingsBackupCreated = $false
$configBackupCreated = $false
$addonsInstalled = $false
$settingsInstalled = $false
try {
    Write-Host "Staging shared KUS payload..."
    Copy-TreeContent -Source $PayloadRoot -Destination $IncomingRoot -SkipWindowsOverlay
    if (-not (Test-Path -LiteralPath $WindowsOverlay -PathType Container)) { throw "Windows overlay is missing: $WindowsOverlay" }
    Write-Host "Flattening game\csgo\addons\windows\ into Windows runtime..."
    Copy-TreeContent -Source $WindowsOverlay -Destination $IncomingRoot
    Write-Host "Prepared $(@(Get-ChildItem -LiteralPath $IncomingRoot -Recurse -File -Force).Count) payload files."

    if (Test-Path -LiteralPath $ConfigDestination -PathType Container) {
        New-Item -ItemType Directory -Force -Path $BackupConfig | Out-Null
        Copy-TreeContent -Source $ConfigDestination -Destination $BackupConfig
        $configBackupCreated = $true
    }
    Copy-PayloadFiles -Source $IncomingRoot -Destination $RuntimeRoot

    if (Test-Path -LiteralPath $RuntimeAddons -PathType Container) {
        Move-Item -LiteralPath $RuntimeAddons -Destination $BackupAddons
        $addonsBackupCreated = $true
    }
    Move-Item -LiteralPath $IncomingAddons -Destination $RuntimeAddons
    $addonsInstalled = $true

    if (Test-Path -LiteralPath $RuntimeSettings -PathType Container) {
        Move-Item -LiteralPath $RuntimeSettings -Destination $BackupSettings
        $settingsBackupCreated = $true
    }
    if (Test-Path -LiteralPath $IncomingSettings -PathType Container) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $RuntimeSettings) | Out-Null
        Move-Item -LiteralPath $IncomingSettings -Destination $RuntimeSettings
        $settingsInstalled = $true
    }
    if ($settingsBackupCreated -and (Test-Path -LiteralPath $BackupSettings)) { Copy-TreeContent -Source $BackupSettings -Destination $RuntimeSettings }
    if ($configBackupCreated) {
        New-Item -ItemType Directory -Force -Path $ConfigDestination | Out-Null
        Copy-TreeContent -Source $BackupConfig -Destination $ConfigDestination
    }
    if ($addonsBackupCreated -and (Test-Path -LiteralPath $BackupAddons)) { Remove-Item -LiteralPath $BackupAddons -Recurse -Force }
    Write-Host "SUCCESS: payload deployed; cfg/settings and CSS configs were preserved."
}
catch {
    if ($settingsInstalled -and (Test-Path -LiteralPath $RuntimeSettings -PathType Container)) { Remove-Item -LiteralPath $RuntimeSettings -Recurse -Force }
    if ($settingsBackupCreated -and (Test-Path -LiteralPath $BackupSettings -PathType Container)) { Move-Item -LiteralPath $BackupSettings -Destination $RuntimeSettings -Force }
    if ($addonsInstalled -and (Test-Path -LiteralPath $RuntimeAddons -PathType Container)) { Remove-Item -LiteralPath $RuntimeAddons -Recurse -Force }
    if ($addonsBackupCreated -and (Test-Path -LiteralPath $BackupAddons -PathType Container)) { Move-Item -LiteralPath $BackupAddons -Destination $RuntimeAddons -Force }
    throw
}
finally { if (Test-Path -LiteralPath $WorkRoot -PathType Container) { Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue } }
'@
Write-Utf8 -Path $deployPath -Text $deploy

$winPath = Join-Path $RepoRoot "win.bat"
$winBat = @'
@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Prepare and Deploy
set "PAUSE_ON_EXIT=1"
if /I "%~1"=="--no-pause" set "PAUSE_ON_EXIT=0"
set "RC=1"
cd /d "%~dp0"
set "ROOT_DIR=%~dp0"
set "PAYLOAD_DIR=%ROOT_DIR%game\csgo"
set "SERVER_DIR=%ROOT_DIR%server"
set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"
set "GAMEINFO=%SERVER_DIR%\game\csgo\gameinfo.gi"
echo.
echo ============================================
echo       CS2 KUS Addons - Prepare and Deploy
echo ============================================
echo Tracked payload: %PAYLOAD_DIR%
echo Installed game:  %SERVER_DIR%
echo Runtime target:  %SERVER_DIR%\game\csgo
echo.
if not exist "%ROOT_DIR%DEPENDENCIES.json" (echo ERROR: DEPENDENCIES.json is missing.& goto :finish)
if not exist "%PAYLOAD_DIR%\addons\" (echo ERROR: Tracked payload is missing from game\csgo.& goto :finish)
if not exist "%CS2_EXE%" (echo ERROR: CS2 is not installed. Run install.bat first.& goto :finish)
if not exist "%GAMEINFO%" (echo ERROR: gameinfo.gi is missing. Run install.bat/SteamCMD first.& goto :finish)
if not exist "%PAYLOAD_DIR%\addons\windows\addons\counterstrikesharp\dotnet\dotnet.exe" (
    echo ERROR: CounterStrikeSharp Windows with-runtime payload is missing.
    echo Run addons-update.bat -Only CounterStrikeSharp after updating this checkout.
    goto :finish
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%scripts\Deploy-Runtime.ps1"
if errorlevel 1 (echo ERROR: Payload deployment failed.& goto :finish)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%scripts\Patch-GameInfo.ps1" -GameInfoPath "%GAMEINFO%"
if errorlevel 1 (echo ERROR: Could not patch the installed gameinfo.gi.& goto :finish)
if not exist "%SERVER_DIR%\game\csgo\addons\metamod\bin\win64\metamod.2.cs2.dll" (echo ERROR: Windows Metamod binary is missing after deployment.& goto :finish)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%scripts\Test-AddonOverlay.ps1" -VerifyAddons -VerifyRuntime
if errorlevel 1 (echo ERROR: Deployed runtime verification failed.& goto :finish)
echo.
echo SUCCESS: game\csgo payload deployed and gameinfo.gi patched.
echo No Git pull, SteamCMD update, or server launch was performed.
set "RC=0"
:finish
echo.
if "%RC%"=="0" (echo Result: SUCCESS) else (echo Result: FAILED ^(exit code %RC%^))
if "%PAUSE_ON_EXIT%"=="1" (echo. & echo Press any key to close this window . . . & pause >nul)
endlocal & exit /b %RC%
'@
Write-Utf8 -Path $winPath -Text $winBat

foreach ($batName in @("install.bat", "game-update.bat")) {
    $batPath = Join-Path $RepoRoot $batName
    $bat = Get-Content -LiteralPath $batPath -Raw
    $pattern = '(?m)^\s*"%STEAMCMD%" \+force_install_dir "%SERVER_DIR%" \+login anonymous \+app_update 730(?: validate)? \+quit\s*$'
    if ($bat -notmatch $pattern) { throw "Could not find SteamCMD invocation in $batName." }
    $newCommand = 'pushd "%STEAMCMD_DIR%"' + [Environment]::NewLine +
        'start "" /wait "%STEAMCMD%" +force_install_dir ..\server +login anonymous +app_update 730 +quit' + [Environment]::NewLine +
        'set "STEAMCMD_RC=%ERRORLEVEL%"' + [Environment]::NewLine + 'popd'
    $bat = [regex]::Replace($bat, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $newCommand }, 1)
    $bat = $bat.Replace($newCommand + [Environment]::NewLine + 'set "STEAMCMD_RC=%ERRORLEVEL%"', $newCommand)
    if ($batName -eq "install.bat") {
        $bat = $bat.Replace('echo SteamCMD will verify, update, and repair this installation as needed.', 'echo SteamCMD will check/update the existing game with the KUS-compatible command.')
        $bat = $bat.Replace('echo SteamCMD will install the game now.', 'echo SteamCMD will install the game with the KUS-compatible command.')
        $bat = $bat.Replace('echo ERROR: SteamCMD failed to install, update, or validate CS2', 'echo ERROR: SteamCMD failed to install or update CS2. Check steamcmd\logs\stderr.txt.')
    } else {
        $bat = $bat.Replace('set "STEAMCMD=%ROOT_DIR%steamcmd\steamcmd.exe"', 'set "STEAMCMD_DIR=%ROOT_DIR%steamcmd"' + [Environment]::NewLine + 'set "STEAMCMD=%STEAMCMD_DIR%\steamcmd.exe"')
        $manifestBlock = 'if not exist "%APP_MANIFEST%" (' + [Environment]::NewLine + '    echo ERROR: CS2 app manifest was not found. Run install.bat first.' + [Environment]::NewLine + '    goto :finish' + [Environment]::NewLine + ')' + [Environment]::NewLine
        $bat = $bat.Replace($manifestBlock, '')
        $bat = $bat.Replace('echo Updating CS2 game files through SteamCMD...', 'echo Updating/checking CS2 game files through SteamCMD (KUS-compatible command)...')
        $bat = $bat.Replace('if errorlevel 1 (' + [Environment]::NewLine + '    echo ERROR: SteamCMD game update failed.' + [Environment]::NewLine + '    goto :finish' + [Environment]::NewLine + ')',
            'if not "%STEAMCMD_RC%"=="0" (' + [Environment]::NewLine + '    echo ERROR: SteamCMD game update failed. Check steamcmd\logs\stderr.txt.' + [Environment]::NewLine + '    goto :finish' + [Environment]::NewLine + ')')
    }
    Write-Utf8 -Path $batPath -Text $bat
}

# Update the optional KUS re-import script to keep its platform overlay nested.
$integratorPath = Join-Path $RepoRoot "scripts/Integrate-KUS.ps1"
$integrator = Get-Content -LiteralPath $integratorPath -Raw
$rewriteStart = $integrator.IndexOf("function Rewrite-Paths {")
$rewriteEnd = $integrator.IndexOf([Environment]::NewLine + [Environment]::NewLine + '$RepoRoot =', $rewriteStart)
if ($rewriteStart -lt 0 -or $rewriteEnd -lt $rewriteStart) { throw "Could not isolate Rewrite-Paths in Integrate-KUS.ps1." }
$newRewrite = 'function Rewrite-Paths {' + [Environment]::NewLine +
    '    param([string]$Path)' + [Environment]::NewLine +
    '    # KUS differentiates the tracked payload from the installed runtime.' + [Environment]::NewLine +
    '    return' + [Environment]::NewLine + '}'
$integrator = $integrator.Substring(0, $rewriteStart) + $newRewrite + $integrator.Substring($rewriteEnd + (2 * [Environment]::NewLine.Length))
$integrator = $integrator.Replace('$runtimeRoot = Join-Path $RepoRoot "server/game/csgo"', '$runtimeRoot = Join-Path $RepoRoot "game/csgo"')
$integrator = $integrator.Replace('git -C $RepoRoot ls-files -- "server/game/csgo"', 'git -C $RepoRoot ls-files -- "game/csgo"')
$integrator = $integrator.Replace('$_.StartsWith("server/game/csgo/")', '$_.StartsWith("game/csgo/")')
$integrator = $integrator.Replace('$trackedPath.StartsWith("server/game/csgo/")', '$trackedPath.StartsWith("game/csgo/")')
$integrator = $integrator.Replace('"server/game/csgo/".Length', '"game/csgo/".Length')
$integrator = $integrator.Replace('Copy-Tree -Source $KusRuntime -Destination $runtimeRoot -SkipWindows', 'Copy-Tree -Source $KusRuntime -Destination $runtimeRoot')
$flattenBlock = '$windowsTree = Join-Path $KusRuntime "addons/windows"' + [Environment]::NewLine + 'if (Test-Path -LiteralPath $windowsTree -PathType Container) { Copy-Tree -Source $windowsTree -Destination $runtimeRoot }'
$integrator = $integrator.Replace($flattenBlock, '')
$readmeStart = $integrator.IndexOf("# Build the root README from the authoritative unified header plus the full upstream guide.")
$ignoreStart = $integrator.IndexOf("# The combined repository owns the final server path; keep the SteamCMD installation local.")
if ($readmeStart -lt 0 -or $ignoreStart -lt $readmeStart) { throw "Could not safely update Integrate-KUS.ps1 README/path block." }
$readmeBlock = @'
# Keep the unified README authoritative; archive the source README as a reference.
$kusReadme = [IO.File]::ReadAllText((Join-Path $KusRootResolved "README.md"))
Write-Utf8 -Path (Join-Path $RepoRoot "docs/upstream/KUS-README.md") -Text $kusReadme

'@
$integrator = $integrator.Substring(0, $readmeStart) + $readmeBlock + $integrator.Substring($ignoreStart)
$integrator = $integrator.Replace('# The combined repository owns the final server path; keep the SteamCMD installation local.', '# Keep local SteamCMD output separate from the tracked payload.')
$oldIgnore = '/server/*' + [Environment]::NewLine + '!/server/game/' + [Environment]::NewLine +
    '/server/game/*' + [Environment]::NewLine + '!/server/game/csgo/' + [Environment]::NewLine +
    '/server/game/csgo/*' + [Environment]::NewLine + '!/server/game/csgo/addons/' + [Environment]::NewLine +
    '!/server/game/csgo/addons/**' + [Environment]::NewLine + '!/server/game/csgo/cfg/' + [Environment]::NewLine +
    '/server/game/csgo/cfg/*' + [Environment]::NewLine + '!/server/game/csgo/gamemodes_server.txt' + [Environment]::NewLine +
    '!/server/game/csgo/mapcycle.txt' + [Environment]::NewLine + '!/server/game/csgo/subscribed_collection_ids.txt' + [Environment]::NewLine +
    '!/server/game/csgo/subscribed_file_ids.txt'
$integrator = $integrator.Replace($oldIgnore, '/server/')
$integrator = $integrator.Replace('runtime_root = "server/game/csgo"', 'runtime_root = "game/csgo"')
$integrator = $integrator.Replace('windows_overlay_policy = "Flatten Windows-specific payloads into server/game/csgo, then restore Larnz overlay last."', 'windows_overlay_policy = "Keep Windows-specific payloads under game/csgo/addons/windows; flatten only during Windows deployment."')
Write-Utf8 -Path $integratorPath -Text $integrator

# Workflow YAML is managed through the repository API; do not edit .github/workflows from this runner.

# Keep shared map tools writing to the tracked payload.
$addMapPath = Join-Path $RepoRoot "scripts/add-map.py"
$addMap = Get-Content -LiteralPath $addMapPath -Raw
$addMap = $addMap.Replace("server/game/csgo/gamemodes_server.txt", "game/csgo/gamemodes_server.txt")
$addMap = $addMap.Replace("server/game/csgo/subscribed_file_ids.txt", "game/csgo/subscribed_file_ids.txt")
$addMap = [regex]::Replace($addMap, '(?s)    parser\.add_argument\(\s*"--custom".*?    args = parser\.parse_args\(\)\s*gamemodes_server_path = pathlib\.Path\(\s*"custom_files/gamemodes_server\.txt".*?    add_map_to_group\(', '    args = parser.parse_args()' + [Environment]::NewLine +
    '    gamemodes_server_path = pathlib.Path("game/csgo/gamemodes_server.txt")' + [Environment]::NewLine +
    '    subscribed_file_ids_path = pathlib.Path("game/csgo/subscribed_file_ids.txt")' + [Environment]::NewLine + [Environment]::NewLine +
    '    add_map_to_group(', 1)
Write-Utf8 -Path $addMapPath -Text $addMap

$updateLibPath = Join-Path $RepoRoot "scripts/update/lib.sh"
if (Test-Path -LiteralPath $updateLibPath) {
    $updateLib = Get-Content -LiteralPath $updateLibPath -Raw
    $updateLib = $updateLib.Replace("server/game/csgo/addons/", "game/csgo/addons/")
    Write-Utf8 -Path $updateLibPath -Text $updateLib
}

# Update source documentation at the top level to separate the tracked payload from the installed runtime.
$readmePath = Join-Path $RepoRoot "README.md"
$readme = Get-Content -LiteralPath $readmePath -Raw
$readme = [regex]::Replace($readme, '(?m)^\*\*The repository''s canonical runtime path is.*$', '**The repository follows KUS''s staged payload model.** game/csgo/ is the tracked source payload; server/ is the local Windows SteamCMD install and is ignored by Git. win.bat deploys the source payload into server/game/csgo/, flattens game/csgo/addons/windows/ on Windows, patches gameinfo.gi and verifies deployed files. Linux uses only the shared/base payload.', 1)
$readme = $readme.Replace('| server/ | Canonical SteamCMD installation root. The large downloaded game binaries remain local and are not committed. |', '| server/ | Local Windows SteamCMD installation root; ignored by Git. |')
$readme = $readme.Replace('| server/game/csgo/addons/ | KUS and Larnz plugin payloads in their final runtime locations. |', '| game/csgo/addons/ | Tracked KUS and Larnz payloads, including platform-neutral/Linux base files. |')
$readme = $readme.Replace('| server/game/csgo/cfg/ | Runtime configuration tree. Existing Larnz settings are preserved during KUS imports. |', '| game/csgo/cfg/ | Tracked shared configuration source, deployed into the runtime. |')
$readme = $readme.Replace('maps files into server/game/csgo/, verifies required paths and commits successful add-on updates.', 'maps release assets into the tracked game/csgo/ payload, verifies required paths and commits successful add-on updates.')
$readme = $readme.Replace('The canonical shared files are already stored at their final runtime locations:', 'Tracked shared files live under game/csgo/ and are deployed into the SteamCMD runtime:')
$readme = $readme.Replace('server/game/csgo/cfg/', 'game/csgo/cfg/')
$readme = $readme.Replace('server/game/csgo/addons/counterstrikesharp/configs/', 'game/csgo/addons/counterstrikesharp/configs/')
$readme = $readme.Replace('server/game/csgo/gamemodes_server.txt', 'game/csgo/gamemodes_server.txt')
$readme = $readme.Replace('server/game/csgo/subscribed_file_ids.txt', 'game/csgo/subscribed_file_ids.txt')
$readme = $readme.Replace('server/game/csgo/addons/counterstrikesharp/plugins/', 'game/csgo/addons/counterstrikesharp/plugins/')
$readme = $readme.Replace('The unified and CI-verified deployment path currently targets Windows. The original KUS setup guide covered Linux, Google Cloud, Docker and Kubernetes, but those entrypoints have not yet been migrated to the single-repository runtime. The active runtime path is still server/game/csgo/; the limitation is the platform bootstrap/update scripts, not the tracked plugin tree.', 'The tracked source payload follows KUS game/csgo/ layout. Windows deployment is CI-verified. Linux and Docker scripts are being aligned to the staged layout and still need a live server test; Google Cloud and Kubernetes are not claimed as fully tested.')
Write-Utf8 -Path $readmePath -Text $readme

$headerPath = Join-Path $RepoRoot "docs/Unified-README-HEADER.md"
$header = Get-Content -LiteralPath $headerPath -Raw
$header = [regex]::Replace($header, '(?m)^\*\*The repository''s canonical runtime path is.*$', '**The repository follows KUS''s staged payload model.** game/csgo/ is the tracked source payload; server/ is the local Windows SteamCMD install ignored by Git. Windows deploys the source payload into server/game/csgo/ and flattens game/csgo/addons/windows/ only at deployment time.', 1)
$header = $header.Replace('server/game/csgo/addons/', 'game/csgo/addons/').Replace('server/game/csgo/cfg/', 'game/csgo/cfg/')
Write-Utf8 -Path $headerPath -Text $header

$metadataPath = Join-Path $RepoRoot "docs/upstream/KUS-IMPORT.json"
$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$metadata.runtime_root = "game/csgo"
$metadata.runtime_file_count = @(Get-ChildItem -LiteralPath $PayloadRoot -Recurse -File -Force).Count
$metadata.runtime_bytes = [long]((Get-ChildItem -LiteralPath $PayloadRoot -Recurse -File -Force | Measure-Object -Property Length -Sum).Sum)
$metadata.windows_overlay_policy = "Keep Windows-specific payloads under game/csgo/addons/windows; flatten only during Windows deployment."
Write-Utf8 -Path $metadataPath -Text ($metadata | ConvertTo-Json -Depth 10)

Remove-Item -LiteralPath $LegacyRuntime -Recurse -Force
Write-Host "Removed tracked runtime copy at server/game/csgo; server/ is now local install output."
if (-not (Test-Path -LiteralPath (Join-Path $PayloadRoot "addons/counterstrikesharp/bin/linuxsteamrt64/counterstrikesharp.so") -PathType Leaf)) {
    throw "Linux CounterStrikeSharp native binary is missing from base payload."
}
if (-not (Test-Path -LiteralPath (Join-Path $PayloadRoot "addons/windows/addons/counterstrikesharp/dotnet/dotnet.exe") -PathType Leaf)) {
    throw "Windows CounterStrikeSharp with-runtime overlay is missing."
}
if (Test-Path -LiteralPath $LegacyRuntime) { throw "Old tracked server/game/csgo payload still exists." }
Write-Host "Migration preparation completed: $kusCommit"
