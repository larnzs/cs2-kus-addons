@echo off
setlocal EnableExtensions
title CS2 KUS Addons - Update Repository
cd /d "%~dp0"

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo ERROR: This directory is not a Git checkout. Clone the private repository first.
    exit /b 1
)
git diff --quiet
if errorlevel 1 goto :dirty
git diff --cached --quiet
if errorlevel 1 goto :dirty
for /f "delims=" %%A in ('git status --porcelain') do goto :dirty

echo Pulling the unified repository (fast-forward only)...
git pull --ff-only
if errorlevel 1 (
    echo ERROR: git pull failed. Check credentials, branch, or repository state.
    exit /b 1
)

call "%~dp0win.bat"
set "RC=%ERRORLEVEL%"
exit /b %RC%

:dirty
echo ERROR: The repository has local changes or untracked files.
echo Commit or stash them before updating. Ignored downloaded game files are not affected.
exit /b 1
