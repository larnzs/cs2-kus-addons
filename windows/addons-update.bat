@echo off
setlocal EnableExtensions
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
cd /d "%ROOT_DIR%"

if not exist "%ROOT_DIR%\scripts\Update-Addons.ps1" (
    echo ERROR: scripts\Update-Addons.ps1 was not found.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\Update-Addons.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo Larnz-managed add-on update finished.
) else (
    echo Larnz-managed add-on update failed with code %RC%.
)
exit /b %RC%
