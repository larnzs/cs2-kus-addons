@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Prepare and Validate
cd /d "%~dp0"

set "ROOT_DIR=%~dp0"
set "SERVER_DIR=%ROOT_DIR%server"
set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"
set "GAMEINFO=%SERVER_DIR%\game\csgo\gameinfo.gi"
set "METAMOD_DLL=%SERVER_DIR%\game\csgo\addons\metamod\bin\win64\metamod.2.cs2.dll"

echo.
echo ============================================
echo       CS2 KUS Addons - Prepare and Validate
echo ============================================
echo Server: %SERVER_DIR%
echo.

if not exist "%ROOT_DIR%DEPENDENCIES.json" (
    echo ERROR: DEPENDENCIES.json is missing. Run this from the repository root.
    exit /b 1
)
if not exist "%CS2_EXE%" (
    echo ERROR: CS2 is not installed. Run install.bat first.
    exit /b 1
)
if not exist "%GAMEINFO%" (
    echo ERROR: gameinfo.gi is missing. Verify the CS2 installation.
    exit /b 1
)
if not exist "%METAMOD_DLL%" (
    echo ERROR: Windows Metamod binary is missing:
    echo        %METAMOD_DLL%
    exit /b 1
)
if not exist "%SERVER_DIR%\game\csgo\addons\multiaddonmanager\bin\multiaddonmanager.dll" (
    echo ERROR: KUS MultiAddonManager binary is missing.
    exit /b 1
)
if not exist "%SERVER_DIR%\game\csgo\addons\serverlistplayersfix_mm\bin\win64\serverlistplayersfix_mm.dll" (
    echo ERROR: KUS ServerListPlayersFix binary is missing.
    exit /b 1
)
if not exist "%SERVER_DIR%\game\csgo\addons\MovementUnlocker\bin\win64\MovementUnlocker.dll" (
    echo ERROR: KUS MovementUnlocker binary is missing.
    exit /b 1
)
if not exist "%SERVER_DIR%\game\csgo\addons\cs2fixes-rampbugfix\bin\win64\cs2fixes-rampbugfix.dll" (
    echo ERROR: KUS RampbugFix binary is missing.
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%scripts\Patch-GameInfo.ps1" -GameInfoPath "%GAMEINFO%"
if errorlevel 1 (
    echo ERROR: Could not patch gameinfo.gi.
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%scripts\Test-AddonOverlay.ps1" -VerifyAddons
if errorlevel 1 (
    echo ERROR: Managed runtime verification failed.
    exit /b 1
)

echo.
echo SUCCESS: server\game\csgo is the canonical runtime path.
echo No plugin copying, deletion, SteamCMD update, Git pull, or server launch was performed.
exit /b 0
