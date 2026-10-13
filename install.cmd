@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0install-windows.ps1" %*
exit /b %errorlevel%
