@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Prepare and Deploy
set "PAUSE_ON_EXIT=1"
if /I "%~1"=="--no-pause" set "PAUSE_ON_EXIT=0"
set "RC=1"
cd /d "%~dp0"
set "ROOT_DIR=%~dp0"
set "PAYLOAD_DIR=%ROOT_DIR%game\csgo"
set "SERVER_DIR=%ROOT_DIR%server"
set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"
set "GAMEINFO=%SERVER_DIR%\game\csgo\gameinfo.gi"
echo.
echo ============================================
echo       CS2 KUS Addons - Prepare and Deploy
echo ============================================
echo Tracked payload: %PAYLOAD_DIR%
echo Installed game:  %SERVER_DIR%
echo Runtime target:  %SERVER_DIR%\game\csgo
echo.
if not exist "%ROOT_DIR%DEPENDENCIES.json" (echo ERROR: DEPENDENCIES.json is missing.& goto :finish)
if not exist "%PAYLOAD_DIR%\addons\" (echo ERROR: Tracked payload is missing from game\csgo.& goto :finish)
if not exist "%CS2_EXE%" (echo ERROR: CS2 is not installed. Run install.bat first.& goto :finish)
if not exist "%GAMEINFO%" (echo ERROR: gameinfo.gi is missing. Run install.bat/SteamCMD first.& goto :finish)
if not exist "%PAYLOAD_DIR%\addons\windows\addons\counterstrikesharp\dotnet\dotnet.exe" (
    echo ERROR: CounterStrikeSharp Windows with-runtime payload is missing.
    echo Run addons-update.bat -Only CounterStrikeSharp after updating this checkout.
    goto :finish
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%scripts\Deploy-Runtime.ps1"
if errorlevel 1 (echo ERROR: Payload deployment failed.& goto :finish)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%scripts\Patch-GameInfo.ps1" -GameInfoPath "%GAMEINFO%"
if errorlevel 1 (echo ERROR: Could not patch the installed gameinfo.gi.& goto :finish)
if not exist "%SERVER_DIR%\game\csgo\addons\metamod\bin\win64\metamod.2.cs2.dll" (echo ERROR: Windows Metamod binary is missing after deployment.& goto :finish)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%scripts\Test-AddonOverlay.ps1" -VerifyAddons -VerifyRuntime
if errorlevel 1 (echo ERROR: Deployed runtime verification failed.& goto :finish)
echo.
echo SUCCESS: game\csgo payload deployed and gameinfo.gi patched.
echo No Git pull, SteamCMD update, or server launch was performed.
set "RC=0"
:finish
echo.
if "%RC%"=="0" (echo Result: SUCCESS) else (echo Result: FAILED ^(exit code %RC%^))
if "%PAUSE_ON_EXIT%"=="1" (echo. & echo Press any key to close this window . . . & pause >nul)
endlocal & exit /b %RC%