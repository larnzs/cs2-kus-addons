@echo off
setlocal EnableExtensions EnableDelayedExpansion

title CS2 KUS Addons
cd /d "%~dp0"

set "ROOT_DIR=%~dp0"
set "CONFIG_FILE=%ROOT_DIR%win.ini"

if not exist "%CONFIG_FILE%" (
    echo ERROR: %CONFIG_FILE% not found.
    goto :end
)

set "KUS_ROOT="
for /f "usebackq eol=; tokens=* delims=" %%S in ("%CONFIG_FILE%") do set "%%S"

if not defined KUS_ROOT (
    echo ERROR: KUS_ROOT is not configured in win.ini.
    goto :end
)

if "%KUS_ROOT:~1,1%"==":" (
    for %%I in ("%KUS_ROOT%") do set "KUS_ROOT=%%~fI"
) else (
    for %%I in ("%ROOT_DIR%%KUS_ROOT%") do set "KUS_ROOT=%%~fI"
)

if not exist "%KUS_ROOT%\win.ini" (
    echo ERROR: KUS win.ini not found:
    echo        %KUS_ROOT%\win.ini
    goto :end
)

for /f "usebackq eol=; tokens=* delims=" %%S in ("%KUS_ROOT%\win.ini") do set "%%S"

if not defined PORT set "PORT=27015"
if not defined MAXPLAYERS set "MAXPLAYERS=32"
if not defined TICKRATE set "TICKRATE=128"
if not defined IP set "IP=0.0.0.0"
if not defined LAN set "LAN=0"
if not defined SERVER_PASSWORD set "SERVER_PASSWORD="
if not defined RCON_PASSWORD set "RCON_PASSWORD=changeme"
if not defined EXEC set "EXEC=on_boot.cfg"
if not defined CUSTOM_FOLDER set "CUSTOM_FOLDER=custom_files"

set "GAMEINFO=%KUS_ROOT%\server\game\csgo\gameinfo.gi"
set "BAKFILE=%GAMEINFO%.bak"
set "TEMPFILE=%GAMEINFO%.tmp"
set "SEARCHSTRING=Game	csgo/addons/metamod"
set "INSERTAFTER=Game_LowViolence	csgo_lv"

echo.
echo ============================================
echo          CS2 KUS Addons - Start
echo ============================================
echo.
echo KUS base:     %KUS_ROOT%
echo Addon layer:  %ROOT_DIR%
echo.

if not exist "%KUS_ROOT%\steamcmd\steamcmd.exe" (
    echo Downloading SteamCMD...
    if not exist "%KUS_ROOT%\steamcmd" mkdir "%KUS_ROOT%\steamcmd"

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Invoke-WebRequest -Uri 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' -OutFile '%KUS_ROOT%\steamcmd\steamcmd.zip'"
    if errorlevel 1 goto :error

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "Expand-Archive -Path '%KUS_ROOT%\steamcmd\steamcmd.zip' -DestinationPath '%KUS_ROOT%\steamcmd' -Force"
    if errorlevel 1 goto :error

    del /q "%KUS_ROOT%\steamcmd\steamcmd.zip"
)

echo Checking CS2 for updates...
"%KUS_ROOT%\steamcmd\steamcmd.exe" +force_install_dir "%KUS_ROOT%\server" +login anonymous +app_update 730 +quit
if errorlevel 1 goto :error

if not exist "%GAMEINFO%" (
    echo ERROR: %GAMEINFO% does not exist.
    goto :error
)

if not exist "%BAKFILE%" (
    echo Creating gameinfo.gi backup...
    copy "%GAMEINFO%" "%BAKFILE%" >nul
    if errorlevel 1 goto :error
)

findstr /m /c:"%SEARCHSTRING%" "%GAMEINFO%" >nul
if errorlevel 1 (
    echo Patching gameinfo.gi for Metamod...

    >"%TEMPFILE%" (
        set "ADDED=0"
        for /f "tokens=* delims=" %%A in ('findstr /n "^" "%GAMEINFO%"') do (
            set "LINE=%%A"
            setlocal EnableDelayedExpansion
            set "LINE=!LINE:*:=!"

            if "!LINE!" neq "" (
                if "!LINE!"=="!LINE:%INSERTAFTER%=!" (
                    echo(!LINE!
                ) else (
                    if "!ADDED!"=="0" (
                        echo(!LINE!
                        echo(			%SEARCHSTRING%
                        set "ADDED=1"
                    )
                )
            ) else (
                echo(
            )

            endlocal
        )
    )

    if not exist "%TEMPFILE%" goto :error
    move /y "%TEMPFILE%" "%GAMEINFO%" >nul
    if errorlevel 1 goto :error
) else (
    echo gameinfo.gi is already patched.
)

rem KUS owns this cleanup. Our addon layer is pasted back immediately afterwards.
echo Rebuilding KUS base files...

if exist "%KUS_ROOT%\server\game\csgo\addons\" (
    rmdir /S /Q "%KUS_ROOT%\server\game\csgo\addons"
)

if exist "%KUS_ROOT%\server\game\csgo\cfg\settings\" (
    rmdir /S /Q "%KUS_ROOT%\server\game\csgo\cfg\settings"
)

call :MERGE "%KUS_ROOT%\game\csgo" "%KUS_ROOT%\server\game\csgo"
if errorlevel 1 goto :error

if exist "%KUS_ROOT%\game\csgo\addons\windows\" (
    call :MERGE "%KUS_ROOT%\game\csgo\addons\windows" "%KUS_ROOT%\server\game\csgo"
    if errorlevel 1 goto :error
)

rem Our repository is an overlay: merge only, never delete from the destination.
if exist "%ROOT_DIR%server\game\csgo\" (
    echo Merging cs2-kus-addons layer...
    call :MERGE "%ROOT_DIR%server\game\csgo" "%KUS_ROOT%\server\game\csgo"
    if errorlevel 1 goto :error
) else (
    echo WARNING: addon staging directory not found:
    echo          %ROOT_DIR%server\game\csgo
)

rem KUS custom files first, our custom files last.
if exist "%KUS_ROOT%\custom_files\" (
    echo Merging KUS custom files...
    call :MERGE "%KUS_ROOT%\custom_files" "%KUS_ROOT%\server\game\csgo"
    if errorlevel 1 goto :error
)

if exist "%ROOT_DIR%custom_files\" (
    echo Merging cs2-kus-addons custom files...
    call :MERGE "%ROOT_DIR%custom_files" "%KUS_ROOT%\server\game\csgo"
    if errorlevel 1 goto :error
)

if not exist "%KUS_ROOT%\server\game\bin\win64\cs2.exe" (
    echo ERROR: cs2.exe was not installed by SteamCMD.
    goto :error
)

echo.
echo CS2 started.
echo.

pushd "%KUS_ROOT%"
start "CS2" /wait "%KUS_ROOT%\server\game\bin\win64\cs2.exe" ^
    -dedicated -console -debug -condebug -conclearlog -usercon ^
    -disable_workshop_command_filtering ^
    +game_type 0 +game_mode 0 +mapgroup mg_active +map de_dust2 ^
    -port %PORT% -ip 0.0.0.0 +net_public_adr %IP% ^
    -tickrate %TICKRATE% +sv_visiblemaxplayers %MAXPLAYERS% ^
    -authkey %API_KEY% +sv_setsteamaccount %STEAM_ACCOUNT% ^
    +sv_lan %LAN% +sv_password %SERVER_PASSWORD% ^
    +rcon_password %RCON_PASSWORD% +exec %EXEC%
popd

echo.
echo WARNING: CS2 closed or crashed.
goto :end

:MERGE
robocopy "%~1" "%~2" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XF .gitnote .gitkeep >nul
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 exit /b 1
exit /b 0

:error
echo.
echo ============================================
echo ERROR: update/start process failed.
echo ============================================

:end
pause
endlocal
