@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Inspect Releases
set "RC=1"
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
cd /d "%ROOT_DIR%"
if errorlevel 1 (
    echo ERROR: Could not enter the repository directory.
    set "RC=1"
    goto :finish
)

if not exist "%ROOT_DIR%\scripts\Inspect-Releases.ps1" (
    echo ERROR: scripts\Inspect-Releases.ps1 was not found.
    set "RC=1"
    goto :finish
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\Inspect-Releases.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo Release inspection finished.
) else (
    echo Release inspection failed (exit code %RC%).
)

:finish
echo.
if "%RC%"=="0" (echo Result: SUCCESS) else (echo Result: FAILED ^(exit code %RC%^))
echo.
echo Please press any key to exit . . .
pause >nul
endlocal & exit /b %RC%
