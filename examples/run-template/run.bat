@echo off
setlocal EnableExtensions DisableDelayedExpansion

title CS2 Instance Runner
set "PAUSE_ON_EXIT=0"
set "RC=2"

:parse_args
if "%~1"=="" goto :args_done
if /I "%~1"=="--pause" set "PAUSE_ON_EXIT=1"
shift
goto :parse_args

:args_done
set "INSTANCE_DIR=%~dp0"
if "%INSTANCE_DIR:~-1%"=="\" set "INSTANCE_DIR=%INSTANCE_DIR:~0,-1%"
set "INI_FILE=%INSTANCE_DIR%\instance.ini"
if not exist "%INI_FILE%" goto :MissingIni

for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%INI_FILE%") do set "%%A=%%B"
if not defined SERVER_DIR set "SERVER_DIR=..\..\server"
if "%SERVER_DIR:~0,2%"=="\\" goto :resolve_server
if "%SERVER_DIR:~1,1%"==":" goto :resolve_server
for %%I in ("%INSTANCE_DIR%\%SERVER_DIR%") do set "SERVER_DIR=%%~fI"
:resolve_server

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
set "LOCK_DIR=%TEMP%\CS2-KUS-Maintenance.lock"
set "CS2_LOCK_DIR=%LOCK_DIR%"

if not exist "%CS2_EXE%" goto :MissingCS2
if not exist "%GAMEINFO%" goto :MissingGameInfo

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
echo Server:  %SERVER_DIR%
echo Address: %IP%  Port: %PORT%
echo Map:     %MAP%
echo.

rem If update.bat is deploying shared files, wait before opening cs2.exe.
call :WaitForMaintenance

rem Apply this Instance's optional cfg/addons overlay before every server start.
call :SyncCustomFiles
if errorlevel 1 goto :CustomSyncFailed

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
echo WARNING: CS2 exited with code %SERVER_EXIT%; returning to the VBS anti-crash loop.
set "RC=100"
goto :finish

:WaitForMaintenance
if not exist "%LOCK_DIR%\" exit /b 0
if not exist "%LOCK_DIR%\owner.pid" goto :CheckIncompleteLock
set "LOCK_OWNER_PID="
set /p LOCK_OWNER_PID=<"%LOCK_DIR%\owner.pid"
if not defined LOCK_OWNER_PID goto :CheckIncompleteLock
set "CS2_LOCK_OWNER_PID=%LOCK_OWNER_PID%"
powershell -NoProfile -Command "if(Get-Process -Id $env:CS2_LOCK_OWNER_PID -ErrorAction SilentlyContinue){exit 0}else{exit 1}" >nul 2>&1
if errorlevel 1 goto :RemoveStaleLock
timeout /t 1 /nobreak >nul
goto :WaitForMaintenance

:CheckIncompleteLock
powershell -NoProfile -Command "$d=Get-Item -LiteralPath $env:CS2_LOCK_DIR -ErrorAction SilentlyContinue; if($d -and ((Get-Date)-$d.CreationTime).TotalSeconds -gt 30){exit 1}else{exit 0}" >nul 2>&1
if errorlevel 1 goto :RemoveStaleLock
timeout /t 1 /nobreak >nul
goto :WaitForMaintenance

:RemoveStaleLock
echo [%date% %time%] Removing a stale maintenance lock before launching CS2.
rd /s /q "%LOCK_DIR%" >nul 2>&1
goto :WaitForMaintenance

:SyncCustomFiles
if not exist "%CUSTOM_DIR%\" (
    echo [%date% %time%] Custom folder not found; skipping optional overrides: "%CUSTOM_DIR%"
    exit /b 0
)

echo [%date% %time%] Syncing custom files from "%CUSTOM_DIR%"
if exist "%CUSTOM_DIR%\cfg\" (
    robocopy "%CUSTOM_DIR%\cfg" "%GAME_DIR%\cfg" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /IS /IT >nul
    if errorlevel 8 exit /b 1
)
if exist "%CUSTOM_DIR%\addons\" (
    rem Keep live CounterStrikeSharp configs server-managed. Existing files are never purged.
    robocopy "%CUSTOM_DIR%\addons" "%GAME_DIR%\addons" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /IS /IT /XD "%CUSTOM_DIR%\addons\counterstrikesharp\configs" "%CUSTOM_DIR%\addons\windows\addons\counterstrikesharp\configs" >nul
    if errorlevel 8 exit /b 1
)
exit /b 0

:CustomSyncFailed
echo ERROR: A custom-folder overlay failed. CS2 will not be launched from a partially applied override.
set "RC=3"
goto :finish

:MissingIni
echo ERROR: Missing instance configuration: %INI_FILE%
echo Copy instance.example.ini to instance.ini and edit it first.
set "RC=2"
goto :finish

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
if "%RC%"=="100" echo Result: CS2_EXITED (VBS will restart this launch-only batch after 100 ms)
if not "%RC%"=="100" echo Result: FAILED (exit code %RC%)
if "%PAUSE_ON_EXIT%"=="1" (
    echo.
    echo Press any key to close this window . . .
    pause >nul
)
endlocal & exit /b %RC%
