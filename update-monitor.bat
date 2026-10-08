@echo off
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Update-CS2UpdateMonitor.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo CS2 Update Monitor update finished.
) else (
    echo CS2 Update Monitor update failed.
)
echo.

pause
exit /b %RC%
