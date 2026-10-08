[CmdletBinding()]
param(
    [string[]]$Only,
    [switch]$DryRun,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $RepoRoot "DEPENDENCIES.json"
$ReadmePath = Join-Path $RepoRoot "README.md"
$ServerRoot = Join-Path $RepoRoot "server\game\csgo"
$CacheRoot = Join-Path $RepoRoot "tmp\addons"
$UserAgent = "cs2-kus-addons"

function Write-Info([string]$Message) {
    Write-Host "  > $Message"
}

function Write-Warn([string]$Message) {
    Write-Host "  ! $Message" -ForegroundColor Yellow
}

function Normalize-Version([string]$Tag) {
    if ($null -eq $Tag) { return "" }
    return [regex]::Replace($Tag, "^[^0-9]*", "")
}

function Get-GitHubHeaders() {
    $headers = @{
        Accept = "application/vnd.github+json"
        "User-Agent" = $UserAgent
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    if ($env:GITHUB_TOKEN) {
        $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)"
    }

    return $headers
}

function Invoke-GitHubApi([string]$Url) {
    try {
        return Invoke-RestMethod -Uri $Url -Headers (Get-GitHubHeaders) -Method Get
    }
    catch {
        throw "GitHub API request failed: $Url -- $($_.Exception.Message)"
    }
}

function Get-RepoSlug([string]$Url) {
    return [regex]::Replace($Url, "^https?://(www\.)?github\.com/", "").TrimEnd("/")
}

function Get-ReleaseForAddon($Addon) {
    $repo = Get-RepoSlug $Addon.repository

    if ($Addon.track -eq "pinned") {
        $wanted = [string]$Addon.version
        $releases = Invoke-GitHubApi "https://api.github.com/repos/$repo/releases?per_page=30"
        $release = @(
            $releases | Where-Object {
                -not $_.draft -and (Normalize-Version $_.tag_name) -eq $wanted
            }
        ) | Select-Object -First 1

        if (-not $release) {
            throw "No release in $repo matches pinned version '$wanted'."
        }

        return $release
    }

    return Invoke-GitHubApi "https://api.github.com/repos/$repo/releases/latest"
}

function Get-ReleaseAssets($Release, $Addon) {
    $selected = @()

    foreach ($pattern in @($Addon.assets)) {
        $resolved = ([string]$pattern).Replace("{version}", (Normalize-Version $Release.tag_name))
        $matches = @($Release.assets | Where-Object { $_.name -like $resolved })

        if ($matches.Count -ne 1) {
            $names = ($Release.assets | ForEach-Object { $_.name }) -join ", "
            throw "Asset pattern '$resolved' for '$($Addon.name)' matched $($matches.Count) assets. Available: $names"
        }

        $selected += $matches[0]
    }

    return $selected
}

function Download-Asset($Asset, [string]$Destination) {
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if ((Test-Path $Destination) -and -not $Force) {
        return
    }

    Write-Info "Downloading $($Asset.name)"
    Invoke-WebRequest -Uri $Asset.browser_download_url -Headers (Get-GitHubHeaders) -OutFile $Destination -UseBasicParsing
}

function Find-CsgoRoot([string]$ExtractRoot) {
    $csgo = @(
        Get-ChildItem -LiteralPath $ExtractRoot -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ieq "csgo" -and (Test-Path (Join-Path $_.FullName "addons"))
            }
    ) | Select-Object -First 1

    if ($csgo) {
        return $csgo.FullName
    }

    $addons = @(
        Get-ChildItem -LiteralPath $ExtractRoot -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq "addons" }
    ) | Select-Object -First 1

    if ($addons) {
        return $addons.Parent.FullName
    }

    return $null
}

function Merge-Directory([string]$Source, [string]$Destination) {
    if (-not (Test-Path $Source -PathType Container)) {
        throw "Source directory does not exist: $Source"
    }

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        if ($_.Name -in ".gitnote", ".gitkeep") {
            return
        }

        $dest = Join-Path $Destination $_.Name

        if ($_.PSIsContainer) {
            Merge-Directory $_.FullName $dest
        }
        else {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
        }
    }
}

function Install-ReleaseAddon($Addon, $Release) {
    $assets = @(Get-ReleaseAssets $Release $Addon)
    $version = Normalize-Version $Release.tag_name
    $safeName = $Addon.name -replace '[^A-Za-z0-9._-]', '-'
    $workRoot = Join-Path $CacheRoot ("{0}\{1}" -f $safeName, $version)

    if ($DryRun) {
        Write-Info "Would install $($Addon.name) $version from tag $($Release.tag_name)"
        foreach ($asset in $assets) {
            Write-Info "Would download $($asset.name)"
        }
        return $version
    }

    New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

    foreach ($asset in $assets) {
        $archive = Join-Path $workRoot $asset.name
        Download-Asset $asset $archive

        if (-not $archive.ToLowerInvariant().EndsWith(".zip")) {
            throw "Unsupported archive type for '$($asset.name)'. Current Windows updater expects ZIP."
        }

        $extractName = [IO.Path]::GetFileNameWithoutExtension($asset.name)
        $extract = Join-Path $workRoot ("extract-" + $extractName)

        if (Test-Path $extract) {
            Remove-Item -LiteralPath $extract -Recurse -Force
        }

        Write-Info "Extracting $($asset.name)"
        Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force

        $csgo = Find-CsgoRoot $extract
        if (-not $csgo) {
            throw "Could not locate a CS2 game root/addons directory in $($asset.name)."
        }

        Merge-Directory $csgo $ServerRoot
    }

    return $version
}

function Get-BranchCommit($Addon) {
    $repo = Get-RepoSlug $Addon.repository
    return Invoke-GitHubApi "https://api.github.com/repos/$repo/commits/$($Addon.branch)"
}

function Install-SourceBuildAddon($Addon, $Commit) {
    if ($DryRun) {
        Write-Info "Would build $($Addon.name) from $($Addon.branch) at $($Commit.sha)"
        return $Commit.sha
    }

    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw "dotnet SDK is required to build $($Addon.name)."
    }

    $version = $Commit.sha
    $safeName = $Addon.name -replace '[^A-Za-z0-9._-]', '-'
    $workRoot = Join-Path $CacheRoot ("{0}\source-{1}" -f $safeName, $version.Substring(0,12))

    if (Test-Path $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

    $zip = Join-Path $workRoot "source.zip"
    $repo = Get-RepoSlug $Addon.repository
    $url = "https://github.com/$repo/archive/refs/heads/$($Addon.branch).zip"

    Write-Info "Downloading $($Addon.name) source"
    Invoke-WebRequest -Uri $url -Headers (Get-GitHubHeaders) -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $workRoot -Force

    $project = @(
        Get-ChildItem -LiteralPath $workRoot -Recurse -File -Filter ([string]$Addon.project)
    ) | Select-Object -First 1

    if (-not $project) {
        throw "Could not find build project '$($Addon.project)'."
    }

    $output = Join-Path $workRoot "publish"
    New-Item -ItemType Directory -Force -Path $output | Out-Null

    Write-Info "Building $($Addon.name)"
    & dotnet build $project.FullName -c Release -o $output --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed for $($Addon.name)."
    }

    $built = Join-Path $output ([string]$Addon.output_file)
    if (-not (Test-Path $built -PathType Leaf)) {
        throw "Build completed but expected output was not found: $built"
    }

    $destination = Join-Path $ServerRoot ([string]$Addon.install_path)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $built -Destination $destination -Force

    return $version
}

function Update-ReadmeVersion([string]$Name, [string]$Repository, [string]$DisplayVersion) {
    if (-not (Test-Path $ReadmePath) -or $DryRun) {
        return
    }

    $text = Get-Content -LiteralPath $ReadmePath -Raw
    $escapedUrl = [regex]::Escape($Repository)
    $escapedName = [regex]::Escape($Name)
    $backtick = [char]96
    $pattern = "(?m)^\| \[$escapedName\]\($escapedUrl\) \| $backtick[^$backtick]*$backtick \|"
    $replacement = "| [$Name]($Repository) | $backtick$DisplayVersion$backtick |"

    $newText = [regex]::Replace($text, $pattern, $replacement, 1)

    if ($newText -eq $text) {
        Write-Warn "README row not updated for $Name"
        return
    }

    [IO.File]::WriteAllText(
        $ReadmePath,
        $newText,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

if (-not (Test-Path $ManifestPath)) {
    throw "Missing $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$addons = @($manifest.addons | Sort-Object order)

if ($Only) {
    $selected = @(
        $addons | Where-Object {
            $slug = (($_.name) -replace '[^A-Za-z0-9]+','-').Trim('-').ToLowerInvariant()
            ($Only -contains $_.name) -or
            ($Only -contains $slug) -or
            ($Only -contains $_.repository)
        }
    )

    if ($selected.Count -eq 0) {
        throw "No addon matched -Only: $($Only -join ', ')"
    }

    $addons = $selected
}

New-Item -ItemType Directory -Force -Path $ServerRoot | Out-Null

Write-Host ""
Write-Host "CS2 KUS Addons updater" -ForegroundColor Cyan
Write-Host "Target: $ServerRoot"
if ($DryRun) {
    Write-Host "Mode: DRY RUN" -ForegroundColor Yellow
}
Write-Host ""

foreach ($addon in $addons) {
    Write-Host "[$($addon.order)] $($addon.name)" -ForegroundColor White

    if ($addon.PSObject.Properties.Name -contains "automation_supported" -and
        -not [bool]$addon.automation_supported) {
        Write-Warn "This addon is tracked in the manifest but is not automated by this updater."
        continue
    }

    try {
        if ($addon.type -eq "github_release") {
            $release = Get-ReleaseForAddon $addon
            $version = Normalize-Version $release.tag_name

            $needsUpdate = [bool]$Force -or
                -not [bool]$addon.installed -or
                ([string]$addon.version -ne $version)

            if (-not $needsUpdate) {
                Write-Info "Already at $version"
                continue
            }

            $newVersion = Install-ReleaseAddon $addon $release

            if (-not $DryRun) {
                $addon.installed = $true
                $addon.version = $newVersion
                $addon.release_tag = $release.tag_name
            }

            Update-ReadmeVersion $addon.name $addon.repository $newVersion
            Write-Host "  OK $newVersion" -ForegroundColor Green
        }
        elseif ($addon.type -eq "github_source_build") {
            $commit = Get-BranchCommit $addon
            $version = $commit.sha

            $needsUpdate = [bool]$Force -or
                -not [bool]$addon.installed -or
                ([string]$addon.version -ne $version)

            if (-not $needsUpdate) {
                Write-Info "Already at $($version.Substring(0,12))"
                continue
            }

            $newVersion = Install-SourceBuildAddon $addon $commit

            if (-not $DryRun) {
                $addon.installed = $true
                $addon.version = $newVersion
                $addon.source_commit = $newVersion
            }

            $display = "$($addon.branch)@$($newVersion.Substring(0,12))"
            Update-ReadmeVersion $addon.name $addon.repository $display
            Write-Host "  OK $display" -ForegroundColor Green
        }
        else {
            throw "Unsupported addon type '$($addon.type)'."
        }
    }
    catch {
        Write-Host "  ERROR $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if (-not $DryRun) {
    $json = $manifest | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText(
        $ManifestPath,
        $json + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
if (-not $DryRun) {
    Write-Host "Review changes with: git status" -ForegroundColor DarkGray
}
