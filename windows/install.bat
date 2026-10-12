@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Install and Update (no server launch)
set "PAUSE_ON_EXIT=1"
if /I "%~1"=="--no-pause" set "PAUSE_ON_EXIT=0"
set "RC=1"
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
cd /d "%ROOT_DIR%" || goto :finish

set "SERVER_DIR=%ROOT_DIR%\server"
set "STEAMCMD_DIR=%ROOT_DIR%\steamcmd"
set "STEAMCMD=%STEAMCMD_DIR%\steamcmd.exe"
set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"
set "APP_MANIFEST=%SERVER_DIR%\steamapps\appmanifest_730.acf"
set "GAMEINFO=%SERVER_DIR%\game\csgo\gameinfo.gi"

echo.
echo ============================================
echo       CS2 KUS Addons - Install and Update
echo ============================================
echo Repository: %ROOT_DIR%
echo Server:     %SERVER_DIR%
echo This script updates the repo, add-ons and game, deploys add-ons safely,
echo and patches gameinfo.gi. It never launches the CS2 server.
echo.

tasklist /FI "IMAGENAME eq cs2.exe" /FO LIST 2>nul | findstr /I /C:"cs2.exe" >nul
if not errorlevel 1 (
    echo ERROR: A cs2.exe process is running. Stop all CS2 instances before maintenance.
    goto :finish
)

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: Clone this private Git repository before running install.bat.
    goto :finish
)
if not exist "%ROOT_DIR%\DEPENDENCIES.json" (
    echo ERROR: DEPENDENCIES.json is missing. Run this from the repository root.
    goto :finish
)
if not exist "%ROOT_DIR%\scripts\Invoke-RuntimeAddonUpdate.ps1" (
    echo ERROR: scripts\Invoke-RuntimeAddonUpdate.ps1 is missing.
    goto :finish
)

rem Never pull over local edits or unknown files.
git diff --quiet
if errorlevel 1 goto :dirty
git diff --cached --quiet
if errorlevel 1 goto :dirty
for /f "delims=" %%S in ('git status --porcelain --untracked-files=all') do goto :dirty

echo [1/5] Updating repository branch...
call "%ROOT_DIR%\windows\update.bat" --no-pause
if errorlevel 1 (
    echo ERROR: Repository update failed.
    goto :finish
)

echo.
echo [2/5] Checking upstream add-on releases and publishing updates...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\Invoke-RuntimeAddonUpdate.ps1" -RepositoryRoot "%ROOT_DIR%" -Branch "integration/kus-monorepo"
if errorlevel 1 (
    echo ERROR: Add-on update/publish failed.
    goto :finish
)

rem The updater publishes from an isolated worktree; fast-forward this checkout
rem so the deployed payload matches the release commits published to the repo.
git -C "%ROOT_DIR%" pull --ff-only origin integration/kus-monorepo
if errorlevel 1 (
    echo ERROR: Could not pull the newly published add-on payload.
    goto :finish
)

if not exist "%STEAMCMD%" (
    echo.
    echo Downloading SteamCMD...
    if not exist "%STEAMCMD_DIR%\" mkdir "%STEAMCMD_DIR%"
    if errorlevel 1 (
        echo ERROR: Could not create the SteamCMD directory.
        goto :finish
    )
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' -OutFile '%STEAMCMD_DIR%\steamcmd.zip' -UseBasicParsing -ErrorAction Stop"
    if errorlevel 1 (
        echo ERROR: SteamCMD download failed.
        goto :finish
    )
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%STEAMCMD_DIR%\steamcmd.zip' -DestinationPath '%STEAMCMD_DIR%' -Force -ErrorAction Stop"
    if errorlevel 1 (
        echo ERROR: SteamCMD extraction failed.
        goto :finish
    )
    del /q "%STEAMCMD_DIR%\steamcmd.zip" >nul 2>&1
)
if not exist "%STEAMCMD%" (
    echo ERROR: steamcmd.exe is missing.
    goto :finish
)

if not exist "%SERVER_DIR%\" mkdir "%SERVER_DIR%"
if errorlevel 1 (
    echo ERROR: Could not create the server directory.
    goto :finish
)

echo.
echo [3/5] Installing or updating CS2 through SteamCMD...
pushd "%STEAMCMD_DIR%"
start "" /wait "%STEAMCMD%" +force_install_dir "%SERVER_DIR%" +login anonymous +app_update 730 +quit
set "STEAMCMD_RC=%ERRORLEVEL%"
popd
if not "%STEAMCMD_RC%"=="0" (
    echo ERROR: SteamCMD failed with exit code %STEAMCMD_RC%. Check steamcmd\logs\stderr.txt.
    set "RC=%STEAMCMD_RC%"
    goto :finish
)
if not exist "%CS2_EXE%" (
    echo ERROR: CS2 executable was not found after SteamCMD completed.
    goto :finish
)
if not exist "%APP_MANIFEST%" (
    echo ERROR: appmanifest_730.acf was not found after SteamCMD completed.
    goto :finish
)
if not exist "%GAMEINFO%" (
    echo ERROR: gameinfo.gi was not found after SteamCMD completed.
    goto :finish
)

echo.
echo [4/5] Safely overlaying the tracked payload (overwrite only)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\Deploy-Runtime.ps1"
if errorlevel 1 (
    echo ERROR: Safe runtime overlay failed.
    goto :finish
)

echo.
echo [5/5] Patching and verifying the runtime...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\Patch-GameInfo.ps1" -GameInfoPath "%GAMEINFO%"
if errorlevel 1 (
    echo ERROR: gameinfo.gi patch failed.
    goto :finish
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\Test-AddonOverlay.ps1" -VerifyAddons -VerifyRuntime
if errorlevel 1 (
    echo ERROR: Deployed add-on verification failed.
    goto :finish
)

echo.
echo SUCCESS: Repository, add-ons and CS2 are updated; add-ons were safely overlaid.
echo Runtime-only files and existing CounterStrikeSharp configs were not deleted or replaced.
echo The CS2 server was NOT launched.
set "RC=0"
goto :finish

:dirty
echo ERROR: The repository contains local changes or untracked files.
echo Commit or move them before updating; no repository or game files were changed.
set "RC=1"

:finish
echo.
if "%RC%"=="0" (echo Result: SUCCESS) else (echo Result: FAILED ^(exit code %RC%^))
if "%PAUSE_ON_EXIT%"=="1" (
    echo.
    echo Please press any key to exit . . .
    pause >nul
)
endlocal & exit /b %RC%
