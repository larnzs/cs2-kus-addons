@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Update Unified Repository
cd /d "%~dp0"

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: This directory is not a Git checkout.
    exit /b 1
)
git diff --quiet
if errorlevel 1 goto :dirty
git diff --cached --quiet
if errorlevel 1 goto :dirty
for /f "delims=" %%A in ('git status --porcelain') do goto :dirty

echo Pulling the unified repository...
git pull --ff-only
if errorlevel 1 (
    echo ERROR: git pull failed. Resolve the repository state before retrying.
    exit /b 1
)

call "%~dp0win.bat"
exit /b %ERRORLEVEL%

:dirty
echo ERROR: The repository has local changes or untracked files.
echo Commit or stash changes before updating.
exit /b 1
