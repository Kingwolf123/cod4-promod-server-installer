@echo off
setlocal EnableExtensions
title COD4_PROMOD_SERVER_INSTALLER

set "RELAUNCHED=0"
if /i "%~1"=="--pwsh-relaunched" set "RELAUNCHED=1"

where winget.exe >nul 2>nul
if errorlevel 1 goto need_winget
echo WinGet detected. Continuing with installer checks...

call :find_pwsh
call :get_pwsh_major
if defined PWSH_EXE if defined PWSH_MAJOR if %PWSH_MAJOR% GEQ 7 goto run_installer

echo This package requires PowerShell 7.x.
choice /c YN /n /m "Install or upgrade PowerShell automatically now? [Y/N] "
if errorlevel 2 goto no_install

echo Updating PowerShell to the latest release...
winget upgrade --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
if errorlevel 1 (
    echo PowerShell was not upgraded through winget. Trying a fresh install...
    winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
    if errorlevel 1 (
        echo Automatic PowerShell install or upgrade failed.
        echo Install PowerShell 7 manually, then run this file again.
        goto finish_error
    )
)

call :find_pwsh
call :get_pwsh_major
if defined PWSH_EXE if defined PWSH_MAJOR if %PWSH_MAJOR% GEQ 7 goto run_installer

if "%RELAUNCHED%"=="0" (
    echo PowerShell was installed or upgraded. Reopening the installer in a fresh terminal...
    start "COD4_PROMOD_SERVER_INSTALLER" "%ComSpec%" /k "\"%~f0\" --pwsh-relaunched"
    goto finish_ok
)

echo PowerShell was installed or upgraded, but pwsh.exe is still not visible in PATH.
echo Close this window, open a new one, and run install_server.bat again.
goto finish_error

:need_winget
echo WinGet is required before installation can continue.
echo This installer uses winget for both PowerShell 7 and Python setup.
echo Install App Installer from Microsoft so winget is available, then run this file again.
goto finish_error

:no_install
echo The installer cannot continue without PowerShell 7.x.
goto finish_error

:run_installer
"%PWSH_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0installation_scripts\install_server.ps1"
set "INSTALL_EXIT=%errorlevel%"
goto finish_install

:finish_install
echo.
if "%INSTALL_EXIT%"=="0" (
    echo Installation successful.
    echo Open server\start_match.bat to start the server.
) else (
    echo Installer failed with exit code %INSTALL_EXIT%.
)
echo Press any key to continue . . .
pause >nul
exit /b %INSTALL_EXIT%

:finish_ok
echo.
echo Installer finished.
echo Press any key to continue . . .
pause >nul
exit /b 0

:finish_error
echo.
echo Installer stopped before completion.
echo Press any key to continue . . .
pause >nul
exit /b 1

:find_pwsh
set "PWSH_EXE="
for /f "delims=" %%I in ('where pwsh.exe 2^>nul') do (
    set "PWSH_EXE=%%I"
    goto :eof
)
exit /b 0

:get_pwsh_major
set "PWSH_MAJOR="
if not defined PWSH_EXE exit /b 0
for /f "usebackq delims=" %%I in (`""%PWSH_EXE%" -NoProfile -Command "$PSVersionTable.PSVersion.Major""`) do (
    if not defined PWSH_MAJOR set "PWSH_MAJOR=%%I"
)
exit /b 0

