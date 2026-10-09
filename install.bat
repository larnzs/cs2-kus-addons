@echo off
setlocal EnableExtensions EnableDelayedExpansion
title CS2 KUS Addons - One-Repository Installer
cd /d "%~dp0"

set "ROOT_DIR=%~dp0"
set "CONFIG_FILE=%ROOT_DIR%win.ini"
set "SERVER_REL=server"

if not exist "%CONFIG_FILE%" (
    echo ERROR: win.ini is missing.
    exit /b 1
)
for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
    if /I "%%A"=="SERVER_DIR" set "SERVER_REL=%%B"
)
for %%I in ("%ROOT_DIR%%SERVER_REL%") do set "SERVER_DIR=%%~fI"

set "STEAMCMD_DIR=%ROOT_DIR%steamcmd"
set "STEAMCMD=%STEAMCMD_DIR%\steamcmd.exe"
set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"
set "APP_MANIFEST=%SERVER_DIR%\steamapps\appmanifest_730.acf"

echo.
echo ============================================
echo       CS2 KUS Addons - One-Repo Install
echo ============================================
echo Repository: %ROOT_DIR%
echo Server:     %SERVER_DIR%
echo.

git -C "%ROOT_DIR%" rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: Run this script from a cloned cs2-kus-addons repository.
    exit /b 1
)

if not exist "%STEAMCMD%" (
    echo Downloading SteamCMD...
    if not exist "%STEAMCMD_DIR%\" mkdir "%STEAMCMD_DIR%"
    if errorlevel 1 exit /b 1
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' -OutFile '%STEAMCMD_DIR%\steamcmd.zip' -UseBasicParsing"
    if errorlevel 1 exit /b 1
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%STEAMCMD_DIR%\steamcmd.zip' -DestinationPath '%STEAMCMD_DIR%' -Force"
    if errorlevel 1 exit /b 1
    del /q "%STEAMCMD_DIR%\steamcmd.zip" >nul 2>&1
)
if not exist "%STEAMCMD%" (
    echo ERROR: SteamCMD extraction did not produce steamcmd.exe.
    exit /b 1
)

if exist "%CS2_EXE%" if exist "%APP_MANIFEST%" goto :game_installed

echo Installing the CS2 dedicated server through SteamCMD (initial install only)...
if not exist "%SERVER_DIR%\" mkdir "%SERVER_DIR%"
if errorlevel 1 exit /b 1
"%STEAMCMD%" +force_install_dir "%SERVER_DIR%" +login anonymous +app_update 730 +quit
if errorlevel 1 exit /b 1
if not exist "%CS2_EXE%" (
    echo ERROR: cs2.exe was not found after SteamCMD completed.
    exit /b 1
)
if not exist "%APP_MANIFEST%" (
    echo ERROR: appmanifest_730.acf was not found after SteamCMD completed.
    exit /b 1
)

:game_installed
echo CS2 files are present. The installer will not run SteamCMD on ordinary restarts.
call "%ROOT_DIR%win.bat"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo ERROR: Server preparation failed with code %RC%.
    exit /b %RC%
)
echo.
echo Initial installation completed. The server was not started.
echo Configure examples\run-template\instance.ini and use run.vbs to launch it.
exit /b 0
