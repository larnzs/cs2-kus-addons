param([string]$KusRoot = "../kus-source")
$ErrorActionPreference = "Stop"

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Copy-Tree {
    param([string]$Source, [string]$Destination, [string]$Rel = "", [switch]$SkipWindows, [switch]$OnlyMissing, [switch]$TrackText)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Missing source directory: $Source" }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        $relative = if ($Rel) { "$Rel/$($item.Name)" } else { $item.Name }
        $normalized = $relative.Replace("\", "/")
        if ($SkipWindows -and ($normalized -eq "addons/windows" -or $normalized.StartsWith("addons/windows/"))) { continue }
        if ($item.PSIsContainer) {
            Copy-Tree -Source $item.FullName -Destination (Join-Path $Destination $item.Name) -Rel $relative -SkipWindows:$SkipWindows -OnlyMissing:$OnlyMissing -TrackText:$TrackText
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
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -notin @(".sh", ".bat", ".cmd", ".ps1", ".md", ".yml", ".yaml", ".json", ".ini", ".txt", ".xml", ".toml", ".py") -and (Split-Path -Leaf $Path) -ne "Dockerfile") { return }
    $text = [IO.File]::ReadAllText($Path)
    $text = $text.Replace("game/csgo", "server/game/csgo").Replace("game\csgo", "server\game\csgo")
    Write-Utf8 -Path $Path -Text $text
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
if (Test-Path -LiteralPath $marker) { Write-Host "KUS was already imported on this branch."; exit 0 }

$script:ImportedText = [System.Collections.Generic.List[string]]::new()
$kusCommit = (git -C $KusRootResolved rev-parse HEAD).Trim()
$runtimeRoot = Join-Path $RepoRoot "server/game/csgo"
$tempOverlay = Join-Path ([IO.Path]::GetTempPath()) ("larnz-overlay-" + [guid]::NewGuid().ToString("N"))

Write-Host "Importing KUS payloads into $runtimeRoot"
if (Test-Path -LiteralPath $runtimeRoot -PathType Container) { Copy-Tree -Source $runtimeRoot -Destination $tempOverlay }
Copy-Tree -Source $KusRuntime -Destination $runtimeRoot -SkipWindows
$windowsTree = Join-Path $KusRuntime "addons/windows"
if (Test-Path -LiteralPath $windowsTree -PathType Container) { Copy-Tree -Source $windowsTree -Destination $runtimeRoot }
if (Test-Path -LiteralPath $tempOverlay -PathType Container) {
    Copy-Tree -Source $tempOverlay -Destination $runtimeRoot
    Remove-Item -LiteralPath $tempOverlay -Recurse -Force
}

# Import support files, dependency scripts and CI helpers, but never the source game/ staging tree or personal cfg layers.
$skip = @(".git", ".env", ".gitignore", "README.md", "game", "custom_files", "custom_files_example", "win.bat", "update.bat", "win.ini")
foreach ($item in Get-ChildItem -LiteralPath $KusRootResolved -Force) {
    if ($skip -contains $item.Name) { continue }
    $target = Join-Path $RepoRoot $item.Name
    if ($item.PSIsContainer) {
        $exclude = @()
        if ($item.Name -eq ".github") { $exclude = @(".github/workflows/auto-update-mods.yml") }
        Copy-Tree -Source $item.FullName -Destination $target -OnlyMissing -TrackText -Rel "" 
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
    @{ Source = ".github/workflows/auto-update-mods.yml"; Target = "auto-update-mods.yml" }
)
foreach ($original in $originals) {
    $src = Join-Path $KusRootResolved $original.Source
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        $dest = Join-Path $RepoRoot ("docs/upstream/kus-original/" + $original.Target)
        Write-Utf8 -Path $dest -Text ([IO.File]::ReadAllText($src))
    }
}
foreach ($path in $script:ImportedText) { Rewrite-Paths -Path $path }

# Merge both guides so the root README keeps the Larnz notes and every KUS section/table.
$readmePath = Join-Path $RepoRoot "README.md"
$larnzReadme = [IO.File]::ReadAllText($readmePath)
Write-Utf8 -Path (Join-Path $RepoRoot "docs/Larnz-Addons-README.md") -Text $larnzReadme
$kusReadme = [IO.File]::ReadAllText((Join-Path $KusRootResolved "README.md"))
$kusReadme = $kusReadme.Replace("game/csgo", "server/game/csgo").Replace("game\csgo", "server\game\csgo")
$note = @'
## Unified repository layout

All managed KUS and Larnz runtime payloads are stored directly under server/game/csgo/. The old game/csgo staging directory is not retained. The KUS Windows-specific payload is flattened into the canonical runtime tree during this one-time import. The existing Larnz overlay and personal settings are restored last.

The complete KUS guide follows below to retain the upstream plugin tables, dependency notes, deployment instructions, and troubleshooting material. The upstream source is https://github.com/kus/cs2-modded-server and its LGPL-3.0 license is retained in LICENSE.
'@
$joined = $larnzReadme.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $note + [Environment]::NewLine + [Environment]::NewLine + $kusReadme.TrimStart()
Write-Utf8 -Path $readmePath -Text $joined
Write-Utf8 -Path (Join-Path $RepoRoot "docs/upstream/KUS-README.md") -Text $kusReadme

# The combined repository owns the final server path; keep the SteamCMD installation local.
$ignorePath = Join-Path $RepoRoot ".gitignore"
$ignoreText = [IO.File]::ReadAllText($ignorePath).TrimEnd()
$ignoreText += @'

# Unified KUS/Larnz server: only the managed payload trees are tracked.
.env
/steamcmd/
/server/*
!/server/game/
/server/game/*
!/server/game/csgo/
/server/game/csgo/*
!/server/game/csgo/addons/
/server/game/csgo/addons/**
!/server/game/csgo/cfg/
/server/game/csgo/cfg/*
!/server/game/csgo/gamemodes_server.txt
!/server/game/csgo/mapcycle.txt
!/server/game/csgo/subscribed_collection_ids.txt
!/server/game/csgo/subscribed_file_ids.txt
/custom_files/*
!/custom_files/.gitkeep
'@
$cfgRoot = Join-Path $runtimeRoot "cfg"
if (Test-Path -LiteralPath $cfgRoot -PathType Container) {
    foreach ($dir in Get-ChildItem -LiteralPath $cfgRoot -Directory -Recurse | Sort-Object { $_.FullName.Length }) {
        $relative = $dir.FullName.Substring($RepoRoot.Length).Replace("\", "/")
        $ignoreText += [Environment]::NewLine + "!/$relative/"
    }
    foreach ($file in Get-ChildItem -LiteralPath $cfgRoot -File) {
        $relative = $file.FullName.Substring($RepoRoot.Length).Replace("\", "/")
        $ignoreText += [Environment]::NewLine + "!/$relative"
    }
}
Write-Utf8 -Path $ignorePath -Text ($ignoreText + [Environment]::NewLine)

# Make the sample runner target the only server directory.
$exampleIni = Join-Path $RepoRoot "examples/run-template/instance.example.ini"
if (Test-Path -LiteralPath $exampleIni) {
    $text = [IO.File]::ReadAllText($exampleIni) -replace '(?m)^SERVER_DIR=.*$', 'SERVER_DIR=..\..\server'
    Write-Utf8 -Path $exampleIni -Text $text
}

$runtimeFiles = @(Get-ChildItem -LiteralPath $runtimeRoot -File -Recurse)
$runtimeBytes = [long](($runtimeFiles | Measure-Object -Property Length -Sum).Sum)
$metadata = [ordered]@{
    upstream_repository = "https://github.com/kus/cs2-modded-server"
    upstream_branch = "master"
    upstream_commit = $kusCommit
    imported_at_utc = [DateTime]::UtcNow.ToString("o")
    runtime_root = "server/game/csgo"
    runtime_file_count = $runtimeFiles.Count
    runtime_bytes = $runtimeBytes
    windows_overlay_policy = "Flatten Windows-specific payloads into server/game/csgo, then restore Larnz overlay last."
    excluded = @(".env", "custom_files", "custom_files_example", "the old KUS game/ staging root")
}
Write-Utf8 -Path $marker -Text ($metadata | ConvertTo-Json -Depth 5)
Write-Host "KUS integration completed. Runtime files: $($runtimeFiles.Count); bytes: $runtimeBytes; source commit: $kusCommit"
