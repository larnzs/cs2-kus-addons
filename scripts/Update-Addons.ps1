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
$PayloadRoot = Join-Path $RepoRoot "game\csgo"
$CacheRoot = Join-Path $RepoRoot "tmp\releases"
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

function Get-AddonVersion($Addon, [string]$Tag) {
    $version = Normalize-Version $Tag
    if ($Addon.PSObject.Properties.Name -contains "version_format" -and
        [string]$Addon.version_format -eq "metamod") {
        # Metamod tags are 2.0.0.1474; KUS tracks/displays them as 2.0.0-1474.
        $version = $version -replace '^(\d+\.\d+\.\d+)\.(\d+)$', '$1-$2'
    }
    return $version
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

    if ($Addon.PSObject.Properties.Name -contains "version_format" -and
        [string]$Addon.version_format -eq "metamod") {
        # GitHub's /releases/latest may select the older stable 1.12.0 line.
        # KUS tracks the CS2 development builds; choose the newest listed 2.0.0.<git> release.
        $releases = Invoke-GitHubApi "https://api.github.com/repos/$repo/releases?per_page=30"
        $release = @(
            $releases | Where-Object {
                -not $_.draft -and [string]$_.tag_name -match '^2\.0\.0\.\d+$'
            }
        ) | Select-Object -First 1
        if (-not $release) {
            $seen = ($releases | ForEach-Object { [string]$_.tag_name }) -join ", "
            throw "No CS2 Metamod release matching tag 2.0.0.<build> was found in $repo. Tags seen: $seen"
        }
        return $release
    }

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

    if ($Addon.PSObject.Properties.Name -contains "runtime_required" -and [bool]$Addon.runtime_required) {
        $requiredMarker = if ($Addon.PSObject.Properties.Name -contains "required_asset_name_contains") {
            [string]$Addon.required_asset_name_contains
        } else {
            "with-runtime"
        }
        foreach ($asset in $selected) {
            if ([string]$asset.name -notmatch [regex]::Escape($requiredMarker)) {
                throw "Runtime-required addon '$($Addon.name)' selected '$($asset.name)', which does not contain required marker '$requiredMarker'. Refusing to install a no-runtime package."
            }
        }
    }

    return $selected
}

function Get-AddonMissingFiles($Addon) {
    $missing = New-Object System.Collections.Generic.List[string]
    $rootFull = [IO.Path]::GetFullPath($PayloadRoot).TrimEnd([char[]]@('\', '/'))
    $rootPrefix = $rootFull + [IO.Path]::DirectorySeparatorChar

    foreach ($relativeValue in @($Addon.verify_paths)) {
        $relative = ([string]$relativeValue).Replace('/', '\')
        if ([string]::IsNullOrWhiteSpace($relative) -or
            [IO.Path]::IsPathRooted($relative) -or
            $relative -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "Unsafe verify_paths entry for '$($Addon.name)': $relative"
        }

        $fullPath = [IO.Path]::GetFullPath((Join-Path $PayloadRoot $relative))
        if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Verification path escaped game/csgo for '$($Addon.name)': $relative"
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            [void]$missing.Add("game/csgo/$($relative.Replace('\', '/'))")
        }
    }

    if ($Addon.PSObject.Properties.Name -contains "verify_globs") {
        foreach ($relativeValue in @($Addon.verify_globs)) {
            $relative = ([string]$relativeValue).Replace('/', '\')
            if ([string]::IsNullOrWhiteSpace($relative) -or
                [IO.Path]::IsPathRooted($relative) -or
                $relative -match '(^|[\\/])\.\.([\\/]|$)') {
                throw "Unsafe verify_globs entry for '$($Addon.name)': $relative"
            }

            # Normalize wildcard characters only for the containment check; keep the
            # original pattern for Get-ChildItem's real wildcard matching.
            $guardRelative = $relative -replace '[*?]', 'wildcard'
            $guardFull = [IO.Path]::GetFullPath((Join-Path $PayloadRoot $guardRelative))
            if (-not $guardFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Verification glob escaped game/csgo for '$($Addon.name)': $relative"
            }

            $pattern = Join-Path $PayloadRoot $relative
            $matches = @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue)
            if ($matches.Count -eq 0) {
                [void]$missing.Add("game/csgo/$relative (no file matched runtime requirement)")
            }
        }
    }

    return @($missing.ToArray())
}

function Download-Asset($Asset, [string]$Destination) {
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (-not (Test-Path $Destination) -or $Force) {
        Write-Info "Downloading $($Asset.name)"
        Invoke-WebRequest -Uri $Asset.browser_download_url -Headers (Get-GitHubHeaders) -OutFile $Destination -UseBasicParsing
    }
    else {
        Write-Info "Using cached archive $($Asset.name)"
    }

    # Verify cached files too; an interrupted/corrupt download must not be trusted.
    if ($Asset.digest -and $Asset.digest -match "^sha256:(.+)$") {
        $expected = $Matches[1].ToLowerInvariant()
        $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) {
            throw "SHA256 mismatch for $($Asset.name): expected $expected, got $actual. Re-run with -Force to download it again."
        }
        Write-Info "SHA256 verified"
    }
}

function Find-CsgoRoot([string]$ExtractRoot) {
    # Most releases use one of these layouts:
    #   <archive>/addons/...
    #   <archive>/csgo/addons/...
    #   <archive>/<wrapper>/csgo/addons/...
    # Return the directory that must be merged into game/csgo.
    if (Test-Path (Join-Path $ExtractRoot "addons") -PathType Container) {
        return $ExtractRoot
    }

    $directCsgo = Join-Path $ExtractRoot "csgo"
    if (Test-Path (Join-Path $directCsgo "addons") -PathType Container) {
        return $directCsgo
    }

    $csgo = @(
        Get-ChildItem -LiteralPath $ExtractRoot -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ieq "csgo" -and (Test-Path (Join-Path $_.FullName "addons") -PathType Container)
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

function Write-ReleaseLayout([string]$Archive, [string]$ExtractRoot, [string]$CsgoRoot, [string]$OutputFile, [string]$AddonName, [string]$Version) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("ADDON: $AddonName")
    $lines.Add("VERSION: $Version")
    $lines.Add("ARCHIVE: $Archive")
    $lines.Add("EXTRACT ROOT: $ExtractRoot")
    $lines.Add("CS2 ROOT DETECTED: $CsgoRoot")
    $lines.Add("TARGET ROOT: $PayloadRoot")
    $lines.Add("")
    $lines.Add("SOURCE -> DESTINATION")

    Get-ChildItem -LiteralPath $CsgoRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($CsgoRoot.Length).TrimStart("\")
        $lines.Add("$relative -> game\csgo\$relative")
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputFile) | Out-Null
    [IO.File]::WriteAllLines($OutputFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-ReleaseMetadata(
    [string]$OutputFile,
    [string]$AddonName,
    [string]$Repository,
    [string]$Version,
    [string]$ReleaseTag,
    [string]$AssetName,
    [string]$Archive,
    [string]$ExtractRoot,
    $Targets
) {
    $metadata = [ordered]@{
        addon = $AddonName
        repository = $Repository
        version = $Version
        release_tag = $ReleaseTag
        asset = $AssetName
        archive = $Archive
        extract_root = $ExtractRoot
        destination_root = $PayloadRoot
        merge_mode = 'non-destructive-overlay'
        mappings = @($Targets | ForEach-Object {
            [ordered]@{
                merge_mode = $_.MergeMode
                source_root = $_.SourceRoot
                destination_root = $_.DestinationRoot
                destination_display = $_.DestinationDisplay
            }
        })
    }

    [IO.File]::WriteAllText(
        $OutputFile,
        (($metadata | ConvertTo-Json -Depth 20) + [Environment]::NewLine),
        (New-Object System.Text.UTF8Encoding($false))
    )
}
function Test-IsProtectedConfigDestination([string]$DestinationPath) {
    $payloadRootFull = [IO.Path]::GetFullPath($PayloadRoot).TrimEnd([char[]]@('\', '/'))
    $destinationFull = [IO.Path]::GetFullPath($DestinationPath)
    $prefix = $payloadRootFull + [IO.Path]::DirectorySeparatorChar

    if (-not $destinationFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $relative = $destinationFull.Substring($prefix.Length).Replace('\', '/')
    return (
        $relative -match '^(?i:cfg)(/|$)' -or
        $relative -match '^(?i:addons/(windows/addons/)?counterstrikesharp/configs)(/|$)'
    )
}

function Merge-Directory([string]$Source, [string]$Destination) {
    if (-not (Test-Path $Source -PathType Container)) {
        throw "Source directory does not exist: $Source"
    }

    if (Test-IsProtectedConfigDestination $Destination) {
        Write-Info "Preserving fixed/user-managed config path: $Destination"
        return
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
            if (Test-IsProtectedConfigDestination $dest) {
                Write-Info "Preserving fixed/user-managed config file: $dest"
                return
            }

            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
        }
    }
}

function Get-ReleaseMappings($Addon, [string]$AssetName) {
    if ($Addon.PSObject.Properties.Name -contains 'asset_mappings' -and $Addon.asset_mappings) {
        $mappingProperties = @($Addon.asset_mappings.PSObject.Properties)
        $exactMatches = @($mappingProperties | Where-Object { $_.Name -eq $AssetName })

        if ($exactMatches.Count -gt 1) {
            throw "Multiple exact asset mappings found for '$AssetName' in addon '$($Addon.name)'."
        }
        if ($exactMatches.Count -eq 1) {
            return @($exactMatches[0].Value)
        }

        # Versioned archive names must keep working when upstream increments the release version.
        $patternMatches = @($mappingProperties | Where-Object {
            $_.Name.Contains('{version}') -and
            $AssetName -like $_.Name.Replace('{version}', '*')
        })
        if ($patternMatches.Count -gt 1) {
            throw "Ambiguous versioned asset mappings found for '$AssetName' in addon '$($Addon.name)'."
        }
        if ($patternMatches.Count -eq 1) {
            return @($patternMatches[0].Value)
        }

        throw "No asset_mappings entry matches archive '$AssetName' for addon '$($Addon.name)'. Check the ZIP filename and destination mapping."
    }

    return @([pscustomobject]@{
        merge = [string]$Addon.merge
        source_path = if ($Addon.PSObject.Properties.Name -contains 'source_path') { [string]$Addon.source_path } else { '' }
        install_path = if ($Addon.PSObject.Properties.Name -contains 'install_path') { [string]$Addon.install_path } else { '' }
    })
}

function Resolve-ReleaseInstallTargets($Addon, [string]$ExtractRoot, [string]$AssetName) {
    $targets = New-Object System.Collections.Generic.List[object]

    foreach ($mapping in @(Get-ReleaseMappings $Addon $AssetName)) {
        $merge = [string]$mapping.merge
        $sourcePath = if ($mapping.PSObject.Properties.Name -contains 'source_path') { [string]$mapping.source_path } else { '' }
        $installPath = if ($mapping.PSObject.Properties.Name -contains 'install_path') { ([string]$mapping.install_path) -replace '/', '\' } else { '' }

        if ($merge -eq 'release_csgo_root') {
            $sourceRoot = Find-CsgoRoot $ExtractRoot
            if (-not $sourceRoot) {
                throw "Could not locate a CS2 game root/addons directory in the release archive for '$AssetName'."
            }

            [void]$targets.Add(@{
                MergeMode = $merge
                SourceRoot = $sourceRoot
                DestinationRoot = $PayloadRoot
                DestinationDisplay = 'game\csgo'
            })
            continue
        }

        if ($merge -eq 'release_plugin_directory') {
            $sourceParts = $sourcePath -split '[\\/]+' | Where-Object { $_ -ne '' }
            $installParts = $installPath -split '[\\/]+' | Where-Object { $_ -ne '' }

            if ([string]::IsNullOrWhiteSpace($sourcePath) -or [IO.Path]::IsPathRooted($sourcePath) -or ($sourceParts -contains '..')) {
                throw "Invalid release source_path for $($Addon.name) asset '$AssetName': $sourcePath"
            }
            if ([string]::IsNullOrWhiteSpace($installPath) -or [IO.Path]::IsPathRooted($installPath) -or ($installParts -contains '..')) {
                throw "Invalid release install_path for $($Addon.name) asset '$AssetName': $installPath"
            }

            $sourceRoot = Join-Path $ExtractRoot $sourcePath
            if (-not (Test-Path $sourceRoot -PathType Container)) {
                throw "Configured release source_path was not found for '$AssetName': $sourceRoot"
            }

            $destinationRoot = Join-Path $PayloadRoot $installPath
            $payloadFull = [IO.Path]::GetFullPath($PayloadRoot).TrimEnd('\') + '\'
            $destinationFull = [IO.Path]::GetFullPath($destinationRoot)
            if (-not $destinationFull.StartsWith($payloadFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Release install_path escapes game/csgo for '$AssetName': $installPath"
            }

            [void]$targets.Add(@{
                MergeMode = $merge
                SourceRoot = $sourceRoot
                DestinationRoot = $destinationRoot
                DestinationDisplay = "game\csgo\$installPath"
            })
            continue
        }

        throw "Unsupported release merge mode '$merge' for $($Addon.name) asset '$AssetName'."
    }

    if ($targets.Count -eq 0) {
        throw "No release mappings were defined for '$AssetName'."
    }

    return $targets.ToArray()
}
function Install-ReleaseAddon($Addon, $Release) {
    $assets = @(Get-ReleaseAssets $Release $Addon)
    $version = Get-AddonVersion -Addon $Addon -Tag $Release.tag_name
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

        $archiveLower = $archive.ToLowerInvariant()
        if (-not ($archiveLower.EndsWith(".zip") -or $archiveLower.EndsWith(".tar.gz"))) {
            throw "Unsupported archive type for '$($asset.name)'. Expected ZIP or TAR.GZ."
        }

        $extractName = [IO.Path]::GetFileNameWithoutExtension($asset.name)
        $extract = Join-Path $workRoot ("extract-" + $extractName)

        if (Test-Path $extract) {
            Remove-Item -LiteralPath $extract -Recurse -Force
        }

        Write-Info "Extracting $($asset.name)"
        if ($archiveLower.EndsWith(".zip")) {
            Expand-Archive -LiteralPath $archive -DestinationPath $extract -Force
        }
        else {
            $tarCommand = Get-Command "tar.exe" -ErrorAction SilentlyContinue
            if (-not $tarCommand) {
                throw "tar.exe is required to extract '$($asset.name)' but was not found."
            }

            New-Item -ItemType Directory -Force -Path $extract | Out-Null
            $stdoutFile = Join-Path $workRoot ("tar-" + [guid]::NewGuid().ToString("N") + ".stdout.log")
            $stderrFile = Join-Path $workRoot ("tar-" + [guid]::NewGuid().ToString("N") + ".stderr.log")
            $tarArguments = @("-xzf", ('"{0}"' -f $archive), "-C", ('"{0}"' -f $extract))
            $tarProcess = Start-Process -FilePath $tarCommand.Source -ArgumentList $tarArguments -WorkingDirectory $workRoot -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
            if ($tarProcess.ExitCode -ne 0) {
                $tarDetails = @()
                if (Test-Path -LiteralPath $stderrFile) { $tarDetails += Get-Content -LiteralPath $stderrFile -ErrorAction SilentlyContinue }
                if (Test-Path -LiteralPath $stdoutFile) { $tarDetails += Get-Content -LiteralPath $stdoutFile -ErrorAction SilentlyContinue }
                throw "tar extraction failed for '$($asset.name)' with exit code $($tarProcess.ExitCode): $($tarDetails -join ' ')"
            }
        }

        $targets = @(Resolve-ReleaseInstallTargets $Addon $extract $asset.name)
        foreach ($target in $targets) {
            Merge-Directory $target.SourceRoot $target.DestinationRoot
        }

        $layoutFile = Join-Path $workRoot ("layout-" + [IO.Path]::GetFileNameWithoutExtension($asset.name) + ".txt")
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("ADDON: $($Addon.name)")
        $lines.Add("VERSION: $version")
        $lines.Add("ARCHIVE: $archive")
        $lines.Add("EXTRACT ROOT: $extract")
        $lines.Add('')
        $lines.Add('SOURCE -> DESTINATION')
        foreach ($target in $targets) {
            $lines.Add("")
            $lines.Add("[$($target.MergeMode)] $($target.SourceRoot) -> $($target.DestinationDisplay)")
            Get-ChildItem -LiteralPath $target.SourceRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
                $relative = $_.FullName.Substring($target.SourceRoot.Length).TrimStart('\')
                $lines.Add("$relative -> $($target.DestinationDisplay)\$relative")
            }
        }
        [IO.File]::WriteAllLines($layoutFile, $lines, (New-Object System.Text.UTF8Encoding($false)))

        $metadataFile = Join-Path $workRoot ("release-" + [IO.Path]::GetFileNameWithoutExtension($asset.name) + ".json")
        Write-ReleaseMetadata $metadataFile $Addon.name $Addon.repository $version $Release.tag_name $asset.name $archive $extract $targets

        Write-Info "Extracted tree: $($targets[0].SourceRoot)"
        Write-Info "Mappings: $($targets.Count)"
        foreach ($target in $targets) {
            Write-Info "Destination: $($target.DestinationDisplay)"
        }
        Write-Info "Layout written to $layoutFile"
        Write-Info "Metadata written to $metadataFile"
    }

    # Do not report/commit a version unless all required paths and runtime globs exist.
    $missing = @(Get-AddonMissingFiles $Addon)
    if ($missing.Count -gt 0) {
        throw ("Add-on '$($Addon.name)' did not install all declared runtime requirements:" + [Environment]::NewLine + ($missing -join [Environment]::NewLine))
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
    $url = "https://github.com/$repo/archive/$($Commit.sha).zip"

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
    $buildLog = Join-Path $workRoot "build.log"
    & dotnet build $project.FullName -c Release -o $output --nologo *> $buildLog
    if ($LASTEXITCODE -ne 0) {
        $tail = (Get-Content -LiteralPath $buildLog -Tail 40 -ErrorAction SilentlyContinue) -join [Environment]::NewLine
        throw "dotnet build failed for $($Addon.name): $tail"
    }

    $built = Join-Path $output ([string]$Addon.output_file)
    if (-not (Test-Path $built -PathType Leaf)) {
        throw "Build completed but expected output was not found: $built"
    }

    $destination = Join-Path $PayloadRoot ([string]$Addon.install_path)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $built -Destination $destination -Force

    return [string]$version
}

function Save-Manifest() {
    if ($DryRun) { return }

    $json = $manifest | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText(
        $ManifestPath,
        $json + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Commit-AddonUpdate([string]$AddonName, [string]$Version) {
    if ($DryRun) {
        return
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git is required to commit addon updates."
    }

    & git -C $RepoRoot add -- game/csgo README.md DEPENDENCIES.json
    if ($LASTEXITCODE -ne 0) {
        throw "git add failed."
    }

    $staged = @(& git -C $RepoRoot diff --cached --name-only)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect staged changes."
    }

    foreach ($file in $staged) {
        if ($file -ne "README.md" -and $file -ne "DEPENDENCIES.json" -and
            -not $file.StartsWith("game/csgo/", [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unexpected staged path: $file"
        }
    }

    if ($staged.Count -eq 0) {
        throw "Addon update produced no Git changes to commit."
    }

    $message = "Update addon: $AddonName $Version"
    & git -C $RepoRoot commit -m $message
    if ($LASTEXITCODE -ne 0) {
        throw "git commit failed for $AddonName."
    }

    $short = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
    Write-Info "Committed $short"
}

function Update-ReadmeVersion([string]$Name, [string]$Repository, [string]$DisplayVersion) {
    if (-not (Test-Path $ReadmePath) -or $DryRun) {
        return
    }

    $text = Get-Content -LiteralPath $ReadmePath -Raw
    $escapedUrl = [regex]::Escape($Repository)
    $escapedName = [regex]::Escape($Name)
    $backtick = [char]96
    $pattern = "(?m)^[ \t]*\|?[ \t]*\[$escapedName\]\($escapedUrl\)[ \t]*\|[^|\r\n]*\|"
    $replacement = "| [$Name]($Repository) | $backtick$DisplayVersion$backtick |"
    $newText = [regex]::Replace($text, $pattern, $replacement, 1)

    # Support legacy plain-text rows while migrating them to repository links.
    # The full table is also reconciled against DEPENDENCIES.json after the update pass.
    if ($newText -eq $text) {
        $sectionMarker = "## Larnz-managed add-ons"
        $sectionStart = $text.IndexOf($sectionMarker, [StringComparison]::Ordinal)
        if ($sectionStart -ge 0) {
            $tailStart = $sectionStart + $sectionMarker.Length
            $tail = $text.Substring($tailStart)
            $nextHeading = [regex]::Match($tail, "(?m)^##\s")
            $sectionEnd = if ($nextHeading.Success) { $tailStart + $nextHeading.Index } else { $text.Length }
            $section = $text.Substring($sectionStart, $sectionEnd - $sectionStart)
            $plainPattern = "(?m)^\|\s*$escapedName\s*\|[^|\r\n]*\|"
            $plainReplacement = "| [$Name]($Repository) | $backtick$DisplayVersion$backtick |"
            $updatedSection = [regex]::Replace($section, $plainPattern, $plainReplacement, 1)
            if ($updatedSection -ne $section) {
                $newText = $text.Substring(0, $sectionStart) + $updatedSection + $text.Substring($sectionEnd)
            }
        }
    }

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


function Sync-ReadmeAddonTable() {
    if (-not (Test-Path -LiteralPath $ReadmePath) -or $DryRun) {
        return
    }

    $text = Get-Content -LiteralPath $ReadmePath -Raw
    $newline = if ($text.Contains(([string][char]13) + ([string][char]10))) {
        ([string][char]13) + ([string][char]10)
    } else {
        [string][char]10
    }
    $lines = [regex]::Split($text, "\r\n|\n")
    $sectionStart = -1
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i].Trim() -eq "## Larnz-managed add-ons") {
            $sectionStart = $i
            break
        }
    }
    if ($sectionStart -lt 0) {
        throw "README is missing the Larnz-managed add-ons section."
    }

    $sectionEnd = $lines.Length
    for ($i = $sectionStart + 1; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match "^##\s") {
            $sectionEnd = $i
            break
        }
    }

    $headerIndex = -1
    for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
        if ($lines[$i].Trim() -eq "| Add-on | Version | Purpose |") {
            $headerIndex = $i
            break
        }
    }
    if ($headerIndex -lt 0 -or $headerIndex + 1 -ge $sectionEnd -or
        $lines[$headerIndex + 1].Trim() -ne "| --- | --- | --- |") {
        throw "README Larnz add-on table header is missing or malformed."
    }

    $dataStart = $headerIndex + 2
    $dataEnd = $dataStart
    while ($dataEnd -lt $sectionEnd -and $lines[$dataEnd] -match "^\s*\|.*\|\s*$") {
        $dataEnd++
    }

    $purposes = @{}
    for ($i = $dataStart; $i -lt $dataEnd; $i++) {
        if ($lines[$i] -match "^\|\s*(?<label>.*?)\s*\|\s*(?<version>.*?)\s*\|\s*(?<purpose>.*?)\s*\|\s*$") {
            $label = $Matches["label"].Trim()
            if ($label -match "^\[(?<linkedName>[^\]]+)\]\([^)]+\)$") {
                $label = $Matches["linkedName"]
            }
            if (-not [string]::IsNullOrWhiteSpace($label)) {
                $purposes[$label] = $Matches["purpose"].Trim()
            }
        }
    }

    # Metamod is already documented in the KUS catalog table, so avoid duplicating it.
    $tableAddons = @(
        $manifest.addons |
            Where-Object { [string]$_.name -ne "Metamod:Source" } |
            Sort-Object { [int]$_.order }
    )
    if ($tableAddons.Count -eq 0) {
        throw "DEPENDENCIES.json contains no Larnz-managed add-ons to document."
    }

    $backtick = [string][char]96
    $newRows = [System.Collections.Generic.List[string]]::new()
    foreach ($addon in $tableAddons) {
        $name = [string]$addon.name
        $repository = [string]$addon.repository
        $displayVersion = [string]$addon.version
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($repository) -or
            [string]::IsNullOrWhiteSpace($displayVersion)) {
            throw "A Larnz-managed manifest entry is missing name, repository, or version."
        }

        if ([string]$addon.type -eq "github_source_build" -and
            -not [string]::IsNullOrWhiteSpace([string]$addon.branch)) {
            $shortCommit = $displayVersion.Substring(0, [Math]::Min(12, $displayVersion.Length))
            $displayVersion = "$([string]$addon.branch)@$shortCommit"
        }

        if ($purposes.ContainsKey($name)) {
            $purpose = [string]$purposes[$name]
        } elseif ([bool]$addon.installed -eq $false) {
            $purpose = "Not installed; tracked as a manual manifest entry."
        } else {
            $purpose = "Manifest-managed add-on."
        }

        # Derive install status from the manifest rather than freezing it into prose.
        $purpose = $purpose -replace "(?i);\s*not installed and marked manual in the Larnz manifest$", ""
        $purpose = $purpose -replace "(?i);\s*not installed$", ""
        if ([bool]$addon.installed -eq $false) {
            if ([string]$addon.automation_supported -eq "False") {
                $purpose += "; not installed and marked manual in the Larnz manifest"
            } elseif ($purpose -notmatch "(?i)\bnot installed\b") {
                $purpose += "; not installed"
            }
        }

        $versionCell = $backtick + $displayVersion + $backtick
        $newRows.Add("| [$name]($repository) | $versionCell | $purpose |")
    }

    $updatedLines = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $dataStart; $i++) {
        $updatedLines.Add($lines[$i])
    }
    foreach ($row in $newRows) {
        $updatedLines.Add($row)
    }
    for ($i = $dataEnd; $i -lt $lines.Length; $i++) {
        $updatedLines.Add($lines[$i])
    }

    $newText = [string]::Join($newline, $updatedLines.ToArray())
    if ($newText -ne $text) {
        [IO.File]::WriteAllText(
            $ReadmePath,
            $newText,
            (New-Object System.Text.UTF8Encoding($false))
        )
        Write-Info "Synchronized the Larnz add-on links and versions from DEPENDENCIES.json."
    }
}

if (-not (Test-Path $ManifestPath)) {
    throw "Missing $ManifestPath"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required by the KUS-style updater."
}

if (-not (Test-Path (Join-Path $RepoRoot ".git"))) {
    throw "$RepoRoot is not a Git working tree."
}

if (-not $DryRun) {
    # This updater changes only the tracked source payload under game/csgo/ and
    # README/manifest metadata. The live runtime is separate under server/game/csgo/,
    # so fetching/committing release files is safe while CS2 instances are running.
    # Runtime deployment and SteamCMD updates have their own active-process guards.
    $status = @(& git -C $RepoRoot status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read Git working tree status."
    }
    if ($status.Count -gt 0) {
        throw ("Working tree is not clean. Commit/stash existing changes before running the updater:" + [Environment]::NewLine + ($status -join [Environment]::NewLine))
    }
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$addons = @($manifest.addons | Sort-Object order)

$available = @{}
foreach ($addon in $addons) {
    if (-not [bool]$addon.installed) {
        $available[$addon.name] = $false
    }
    else {
        $available[$addon.name] = $true
    }
}


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

if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $PayloadRoot | Out-Null }

Write-Host ""
Write-Host "CS2 KUS Addons updater" -ForegroundColor Cyan
Write-Host "Target: $PayloadRoot"
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

    foreach ($dependency in @($addon.depends_on)) {
        if (-not $available.ContainsKey([string]$dependency) -or -not [bool]$available[[string]$dependency]) {
            throw "$($addon.name) requires '$dependency'. Run the updater in dependency order or install that dependency first."
        }
    }

    try {
        if ($addon.type -eq "github_release") {
            $release = Get-ReleaseForAddon $addon
            $version = Get-AddonVersion -Addon $addon -Tag $release.tag_name

            $missingFiles = @(Get-AddonMissingFiles $addon)
            $needsRepair = $missingFiles.Count -gt 0
            $needsUpdate = [bool]$Force -or
                -not [bool]$addon.installed -or
                ([string]$addon.version -ne $version) -or
                $needsRepair

            if (-not $needsUpdate) {
                Write-Info "Already at $version; all required files are present."
                continue
            }
            if ($needsRepair) {
                Write-Warn ("Runtime requirements are missing; reinstalling {0} {1}:{2}{3}" -f $addon.name, $version, [Environment]::NewLine, ($missingFiles -join [Environment]::NewLine))
            }

            $newVersion = Install-ReleaseAddon $addon $release

            if (-not $DryRun) {
                $addon.installed = $true
                $addon.version = $newVersion
                $addon.release_tag = $release.tag_name
            }

            $readmeUrl = if ($addon.PSObject.Properties.Name -contains "readme_url" -and -not [string]::IsNullOrWhiteSpace([string]$addon.readme_url)) { [string]$addon.readme_url } else { [string]$addon.repository }
            Update-ReadmeVersion $addon.name $readmeUrl $newVersion
            Save-Manifest
            Commit-AddonUpdate $addon.name $newVersion
            $available[$addon.name] = $true
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
                if ($addon.PSObject.Properties.Name -contains "source_commit") {
                    $addon.source_commit = $newVersion
                }
                else {
                    Add-Member -InputObject $addon -MemberType NoteProperty -Name source_commit -Value $newVersion -Force
                }
            }

            $display = "$($addon.branch)@$($newVersion.Substring(0,12))"
            Update-ReadmeVersion $addon.name $addon.repository $display
            Save-Manifest
            Commit-AddonUpdate $addon.name $display
            $available[$addon.name] = $true
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


Sync-ReadmeAddonTable
if (-not $DryRun) {
    # If no release needed an update, the README may still need reconciliation.
    # Commit only this expected documentation path, never unrelated working-tree files.
    & git -C $RepoRoot diff --quiet -- README.md
    $readmeDiffExit = $LASTEXITCODE
    if ($readmeDiffExit -eq 1) {
        & git -C $RepoRoot add -- README.md
        if ($LASTEXITCODE -ne 0) {
            throw "git add failed while staging README synchronization."
        }

        $stagedFiles = @(& git -C $RepoRoot diff --cached --name-only)
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect staged README synchronization."
        }
        $unexpectedStaged = @($stagedFiles | Where-Object { $_ -ne "README.md" })
        if ($unexpectedStaged.Count -gt 0) {
            throw ("README synchronization found unexpected staged changes: " + ($unexpectedStaged -join ", "))
        }
        if ($stagedFiles -contains "README.md") {
            & git -C $RepoRoot commit -m "Sync README add-on table from manifest"
            if ($LASTEXITCODE -ne 0) {
                throw "Could not commit README synchronization."
            }
            $short = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
            Write-Info "Committed README synchronization $short"
        }
    } elseif ($readmeDiffExit -ne 0) {
        throw "Could not check README synchronization diff."
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
if (-not $DryRun) {
    Write-Host "Review changes with: git status" -ForegroundColor DarkGray
}
