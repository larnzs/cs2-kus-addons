[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameInfoPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $GameInfoPath -PathType Leaf)) {
    throw "gameinfo.gi was not found: $GameInfoPath"
}

$text = [IO.File]::ReadAllText($GameInfoPath)
$metamodPattern = '(?im)^[ \t]*Game[ \t]+csgo/addons/metamod(?:[ \t]+//[^\r\n]*)?[ \t]*$'
$metamodMatches = [regex]::Matches($text, $metamodPattern)
if ($metamodMatches.Count -gt 1) {
    throw "gameinfo.gi has multiple Metamod search-path entries; refusing to edit it automatically."
}
if ($metamodMatches.Count -eq 1) {
    Write-Host "Metamod entry is already present."
    exit 0
}

$markerPattern = '(?m)^[ \t]*Game_LowViolence[ \t]+csgo_lv[^\r\n]*$'
$marker = [regex]::Match($text, $markerPattern)
if (-not $marker.Success) {
    throw "Could not find the Game_LowViolence csgo_lv insertion marker in gameinfo.gi."
}

$backupPath = "$GameInfoPath.bak"
if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
    Copy-Item -LiteralPath $GameInfoPath -Destination $backupPath
}

$crlf = [string][char]13 + [string][char]10
$newLine = if ($text.Contains($crlf)) { $crlf } else { [string][char]10 }
$tab = [string][char]9
$entry = $tab + $tab + $tab + "Game" + $tab + "csgo/addons/metamod"
$replacement = $marker.Value + $newLine + $entry
$updated = $text.Remove($marker.Index, $marker.Length).Insert($marker.Index, $replacement)
$encoding = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($GameInfoPath, $updated, $encoding)

$verify = [regex]::Matches([IO.File]::ReadAllText($GameInfoPath), $metamodPattern)
if ($verify.Count -ne 1) {
    throw "Metamod entry verification failed after patching gameinfo.gi."
}
Write-Host "Inserted and verified the Metamod entry. Backup: $backupPath"
