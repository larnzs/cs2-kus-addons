@echo off
setlocal EnableExtensions EnableDelayedExpansion
title CS2 KUS Addons - Prepare and Deploy
set "PAUSE_ON_EXIT=1"
if /I "%~1"=="--no-pause" set "PAUSE_ON_EXIT=0"
set "RC=1"
cd /d "%~dp0"
set "ROOT_DIR=%~dp0"
set "PAYLOAD_DIR=%ROOT_DIR%game\csgo"
set "SERVER_DIR=%ROOT_DIR%server"
set "CS2_EXE=%SERVER_DIR%\game\bin\win64\cs2.exe"
set "GAMEINFO=%SERVER_DIR%\game\csgo\gameinfo.gi"
echo.
echo ============================================
echo       CS2 KUS Addons - Prepare and Deploy
echo ============================================
echo Tracked payload: %PAYLOAD_DIR%
echo Installed game:  %SERVER_DIR%
echo Runtime target:  %SERVER_DIR%\game\csgo
echo.
if not exist "%ROOT_DIR%DEPENDENCIES.json" (echo ERROR: DEPENDENCIES.json is missing.& goto :finish)
if not exist "%PAYLOAD_DIR%\addons\" (echo ERROR: Tracked payload is missing from game\csgo.& goto :finish)
if not exist "%CS2_EXE%" (echo ERROR: CS2 is not installed. Run install.bat first.& goto :finish)
if not exist "%GAMEINFO%" (echo ERROR: gameinfo.gi is missing. Run install.bat/SteamCMD first.& goto :finish)
if not exist "%PAYLOAD_DIR%\addons\windows\addons\counterstrikesharp\dotnet\dotnet.exe" (
    echo ERROR: CounterStrikeSharp Windows with-runtime payload is missing.
    echo Run addons-update.bat -Only CounterStrikeSharp after updating this checkout.
    goto :finish
)
if not exist "%PAYLOAD_DIR%\addons\metamod\bin\win64\metamod.2.cs2.dll" (
    echo ERROR: KUS Windows Metamod binary is missing from the tracked payload.
    goto :finish
)
if not exist "%PAYLOAD_DIR%\addons\multiaddonmanager\bin\multiaddonmanager.dll" (
    echo ERROR: KUS MultiAddonManager binary is missing from the tracked payload.
    goto :finish
)
if not exist "%PAYLOAD_DIR%\addons\serverlistplayersfix_mm\bin\win64\serverlistplayersfix_mm.dll" (
    echo ERROR: KUS ServerListPlayersFix binary is missing from the tracked payload.
    goto :finish
)
if not exist "%PAYLOAD_DIR%\addons\MovementUnlocker\bin\win64\MovementUnlocker.dll" (
    echo ERROR: KUS MovementUnlocker binary is missing from the tracked payload.
    goto :finish
)
if not exist "%PAYLOAD_DIR%\addons\cs2fixes-rampbugfix\bin\win64\cs2fixes-rampbugfix.dll" (
    echo ERROR: KUS RampbugFix binary is missing from the tracked payload.
    goto :finish
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%scripts\Deploy-Runtime.ps1"
if errorlevel 1 (echo ERROR: Payload deployment failed.& goto :finish)
rem Patch gameinfo.gi using the same substring-based insertion method as upstream KUS.
set "GAMEINFO_BAK=%GAMEINFO%.bak"
set "GAMEINFO_TMP=%GAMEINFO%.tmp"
set "SEARCHSTRING=Game	csgo/addons/metamod"
set "INSERTAFTER=Game_LowViolence	csgo_lv"
if not exist "%GAMEINFO_BAK%" (
    copy "%GAMEINFO%" "%GAMEINFO_BAK%" >nul
    if errorlevel 1 (echo ERROR: Could not back up gameinfo.gi.& goto :finish)
)
findstr /m /c:"%SEARCHSTRING%" "%GAMEINFO%" >nul
if not errorlevel 1 goto :gameinfo_patched
findstr /m /c:"%INSERTAFTER%" "%GAMEINFO%" >nul
if errorlevel 1 (
    echo ERROR: Could not find the KUS Game_LowViolence csgo_lv insertion marker in gameinfo.gi.
    goto :finish
)
echo Patching gameinfo.gi for MetaMod using the KUS-compatible method...
> "%GAMEINFO_TMP%" (
    set "ADDED=0"
    for /f "tokens=* delims=" %%A in ('findstr /n "^" "%GAMEINFO%"') do (
        set "LINE=%%A"
        setlocal EnableDelayedExpansion
        set "LINE=!LINE:*:=!"
        if "!LINE!" neq "" (
            if "!LINE!"=="!LINE:%INSERTAFTER%=!" (
                echo(!LINE!
            ) else (
                echo(!LINE!
                if "!ADDED!"=="0" (
                    echo(           Game	csgo/addons/metamod
                    set "ADDED=1"
                )
            )
        ) else (
            echo(
        )
        endlocal & set "ADDED=!ADDED!"
    )
)
if not exist "%GAMEINFO_TMP%" (
    echo ERROR: Could not create the patched gameinfo temporary file.
    goto :finish
)
findstr /m /c:"%SEARCHSTRING%" "%GAMEINFO_TMP%" >nul
if errorlevel 1 (
    del /q "%GAMEINFO_TMP%" >nul 2>&1
    echo ERROR: MetaMod entry was not inserted into gameinfo.gi.
    goto :finish
)
move /y "%GAMEINFO_TMP%" "%GAMEINFO%" >nul
if errorlevel 1 (echo ERROR: Could not replace gameinfo.gi with the patched file.& goto :finish)
:gameinfo_patched
findstr /m /c:"%SEARCHSTRING%" "%GAMEINFO%" >nul
if errorlevel 1 (
    echo ERROR: gameinfo.gi is missing the required MetaMod entry.
    goto :finish
)
if not exist "%SERVER_DIR%\game\csgo\addons\metamod\bin\win64\metamod.2.cs2.dll" (echo ERROR: Windows Metamod binary is missing after deployment.& goto :finish)
if not exist "%SERVER_DIR%\game\csgo\addons\multiaddonmanager\bin\multiaddonmanager.dll" (echo ERROR: KUS MultiAddonManager is missing after deployment.& goto :finish)
if not exist "%SERVER_DIR%\game\csgo\addons\serverlistplayersfix_mm\bin\win64\serverlistplayersfix_mm.dll" (echo ERROR: KUS ServerListPlayersFix is missing after deployment.& goto :finish)
if not exist "%SERVER_DIR%\game\csgo\addons\MovementUnlocker\bin\win64\MovementUnlocker.dll" (echo ERROR: KUS MovementUnlocker is missing after deployment.& goto :finish)
if not exist "%SERVER_DIR%\game\csgo\addons\cs2fixes-rampbugfix\bin\win64\cs2fixes-rampbugfix.dll" (echo ERROR: KUS RampbugFix is missing after deployment.& goto :finish)
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%scripts\Test-AddonOverlay.ps1" -VerifyAddons -VerifyRuntime
if errorlevel 1 (echo ERROR: Deployed runtime verification failed.& goto :finish)
echo.
echo SUCCESS: game\csgo payload deployed and gameinfo.gi patched.
echo No Git pull, SteamCMD update, or server launch was performed.
set "RC=0"
:finish
echo.
if "%RC%"=="0" (echo Result: SUCCESS) else (echo Result: FAILED ^(exit code %RC%^))
if "%PAUSE_ON_EXIT%"=="1" (echo. & echo Press any key to close this window . . . & pause >nul)
endlocal & exit /b %RC%