@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Initial Install
cd /d "%~dp0"

set "ROOT_DIR=%~dp0"
set "SERVER_DIR=%ROOT_DIR%server"
set "STEAMCMD_DIR=%ROOT_DIR%steamcmd"
set "STEAMCMD=%STEAMCMD_DIR%\steamcmd.exe"
set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"
set "APP_MANIFEST=%SERVER_DIR%\steamapps\appmanifest_730.acf"

echo.
echo ============================================
echo       CS2 KUS Addons - Initial Install
echo ============================================
echo Repository: %ROOT_DIR%
echo Server:     %SERVER_DIR%
echo.

git -C "%ROOT_DIR%" rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: Clone this private Git repository before running install.bat.
    exit /b 1
)
if not exist "%ROOT_DIR%DEPENDENCIES.json" (
    echo ERROR: DEPENDENCIES.json is missing; run this from the repository root.
    exit /b 1
)

if not exist "%STEAMCMD%" (
    echo Downloading SteamCMD...
    if not exist "%STEAMCMD_DIR%\" mkdir "%STEAMCMD_DIR%"
    if errorlevel 1 exit /b 1
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' -OutFile '%STEAMCMD_DIR%\steamcmd.zip' -UseBasicParsing"
    if errorlevel 1 (
        echo ERROR: SteamCMD download failed.
        exit /b 1
    )
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%STEAMCMD_DIR%\steamcmd.zip' -DestinationPath '%STEAMCMD_DIR%' -Force"
    if errorlevel 1 (
        echo ERROR: SteamCMD extraction failed.
        exit /b 1
    )
    del /q "%STEAMCMD_DIR%\steamcmd.zip" >nul 2>&1
)
if not exist "%STEAMCMD%" (
    echo ERROR: steamcmd.exe was not found after extraction.
    exit /b 1
)

if exist "%CS2_EXE%" if exist "%APP_MANIFEST%" goto :game_installed

echo Installing CS2 through SteamCMD (initial install only)...
if not exist "%SERVER_DIR%\" mkdir "%SERVER_DIR%"
if errorlevel 1 exit /b 1
"%STEAMCMD%" +force_install_dir "%SERVER_DIR%" +login anonymous +app_update 730 validate +quit
if errorlevel 1 (
    echo ERROR: SteamCMD failed to install CS2.
    exit /b 1
)
if not exist "%CS2_EXE%" (
    echo ERROR: cs2.exe was not found after SteamCMD completed.
    exit /b 1
)
if not exist "%APP_MANIFEST%" (
    echo ERROR: appmanifest_730.acf was not found after SteamCMD completed.
    exit /b 1
)

:game_installed
call "%ROOT_DIR%win.bat"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo ERROR: Server preparation failed with code %RC%.
    exit /b %RC%
)
echo.
echo Initial installation completed. The server was NOT started.
echo Copy examples\run-template\instance.example.ini to instance.ini, configure it, then launch run.vbs.
exit /b 0
