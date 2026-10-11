@echo off
setlocal EnableExtensions
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
cd /d "%ROOT_DIR%"

if not exist "%ROOT_DIR%\scripts\Inspect-Releases.ps1" (
    echo ERROR: scripts\Inspect-Releases.ps1 was not found.
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\Inspect-Releases.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo Release inspection finished.
) else (
    echo Release inspection failed with code %RC%.
)
exit /b %RC%
