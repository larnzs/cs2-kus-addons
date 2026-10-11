param([string]$KusRoot = "../kus-source")
$ErrorActionPreference = "Stop"

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Copy-Tree {
    param([string]$Source, [string]$Destination, [string]$Rel = "", [string[]]$ExcludePaths = @(), [switch]$SkipWindows, [switch]$OnlyMissing, [switch]$TrackText)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Missing source directory: $Source" }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        $relative = if ($Rel) { "$Rel/$($item.Name)" } else { $item.Name }
        $normalized = $relative.Replace("\", "/")
        if ($ExcludePaths -contains $normalized) { continue }
        if ($SkipWindows -and ($normalized -eq "addons/windows" -or $normalized.StartsWith("addons/windows/"))) { continue }
        if ($item.PSIsContainer) {
            Copy-Tree -Source $item.FullName -Destination (Join-Path $Destination $item.Name) -Rel $relative -ExcludePaths $ExcludePaths -SkipWindows:$SkipWindows -OnlyMissing:$OnlyMissing -TrackText:$TrackText
        } else {
            $target = Join-Path $Destination $item.Name
            if ($OnlyMissing -and (Test-Path -LiteralPath $target)) { continue }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
            if ($TrackText) { $script:ImportedText.Add($target) }
        }
    }
}

function Rewrite-Paths {
    param([string]$Path)
    # KUS differentiates the tracked payload from the installed runtime.
    return
}

$RepoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $RepoRoot) { throw "Run inside the unified repository's Git checkout." }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot.Trim())
$branch = (git -C $RepoRoot branch --show-current).Trim()
if (-not $branch -or $branch -in @("main", "master")) { throw "This import only runs on a dedicated integration branch, not '$branch'." }

$KusRootResolved = [IO.Path]::GetFullPath((Join-Path $RepoRoot $KusRoot))
if (-not (Test-Path -LiteralPath (Join-Path $KusRootResolved ".git"))) { throw "KUS checkout not found at $KusRootResolved." }
$KusRuntime = Join-Path $KusRootResolved "game/csgo"
if (-not (Test-Path -LiteralPath $KusRuntime -PathType Container)) { throw "KUS runtime tree not found: $KusRuntime" }

$marker = Join-Path $RepoRoot "docs/upstream/KUS-IMPORT.json"
# Safe to re-run: existing Larnz files are saved/restored and the original README is kept separately.

$script:ImportedText = [System.Collections.Generic.List[string]]::new()
$kusCommit = (git -C $KusRootResolved rev-parse HEAD).Trim()
$runtimeRoot = Join-Path $RepoRoot "game/csgo"
$tempOverlay = Join-Path ([IO.Path]::GetTempPath()) ("larnz-overlay-" + [guid]::NewGuid().ToString("N"))
$overlayManifest = Join-Path $RepoRoot "docs/upstream/LARNZ-RUNTIME-FILES.txt"

# Capture the pre-integration Larnz file list once. On later imports this manifest prevents
# all previously imported KUS files from being misidentified as personal overlay files.
if (-not (Test-Path -LiteralPath $overlayManifest)) {
    $trackedOverlay = @(git -C $RepoRoot ls-files -- "game/csgo" | Where-Object { $_ -and $_.StartsWith("game/csgo/") })
    if ($trackedOverlay.Count -eq 0) { throw "Could not discover the original tracked Larnz runtime overlay." }
    Write-Utf8 -Path $overlayManifest -Text ($trackedOverlay -join [Environment]::NewLine)
}
New-Item -ItemType Directory -Force -Path $tempOverlay | Out-Null
foreach ($trackedPath in Get-Content -LiteralPath $overlayManifest) {
    $trackedPath = $trackedPath.Trim()
    if (-not $trackedPath.StartsWith("game/csgo/")) { continue }
    $sourcePath = Join-Path $RepoRoot ($trackedPath.Replace("/", [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }
    $relativePath = $trackedPath.Substring("game/csgo/".Length).Replace("/", [IO.Path]::DirectorySeparatorChar)
    $destinationPath = Join-Path $tempOverlay $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationPath) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}
$ProtectedConfigPaths = @(
    "addons/counterstrikesharp/configs",
    "addons/windows/addons/counterstrikesharp/configs"
)
$PreservedManualPaths = @("cfg") + $ProtectedConfigPaths

# Personal/user-managed configuration remains protected even if added after the initial manifest.
foreach ($protectedRelative in $PreservedManualPaths) {
    $protectedSource = Join-Path $runtimeRoot $protectedRelative
    if (Test-Path -LiteralPath $protectedSource -PathType Container) {
        Copy-Tree -Source $protectedSource -Destination (Join-Path $tempOverlay $protectedRelative)
    }
}

Write-Host "Importing KUS payloads into $runtimeRoot"
Copy-Tree -Source $KusRuntime -Destination $runtimeRoot -ExcludePaths $ProtectedConfigPaths

if (Test-Path -LiteralPath $tempOverlay -PathType Container) {
    Copy-Tree -Source $tempOverlay -Destination $runtimeRoot
    Remove-Item -LiteralPath $tempOverlay -Recurse -Force
}

# Import support files, dependency scripts and CI helpers, but never the source game/ staging tree or personal cfg layers.
$skip = @(".git", ".env", ".gitignore", "README.md", "game", "custom_files", "custom_files_example", "win.bat", "update.bat", "install.bat", "game-update.bat", "addons-update.bat", "addons-inspect.bat", "install.sh", "run.sh", "start.sh", "stop.sh", "gcp.sh", "install_docker.sh", "Dockerfile", "docker-compose.yml", "manifest.yaml", "windows", "linux", "docker", "win.ini")
foreach ($item in Get-ChildItem -LiteralPath $KusRootResolved -Force) {
    if ($skip -contains $item.Name) { continue }
    $target = Join-Path $RepoRoot $item.Name
    if ($item.PSIsContainer) {
        $exclude = @()
        if ($item.Name -eq ".github") { $exclude = @("workflows/auto-update-mods.yml", "workflows/docker-image.yml") }
        Copy-Tree -Source $item.FullName -Destination $target -ExcludePaths $exclude -OnlyMissing -TrackText -Rel "" 
    } else {
        if (Test-Path -LiteralPath $target) { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        $script:ImportedText.Add($target)
    }
}

# Preserve upstream entrypoints which will be replaced by the unified versions.
$originals = @(
    @{ Source = "win.bat"; Target = "win.bat" },
    @{ Source = "update.bat"; Target = "update.bat" },
    @{ Source = "win.ini"; Target = "win.ini" },
    @{ Source = "install.sh"; Target = "install.sh" },
    @{ Source = "start.sh"; Target = "start.sh" },
    @{ Source = "install_docker.sh"; Target = "install_docker.sh" },
    @{ Source = "run.sh"; Target = "run.sh" },
    @{ Source = ".github/workflows/auto-update-mods.yml"; Target = "auto-update-mods.yml" },
    @{ Source = ".github/workflows/docker-image.yml"; Target = "docker-image.yml" }
)
foreach ($original in $originals) {
    $src = Join-Path $KusRootResolved $original.Source
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        $dest = Join-Path $RepoRoot ("docs/upstream/kus-original/" + $original.Target)
        Write-Utf8 -Path $dest -Text ([IO.File]::ReadAllText($src))
    }
}
foreach ($path in $script:ImportedText) { Rewrite-Paths -Path $path }
# Re-apply idempotent path normalization to all KUS-owned support files.
# This repairs a partial earlier import while leaving cfg/custom file layers out.
$excludedTop = @(".git", ".env", ".gitignore", "README.md", "game", "custom_files", "custom_files_example", "win.bat", "update.bat", "install.bat", "game-update.bat", "addons-update.bat", "addons-inspect.bat", "install.sh", "run.sh", "start.sh", "stop.sh", "gcp.sh", "install_docker.sh", "Dockerfile", "docker-compose.yml", "manifest.yaml", "windows", "linux", "docker", "win.ini")
$excludedExact = @(".github/workflows/auto-update-mods.yml", ".github/workflows/docker-image.yml")
foreach ($sourceFile in Get-ChildItem -LiteralPath $KusRootResolved -File -Recurse -Force) {
    $relative = $sourceFile.FullName.Substring($KusRootResolved.Length).TrimStart("\", "/").Replace("\", "/")
    $top = $relative.Split("/")[0]
    if ($excludedTop -contains $top) { continue }
    if ($excludedExact -contains $relative) { continue }
    $targetFile = Join-Path $RepoRoot ($relative.Replace("/", [IO.Path]::DirectorySeparatorChar))
    if (Test-Path -LiteralPath $targetFile -PathType Leaf) { Rewrite-Paths -Path $targetFile }
}


# Keep the unified README authoritative; archive the source README as a reference.
$kusReadme = [IO.File]::ReadAllText((Join-Path $KusRootResolved "README.md"))
Write-Utf8 -Path (Join-Path $RepoRoot "docs/upstream/KUS-README.md") -Text $kusReadme
# Keep local SteamCMD output separate from the tracked payload.
$ignorePath = Join-Path $RepoRoot ".gitignore"
$ignoreMarker = "# KUS-style architecture: tracked source payload and local SteamCMD install are separate."
$ignoreText = [IO.File]::ReadAllText($ignorePath)
$markerIndex = $ignoreText.IndexOf($ignoreMarker, [StringComparison]::Ordinal)
if ($markerIndex -ge 0) {
    $ignoreText = $ignoreText.Substring(0, $markerIndex).TrimEnd()
} else {
    $ignoreText = $ignoreText.TrimEnd()
}
$ignoreText += @'

# KUS-style architecture: tracked source payload and local SteamCMD install are separate.
.env
/steamcmd/
/server/
/game/*
!/game/csgo/
/custom_files/*
!/custom_files/.gitkeep
'@
$cfgRoot = Join-Path $runtimeRoot "cfg"
if (Test-Path -LiteralPath $cfgRoot -PathType Container) {
    foreach ($dir in Get-ChildItem -LiteralPath $cfgRoot -Directory -Recurse | Sort-Object { $_.FullName.Length }) {
        $relative = $dir.FullName.Substring($RepoRoot.Length).TrimStart("\", "/").Replace("\", "/")
        $ignoreText += [Environment]::NewLine + "!/$relative/"
    }
    foreach ($file in Get-ChildItem -LiteralPath $cfgRoot -File) {
        $relative = $file.FullName.Substring($RepoRoot.Length).TrimStart("\", "/").Replace("\", "/")
        $ignoreText += [Environment]::NewLine + "!/$relative"
    }
}
Write-Utf8 -Path $ignorePath -Text ($ignoreText + [Environment]::NewLine)

# Make the sample runner target the only server directory.
$exampleIni = Join-Path $RepoRoot "windows/instance-template/instance.example.ini"
if (Test-Path -LiteralPath $exampleIni) {
    $text = [IO.File]::ReadAllText($exampleIni) -replace '(?m)^SERVER_DIR=.*$', 'SERVER_DIR=C:\REPLACE_ME\cs2-kus-addons\server'
    Write-Utf8 -Path $exampleIni -Text $text
}

$runtimeFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -File -Recurse)
$runtimeBytes = [long](($runtimeFiles | Measure-Object -Property Length -Sum).Sum)
$metadata = [ordered]@{
    upstream_repository = "https://github.com/kus/cs2-modded-server"
    upstream_branch = "master"
    upstream_commit = $kusCommit
    imported_at_utc = [DateTime]::UtcNow.ToString("o")
    runtime_root = "game/csgo"
    runtime_file_count = $runtimeFiles.Count
    runtime_bytes = $runtimeBytes
    windows_overlay_policy = "Keep Windows-specific payloads under game/csgo/addons/windows; flatten only during Windows deployment."
    excluded = @(".env", "custom_files", "custom_files_example", "the old merged server/game/csgo runtime root")
}
Write-Utf8 -Path $marker -Text ($metadata | ConvertTo-Json -Depth 5)
Write-Host "KUS integration completed. Runtime files: $($runtimeFiles.Count); bytes: $runtimeBytes; source commit: $kusCommit"
