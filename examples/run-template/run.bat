@echo off
setlocal EnableExtensions DisableDelayedExpansion

title CS2 Instance Runner Template
set "INSTANCE_DIR=%~dp0"
if "%INSTANCE_DIR:~-1%"=="\" set "INSTANCE_DIR=%INSTANCE_DIR:~0,-1%"

set "INI_FILE=%INSTANCE_DIR%\instance.ini"
if not exist "%INI_FILE%" (
    echo ERROR: Missing instance configuration:
    echo        %INI_FILE%
    echo Copy instance.example.ini to instance.ini and edit it first.
    pause
    exit /b 2
)

for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%INI_FILE%") do set "%%A=%%B"

if not defined SERVER_DIR (
    echo ERROR: SERVER_DIR is missing in instance.ini.
    pause
    exit /b 2
)
if "%SERVER_DIR:~0,2%"=="\\" goto :server_path_ready
if "%SERVER_DIR:~1,1%"==":" goto :server_path_ready
for %%I in ("%INSTANCE_DIR%\%SERVER_DIR%") do set "SERVER_DIR=%%~fI"
:server_path_ready

if not defined CUSTOM_FOLDER set "CUSTOM_FOLDER=aim"
if "%CUSTOM_FOLDER:~0,2%"=="\\" (
    for %%I in ("%CUSTOM_FOLDER%") do set "CUSTOM_DIR=%%~fI"
) else if "%CUSTOM_FOLDER:~1,1%"==":" (
    for %%I in ("%CUSTOM_FOLDER%") do set "CUSTOM_DIR=%%~fI"
) else (
    for %%I in ("%INSTANCE_DIR%\%CUSTOM_FOLDER%") do set "CUSTOM_DIR=%%~fI"
)

if not defined IP set "IP=0.0.0.0"
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

set "GAME_DIR=%SERVER_DIR%\game\csgo"
set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"

if not exist "%CS2_EXE%" (
    echo ERROR: cs2.exe was not found:
    echo        %CS2_EXE%
    echo Run the repository's install.bat first.
    pause
    exit /b 2
)

if not exist "%GAME_DIR%\" (
    echo ERROR: CS2 game directory was not found:
    echo        %GAME_DIR%
    pause
    exit /b 2
)

set "AUTH_ARGS="
if defined API_KEY set "AUTH_ARGS=-authkey %API_KEY%"
set "GSLT_ARGS="
if defined STEAM_ACCOUNT set "GSLT_ARGS=+sv_setsteamaccount %STEAM_ACCOUNT%"
set "WORKSHOP_ARGS="
if defined WORKSHOP_COLLECTION set "WORKSHOP_ARGS=+host_workshop_collection %WORKSHOP_COLLECTION%"

echo.
echo ============================================
echo       CS2 Instance Runner Template
echo ============================================
echo Server: %SERVER_DIR%
echo Custom: %CUSTOM_DIR%
echo Address: %IP%  Port: %PORT%
echo Map: %MAP%
echo The game is NOT updated by this runner.
echo.

if not exist "%CUSTOM_DIR%\" (
    echo WARNING: Custom files folder does not exist:
    echo          %CUSTOM_DIR%
    echo Custom file sync will be skipped.
)

:loop
echo.
echo [%date% %time%] Syncing custom files...

if exist "%CUSTOM_DIR%\cfg\" (
    robocopy "%CUSTOM_DIR%\cfg" "%GAME_DIR%\cfg" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 >nul
    if errorlevel 8 goto :sync_failed
)

if exist "%CUSTOM_DIR%\addons\" (
    robocopy "%CUSTOM_DIR%\addons" "%GAME_DIR%\addons" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 >nul
    if errorlevel 8 goto :sync_failed
)

echo [%date% %time%] Starting CS2 instance on port %PORT%...

start "" /wait "%CS2_EXE%" ^
 -dedicated -console -debug -condebug -conclearlog -usercon -disable_workshop_command_filtering ^
 +game_type 0 +game_mode 0 +mapgroup %MAPGROUP% +map %MAP% %WORKSHOP_ARGS% ^
 -port %PORT% -ip %BIND_IP% +net_public_adr %IP% ^
 -tickrate %TICKRATE% +sv_maxplayers %MAXPLAYERS% +sv_visiblemaxplayers %MAXPLAYERS% ^
 %AUTH_ARGS% %GSLT_ARGS% ^
 +sv_lan %LAN% +sv_password "%SERVER_PASSWORD%" +rcon_password "%RCON_PASSWORD%" ^
 +exec %EXEC%

set "SERVER_EXIT=%ERRORLEVEL%"
echo WARNING: CS2 exited with code %SERVER_EXIT%.
echo Restarting this instance in 5 seconds...
timeout /t 5 /nobreak >nul
goto :loop

:sync_failed
echo ERROR: Custom files sync failed. Check the custom folder paths and permissions.
echo Retrying the sync in 10 seconds...
timeout /t 10 /nobreak >nul
goto :loop
