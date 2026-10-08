@echo off
setlocal EnableExtensions EnableDelayedExpansion

title CS2 KUS Addons - Repository Update
cd /d "%~dp0"

echo.
echo ============================================
echo    CS2 KUS Addons - Repository Update
echo ============================================
echo.

git -C "%~dp0." rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: This folder is not a Git clone of cs2-kus-addons.
    pause
    exit /b 1
)

set "KUS_ROOT="
for /f "usebackq eol=; tokens=* delims=" %%S in ("%~dp0win.ini") do set "%%S"

if not defined KUS_ROOT (
    echo ERROR: KUS_ROOT is not configured in win.ini.
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
    echo Run install.bat first.
    pause
    exit /b 1
)

git -C "%KUS_ROOT%" rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: KUS_ROOT is not a Git working tree:
    echo        %KUS_ROOT%
    pause
    exit /b 1
)

rem Check both working trees before pulling either repository.
set "OWN_DIRTY="
for /f "delims=" %%S in ('git -C "%~dp0." status --porcelain') do set "OWN_DIRTY=1"
if defined OWN_DIRTY (
    echo ERROR: cs2-kus-addons has local changes. Commit or stash them before updating.
    pause
    exit /b 1
)

set "KUS_DIRTY="
for /f "delims=" %%S in ('git -C "%KUS_ROOT%" status --porcelain') do set "KUS_DIRTY=1"
if defined KUS_DIRTY (
    echo ERROR: KUS has local changes. Commit or stash them before updating.
    pause
    exit /b 1
)

echo [1/3] Pulling cs2-kus-addons updates...
git -C "%~dp0." pull --ff-only
if errorlevel 1 (
    echo ERROR: cs2-kus-addons git pull failed.
    pause
    exit /b 1
)

rem Reload KUS_ROOT in case the pulled win.ini changed.
set "KUS_ROOT="
for /f "usebackq eol=; tokens=* delims=" %%S in ("%~dp0win.ini") do set "%%S"
if not defined KUS_ROOT (
    echo ERROR: KUS_ROOT is no longer configured after the pull.
    pause
    exit /b 1
)
if "%KUS_ROOT:~1,1%"==":" (
    for %%I in ("%KUS_ROOT%") do set "KUS_ROOT=%%~fI"
) else (
    for %%I in ("%~dp0%KUS_ROOT%") do set "KUS_ROOT=%%~fI"
)
if not exist "%KUS_ROOT%\win.bat" (
    echo ERROR: KUS base was not found after updating cs2-kus-addons:
    echo        %KUS_ROOT%
    pause
    exit /b 1
)

echo.
echo [2/3] Pulling KUS base updates...
git -C "%KUS_ROOT%" pull --ff-only
if errorlevel 1 (
    echo ERROR: KUS git pull failed.
    pause
    exit /b 1
)

echo.
echo [3/3] Re-applying KUS base + addon overlay...
echo This step does not update CS2 through SteamCMD and does not start the server.
call "%~dp0win.bat"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo ERROR: win.bat failed with exit code %RC%.
    pause
    exit /b %RC%
)

echo.
echo Repository update completed. CS2 was not updated and the server was not started.
pause
exit /b 0
