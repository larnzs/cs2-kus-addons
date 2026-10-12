@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Update Repository
set "PAUSE_ON_EXIT=1"
if /I "%~1"=="--no-pause" set "PAUSE_ON_EXIT=0"
set "RC=1"
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
cd /d "%ROOT_DIR%"
if errorlevel 1 (
    echo ERROR: Could not enter the repository directory.
    set "RC=1"
    goto :finish
)

git switch integration/kus-monorepo
if errorlevel 1 (
    set "RC=1"
    goto :finish
)

git pull --ff-only origin integration/kus-monorepo
set "RC=%ERRORLEVEL%"

:finish
echo.
if "%RC%"=="0" (
    echo Result: SUCCESS
) else (
    echo Result: FAILED (exit code %RC%)
)
if "%PAUSE_ON_EXIT%"=="1" (
    echo.
    echo Please press any key to exit . . .
    pause >nul
)
endlocal & exit /b %RC%
