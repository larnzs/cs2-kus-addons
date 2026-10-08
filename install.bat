@echo off
setlocal EnableExtensions EnableDelayedExpansion

title CS2 KUS Addons - Initial Install
cd /d "%~dp0"

set "ROOT_DIR=%~dp0"
set "CONFIG_FILE=%ROOT_DIR%win.ini"
set "EXIT_CODE=0"

echo.
echo ============================================
echo       CS2 KUS Addons - Initial Install
echo ============================================
echo.

if not exist "%CONFIG_FILE%" (
    echo ERROR: %CONFIG_FILE% not found.
    goto :error
)

git --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git is required. Install Git for Windows, then run install.bat again.
    goto :error
)

git -C "%ROOT_DIR%" rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: This folder is not a Git clone of cs2-kus-addons.
    echo Clone the private addon repository first, then run install.bat from it.
    goto :error
)

set "KUS_ROOT="
for /f "usebackq eol=; tokens=* delims=" %%S in ("%CONFIG_FILE%") do set "%%S"

if not defined KUS_ROOT (
    echo ERROR: KUS_ROOT is not configured in win.ini.
    goto :error
)

if "%KUS_ROOT:~1,1%"==":" (
    for %%I in ("%KUS_ROOT%") do set "KUS_ROOT=%%~fI"
) else (
    for %%I in ("%ROOT_DIR%%KUS_ROOT%") do set "KUS_ROOT=%%~fI"
)

echo [1/3] Preparing the KUS raw base...
if not exist "%KUS_ROOT%\win.bat" (
    if exist "%KUS_ROOT%" (
        echo ERROR: KUS_ROOT exists but is not a valid KUS checkout:
        echo        %KUS_ROOT%
        echo Move the incomplete folder away, then run install.bat again.
        goto :error
    )

    for %%I in ("%KUS_ROOT%\..") do set "KUS_PARENT=%%~fI"
    if not exist "!KUS_PARENT!\" mkdir "!KUS_PARENT!"
    if errorlevel 1 (
        echo ERROR: Could not create the parent directory for KUS_ROOT.
        goto :error
    )

    echo Cloning https://github.com/kus/cs2-modded-server.git
    git clone https://github.com/kus/cs2-modded-server.git "%KUS_ROOT%"
    if errorlevel 1 goto :error
)

git -C "%KUS_ROOT%" rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: KUS_ROOT is not a Git working tree:
    echo        %KUS_ROOT%
    goto :error
)

set "KUS_REMOTE="
for /f "delims=" %%U in ('git -C "%KUS_ROOT%" remote get-url origin 2^>nul') do set "KUS_REMOTE=%%U"
echo(!KUS_REMOTE!| findstr /I /C:"kus/cs2-modded-server" >nul
if errorlevel 1 (
    echo ERROR: The origin at KUS_ROOT is not kus/cs2-modded-server.
    echo        Origin: !KUS_REMOTE!
    goto :error
)

if not exist "%KUS_ROOT%\game\csgo\" (
    echo ERROR: KUS raw game files are missing:
    echo        %KUS_ROOT%\game\csgo
    goto :error
)

set "SERVER_ROOT=%KUS_ROOT%\server"
set "CS2_EXE=%SERVER_ROOT%\game\bin\win64\cs2.exe"
set "APP_MANIFEST=%SERVER_ROOT%\steamapps\appmanifest_730.acf"
set "STEAMCMD=%KUS_ROOT%\steamcmd\steamcmd.exe"

echo.
echo [2/3] Checking the one-time CS2 game installation...
if exist "%CS2_EXE%" if exist "%APP_MANIFEST%" goto :game_installed

if not exist "%STEAMCMD%" (
    echo SteamCMD is missing; downloading it...
    if not exist "%KUS_ROOT%\steamcmd\" mkdir "%KUS_ROOT%\steamcmd"
    if errorlevel 1 goto :error

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Invoke-WebRequest -Uri 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' -OutFile '%KUS_ROOT%\steamcmd\steamcmd.zip' -UseBasicParsing"
    if errorlevel 1 goto :error

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Expand-Archive -LiteralPath '%KUS_ROOT%\steamcmd\steamcmd.zip' -DestinationPath '%KUS_ROOT%\steamcmd' -Force"
    if errorlevel 1 goto :error

    del /q "%KUS_ROOT%\steamcmd\steamcmd.zip" >nul 2>&1
)

if not exist "%STEAMCMD%" (
    echo ERROR: SteamCMD extraction did not produce steamcmd.exe.
    goto :error
)

if not exist "%SERVER_ROOT%\" mkdir "%SERVER_ROOT%"
if errorlevel 1 goto :error

echo Installing CS2 through SteamCMD (initial install only)...
"%STEAMCMD%" +force_install_dir "%SERVER_ROOT%" +login anonymous +app_update 730 +quit
if errorlevel 1 goto :error

if not exist "%CS2_EXE%" (
    echo ERROR: SteamCMD finished but cs2.exe was not found.
    goto :error
)
if not exist "%APP_MANIFEST%" (
    echo ERROR: SteamCMD finished but appmanifest_730.acf was not found.
    goto :error
)

:game_installed
echo CS2 files and app manifest are present. No recurring SteamCMD update is performed here.

echo.
echo [3/3] Applying KUS base files and the cs2-kus-addons overlay...
call "%ROOT_DIR%win.bat"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
    echo.
    echo ERROR: win.bat failed with exit code %RC%.
    set "EXIT_CODE=%RC%"
    goto :finish
)

echo.
echo Initial installation finished. The dedicated server was not started.
echo Run the VBS supervisor only after its update-checker handoff is configured.
goto :success

:error
set "EXIT_CODE=1"
echo.
echo ============================================
echo ERROR: Initial installation failed.
echo ============================================
goto :finish

:success
set "EXIT_CODE=0"
goto :finish

:finish
endlocal & exit /b %EXIT_CODE%
