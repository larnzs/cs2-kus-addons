@echo off
setlocal EnableExtensions EnableDelayedExpansion

title CS2 KUS Addons Update
cd /d "%~dp0"

echo.
echo ============================================
echo       CS2 KUS Addons - Full Update
echo ============================================
echo.

echo [1/3] Updating cs2-kus-addons repository...
git pull --ff-only
if errorlevel 1 (
    echo.
    echo ERROR: cs2-kus-addons git pull failed.
    echo Make sure the working tree is clean and this folder is a Git clone.
    pause
    exit /b 1
)

set "KUS_ROOT="
for /f "usebackq eol=; tokens=* delims=" %%S in ("%~dp0win.ini") do set "%%S"

if not defined KUS_ROOT (
    echo ERROR: KUS_ROOT is not configured in win.ini
    pause
    exit /b 1
)

if "%KUS_ROOT:~1,1%"==":" (
    for %%I in ("%KUS_ROOT%") do set "KUS_ROOT=%%~fI"
) else (
    for %%I in ("%~dp0%KUS_ROOT%") do set "KUS_ROOT=%%~fI"
)

if not exist "%KUS_ROOT%\win.bat" (
    echo ERROR: KUS base was not found:
    echo        %KUS_ROOT%
    echo.
    echo Edit KUS_ROOT in win.ini.
    pause
    exit /b 1
)

echo.
echo [2/3] Updating KUS base repository...
git -C "%KUS_ROOT%" pull --ff-only
if errorlevel 1 (
    echo.
    echo ERROR: KUS git pull failed.
    echo Fix the KUS repository and run this update again.
    pause
    exit /b 1
)

echo.
echo [3/3] Updating CS2 and installing the current addon layer...
echo The dedicated server will NOT be started by this script.
call "%~dp0win.bat"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo.
    echo ERROR: win.bat failed with exit code %RC%.
    pause
    exit /b %RC%
)

echo.
echo Full update completed. The server remains stopped until the VBS supervisor starts it.
pause
exit /b 0
