@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if not exist "%~dp0scripts\Update-Addons.ps1" (
    echo ERROR: scripts\Update-Addons.ps1 was not found.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Update-Addons.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo Larnz-managed add-on update finished.
) else (
    echo Larnz-managed add-on update failed with code %RC%.
)
exit /b %RC%
