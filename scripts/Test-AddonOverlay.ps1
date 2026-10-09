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