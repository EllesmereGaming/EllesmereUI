@echo off
rem Build a local release zip in .release\ via release.sh (needs Git for Windows plus svn and zip on PATH).
setlocal

set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%BASH%" set "BASH=bash"
if "%BASH%"=="bash" where bash >nul 2>nul || (echo Git for Windows not found: install it, plus svn and zip, then run this again.& exit /b 1)

"%BASH%" "%~dp0release.sh" %*
exit /b %ERRORLEVEL%
