@echo off
rem Build a local release zip in .release\ via release.sh (needs Git for Windows plus svn and zip on PATH).
setlocal

set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%BASH%" set "BASH=bash"

"%BASH%" "%~dp0release.sh" %*
exit /b %ERRORLEVEL%
