@echo off
setlocal
set "SCRIPT=%~dp0Start-PrivateChannelMembersUI.ps1"
set "PORT=%~1"
if "%PORT%"=="" set "PORT=8765"
start "Private Teams Channel Manager" powershell.exe -NoLogo -NoExit -ExecutionPolicy Bypass -Command "& '%SCRIPT%' -Port %PORT%"
endlocal