@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Explicit Game Update
set "PAUSE_ON_EXIT=1"
if /I "%~1"=="--no-pause" set "PAUSE_ON_EXIT=0"
set "RC=1"
cd /d "%~dp0"

set "ROOT_DIR=%~dp0"
set "SERVER_DIR=%ROOT_DIR%server"
set "STEAMCMD=%ROOT_DIR%steamcmd\steamcmd.exe"
set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"
set "APP_MANIFEST=%SERVER_DIR%\steamapps\appmanifest_730.acf"

if not exist "%CS2_EXE%" (
    echo ERROR: CS2 is not installed. Run install.bat first.
    goto :finish
)
if not exist "%APP_MANIFEST%" (
    echo ERROR: CS2 app manifest was not found. Run install.bat first.
    goto :finish
)
if not exist "%STEAMCMD%" (
    echo ERROR: SteamCMD was not found. Run install.bat first.
    goto :finish
)

tasklist /FI "IMAGENAME eq cs2.exe" /FO LIST 2>nul | findstr /I /C:"cs2.exe" >nul
if not errorlevel 1 (
    echo ERROR: A cs2.exe process is running. Stop all CS2 server instances before updating.
    goto :finish
)

echo Updating CS2 game files through SteamCMD...
"%STEAMCMD%" +force_install_dir "%SERVER_DIR%" +login anonymous +app_update 730 validate +quit
if errorlevel 1 (
    echo ERROR: SteamCMD game update failed.
    goto :finish
)

call "%ROOT_DIR%win.bat" --no-pause
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo ERROR: Post-update runtime validation failed with code %RC%.
    goto :finish
)
echo CS2 game update and post-update validation completed. The server was not started.
set "RC=0"

:finish
echo.
if "%RC%"=="0" (
    echo Result: SUCCESS
) else (
    echo Result: FAILED ^(exit code %RC%^)
)
if "%PAUSE_ON_EXIT%"=="1" (
    echo.
    echo Press any key to close this window . . .
    pause >nul
)
endlocal & exit /b %RC%
