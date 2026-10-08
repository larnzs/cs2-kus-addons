[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$CacheRoot = Join-Path $RepoRoot 'tmp\releases\CS2UpdateMonitor'
$TargetRoot = Join-Path $RepoRoot 'server\game\csgo\addons\counterstrikesharp\plugins\CS2UpdateMonitor'
$VersionFile = Join-Path $TargetRoot 'VERSION'
$UserAgent = 'cs2-kus-addons'
$ApiUrl = 'https://api.github.com/repos/beanman109/cs2-updatemonitor/releases/latest'

function Get-Headers {
    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = $UserAgent
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    if ($env:GITHUB_TOKEN) {
        $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)"
    }
    return $headers
}

$release = Invoke-RestMethod -Uri $ApiUrl -Headers (Get-Headers) -Method Get
if ($release.draft -or $release.prerelease) {
    throw 'Latest CS2 Update Monitor release is a draft/prerelease.'
}

$tag = [string]$release.tag_name
$version = $tag -replace '^v', ''
$asset = @($release.assets | Where-Object { $_.name -eq "CS2UpdateMonitor-$version-windows-x64.zip" }) | Select-Object -First 1
if (-not $asset) {
    $available = ($release.assets | ForEach-Object { $_.name }) -join ', '
    throw "Windows release asset was not found for $version. Available: $available"
}

$installedVersion = ''
if (Test-Path $VersionFile -PathType Leaf) {
    $installedVersion = (Get-Content -LiteralPath $VersionFile -Raw).Trim()
}

if (-not $Force -and -not [string]::IsNullOrWhiteSpace($installedVersion) -and $installedVersion -eq $version) {
    Write-Host "CS2 Update Monitor is already at $version." -ForegroundColor DarkGray
    exit 0
}

$workRoot = Join-Path $CacheRoot $version
$archive = Join-Path $workRoot $asset.name
$extractRoot = Join-Path $workRoot ('extract-' + [IO.Path]::GetFileNameWithoutExtension($asset.name))
$layoutFile = Join-Path $workRoot 'layout.txt'
$metadataFile = Join-Path $workRoot 'release.json'

if ($DryRun) {
    Write-Host "Would install CS2 Update Monitor $version from $tag." -ForegroundColor Cyan
    Write-Host "Asset: $($asset.name)"
    Write-Host "Destination: server\game\csgo\addons\counterstrikesharp\plugins\CS2UpdateMonitor"
    exit 0
}

New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
if (Test-Path $archive) {
    Write-Host "Using cached archive: $archive" -ForegroundColor DarkGray
} else {
    Write-Host "Downloading $($asset.name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers (Get-Headers) -OutFile $archive -UseBasicParsing
}

if ($asset.digest -and $asset.digest -match '^sha256:(.+)$') {
    $expected = $Matches[1].ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "SHA256 mismatch: expected $expected, got $actual"
    }
    Write-Host 'SHA256 verified.' -ForegroundColor Green
}

if (Test-Path $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
}
Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot -Force

$sourceRoot = Join-Path $extractRoot 'CS2UpdateMonitor'
if (-not (Test-Path $sourceRoot -PathType Container)) {
    throw "Release did not contain the expected CS2UpdateMonitor directory: $sourceRoot"
}

New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null
Get-ChildItem -LiteralPath $sourceRoot -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $TargetRoot $_.Name) -Recurse -Force
}

[IO.File]::WriteAllText($VersionFile, $version + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("ADDON: CS2UpdateMonitor")
$lines.Add("VERSION: $version")
$lines.Add("RELEASE TAG: $tag")
$lines.Add("ARCHIVE: $archive")
$lines.Add("EXTRACT ROOT: $extractRoot")
$lines.Add("SOURCE ROOT: $sourceRoot")
$lines.Add("DESTINATION ROOT: $TargetRoot")
$lines.Add('')
$lines.Add('SOURCE -> DESTINATION')
Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart('\')
    $lines.Add("$relative -> server\game\csgo\addons\counterstrikesharp\plugins\CS2UpdateMonitor\$relative")
}
[IO.File]::WriteAllLines($layoutFile, $lines, (New-Object System.Text.UTF8Encoding($false)))

$metadata = [ordered]@{
    addon = 'CS2UpdateMonitor'
    repository = 'https://github.com/beanman109/cs2-updatemonitor'
    version = $version
    release_tag = $tag
    asset = $asset.name
    archive = $archive
    extract_root = $extractRoot
    source_root = $sourceRoot
    destination_root = 'server\game\csgo\addons\counterstrikesharp\plugins\CS2UpdateMonitor'
    merge_mode = 'non-destructive-overlay'
}
[IO.File]::WriteAllText($metadataFile, (($metadata | ConvertTo-Json -Depth 10) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Installed tree: server\game\csgo\addons\counterstrikesharp\plugins\CS2UpdateMonitor" -ForegroundColor Green
Write-Host "Layout: $layoutFile"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is required to commit the tracked update.'
}

& git -C $RepoRoot add -- server/game/csgo/addons/counterstrikesharp/plugins/CS2UpdateMonitor
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }

$staged = @(& git -C $RepoRoot diff --cached --name-only)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect staged changes.' }
if ($staged.Count -eq 0) {
    Write-Host 'No tracked changes to commit.' -ForegroundColor DarkGray
    exit 0
}

& git -C $RepoRoot commit -m "Update CS2 Update Monitor $version"
if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }

$short = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
Write-Host "Committed $short" -ForegroundColor Green