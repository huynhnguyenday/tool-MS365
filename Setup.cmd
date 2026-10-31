@echo off
setlocal
if "%~1"=="" (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Create-TeamsChannelManagerShortcut.ps1" -Force
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Create-TeamsChannelManagerShortcut.ps1" -ShortcutPath "%~1" -Force
)
set "SETUP_EXIT_CODE=%ERRORLEVEL%"
if not "%SETUP_EXIT_CODE%"=="0" pause
endlocal & exit /b %SETUP_EXIT_CODE%
