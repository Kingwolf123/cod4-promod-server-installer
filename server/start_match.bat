@echo off
setlocal EnableExtensions
REM To edit COD4 launch arguments, open server\start_script\server_args.psd1 with notepad / text editor

where pwsh.exe >nul 2>nul
if errorlevel 1 (
    echo PowerShell 7 is required to start this server.
    echo Run ..\install_server.bat first.
    exit /b 1
)

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_script\start_services.ps1" -Action Match %*
set "START_EXIT=%errorlevel%"
if not "%START_EXIT%"=="0" (
    echo.
    pause
)
exit /b %START_EXIT%

