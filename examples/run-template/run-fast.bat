@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Fast server-only launcher. run.bat owns shared config and launch logic;
rem this entrypoint bypasses Git, release checks, SteamCMD, gameinfo patching and runtime overlays.
call "%~dp0run.bat" --no-update %*
exit /b %ERRORLEVEL%
