@echo off
rem ==========================================================================
rem  Zenith - PC optimizer (AI FPS Tweaks)
rem  Double-click this file to start Zenith. Windows will ask for administrator
rem  permission (needed to change system settings) - choose Yes.
rem ==========================================================================
setlocal
set "ZROOT=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
rem Files downloaded from the internet are marked "blocked" by Windows. Unblock Zenith's own files.
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath $env:ZROOT -Recurse -File | Unblock-File" >nul 2>&1
start "" "%PS%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%ZROOT%app\Zenith.ps1"
endlocal
