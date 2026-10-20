@echo off
rem ==========================================================================
rem  Zenith - Emergency Restore
rem  Undoes EVERY change Zenith has made, from a plain console window.
rem  Use this if the Zenith window will not open. Your original settings are
rem  read from %ProgramData%\Zenith\backup.json.
rem ==========================================================================
setlocal
set "ZROOT=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath $env:ZROOT -Recurse -File | Unblock-File" >nul 2>&1
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%ZROOT%app\Zenith.ps1" -RevertAll
endlocal
