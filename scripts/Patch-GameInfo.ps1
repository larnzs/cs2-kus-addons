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

# Keep the KUS patcher's intent: tolerate whitespace around the Game search path,
# while anchoring the match to a single line so CRLF files work on Windows.
$horizontalWhitespace = '[^\S\r\n]'
$metamodPattern = '(?im)^' + $horizontalWhitespace + '*Game' + $horizontalWhitespace +
    '+csgo/addons/metamod(?:' + $horizontalWhitespace + '*//[^\r\n]*)?' +
    $horizontalWhitespace + '*\r?$'
$metamodMatches = [regex]::Matches($text, $metamodPattern)
if ($metamodMatches.Count -gt 1) {
    throw "gameinfo.gi has multiple Metamod search-path entries; refusing to edit it automatically."
}
if ($metamodMatches.Count -eq 1) {
    Write-Host "Metamod entry is already present."
    return
}

# KUS searches for Game_LowViolence + csgo_lv on a line and inserts the Metamod
# path immediately after it. Use Unicode horizontal whitespace and do not require
# a particular trailing comment or end-of-line assertion (the latter can fail
# against CRLF when the pattern excludes carriage returns).
$markerPattern = '(?im)^' + $horizontalWhitespace + '*Game_LowViolence' +
    $horizontalWhitespace + '*csgo_lv\b[^\r\n]*'
$markers = [regex]::Matches($text, $markerPattern)
if ($markers.Count -eq 0) {
    $diagnosticLines = @(
        [regex]::Matches($text, '(?im)^[^\r\n]*Game_LowViolence[^\r\n]*') |
            ForEach-Object { $_.Value.Trim() } |
            Select-Object -First 5
    )
    $diagnostic = if ($diagnosticLines.Count -gt 0) {
        " Similar lines: " + ($diagnosticLines -join " | ")
    } else {
        " No line containing Game_LowViolence was found."
    }
    throw "Could not find the KUS Game_LowViolence/csgo_lv insertion marker in gameinfo.gi.$diagnostic"
}
if ($markers.Count -gt 1) {
    throw "gameinfo.gi has multiple Game_LowViolence/csgo_lv markers; refusing to edit it automatically."
}

$marker = $markers[0]
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

# CS2 gameinfo.gi is UTF-8. Write without adding a BOM, retaining the file's
# existing LF/CRLF style and the original newline immediately after the marker.
$encoding = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($GameInfoPath, $updated, $encoding)

$verifyText = [IO.File]::ReadAllText($GameInfoPath)
$verify = [regex]::Matches($verifyText, $metamodPattern)
if ($verify.Count -ne 1) {
    throw "Metamod entry verification failed after patching gameinfo.gi."
}

$verifyMarker = [regex]::Match($verifyText, $markerPattern)
if (-not $verifyMarker.Success -or $verify.Index -le $verifyMarker.Index) {
    throw "Metamod entry was not inserted after the KUS search-path marker."
}
Write-Host "Inserted and verified the Metamod entry after Game_LowViolence. Backup: $backupPath"
