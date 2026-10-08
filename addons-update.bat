@echo off
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Update-Addons.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo Add-on update finished.
) else (
    echo Add-on update failed.
)
echo.

pause
exit /b %RC%
