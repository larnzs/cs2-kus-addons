@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Update Repository
set "PAUSE_ON_EXIT=1"
if /I "%~1"=="--no-pause" set "PAUSE_ON_EXIT=0"
set "RC=1"
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
cd /d "%ROOT_DIR%"

tasklist /FI "IMAGENAME eq cs2.exe" /FO LIST 2>nul | findstr /I /C:"cs2.exe" >nul
if not errorlevel 1 (
    echo ERROR: A cs2.exe process is running. Stop all CS2 instances before pulling and deploying.
    set "RC=1"
    goto :finish
)

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: This directory is not a Git checkout. Clone the private repository first.
    goto :finish
)
git diff --quiet
if errorlevel 1 goto :dirty
git diff --cached --quiet
if errorlevel 1 goto :dirty
for /f "delims=" %%A in ('git status --porcelain') do goto :dirty

echo Pulling the unified repository (fast-forward only)...
git pull --ff-only
if errorlevel 1 (
    echo ERROR: git pull failed. Check credentials, branch, network, and repository state.
    set "RC=1"
    goto :finish
)

rem Re-apply runtime and the KUS-compatible gameinfo.gi patch after repository updates.
call "%ROOT_DIR%\windows\win.bat" --no-pause
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo ERROR: Post-pull server preparation failed with code %RC%.
goto :finish

:dirty
echo ERROR: The repository has local changes or untracked files.
echo Commit or stash them before updating. Ignored downloaded game files are not affected.
set "RC=1"
goto :finish

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
