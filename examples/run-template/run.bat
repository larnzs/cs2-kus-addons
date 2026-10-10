@echo off
setlocal EnableExtensions DisableDelayedExpansion

title CS2 Instance Runner
set "PAUSE_ON_EXIT=1"
set "SUPERVISED_ONCE=0"
set "POST_EXIT=0"
set "RC=2"

:parse_args
if "%~1"=="" goto :args_done
if /I "%~1"=="--no-pause" set "PAUSE_ON_EXIT=0"
rem Kept for compatibility with older run.vbs copies. Maintenance now belongs to this batch.
if /I "%~1"=="--supervised" set "SUPERVISED_ONCE=1"
shift
goto :parse_args

:args_done
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

if not defined CUSTOM_FOLDER set "CUSTOM_FOLDER=aim"
if "%CUSTOM_FOLDER:~0,2%"=="\\" (
    for %%I in ("%CUSTOM_FOLDER%") do set "CUSTOM_DIR=%%~fI"
) else if "%CUSTOM_FOLDER:~1,1%"==":" (
    for %%I in ("%CUSTOM_FOLDER%") do set "CUSTOM_DIR=%%~fI"
) else (
    for %%I in ("%INSTANCE_DIR%\%CUSTOM_FOLDER%") do set "CUSTOM_DIR=%%~fI"
)

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

if not exist "%REPO_ROOT%\DEPENDENCIES.json" (
    echo ERROR: Could not resolve the cs2-kus-addons repository root.
    echo Resolved path: %REPO_ROOT%
    set "RC=2"
    goto :finish
)
if not exist "%CS2_EXE%" (
    echo ERROR: CS2 was not found: %CS2_EXE%
    echo Run install.bat from the repository root first.
    set "RC=2"
    goto :finish
)
if not exist "%GAMEINFO%" (
    echo ERROR: gameinfo.gi was not found: %GAMEINFO%
    echo Run install.bat from the repository root first.
    set "RC=2"
    goto :finish
)
if not exist "%STEAMCMD%" (
    echo ERROR: SteamCMD was not found: %STEAMCMD%
    echo Run install.bat from the repository root first.
    set "RC=2"
    goto :finish
)
if not exist "%PAYLOAD_DIR%\addons\" (
    echo ERROR: Tracked add-on payload is missing: %PAYLOAD_DIR%\addons
    set "RC=2"
    goto :finish
)
if not exist "%WINDOWS_OVERLAY%\addons\" (
    echo ERROR: Windows add-on overlay is missing: %WINDOWS_OVERLAY%\addons
    set "RC=2"
    goto :finish
)

set "AUTH_ARGS="
if defined API_KEY set "AUTH_ARGS=-authkey %API_KEY%"
set "GSLT_ARGS="
if defined STEAM_ACCOUNT set "GSLT_ARGS=+sv_setsteamaccount %STEAM_ACCOUNT%"
set "WORKSHOP_ARGS="
if defined WORKSHOP_COLLECTION set "WORKSHOP_ARGS=+host_workshop_collection %WORKSHOP_COLLECTION%"
set "PUBLIC_ARGS="
if defined IP set "PUBLIC_ARGS=+net_public_adr %IP%"

echo.
echo ============================================
echo       CS2 Instance Runner
echo ============================================
echo Repository: %REPO_ROOT%
echo Server:     %SERVER_DIR%
echo Custom:     %CUSTOM_DIR%
echo Address:    %IP%  Port: %PORT%
echo Map:        %MAP%
echo Maintenance: in-runner, serialized, non-destructive overlay
echo Add-on source: private repository payload published by the remote updater workflow
echo.

if not exist "%CUSTOM_DIR%\" (
    echo WARNING: Custom files folder does not exist: %CUSTOM_DIR%
    echo Custom file sync will be skipped.
)
if "%LAN%"=="0" if not defined STEAM_ACCOUNT echo WARNING: STEAM_ACCOUNT is empty; the public server may not register.
if "%LAN%"=="0" if not defined RCON_PASSWORD echo WARNING: RCON_PASSWORD is empty.

:main_loop
call :RunMaintenance
if errorlevel 1 goto :maintenance_retry

set "POST_EXIT=0"
call :SyncOverrides
if errorlevel 1 goto :sync_failed

echo.
echo [%date% %time%] Starting CS2 on port %PORT%...
start "" /wait "%CS2_EXE%" ^
 -dedicated -console -debug -condebug -conclearlog -usercon -disable_workshop_command_filtering ^
 +game_type 0 +game_mode 0 +mapgroup %MAPGROUP% +map %MAP% %WORKSHOP_ARGS% ^
 -port %PORT% -ip %BIND_IP% %PUBLIC_ARGS% ^
 -tickrate %TICKRATE% +sv_maxplayers %MAXPLAYERS% +sv_visiblemaxplayers %MAXPLAYERS% ^
 %AUTH_ARGS% %GSLT_ARGS% ^
 +sv_lan %LAN% +sv_password "%SERVER_PASSWORD%" +rcon_password "%RCON_PASSWORD%" ^
 +exec %EXEC%

set "SERVER_EXIT=%ERRORLEVEL%"
echo WARNING: CS2 exited with code %SERVER_EXIT%.
set "POST_EXIT=1"
goto :main_loop

:maintenance_retry
echo.
echo ERROR: Maintenance did not complete. This instance will remain stopped and retry in 60 seconds.
timeout /t 60 /nobreak >nul
goto :main_loop

:sync_failed
echo ERROR: Optional instance override sync failed. Check paths and permissions.
echo The server was not started; retrying in 60 seconds.
timeout /t 60 /nobreak >nul
goto :main_loop

:RunMaintenance
call :AcquireLock
call :IsRecentSuccess
if not errorlevel 1 (
    echo [%date% %time%] Shared maintenance ran recently; skipping duplicate update.
    call :ReleaseLock
    exit /b 0
)

if "%POST_EXIT%"=="1" goto :WaitForAllCS2
call :AnyCS2Running
if not errorlevel 1 goto :SkipStartupMaintenance
goto :DoMaintenance

:WaitForAllCS2
call :AnyCS2Running
if errorlevel 1 goto :DoMaintenance
echo [%date% %time%] Another CS2 instance is still using the shared install.
echo Updates are paused until all cs2.exe processes exit; no runtime files are being changed.
timeout /t 5 /nobreak >nul
goto :WaitForAllCS2

:SkipStartupMaintenance
echo [%date% %time%] Another CS2 instance is active. Skipping shared-file maintenance on startup.
echo No game, add-on, or custom override files will be changed while it is running.
call :ReleaseLock
exit /b 0

:DoMaintenance
call :UpdateRepository
if errorlevel 1 goto :MaintenanceFailed
call :UpdateGame
if errorlevel 1 goto :MaintenanceFailed
call :PatchGameInfo
if errorlevel 1 goto :MaintenanceFailed
call :OverlayPayload
if errorlevel 1 goto :MaintenanceFailed

> "%LAST_SUCCESS%" echo Shared maintenance completed at %date% %time%
echo [%date% %time%] Maintenance completed successfully.
call :ReleaseLock
exit /b 0

:MaintenanceFailed
echo ERROR: Maintenance failed. The server will remain stopped.
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
if not defined LOCK_OWNER_PID goto :WaitForLock
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

:SyncOverrides
call :AnyCS2Running
if not errorlevel 1 (
    echo Another CS2 instance is active; skipping this Instance's shared cfg/addons overrides.
    echo Shared runtime files will not be touched while that process is running.
    exit /b 0
)

echo.
echo [%date% %time%] Syncing optional instance overrides while the shared game is idle...
if exist "%CUSTOM_DIR%\cfg\" (
    robocopy "%CUSTOM_DIR%\cfg" "%GAME_DIR%\cfg" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /IS /IT >nul
    if errorlevel 8 exit /b 1
)
if exist "%CUSTOM_DIR%\addons\" (
    rem CSS config files remain server-managed and must not be overwritten by per-instance overrides.
    robocopy "%CUSTOM_DIR%\addons" "%GAME_DIR%\addons" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /IS /IT /XD "%CUSTOM_DIR%\addons\counterstrikesharp\configs" "%CUSTOM_DIR%\addons\windows\addons\counterstrikesharp\configs" >nul
    if errorlevel 8 exit /b 1
)
exit /b 0

:finish
echo.
if "%RC%"=="0" (
    echo Result: SUCCESS
) else (
    echo Result: FAILED (exit code %RC%)
)
if "%PAUSE_ON_EXIT%"=="1" (
    echo.
    echo Press any key to close this window . . .
    pause >nul
)
endlocal & exit /b %RC%
