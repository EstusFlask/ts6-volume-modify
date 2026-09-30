@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Volume-Unlock.ps1" %*
set "result=%ERRORLEVEL%"
if not "%result%"=="0" pause
exit /b %result%
