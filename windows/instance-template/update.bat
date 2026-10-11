@echo off
setlocal EnableExtensions DisableDelayedExpansion

title CS2 Shared Maintenance
set "RC=1"

set "INSTANCE_DIR=%~dp0"
if "%INSTANCE_DIR:~-1%"=="\" set "INSTANCE_DIR=%INSTANCE_DIR:~0,-1%"
set "REPO_ROOT=%CS2_REPO_ROOT%"

set "INI_FILE=%INSTANCE_DIR%\instance.ini"
if not exist "%INI_FILE%" (
    echo ERROR: Missing instance configuration: %INI_FILE%
    echo Copy instance.example.ini to instance.ini and edit it first.
    set "RC=2"
    goto :finish
)

for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%INI_FILE%") do set "%%A=%%B"
if not defined SERVER_DIR set "SERVER_DIR=..\..\server"
if "%SERVER_DIR:~0,2%"=="\\" goto :resolve_server
if "%SERVER_DIR:~1,1%"==":" goto :resolve_server
for %%I in ("%INSTANCE_DIR%\%SERVER_DIR%") do set "SERVER_DIR=%%~fI"
:resolve_server

if not defined REPO_ROOT for %%I in ("%SERVER_DIR%\..") do set "REPO_ROOT=%%~fI"
if not exist "%REPO_ROOT%\DEPENDENCIES.json" for %%I in ("%SERVER_DIR%\..") do set "REPO_ROOT=%%~fI"

if not defined BIND_IP set "BIND_IP=0.0.0.0"
if not defined MAXPLAYERS set "MAXPLAYERS=24"
if not defined PORT set "PORT=27015"
if not defined TICKRATE set "TICKRATE=128"
if not defined LAN set "LAN=0"
if not defined SERVER_PASSWORD set "SERVER_PASSWORD="
if not defined RCON_PASSWORD set "RCON_PASSWORD="
if not defined EXEC set "EXEC=on_boot.cfg"
if not defined MAPGROUP set "MAPGROUP=mg_aim"
if not defined MAP set "MAP=de_mirage"
if not defined WORKSHOP_COLLECTION set "WORKSHOP_COLLECTION="
if not defined API_KEY set "API_KEY="
if not defined STEAM_ACCOUNT set "STEAM_ACCOUNT="
if not defined IP set "IP="

set "GAME_DIR=%SERVER_DIR%\game\csgo"
set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"
set "GAMEINFO=%GAME_DIR%\gameinfo.gi"
set "STEAMCMD=%REPO_ROOT%\steamcmd\steamcmd.exe"
set "PAYLOAD_DIR=%REPO_ROOT%\game\csgo"
set "WINDOWS_OVERLAY=%PAYLOAD_DIR%\addons\windows"
set "LOCK_DIR=%TEMP%\CS2-KUS-Maintenance.lock"
set "LAST_SUCCESS=%TEMP%\CS2-KUS-Maintenance-success.marker"
set "CS2_LOCK_DIR=%LOCK_DIR%"
set "CS2_LAST_SUCCESS=%LAST_SUCCESS%"
set "CS2_GAMEINFO=%GAMEINFO%"
set "LOCK_HELD=0"

if not exist "%CS2_EXE%" goto :MissingCS2
if not exist "%GAMEINFO%" goto :MissingGameInfo

echo.
echo ============================================
echo       CS2 Shared Maintenance
echo ============================================
echo Repository: %REPO_ROOT%
echo Server:     %SERVER_DIR%
echo.

rem Never update shared runtime files while any CS2 server is running.
call :AnyCS2Running
if not errorlevel 1 goto :SkipStartupMaintenanceNoLock

call :AcquireLock
call :AnyCS2Running
if not errorlevel 1 goto :SkipStartupMaintenance

rem This five-minute marker prevents duplicate startup updates across Instances.
rem It is not used by VBS to select a runner during crash recovery.
call :IsRecentSuccess
if not errorlevel 1 goto :RecentSuccess

goto :DoMaintenance

:RecentSuccess
echo [%date% %time%] A successful shared update is less than five minutes old; skipping duplicate update checks.
echo [%date% %time%] CUSTOM_FOLDER files are copied by run.bat immediately before each server launch.
call :ReleaseLock
set "RC=0"
goto :finish

:SkipStartupMaintenanceNoLock
echo [%date% %time%] Another cs2.exe is active. Shared updates and override syncing are skipped.
set "RC=0"
goto :finish

:SkipStartupMaintenance
echo [%date% %time%] Another cs2.exe became active while waiting for the maintenance lock; shared updates are skipped.
call :ReleaseLock
set "RC=0"
goto :finish

:DoMaintenance
rem Do not start maintenance if prerequisites are missing. This updater is one-shot.
if not exist "%REPO_ROOT%\DEPENDENCIES.json" (
    echo ERROR: Repository manifest is missing: %REPO_ROOT%\DEPENDENCIES.json
    goto :MaintenanceFailed
)
if not exist "%STEAMCMD%" (
    echo ERROR: SteamCMD is missing: %STEAMCMD%
    goto :MaintenanceFailed
)
if not exist "%PAYLOAD_DIR%\addons\" (
    echo ERROR: Tracked add-on payload is missing: %PAYLOAD_DIR%\addons
    goto :MaintenanceFailed
)
if not exist "%WINDOWS_OVERLAY%\addons\" (
    echo ERROR: Windows add-on overlay is missing: %WINDOWS_OVERLAY%\addons
    goto :MaintenanceFailed
)

rem Re-check between update stages. If another Instance starts, abandon the
rem remaining maintenance/deployment work instead of touching shared runtime files.
call :AnyCS2Running
if not errorlevel 1 goto :MaintenanceSkippedBusy

call :UpdateRepository
if errorlevel 1 goto :MaintenanceFailed

call :AnyCS2Running
if not errorlevel 1 goto :MaintenanceSkippedBusy
call :UpdateUpstreamAddons
if errorlevel 1 goto :MaintenanceFailed

call :AnyCS2Running
if not errorlevel 1 goto :MaintenanceSkippedBusy
call :UpdateRepository
if errorlevel 1 goto :MaintenanceFailed

call :AnyCS2Running
if not errorlevel 1 goto :MaintenanceSkippedBusy
call :UpdateGame
if errorlevel 1 goto :MaintenanceFailed

call :AnyCS2Running
if not errorlevel 1 goto :MaintenanceSkippedBusy
call :PatchGameInfo
if errorlevel 1 goto :MaintenanceFailed

call :AnyCS2Running
if not errorlevel 1 goto :MaintenanceSkippedBusy
call :OverlayPayload
if errorlevel 1 goto :MaintenanceFailed

call :AnyCS2Running
if not errorlevel 1 goto :MaintenanceSkippedBusy
echo [%date% %time%] CUSTOM_FOLDER copying is handled by run.bat immediately before launch, not by this updater.

> "%LAST_SUCCESS%" echo Shared maintenance completed at %date% %time%
echo [%date% %time%] Maintenance completed successfully. Returning to launch-only runner.
call :ReleaseLock
exit /b 0

:MaintenanceSkippedBusy
echo ERROR: Another cs2.exe became active during maintenance. Remaining deployment stages were cancelled; this updater will stop without launching a server against a potentially partial update.
call :ReleaseLock
set "RC=1"
goto :finish

:MaintenanceFailed
echo ERROR: Maintenance failed. The runtime overlay never intentionally deletes files.
call :ReleaseLock
exit /b 1

:AcquireLock
2>nul md "%LOCK_DIR%"
if not errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$PID); if(-not $p){exit 1}; Set-Content -LiteralPath (Join-Path $env:CS2_LOCK_DIR 'owner.pid') -Value $p.ParentProcessId -NoNewline" >nul 2>&1
    if errorlevel 1 (
        rd /s /q "%LOCK_DIR%" >nul 2>&1
        timeout /t 2 /nobreak >nul
        goto :AcquireLock
    )
    set "LOCK_HELD=1"
    exit /b 0
)

if exist "%LOCK_DIR%\owner.pid" goto :CheckLockOwner
goto :CheckLockWithoutOwner

:CheckLockOwner
set "LOCK_OWNER_PID="
set /p LOCK_OWNER_PID=<"%LOCK_DIR%\owner.pid"
if not defined LOCK_OWNER_PID goto :CheckLockWithoutOwner
powershell -NoProfile -Command "if(Get-Process -Id %LOCK_OWNER_PID% -ErrorAction SilentlyContinue){exit 0}else{exit 1}" >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] Removing stale maintenance lock from a stopped runner.
    rd /s /q "%LOCK_DIR%" >nul 2>&1
    goto :AcquireLock
)
goto :WaitForLock

:CheckLockWithoutOwner
powershell -NoProfile -Command "$d=Get-Item -LiteralPath $env:CS2_LOCK_DIR -ErrorAction SilentlyContinue; if($d -and ((Get-Date)-$d.CreationTime).TotalSeconds -gt 30){exit 1}else{exit 0}" >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] Removing incomplete stale maintenance lock.
    rd /s /q "%LOCK_DIR%" >nul 2>&1
    goto :AcquireLock
)

:WaitForLock
timeout /t 2 /nobreak >nul
goto :AcquireLock

:ReleaseLock
if "%LOCK_HELD%"=="1" (
    rd /s /q "%LOCK_DIR%" >nul 2>&1
    set "LOCK_HELD=0"
)
exit /b 0

:IsRecentSuccess
powershell -NoProfile -Command "$p=$env:CS2_LAST_SUCCESS; if((Test-Path -LiteralPath $p) -and ((Get-Date)-(Get-Item -LiteralPath $p).LastWriteTime).TotalMinutes -lt 5){exit 0}else{exit 1}" >nul 2>&1
exit /b %ERRORLEVEL%

:AnyCS2Running
tasklist /FI "IMAGENAME eq cs2.exe" /FO CSV /NH 2>nul | findstr /I /C:"cs2.exe" >nul
if not errorlevel 1 exit /b 0
exit /b 1

:UpdateRepository
echo.
echo Pulling the latest private-repository payload (including add-ons already published by the remote updater workflow)...
set "CURRENT_BRANCH="
for /f "delims=" %%B in ('git -C "%REPO_ROOT%" branch --show-current 2^>nul') do set "CURRENT_BRANCH=%%B"
if /I not "%CURRENT_BRANCH%"=="integration/kus-monorepo" (
    echo ERROR: Expected Git branch integration/kus-monorepo; found "%CURRENT_BRANCH%".
    exit /b 1
)
set "GIT_DIRTY="
for /f "delims=" %%S in ('git -C "%REPO_ROOT%" status --porcelain --untracked-files=all 2^>nul') do set "GIT_DIRTY=1"
if defined GIT_DIRTY (
    echo ERROR: The repository has local changes or untracked files.
    echo Move local Instance folders outside the repository and resolve changes before updating.
    exit /b 1
)
git -C "%REPO_ROOT%" pull --ff-only origin integration/kus-monorepo
if errorlevel 1 (
    echo ERROR: Git pull failed; check branch, credentials, network, and repository state.
    exit /b 1
)
if not exist "%PAYLOAD_DIR%\addons\" (
    echo ERROR: Add-on payload is missing after Git pull.
    exit /b 1
)
exit /b 0

:UpdateUpstreamAddons
echo.
echo Checking upstream add-on releases and publishing any new versions to the private repository...
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%\scripts\Invoke-RuntimeAddonUpdate.ps1" -RepositoryRoot "%REPO_ROOT%" -Branch "integration/kus-monorepo"
if errorlevel 1 (
    echo ERROR: Upstream add-on check/update/publish failed.
    exit /b 1
)
exit /b 0

:UpdateGame
echo.
echo Checking/updating CS2 through SteamCMD. This runs only when the shared install is not in use.
start "" /wait "%STEAMCMD%" +force_install_dir "%SERVER_DIR%" +login anonymous +app_update 730 +quit
set "STEAMCMD_RC=%ERRORLEVEL%"
if not "%STEAMCMD_RC%"=="0" (
    echo ERROR: SteamCMD game update failed with code %STEAMCMD_RC%.
    exit /b 1
)
exit /b 0

:PatchGameInfo
if not exist "%GAMEINFO%" (
    echo ERROR: gameinfo.gi is missing after SteamCMD.
    exit /b 1
)
if not exist "%GAMEINFO%.bak" copy /y "%GAMEINFO%" "%GAMEINFO%.bak" >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:CS2_GAMEINFO; if(-not (Test-Path -LiteralPath $p)){exit 1}; $b=[IO.File]::ReadAllBytes($p); $enc=[System.Text.UTF8Encoding]::new($false); if($b.Length -ge 3 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191){$enc=[System.Text.UTF8Encoding]::new($true)} elseif($b.Length -ge 2 -and $b[0] -eq 255 -and $b[1] -eq 254){$enc=[System.Text.Encoding]::Unicode} elseif($b.Length -ge 2 -and $b[0] -eq 254 -and $b[1] -eq 255){$enc=[System.Text.Encoding]::BigEndianUnicode}; $s=[IO.File]::ReadAllText($p); if($s -match '(?im)^\s*Game\s+csgo/addons/metamod\s*$'){exit 0}; $pat='(?im)^([ \t]*Game_LowViolence[ \t]+csgo_lv[^\r\n]*)(\r?\n)'; $m=[regex]::Match($s,$pat); if(-not $m.Success){exit 2}; $nl=$m.Groups[2].Value; $ins=$m.Groups[1].Value+$nl+[char]9+[char]9+[char]9+'Game'+[char]9+'csgo/addons/metamod'+$nl; $s=$s.Remove($m.Index,$m.Length).Insert($m.Index,$ins); [IO.File]::WriteAllText($p,$s,$enc)"
if errorlevel 1 (
    echo ERROR: Could not patch gameinfo.gi for MetaMod.
    exit /b 1
)
findstr /m /c:"csgo/addons/metamod" "%GAMEINFO%" >nul
if errorlevel 1 (
    echo ERROR: The MetaMod entry is still missing from gameinfo.gi.
    exit /b 1
)
exit /b 0

:OverlayPayload
echo.
echo Applying updated files directly to the runtime with overwrite-only copies.
echo Existing add-ons, runtime-only files, and CounterStrikeSharp configs will not be deleted.

rem Pass 1: shared game/csgo files except add-ons, gameinfo.gi, and protected cfg/settings.
robocopy "%PAYLOAD_DIR%" "%GAME_DIR%" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /IS /IT /XD "%PAYLOAD_DIR%\addons" "%PAYLOAD_DIR%\cfg\settings" /XF gameinfo.gi >nul
if errorlevel 8 (
    echo ERROR: Shared game payload overlay failed.
    exit /b 1
)

rem Pass 2: shared add-ons; keep the Windows overlay separate and never overwrite user configs.
robocopy "%PAYLOAD_DIR%\addons" "%GAME_DIR%\addons" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /IS /IT /XD "%PAYLOAD_DIR%\addons\windows" "%PAYLOAD_DIR%\addons\counterstrikesharp\configs" >nul
if errorlevel 8 (
    echo ERROR: Shared add-on overlay failed.
    exit /b 1
)

rem Pass 3: flatten the Windows overlay into game/csgo, with the same protected paths.
robocopy "%WINDOWS_OVERLAY%" "%GAME_DIR%" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /IS /IT /XD "%WINDOWS_OVERLAY%\cfg\settings" "%WINDOWS_OVERLAY%\addons\counterstrikesharp\configs" /XF gameinfo.gi >nul
if errorlevel 8 (
    echo ERROR: Windows add-on overlay failed.
    exit /b 1
)

if not exist "%GAME_DIR%\addons\metamod\bin\win64\metamod.2.cs2.dll" (
    echo ERROR: MetaMod binary is missing after overlay.
    exit /b 1
)
if not exist "%GAME_DIR%\addons\counterstrikesharp\dotnet\dotnet.exe" (
    echo ERROR: CounterStrikeSharp Windows runtime is missing after overlay.
    exit /b 1
)
exit /b 0

:MissingCS2
echo ERROR: CS2 was not found: %CS2_EXE%
echo Run install.bat from the repository root first.
set "RC=2"
goto :finish

:MissingGameInfo
echo ERROR: gameinfo.gi was not found: %GAMEINFO%
echo Run install.bat from the repository root first.
set "RC=2"
goto :finish

:finish
echo.
if "%RC%"=="0" echo Result: SUCCESS OR SAFELY SKIPPED
if not "%RC%"=="0" echo Result: FAILED (exit code %RC%)
endlocal & exit /b %RC%
