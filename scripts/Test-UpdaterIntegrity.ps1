[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$patcher = Join-Path $PSScriptRoot "Patch-GameInfo.ps1"
$manifestPath = Join-Path $repoRoot "DEPENDENCIES.json"

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "TEST FAILED: $Message" }
}
function Write-Utf8Fixture([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}
function Get-MetamodCount([string]$Content) {
    $pattern = '(?im)^[^\S\r\n]*Game[^\S\r\n]+csgo/addons/metamod(?:[^\S\r\n]*//[^\r\n]*)?[^\S\r\n]*\r?$'
    return [regex]::Matches($Content, $pattern).Count
}
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("kus-gameinfo-tests-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$crlf = [string][char]13 + [string][char]10
$lf = [string][char]10
$tab = [string][char]9

try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $names = @($manifest.addons | ForEach-Object { [string]$_.name })
    $orders = @($manifest.addons | ForEach-Object { [int]$_.order })
    Assert-Condition (($names | Sort-Object -Unique).Count -eq $names.Count) "Duplicate add-on names in DEPENDENCIES.json."
    Assert-Condition (($orders | Sort-Object -Unique).Count -eq $orders.Count) "Duplicate add-on order values in DEPENDENCIES.json."
    foreach ($addon in @($manifest.addons)) {
        if ([bool]$addon.installed) {
            Assert-Condition ($addon.PSObject.Properties.Name -contains "verify_paths" -and @($addon.verify_paths).Count -gt 0) "Installed add-on '$($addon.name)' has no verify_paths."
        }
        if ($addon.type -eq "github_release") {
            Assert-Condition (@($addon.assets).Count -gt 0) "Release add-on '$($addon.name)' has no assets."
            Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$addon.merge)) "Release add-on '$($addon.name)' has no merge mode."
        } elseif ($addon.type -eq "github_source_build") {
            Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$addon.project)) "Source-built add-on '$($addon.name)' has no project."
            Assert-Condition (-not [string]::IsNullOrWhiteSpace([string]$addon.output_file)) "Source-built add-on '$($addon.name)' has no output_file."
            $hasInstallDirectory = $false
            $hasInstallPath = $false
            if ($addon.PSObject.Properties.Name -contains "install_directory") {
                $hasInstallDirectory = -not [string]::IsNullOrWhiteSpace([string]$addon.install_directory)
            }
            if ($addon.PSObject.Properties.Name -contains "install_path") {
                $hasInstallPath = -not [string]::IsNullOrWhiteSpace([string]$addon.install_path)
            }
            Assert-Condition ($hasInstallDirectory -or $hasInstallPath) "Source-built add-on '$($addon.name)' has no destination."
        } else {
            throw "TEST FAILED: unsupported add-on type '$($addon.type)'."
        }
    }

    # KUS marker, standard comment and Windows CRLF.
    $case1 = Join-Path $tempRoot "standard-crlf.gi"
    $marker1 = "    Game_LowViolence csgo_lv // Perfect World content override"
    $fixture1 = "SearchPaths" + $crlf + "{" + $crlf + $marker1 + $crlf + "    Game csgo" + $crlf + "}" + $crlf
    Write-Utf8Fixture $case1 $fixture1
    & $patcher -GameInfoPath $case1
    $actual1 = [IO.File]::ReadAllText($case1)
    Assert-Condition ((Get-MetamodCount $actual1) -eq 1) "CRLF file did not receive exactly one Metamod entry."
    Assert-Condition ($actual1.Contains($marker1 + $crlf + $tab + $tab + $tab + "Game" + $tab + "csgo/addons/metamod" + $crlf + "    Game csgo")) "Metamod line was not inserted after KUS marker with CRLF."
    Assert-Condition (([IO.File]::ReadAllText($case1 + ".bak")) -ceq $fixture1) "Backup does not match the original file."

    # Tabs and non-standard comment on LF.
    $case2 = Join-Path $tempRoot "tabs-lf.gi"
    $marker2 = "  Game_LowViolence" + $tab + $tab + "csgo_lv // local comment"
    $fixture2 = "SearchPaths" + $lf + "{" + $lf + $marker2 + $lf + "  Game csgo" + $lf + "}" + $lf
    Write-Utf8Fixture $case2 $fixture2
    & $patcher -GameInfoPath $case2
    $actual2 = [IO.File]::ReadAllText($case2)
    Assert-Condition ((Get-MetamodCount $actual2) -eq 1) "Whitespace-variant LF file did not receive exactly one Metamod entry."
    Assert-Condition ($actual2.Contains($marker2 + $lf + $tab + $tab + $tab + "Game" + $tab + "csgo/addons/metamod" + $lf + "  Game csgo")) "Whitespace-variant marker was not patched immediately after its line."
    Assert-Condition (-not $actual2.Contains([string][char]13)) "LF file was unexpectedly converted to CRLF."

    # An existing CRLF entry must not be duplicated or modified.
    $case3 = Join-Path $tempRoot "already-patched-crlf.gi"
    $fixture3 = "SearchPaths" + $crlf + "{" + $crlf + $tab + "Game" + $tab + "csgo/addons/metamod" + $crlf + $tab + "Game csgo" + $crlf + "}" + $crlf
    Write-Utf8Fixture $case3 $fixture3
    & $patcher -GameInfoPath $case3
    Assert-Condition (([IO.File]::ReadAllText($case3)) -ceq $fixture3) "Already-patched CRLF file was modified."
    Assert-Condition (-not (Test-Path -LiteralPath ($case3 + ".bak"))) "Already-patched file unexpectedly received a backup."

    # Missing marker must fail closed without changing the file.
    $case4 = Join-Path $tempRoot "missing-marker.gi"
    $fixture4 = "SearchPaths" + $crlf + "{" + $crlf + "    Game csgo" + $crlf + "}" + $crlf
    Write-Utf8Fixture $case4 $fixture4
    $thrown = $false
    try { & $patcher -GameInfoPath $case4 } catch {
        $thrown = $true
        Assert-Condition ($_.Exception.Message -match "Could not find the KUS") "Missing-marker error was not descriptive."
    }
    Assert-Condition $thrown "Missing marker was silently accepted."
    Assert-Condition (([IO.File]::ReadAllText($case4)) -ceq $fixture4) "Missing-marker file was modified."

    # Multiple markers must be rejected, without changing the source.
    $case5 = Join-Path $tempRoot "duplicate-markers.gi"
    $fixture5 = "Game_LowViolence csgo_lv // first" + $lf + "Game_LowViolence csgo_lv // second" + $lf
    Write-Utf8Fixture $case5 $fixture5
    $thrown = $false
    try { & $patcher -GameInfoPath $case5 } catch {
        $thrown = $true
        Assert-Condition ($_.Exception.Message -match "multiple Game_LowViolence") "Ambiguous-marker error was not descriptive."
    }
    Assert-Condition $thrown "Multiple markers were silently accepted."
    Assert-Condition (([IO.File]::ReadAllText($case5)) -ceq $fixture5) "Ambiguous-marker file was modified."

    foreach ($name in @("SLAYER_Noscope", "CS2-Gunsmenu")) {
        $manual = @($manifest.addons | Where-Object { $_.name -eq $name })
        Assert-Condition ($manual.Count -eq 1) "Expected exactly one manifest row for '$name'."
        Assert-Condition (($manual[0].PSObject.Properties.Name -contains "automation_supported") -and (-not [bool]$manual[0].automation_supported)) "'$name' must remain non-automated."
    }
    Write-Host "PASS: manifest structure, disabled automation policy and 5 gameinfo patch scenarios." -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
