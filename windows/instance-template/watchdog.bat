@echo off
setlocal EnableExtensions DisableDelayedExpansion

title CS2 Watchdog Guardian
set "VBS=%~dp0run.vbs"
set "CSCRIPT=%SystemRoot%\System32\cscript.exe"

if not exist "%VBS%" (
    echo ERROR: Missing watchdog script: "%VBS%"
    echo Keep watchdog.bat beside run.vbs.
    pause
    exit /b 2
)

:watch
echo [%date% %time%] Starting VBS watchdog host...
"%CSCRIPT%" //nologo "%VBS%"
set "VBS_EXIT=%ERRORLEVEL%"
echo [%date% %time%] VBS host exited with code %VBS_EXIT%. Restarting it in 1 second.
timeout /t 1 /nobreak >nul
goto :watch
