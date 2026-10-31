@echo off
setlocal
set "SCRIPT=%~dp0app\Start-PrivateChannelMembersUI.ps1"
set "PORT=%~1"
if "%PORT%"=="" set "PORT=8765"
start "Private Teams Channel Manager" powershell.exe -NoLogo -NoExit -ExecutionPolicy Bypass -File "%SCRIPT%" -Port %PORT%
endlocal