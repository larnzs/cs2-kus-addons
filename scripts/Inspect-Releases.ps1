[CmdletBinding()]
param(
    [string[]]$Only
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $RepoRoot "DEPENDENCIES.json"
$CacheRoot = Join-Path $RepoRoot "tmp\releases"
$ServerRoot = Join-Path $RepoRoot "server\game\csgo"
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

function Get-Headers() {
    return @{
        Accept = "application/vnd.github+json"
        "User-Agent" = $UserAgent
        "X-GitHub-Api-Version" = "2022-11-28"
    }
}

function Get-RepoSlug([string]$Url) {
    return [regex]::Replace($Url, "^https?://(www\.)?github\.com/", "").TrimEnd("/")
}

function Get-Release($Addon) {
    $repo = Get-RepoSlug $Addon.repository

    if ($Addon.track -eq "pinned") {
        $wanted = [string]$Addon.version
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases?per_page=30" -Headers (Get-Headers) -Method Get
        $release = @($releases | Where-Object {
            -not $_.draft -and (Normalize-Version $_.tag_name) -eq $wanted
        }) | Select-Object -First 1

        if (-not $release) {
            throw "No matching pinned release found for $($Addon.name)."
        }

        return $release
    }

    return Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers (Get-Headers) -Method Get
}

function Get-Assets($Release, $Addon) {
    $selected = @()

    foreach ($pattern in @($Addon.assets)) {
        $resolved = ([string]$pattern).Replace("{version}", (Normalize-Version $Release.tag_name))
        $matches = @($Release.assets | Where-Object { $_.name -like $resolved })

        if ($matches.Count -ne 1) {
            $names = ($Release.assets | ForEach-Object { $_.name }) -join ", "
            throw "Asset pattern '$resolved' matched $($matches.Count) assets for $($Addon.name). Available: $names"
        }

        $selected += $matches[0]
    }

    return $selected
}

function Download-Asset($Asset, [string]$Destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null

    if (-not (Test-Path $Destination)) {
        Write-Info "Downloading $($Asset.name)"
        Invoke-WebRequest -Uri $Asset.browser_download_url -Headers (Get-Headers) -OutFile $Destination -UseBasicParsing
    }

    if ($Asset.digest -and $Asset.digest -match "^sha256:(.+)$") {
        $expected = $Matches[1].ToLowerInvariant()
        $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()

        if ($expected -ne $actual) {
            throw "SHA256 mismatch for $($Asset.name): expected $expected, got $actual"
        }

        Write-Info "SHA256 verified"
    }
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

function Inspect-Addon($Addon) {
    if ($Addon.PSObject.Properties.Name -contains "automation_supported" -and
        -not [bool]$Addon.automation_supported) {
        Write-Warn "$($Addon.name) is marked manual in DEPENDENCIES.json; skipping."
        return
    }

    $release = Get-Release $Addon
    $version = Normalize-Version $release.tag_name
    $safeName = $Addon.name -replace '[^A-Za-z0-9._-]', '-'
    $workRoot = Join-Path $CacheRoot ("{0}\{1}" -f $safeName, $version)

    New-Item -ItemType Directory -Force -Path $workRoot | Out-Null

    Write-Host ""
    Write-Host "$($Addon.name)  $version" -ForegroundColor Cyan
    Write-Info "Release tag: $($release.tag_name)"

    foreach ($asset in @(Get-Assets $release $Addon)) {
        $archive = Join-Path $workRoot $asset.name
        Download-Asset $asset $archive

        if (-not $archive.ToLowerInvariant().EndsWith(".zip")) {
            Write-Warn "Windows inspector currently skips non-ZIP archive: $($asset.name)"
            continue
        }

        $extract = Join-Path $workRoot ("extract-" + [IO.Path]::GetFileNameWithoutExtension($asset.name))

        if (Test-Path $extract) {
            Remove-Item -LiteralPath $extract -Recurse -Force
        }

        Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force

        $csgo = Find-CsgoRoot $extract
        if (-not $csgo) {
            throw "Could not find a CS2 game root/addons directory in $($asset.name)."
        }

        $layout = Join-Path $workRoot ("layout-" + [IO.Path]::GetFileNameWithoutExtension($asset.name) + ".txt")

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("ADDON: $($Addon.name)")
        $lines.Add("VERSION: $version")
        $lines.Add("ASSET: $($asset.name)")
        $lines.Add("ARCHIVE: $archive")
        $lines.Add("EXTRACT ROOT: $extract")
        $lines.Add("DETECTED CS2 ROOT: $csgo")
        $lines.Add("DESTINATION ROOT: $ServerRoot")
        $lines.Add("")
        $lines.Add("SOURCE -> DESTINATION")
        $lines.Add("----------------------------------------")

        Get-ChildItem -LiteralPath $csgo -Recurse -File |
            Sort-Object FullName |
            ForEach-Object {
                $relative = $_.FullName.Substring($csgo.Length).TrimStart("\")
                $lines.Add("$relative -> server\game\csgo\$relative")
            }

        [IO.File]::WriteAllLines($layout, $lines, (New-Object System.Text.UTF8Encoding($false)))

        Write-Info "Layout saved: $layout"
        Get-Content -LiteralPath $layout
    }
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$addons = @($manifest.addons | Sort-Object order)

if ($Only) {
    $addons = @(
        $addons | Where-Object {
            $slug = (($_.name) -replace '[^A-Za-z0-9]+','-').Trim('-').ToLowerInvariant()
            ($Only -contains $_.name) -or
            ($Only -contains $slug) -or
            ($Only -contains $_.repository)
        }
    )

    if ($addons.Count -eq 0) {
        throw "No addon matched -Only: $($Only -join ', ')"
    }
}

foreach ($addon in $addons) {
    Inspect-Addon $addon
}

Write-Host ""
Write-Host "Inspection complete. Nothing was copied to server staging." -ForegroundColor Green
