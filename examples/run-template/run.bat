@echo off
setlocal EnableExtensions DisableDelayedExpansion

title CS2 Instance Runner
set "PAUSE_ON_EXIT=1"
set "SUPERVISED_ONCE=0"
set "RC=2"

:parse_args
if "%~1"=="" goto :args_done
if /I "%~1"=="--no-pause" set "PAUSE_ON_EXIT=0"
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
set "METAMOD_DLL=%GAME_DIR%\addons\metamod\bin\win64\metamod.2.cs2.dll"

if not exist "%CS2_EXE%" (
    echo ERROR: CS2 was not found: %CS2_EXE%
    echo Run install.bat from the repository root first.
    set "RC=2"
    goto :finish
)
if not exist "%GAMEINFO%" (
    echo ERROR: gameinfo.gi was not found: %GAMEINFO%
    echo Run install.bat or win.bat from the repository root first.
    set "RC=2"
    goto :finish
)
if not exist "%METAMOD_DLL%" (
    echo ERROR: Windows Metamod binary was not found: %METAMOD_DLL%
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
echo This runner does not update Git, plugins, or CS2.
echo.

if not exist "%CUSTOM_DIR%\" (
    echo WARNING: Custom files folder does not exist: %CUSTOM_DIR%
    echo Custom file sync will be skipped.
)
if "%LAN%"=="0" if not defined STEAM_ACCOUNT echo WARNING: STEAM_ACCOUNT is empty; the public server may not register.
if "%LAN%"=="0" if not defined RCON_PASSWORD echo WARNING: RCON_PASSWORD is empty.

:loop
echo.
echo [%date% %time%] Syncing optional instance overrides...
if exist "%CUSTOM_DIR%\cfg\" (
    robocopy "%CUSTOM_DIR%\cfg" "%GAME_DIR%\cfg" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 >nul
    if errorlevel 8 goto :sync_failed
)
if exist "%CUSTOM_DIR%\addons\" (
    rem Keep CounterStrikeSharp configs user-managed; do not overlay them from CUSTOM_FOLDER.
    robocopy "%CUSTOM_DIR%\addons" "%GAME_DIR%\addons" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XD "%CUSTOM_DIR%\addons\counterstrikesharp\configs" "%CUSTOM_DIR%\addons\windows\addons\counterstrikesharp\configs" >nul
    if errorlevel 8 goto :sync_failed
)

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

if "%SUPERVISED_ONCE%"=="1" (
    echo Returning control to run.vbs for maintenance before restarting CS2.
    set "RC=0"
    goto :finish
)

echo Restarting this instance in 5 seconds. Close run.vbs/run.bat to stop supervision.
timeout /t 5 /nobreak >nul
goto :loop

:sync_failed
echo ERROR: Optional instance override sync failed. Check paths and permissions.
if "%SUPERVISED_ONCE%"=="1" (
    set "RC=3"
    goto :finish
)
echo Retrying in 10 seconds...
timeout /t 10 /nobreak >nul
goto :loop

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
