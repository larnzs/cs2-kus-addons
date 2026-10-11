@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Reuse the shared instance parser and CS2 command line, skipping update/deployment work.
call "%~dp0run.bat" --fast %*
set "RUNNER_RC=%ERRORLEVEL%"
endlocal & exit /b %RUNNER_RC%
