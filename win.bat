@echo off
setlocal EnableExtensions EnableDelayedExpansion
title CS2 KUS Addons - Prepare Server
cd /d "%~dp0"

set "ROOT_DIR=%~dp0"
set "CONFIG_FILE=%ROOT_DIR%win.ini"
set "SERVER_REL=server"
if exist "%CONFIG_FILE%" (
    for /f "usebackq eol=; tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
        if /I "%%A"=="SERVER_DIR" set "SERVER_REL=%%B"
    )
)
for %%I in ("%ROOT_DIR%%SERVER_REL%") do set "SERVER_DIR=%%~fI"

set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"
set "GAMEINFO=%SERVER_DIR%\game\csgo\gameinfo.gi"
set "BAKFILE=%GAMEINFO%.bak"
set "TEMPFILE=%GAMEINFO%.tmp"
set "SEARCHSTRING=Game	csgo/addons/metamod"
set "INSERTAFTER=Game_LowViolence	csgo_lv"

echo.
echo ============================================
echo       CS2 KUS Addons - Prepare Server
echo ============================================
echo Server: %SERVER_DIR%
echo.
if not exist "%CS2_EXE%" (
    echo ERROR: CS2 is not installed. Run install.bat first.
    exit /b 1
)
if not exist "%GAMEINFO%" (
    echo ERROR: gameinfo.gi is missing. Verify the CS2 installation.
    exit /b 1
)
if not exist "%SERVER_DIR%\game\csgo\addons\metamod\" (
    echo ERROR: Metamod is missing under server\game\csgo\addons.
    exit /b 1
)

if not exist "%BAKFILE%" (
    copy "%GAMEINFO%" "%BAKFILE%" >nul
    if errorlevel 1 (
        echo ERROR: Could not back up gameinfo.gi.
        exit /b 1
    )
)

findstr /m /c:"%SEARCHSTRING%" "%GAMEINFO%" >nul
if errorlevel 1 (
    findstr /m /c:"%INSERTAFTER%" "%GAMEINFO%" >nul
    if errorlevel 1 (
        echo ERROR: Metamod insertion marker was not found in gameinfo.gi.
        exit /b 1
    )

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
        echo ERROR: Could not create temporary gameinfo.gi.
        exit /b 1
    )
    findstr /m /c:"%SEARCHSTRING%" "%TEMPFILE%" >nul
    if errorlevel 1 (
        del /q "%TEMPFILE%" >nul 2>&1
        echo ERROR: Metamod entry was not inserted.
        exit /b 1
    )
    move /y "%TEMPFILE%" "%GAMEINFO%" >nul
    if errorlevel 1 exit /b 1
)

findstr /m /c:"%SEARCHSTRING%" "%GAMEINFO%" >nul
if errorlevel 1 (
    echo ERROR: gameinfo.gi is missing the Metamod entry.
    exit /b 1
)
echo SUCCESS: Managed KUS and Larnz assets already exist in their final server paths.
echo No addon copying, deletion, SteamCMD update or server launch was performed.
exit /b 0
