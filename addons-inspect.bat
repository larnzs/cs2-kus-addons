@echo off
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Inspect-Releases.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo Release inspection finished.
) else (
    echo Release inspection failed.
)
echo.

pause
exit /b %RC%
