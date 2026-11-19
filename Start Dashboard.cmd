@echo off
setlocal
cd /d "%~dp0"
echo Starting Network Diagnostics Dashboard 5.0...
echo No tools run until you press START. No administrator elevation requested.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0NetworkDashboard.ps1"
if errorlevel 1 (
 echo.
 echo Startup failed. Copy the complete error above for troubleshooting.
 echo Extract ALL package files into a normal folder before running.
 pause
)
endlocal
