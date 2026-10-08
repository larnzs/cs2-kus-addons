@echo off
setlocal EnableExtensions EnableDelayedExpansion

title CS2 KUS Addons - Apply Layers
cd /d "%~dp0"

set "EXIT_CODE=0"
set "ROOT_DIR=%~dp0"
set "CONFIG_FILE=%ROOT_DIR%win.ini"

if not exist "%CONFIG_FILE%" (
    echo ERROR: %CONFIG_FILE% not found.
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

if not exist "%KUS_ROOT%\win.bat" (
    echo ERROR: KUS base was not found:
    echo        %KUS_ROOT%
    goto :error
)

if not exist "%KUS_ROOT%\game\csgo\" (
    echo ERROR: KUS base game files were not found:
    echo        %KUS_ROOT%\game\csgo
    goto :error
)

echo.
echo ============================================
echo       CS2 KUS Addons - Apply Layers
echo ============================================
echo KUS base:     %KUS_ROOT%
echo Addon layer:  %ROOT_DIR%
echo.
if not exist "%KUS_ROOT%\server\game\bin\win64\cs2.exe" (
    echo ERROR: CS2 is not installed yet. Run install.bat first.
    goto :error
)

if not exist "%KUS_ROOT%\server\steamapps\appmanifest_730.acf" (
    echo ERROR: appmanifest_730.acf is missing. Run install.bat to repair the initial CS2 installation.
    goto :error
)

echo Rebuilding KUS-managed game files...

if exist "%KUS_ROOT%\server\game\csgo\addons\" (
    rmdir /S /Q "%KUS_ROOT%\server\game\csgo\addons"
    if exist "%KUS_ROOT%\server\game\csgo\addons\" (
        echo ERROR: Could not remove the old KUS addons directory.
        goto :error
    )
)

if exist "%KUS_ROOT%\server\game\csgo\cfg\settings\" (
    rmdir /S /Q "%KUS_ROOT%\server\game\csgo\cfg\settings"
    if exist "%KUS_ROOT%\server\game\csgo\cfg\settings\" (
        echo ERROR: Could not remove the old KUS cfg\settings directory.
        goto :error
    )
)

call :MERGE "%KUS_ROOT%\game\csgo" "%KUS_ROOT%\server\game\csgo"
if errorlevel 1 goto :error

if exist "%KUS_ROOT%\game\csgo\addons\windows\" (
    call :MERGE "%KUS_ROOT%\game\csgo\addons\windows" "%KUS_ROOT%\server\game\csgo"
    if errorlevel 1 goto :error
)

if not exist "%ROOT_DIR%server\game\csgo\" (
    echo ERROR: Addon staging directory was not found:
    echo        %ROOT_DIR%server\game\csgo
    goto :error
)

echo Applying cs2-kus-addons overlay...
call :MERGE "%ROOT_DIR%server\game\csgo" "%KUS_ROOT%\server\game\csgo"
if errorlevel 1 goto :error

rem Merge order: KUS custom files, KUS local secrets, addon custom files, addon local secrets.
if exist "%KUS_ROOT%\custom_files\" (
    echo Merging KUS custom files...
    call :MERGE "%KUS_ROOT%\custom_files" "%KUS_ROOT%\server\game\csgo"
    if errorlevel 1 goto :error
)

if exist "%KUS_ROOT%\custom_files_secret\" (
    echo Merging KUS local secret overrides...
    call :MERGE "%KUS_ROOT%\custom_files_secret" "%KUS_ROOT%\server\game\csgo"
    if errorlevel 1 goto :error
)

if exist "%ROOT_DIR%custom_files\" (
    echo Merging cs2-kus-addons custom files...
    call :MERGE "%ROOT_DIR%custom_files" "%KUS_ROOT%\server\game\csgo"
    if errorlevel 1 goto :error
)

if exist "%ROOT_DIR%custom_files_secret\" (
    echo Merging cs2-kus-addons local secret overrides...
    call :MERGE "%ROOT_DIR%custom_files_secret" "%KUS_ROOT%\server\game\csgo"
    if errorlevel 1 goto :error
)

rem Patch gameinfo.gi after all merges so a copied base file cannot undo the Metamod entry.
set "GAMEINFO=%KUS_ROOT%\server\game\csgo\gameinfo.gi"
set "BAKFILE=%GAMEINFO%.bak"
set "TEMPFILE=%GAMEINFO%.tmp"
set "SEARCHSTRING=Game	csgo/addons/metamod"
set "INSERTAFTER=Game_LowViolence	csgo_lv"

if not exist "%GAMEINFO%" (
    echo ERROR: %GAMEINFO% does not exist after the game update.
    goto :error
)

if not exist "%BAKFILE%" (
    echo Creating gameinfo.gi backup...
    copy "%GAMEINFO%" "%BAKFILE%" >nul
    if errorlevel 1 goto :error
)

findstr /m /c:"%SEARCHSTRING%" "%GAMEINFO%" >nul
if errorlevel 1 (
    findstr /m /c:"%INSERTAFTER%" "%GAMEINFO%" >nul
    if errorlevel 1 (
        echo ERROR: The Metamod insertion marker was not found in gameinfo.gi.
        goto :error
    )

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

    if not exist "%TEMPFILE%" (
        echo ERROR: Could not create the patched gameinfo temporary file.
        goto :error
    )

    findstr /m /c:"%SEARCHSTRING%" "%TEMPFILE%" >nul
    if errorlevel 1 (
        del /q "%TEMPFILE%" >nul 2>&1
        echo ERROR: Metamod entry was not inserted into gameinfo.gi.
        goto :error
    )

    move /y "%TEMPFILE%" "%GAMEINFO%" >nul
    if errorlevel 1 goto :error
)

findstr /m /c:"%SEARCHSTRING%" "%GAMEINFO%" >nul
if errorlevel 1 (
    echo ERROR: gameinfo.gi is missing the required Metamod entry.
    goto :error
)

if not exist "%KUS_ROOT%\server\game\bin\win64\cs2.exe" (
    echo ERROR: cs2.exe was not installed by SteamCMD.
    goto :error
)

echo.
echo SUCCESS: The KUS base and addon overlay are installed. CS2 game files were not updated.
echo The game server was not started; the VBS supervisor can launch it separately.
goto :success

:MERGE
robocopy "%~1" "%~2" /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XF .gitnote .gitkeep >nul
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 exit /b 1
exit /b 0

:error
set "EXIT_CODE=1"
echo.
echo ============================================
echo ERROR: Applying KUS / addon layers failed.
echo ============================================
goto :finish

:success
set "EXIT_CODE=0"
goto :finish

:finish
endlocal & exit /b %EXIT_CODE%
