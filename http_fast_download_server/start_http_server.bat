@echo off
setlocal EnableExtensions

where pwsh.exe >nul 2>nul
if errorlevel 1 (
    echo PowerShell 7 is required to start the FastDL HTTP server.
    echo Run ..\install_server.bat first.
    exit /b 1
)

pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\server\start_script\start_services.ps1" -Action Http %*
exit /b %errorlevel%
