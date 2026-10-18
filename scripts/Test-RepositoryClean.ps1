[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

function Invoke-GitCapture {
    param([Parameter(Mandatory = $true)][string[]]$GitArgs)

    # Git for Windows may emit core.safecrlf warnings while examining files. They
    # are not status records, so suppress stderr and rely on Git's exit code.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& git -C $RepositoryRoot @GitArgs 2>$null)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }

    return [pscustomobject]@{
        ExitCode = [int]$code
        Output = [string[]]@($output | ForEach-Object { [string]$_ })
    }
}

function Write-CurrentStatus {
    $status = Invoke-GitCapture -GitArgs @("status", "--short", "--untracked-files=all")
    if ($status.ExitCode -eq 0 -and $status.Output.Count -gt 0) {
        foreach ($line in $status.Output) {
            Write-Host ("  " + $line)
        }
    }
}

$statusResult = Invoke-GitCapture -GitArgs @("status", "--porcelain=v1", "--untracked-files=all")
if ($statusResult.ExitCode -ne 0) {
    Write-Host "ERROR: Could not inspect the repository's Git status."
    exit 1
}

$statusLines = @($statusResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($statusLines.Count -eq 0) {
    Write-Host "Repository working tree is clean."
    exit 0
}

# Do not try to repair staged changes or remove unknown files.
$staged = @($statusLines | Where-Object {
    $_.Length -ge 2 -and $_.Substring(0, 1) -ne " " -and $_.Substring(0, 1) -ne "?"
})
$untracked = @($statusLines | Where-Object { $_.StartsWith("??", [StringComparison]::Ordinal) })
if ($staged.Count -gt 0 -or $untracked.Count -gt 0) {
    Write-Host "ERROR: Staged changes or untracked files are present. Nothing was changed."
    Write-CurrentStatus
    exit 1
}

$changedResult = Invoke-GitCapture -GitArgs @("diff", "--name-only", "--")
if ($changedResult.ExitCode -ne 0) {
    Write-Host "ERROR: Could not list modified tracked files."
    exit 1
}
$changedPaths = @($changedResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($changedPaths.Count -eq 0) {
    Write-Host "ERROR: Git reports a dirty tree, but no ordinary unstaged file changes were found. Nothing was changed."
    Write-CurrentStatus
    exit 1
}

$lineEndingOnly = New-Object System.Collections.Generic.List[string]
$contentChanges = New-Object System.Collections.Generic.List[string]
foreach ($path in $changedPaths) {
    $compare = Invoke-GitCapture -GitArgs @("diff", "--quiet", "--ignore-cr-at-eol", "--", $path)
    if ($compare.ExitCode -eq 0) {
        [void]$lineEndingOnly.Add($path)
    }
    elseif ($compare.ExitCode -eq 1) {
        [void]$contentChanges.Add($path)
    }
    else {
        Write-Host ("ERROR: Could not safely inspect changed file: " + $path)
        exit 1
    }
}

if ($contentChanges.Count -gt 0) {
    Write-Host "ERROR: The repository contains changes beyond CR-at-end-of-line differences. No tracked content was discarded."
    Write-Host "Review these modified files:"
    foreach ($path in $contentChanges) {
        Write-Host ("  " + $path)
    }
    Write-Host "Full Git status:"
    Write-CurrentStatus
    $stat = Invoke-GitCapture -GitArgs @("diff", "--stat", "--")
    if ($stat.ExitCode -eq 0) {
        foreach ($line in $stat.Output) {
            Write-Host ("  " + $line)
        }
    }
    exit 1
}

if ($lineEndingOnly.Count -eq 0) {
    Write-Host "ERROR: Git reports local changes that could not be classified safely. Nothing was changed."
    Write-CurrentStatus
    exit 1
}

# This is safe only because every unstaged difference has already been proven
# ignorable by Git's --ignore-cr-at-eol comparison. No staged/untracked items
# were present, and no content changes were found.
$restoreArgs = @("restore", "--worktree", "--")
$restoreArgs += @($lineEndingOnly.ToArray())
$restore = Invoke-GitCapture -GitArgs $restoreArgs
if ($restore.ExitCode -ne 0) {
    Write-Host "ERROR: Could not normalize line-ending-only working-tree changes."
    exit 1
}

$finalStatus = Invoke-GitCapture -GitArgs @("status", "--porcelain=v1", "--untracked-files=all")
if ($finalStatus.ExitCode -ne 0 -or @($finalStatus.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    Write-Host "ERROR: The repository is still dirty after line-ending normalization. No content changes were discarded."
    Write-CurrentStatus
    exit 1
}

Write-Host ("Normalized " + $lineEndingOnly.Count + " tracked file(s) with CR-at-end-of-line-only differences.")
Write-Host "Repository working tree is clean."
exit 0
