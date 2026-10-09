@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if not exist "%~dp0scripts\Inspect-Releases.ps1" (
    echo ERROR: scripts\Inspect-Releases.ps1 was not found.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Inspect-Releases.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo Release inspection finished.
) else (
    echo Release inspection failed with code %RC%.
)
exit /b %RC%
