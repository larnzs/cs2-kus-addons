@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Update Repository
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
cd /d "%ROOT_DIR%" || exit /b 1

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: This directory is not a Git checkout.
    exit /b 1
)

git switch integration/kus-monorepo
if errorlevel 1 exit /b %ERRORLEVEL%

git pull --ff-only origin integration/kus-monorepo
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
