# CS2 KUS per-Instance supervisor.
# PowerShell owns the runner wait/restart loop. run.vbs watches this process separately.
$ErrorActionPreference = 'Stop'

$Root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$NormalRunner = Join-Path $Root 'run.bat'
$FastRunner = Join-Path $Root 'run_fast.bat'
$SuccessMarker = Join-Path $env:TEMP 'CS2-KUS-Maintenance-success.marker'

$hashProvider = [System.Security.Cryptography.SHA256]::Create()
try {
    $hashBytes = [System.Text.Encoding]::UTF8.GetBytes($Root.ToUpperInvariant())
    $InstanceHash = [System.BitConverter]::ToString($hashProvider.ComputeHash($hashBytes)).Replace('-', '').Substring(0, 16)
} finally {
    $hashProvider.Dispose()
}
$MutexName = "Global\CS2KUS_Supervisor_$InstanceHash"
$LogPath = Join-Path $env:TEMP "CS2-KUS-Supervisor-$InstanceHash.log"

function Write-SupervisorLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    try {
        if ((Test-Path -LiteralPath $LogPath) -and ((Get-Item -LiteralPath $LogPath).Length -gt 262144)) {
            $previousLog = "$LogPath.previous"
            if (Test-Path -LiteralPath $previousLog) { Remove-Item -LiteralPath $previousLog -Force -ErrorAction SilentlyContinue }
            Move-Item -LiteralPath $LogPath -Destination $previousLog -Force
        }
        Add-Content -LiteralPath $LogPath -Value ("{0:yyyy-MM-dd HH:mm:ss.fff} {1}" -f (Get-Date), $Message) -Encoding UTF8
    } catch { }
}

$mutex = $null
$ownsMutex = $false
try {
    $mutex = [System.Threading.Mutex]::new($false, $MutexName)
    try {
        $ownsMutex = $mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        # The previous supervisor died abruptly. The new process owns the abandoned mutex.
        $ownsMutex = $true
    }

    if (-not $ownsMutex) {
        Write-SupervisorLog 'A supervisor for this Instance already owns the mutex; exiting duplicate process.'
        exit 0
    }

    Write-SupervisorLog "Supervisor online for $Root"
    while ($true) {
        $process = $null
        try {
            $launchPath = $NormalRunner
            if ((Test-Path -LiteralPath $SuccessMarker) -and (Test-Path -LiteralPath $FastRunner)) {
                $launchPath = $FastRunner
            }

            if (-not (Test-Path -LiteralPath $launchPath)) {
                Write-SupervisorLog "Runner missing: $launchPath; checking again in 2 seconds."
                Start-Sleep -Seconds 2
                continue
            }

            # Run the batch in its own hidden cmd.exe process. PowerShell waits for cmd,
            # not for CS2 directly; run.bat owns CS2's start /wait and returns on exit/crash.
            $cmdArguments = '/d /s /c ""{0}""' -f $launchPath
            $process = Start-Process -FilePath $env:ComSpec -ArgumentList $cmdArguments -WorkingDirectory $Root -WindowStyle Hidden -PassThru
            Write-SupervisorLog "Started $(Split-Path -Leaf $launchPath), cmd PID=$($process.Id)."
            $process.WaitForExit()
            $exitCode = $process.ExitCode
            Write-SupervisorLog "Runner returned with exit code $exitCode; retrying in 100 ms."
        } catch {
            Write-SupervisorLog ("Runner supervisor error: " + $_.Exception.Message)
        } finally {
            if ($null -ne $process) {
                try { $process.Dispose() } catch { }
            }
        }
        Start-Sleep -Milliseconds 100
    }
} catch {
    Write-SupervisorLog ("Supervisor fatal error: " + $_.Exception.Message)
    throw
} finally {
    if ($ownsMutex -and $null -ne $mutex) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    if ($null -ne $mutex) {
        try { $mutex.Dispose() } catch { }
    }
}
