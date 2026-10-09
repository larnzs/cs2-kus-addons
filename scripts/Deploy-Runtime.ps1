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