@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Explicit Game Update
cd /d "%~dp0"

set "ROOT_DIR=%~dp0"
set "SERVER_DIR=%ROOT_DIR%server"
set "STEAMCMD=%ROOT_DIR%steamcmd\steamcmd.exe"
set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"
set "APP_MANIFEST=%SERVER_DIR%\steamapps\appmanifest_730.acf"

if not exist "%CS2_EXE%" (
    echo ERROR: CS2 is not installed. Run install.bat first.
    exit /b 1
)
if not exist "%APP_MANIFEST%" (
    echo ERROR: CS2 app manifest was not found. Run install.bat first.
    exit /b 1
)
if not exist "%STEAMCMD%" (
    echo ERROR: SteamCMD was not found. Run install.bat first.
    exit /b 1
)

tasklist /FI "IMAGENAME eq cs2.exe" /FO LIST 2>nul | findstr /I /C:"cs2.exe" >nul
if not errorlevel 1 (
    echo ERROR: A cs2.exe process is running. Stop all CS2 server instances before updating.
    exit /b 1
)

echo Updating CS2 game files through SteamCMD...
"%STEAMCMD%" +force_install_dir "%SERVER_DIR%" +login anonymous +app_update 730 validate +quit
if errorlevel 1 (
    echo ERROR: SteamCMD game update failed.
    exit /b 1
)

call "%ROOT_DIR%win.bat"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo ERROR: Post-update runtime validation failed.
    exit /b %RC%
)
echo CS2 game update and post-update validation completed. The server was not started.
exit /b 0
