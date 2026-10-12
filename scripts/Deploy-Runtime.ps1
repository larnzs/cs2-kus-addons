[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runningCs2 = @(Get-Process -Name "cs2" -ErrorAction SilentlyContinue)
if ($runningCs2.Count -gt 0) {
    throw "A cs2.exe process is running. Stop all instances before deploying shared runtime files."
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$PayloadRoot = Join-Path $RepoRoot "game\csgo"
$RuntimeRoot = Join-Path $RepoRoot "server\game\csgo"
$WindowsOverlay = Join-Path $PayloadRoot "addons\windows"
$GameInfoPath = Join-Path $RuntimeRoot "gameinfo.gi"

if (-not (Test-Path -LiteralPath (Join-Path $PayloadRoot "addons") -PathType Container)) {
    throw "Tracked payload is missing: $PayloadRoot\addons"
}
if (-not (Test-Path -LiteralPath $WindowsOverlay -PathType Container)) {
    throw "Windows overlay is missing: $WindowsOverlay"
}
if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) {
    throw "SteamCMD runtime is missing: $RuntimeRoot"
}
if (-not (Test-Path -LiteralPath $GameInfoPath -PathType Leaf)) {
    throw "gameinfo.gi is missing. Install/update CS2 through SteamCMD first."
}

# Preserve a pre-existing CSS config tree byte-for-byte. On a fresh install, seed
# the default configs from the tracked payload if the runtime config directory is absent.
$PreserveCssConfigs = Test-Path -LiteralPath (Join-Path $RuntimeRoot "addons\counterstrikesharp\configs") -PathType Container

function Copy-SafeOverlayTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$RelativePath = "",
        [switch]$SkipWindowsOverlay
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        $relative = if ($RelativePath) { "$RelativePath/$($item.Name)" } else { $item.Name }
        $normalized = $relative.Replace("\", "/")
        $isWindowsOverlay = $normalized.Equals("addons/windows", [StringComparison]::OrdinalIgnoreCase) -or
            $normalized.StartsWith("addons/windows/", [StringComparison]::OrdinalIgnoreCase)
        $isGameInfo = $normalized.Equals("gameinfo.gi", [StringComparison]::OrdinalIgnoreCase)
        $isCssConfig = $normalized.Equals("addons/counterstrikesharp/configs", [StringComparison]::OrdinalIgnoreCase) -or
            $normalized.StartsWith("addons/counterstrikesharp/configs/", [StringComparison]::OrdinalIgnoreCase)

        if ($SkipWindowsOverlay -and $isWindowsOverlay) { continue }
        if ($isGameInfo) { continue }
        if ($PreserveCssConfigs -and $isCssConfig) { continue }

        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            Copy-SafeOverlayTree -Source $item.FullName -Destination $target -RelativePath $relative -SkipWindowsOverlay:$SkipWindowsOverlay
        }
        else {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}

$PayloadFiles = @(Get-ChildItem -LiteralPath $PayloadRoot -Recurse -File -Force | Where-Object {
    $_.FullName -notmatch '[\\/]addons[\\/]windows([\\/]|$)'
}).Count
Write-Host "Repository: $RepoRoot"
Write-Host "Runtime:    $RuntimeRoot"
Write-Host "Merge mode: safe non-destructive overlay; no runtime files are deleted."
Write-Host "Tracked shared payload files: $PayloadFiles"

Copy-SafeOverlayTree -Source $PayloadRoot -Destination $RuntimeRoot -SkipWindowsOverlay
Write-Host "Applying Windows-specific payload as a safe overlay..."
Copy-SafeOverlayTree -Source $WindowsOverlay -Destination $RuntimeRoot

Write-Host "SUCCESS: payload copied using overwrite-only overlay."
if ($PreserveCssConfigs) {
    Write-Host "SUCCESS: existing CounterStrikeSharp configs were left untouched."
}
Write-Host "Existing add-ons/files not present in the payload were preserved."
