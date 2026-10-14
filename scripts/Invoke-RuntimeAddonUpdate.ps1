[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryRoot,

    [string]$Branch = "integration/kus-monorepo"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$WorktreeParent = Join-Path $RepositoryRoot "tmp"
# Each process gets its own worktree path. A fixed path allowed a second installer
# to try removing the first installer's worktree while Git was still initializing it.
$WorktreeRoot = Join-Path $WorktreeParent ("runtime-addon-update-$PID-$([guid]::NewGuid().ToString('N'))")
# This exclusive OS file lock serializes instances of this updater; the file may
# remain on disk, but the lock is released when the PowerShell process exits.
$WorktreeLockPath = Join-Path $RepositoryRoot ".git\runtime-addon-update.lock"
$WorktreeLockStream = $null
$WorktreeAttempted = $false
$OriginalGitHubToken = $env:GITHUB_TOKEN
$OriginalGitAuthorName = $env:GIT_AUTHOR_NAME
$OriginalGitAuthorEmail = $env:GIT_AUTHOR_EMAIL
$OriginalGitCommitterName = $env:GIT_COMMITTER_NAME
$OriginalGitCommitterEmail = $env:GIT_COMMITTER_EMAIL
$WorktreeCreated = $false
$ExitCode = 0

function Invoke-GitCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$GitArgs
    )

    # Windows PowerShell 5.1 can treat native Git stderr progress (such as
    # "From https://...") as a NativeCommandError. Keep that behavior non-fatal
    # for this invocation, capture the merged output, and trust Git's exit code.
    $savedErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& git -C $Path @GitArgs 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in $output) {
        if ($null -ne $line) {
            $lines.Add([string]$line)
        }
    }

    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output = [string[]]$lines.ToArray()
    }
}
function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$GitArgs
    )

    $result = Invoke-GitCapture -Path $Path -GitArgs $GitArgs
    if ($result.ExitCode -ne 0) {
        $details = (@($result.Output) | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        throw ("git {0} failed with exit code {1}.{2}{3}" -f
            ($GitArgs -join " "), $result.ExitCode, [Environment]::NewLine, $details)
    }

    foreach ($line in $result.Output) {
        [string]$line
    }
}

function Try-UseStoredGitHubToken {
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        Write-Host "Using the configured GITHUB_TOKEN for upstream release checks."
        return
    }

    # Reuse an existing GitHub credential only in this process, if the user
    # already has one stored for the private repository. Never print its value.
    $remote = [string](@(Invoke-Git -Path $RepositoryRoot -GitArgs @("remote", "get-url", "origin")) | Select-Object -First 1)
    if ($remote -notmatch 'github\.com[:/](?<slug>[^/]+/[^/]+?)(?:\.git)?$') {
        Write-Warning "No GitHub API token is configured; release checks will use the unauthenticated API rate limit."
        return
    }

    $slug = $Matches["slug"] -replace '\.git$', ''
    $oldPrompt = $env:GIT_TERMINAL_PROMPT
    $oldGcmInteractive = $env:GCM_INTERACTIVE
    try {
        $env:GIT_TERMINAL_PROMPT = "0"
        $env:GCM_INTERACTIVE = "Never"
        $inputText = "protocol=https" + [Environment]::NewLine + "host=github.com" + [Environment]::NewLine + "path=$slug" + [Environment]::NewLine + [Environment]::NewLine
        $credentialLines = $inputText | & git -C $RepositoryRoot credential fill 2>$null
        $credentialExitCode = $LASTEXITCODE
        if ($credentialExitCode -eq 0) {
            $passwordLine = @($credentialLines | Where-Object { [string]$_ -like "password=*" } | Select-Object -First 1)
            if ($passwordLine.Count -gt 0) {
                $token = ([string]$passwordLine[0]).Substring("password=".Length)
                if (-not [string]::IsNullOrWhiteSpace($token)) {
                    $env:GITHUB_TOKEN = $token
                    Write-Host "Using stored GitHub credentials for authenticated upstream release checks."
                    return
                }
            }
        }
    }
    catch {
        # An absent/non-interactive credential helper is not fatal; the updater
        # can still attempt the public GitHub API without authentication.
    }
    finally {
        $env:GIT_TERMINAL_PROMPT = $oldPrompt
        $env:GCM_INTERACTIVE = $oldGcmInteractive
    }

    Write-Warning "No reusable GitHub API token was found; release checks will use the unauthenticated API rate limit."
}

try {
    if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot ".git"))) {
        throw "RepositoryRoot is not a Git working tree: $RepositoryRoot"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot "scripts\Update-Addons.ps1"))) {
        throw "scripts\Update-Addons.ps1 is missing from $RepositoryRoot"
    }

    $currentBranch = [string](@(Invoke-Git -Path $RepositoryRoot -GitArgs @("branch", "--show-current")) | Select-Object -First 1)
    if ($currentBranch.Trim() -ne $Branch) {
        throw "Expected branch '$Branch' but found '$($currentBranch.Trim())'."
    }

    try {
        $WorktreeLockStream = [System.IO.File]::Open(
            $WorktreeLockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
    }
    catch {
        throw ("Could not acquire the runtime add-on updater lock at '$WorktreeLockPath'. " +
            "Another install/update may already be running, or the lock file is not accessible. " +
            "Wait for the active update to finish, then retry. Details: " + $_.Exception.Message)
    }

    $mainStatus = @(Invoke-Git -Path $RepositoryRoot -GitArgs @("status", "--porcelain", "--untracked-files=all"))
    if ($mainStatus.Count -gt 0) {
        throw ("The main repository must be clean before checking upstream add-ons:" +
            [Environment]::NewLine + ($mainStatus -join [Environment]::NewLine))
    }

    Try-UseStoredGitHubToken

    $gitName = [string](@(& git -C $RepositoryRoot config user.name 2>$null | Select-Object -First 1))
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitName)) {
        $gitName = "CS2 KUS Addon Updater"
    }
    $gitEmail = [string](@(& git -C $RepositoryRoot config user.email 2>$null | Select-Object -First 1))
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitEmail)) {
        $gitEmail = "cs2-kus-addon-updater@users.noreply.github.com"
    }
    $env:GIT_AUTHOR_NAME = $gitName.Trim()
    $env:GIT_AUTHOR_EMAIL = $gitEmail.Trim()
    $env:GIT_COMMITTER_NAME = $gitName.Trim()
    $env:GIT_COMMITTER_EMAIL = $gitEmail.Trim()

    Write-Host ""
    Write-Host "Fetching the latest private branch before checking upstream add-on releases..."
    Invoke-Git -Path $RepositoryRoot -GitArgs @("fetch", "origin", $Branch) | Out-Null
    $originRef = "origin/$Branch"
    $baseSha = [string](@(Invoke-Git -Path $RepositoryRoot -GitArgs @("rev-parse", $originRef)) | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($baseSha)) {
        throw "Could not resolve $originRef."
    }
    $baseSha = $baseSha.Trim()

    # Use a detached, per-process worktree so concurrent installers never
    # inspect/remove the same directory while Git marks it "initializing".
    if (Test-Path -LiteralPath $WorktreeRoot) {
        throw "The uniquely named temporary worktree path already exists: $WorktreeRoot"
    }
    New-Item -ItemType Directory -Force -Path $WorktreeParent | Out-Null
    $WorktreeAttempted = $true
    Invoke-Git -Path $RepositoryRoot -GitArgs @("worktree", "add", "--detach", $WorktreeRoot, $originRef) | Out-Null
    $WorktreeCreated = $true

    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $updaterPath = Join-Path $WorktreeRoot "scripts\Update-Addons.ps1"
    Write-Host ""
    Write-Host "Checking upstream releases and building any configured source add-ons..."
    & $powershell -NoProfile -ExecutionPolicy Bypass -File $updaterPath
    $updaterExitCode = $LASTEXITCODE
    if ($updaterExitCode -ne 0) {
        throw "scripts\Update-Addons.ps1 failed with exit code $updaterExitCode."
    }

    $worktreeStatus = @(Invoke-Git -Path $WorktreeRoot -GitArgs @("status", "--porcelain", "--untracked-files=all"))
    if ($worktreeStatus.Count -gt 0) {
        throw ("The add-on updater left uncommitted changes in its isolated worktree:" +
            [Environment]::NewLine + ($worktreeStatus -join [Environment]::NewLine))
    }

    $aheadText = [string](@(Invoke-Git -Path $WorktreeRoot -GitArgs @("rev-list", "--count", "$baseSha..HEAD")) | Select-Object -First 1)
    $ahead = 0
    if (-not [int]::TryParse($aheadText.Trim(), [ref]$ahead)) {
        throw "Could not determine whether the upstream add-on updater created commits."
    }

    if ($ahead -eq 0) {
        Write-Host ""
        Write-Host "No upstream add-on updates are required; all tracked add-ons are current."
    }
    else {
        Write-Host ""
        Write-Host "$ahead add-on update commit(s) were created. Publishing them to the private repository..."

        $published = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            Invoke-Git -Path $WorktreeRoot -GitArgs @("fetch", "origin", $Branch) | Out-Null

            $rebaseResult = Invoke-GitCapture -Path $WorktreeRoot -GitArgs @("rebase", $originRef)
            if ($rebaseResult.ExitCode -ne 0) {
                & git -C $WorktreeRoot rebase --abort *> $null
                $details = (@($rebaseResult.Output) | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
                throw ("Could not rebase the new add-on commits onto origin/$Branch." +
                    [Environment]::NewLine + $details)
            }

            $pushResult = Invoke-GitCapture -Path $WorktreeRoot -GitArgs @("push", "origin", "HEAD:refs/heads/$Branch")
            if ($pushResult.ExitCode -eq 0) {
                $published = $true
                Write-Host (@($pushResult.Output) -join [Environment]::NewLine)
                break
            }

            Write-Warning ("Push attempt {0} failed (exit {1}): {2}" -f
                $attempt, $pushResult.ExitCode, ((@($pushResult.Output) | ForEach-Object { [string]$_ }) -join " "))
            if ($attempt -lt 3) {
                Start-Sleep -Seconds 2
            }
        }

        if (-not $published) {
            throw "Could not publish upstream add-on updates after 3 attempts. The main checkout remains untouched; maintenance will retry later."
        }

        Write-Host "Upstream add-on updates were published successfully."
    }
}
catch {
    # Do not call Write-Error under ErrorActionPreference=Stop: that would throw
    # again and obscure the original git/updater failure in the final log.
    Write-Host ("ERROR: " + $_.Exception.Message)
    if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
        Write-Host $_.ScriptStackTrace
    }
    $ExitCode = 1
}
finally {
    if ($WorktreeAttempted -or (Test-Path -LiteralPath $WorktreeRoot)) {
        # Git can leave an "initializing" lock if worktree add/remove was
        # interrupted. First try normal removal, then unlock and retry only this
        # process's unique worktree. Never prune the repository's other worktrees.
        $removeResult = Invoke-GitCapture -Path $RepositoryRoot -GitArgs @("worktree", "remove", "--force", $WorktreeRoot)
        if ($removeResult.ExitCode -ne 0) {
            $unlockResult = Invoke-GitCapture -Path $RepositoryRoot -GitArgs @("worktree", "unlock", $WorktreeRoot)
            if ($unlockResult.ExitCode -eq 0) {
                $removeResult = Invoke-GitCapture -Path $RepositoryRoot -GitArgs @("worktree", "remove", "--force", $WorktreeRoot)
            }
        }

        # Do not delete a directory while Git still registers it as a worktree.
        # If Git no longer registers this unique path, removing a leftover partial
        # directory is safe and cannot affect another installer's workspace.
        $registered = $false
        $listResult = Invoke-GitCapture -Path $RepositoryRoot -GitArgs @("worktree", "list", "--porcelain")
        $registrationCheckSucceeded = ($listResult.ExitCode -eq 0)
        if ($registrationCheckSucceeded) {
            $wantedPath = [System.IO.Path]::GetFullPath($WorktreeRoot).TrimEnd([char[]]@([char]'\', [char]'/'))
            foreach ($line in $listResult.Output) {
                if ($line.StartsWith("worktree ", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $listedPath = $line.Substring(9).Trim()
                    try {
                        $listedPath = [System.IO.Path]::GetFullPath($listedPath).TrimEnd([char[]]@([char]'\', [char]'/'))
                        if ($listedPath.Equals($wantedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $registered = $true
                            break
                        }
                    }
                    catch {
                        # Ignore malformed/unresolvable entries from unrelated worktrees.
                    }
                }
            }
        }

        if ($registered) {
            $details = (@($removeResult.Output) | ForEach-Object { [string]$_ }) -join " "
            Write-Host ("WARNING: Git still registers this temporary worktree; leaving it in place rather than deleting an active/locked worktree. " + $WorktreeRoot + " " + $details)
        }
        elseif (-not $registrationCheckSucceeded) {
            $details = (@($listResult.Output) | ForEach-Object { [string]$_ }) -join " "
            Write-Host ("WARNING: Could not verify whether Git still registers temporary worktree '$WorktreeRoot'; leaving it in place. " + $details)
        }
        elseif (Test-Path -LiteralPath $WorktreeRoot) {
            try {
                Remove-Item -LiteralPath $WorktreeRoot -Recurse -Force -ErrorAction Stop
            }
            catch {
                Write-Host ("WARNING: Could not remove leftover temporary directory '$WorktreeRoot': " + $_.Exception.Message)
            }
        }
    }

    if ($null -ne $WorktreeLockStream) {
        try { $WorktreeLockStream.Dispose() } catch { }
    }

    $env:GITHUB_TOKEN = $OriginalGitHubToken
    $env:GIT_AUTHOR_NAME = $OriginalGitAuthorName
    $env:GIT_AUTHOR_EMAIL = $OriginalGitAuthorEmail
    $env:GIT_COMMITTER_NAME = $OriginalGitCommitterName
    $env:GIT_COMMITTER_EMAIL = $OriginalGitCommitterEmail
}

exit $ExitCode
