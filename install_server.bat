@echo off
setlocal EnableExtensions
title COD4_PROMOD_SERVER_INSTALLER

set "RELAUNCHED=0"
if /i "%~1"=="--pwsh-relaunched" set "RELAUNCHED=1"

call :ensure_process_path_entry "%LOCALAPPDATA%\Microsoft\WindowsApps"
call :find_winget
if defined WINGET_EXE goto winget_ready

echo WinGet is required before installation can continue.
echo This installer uses winget for PowerShell 7 and Python setup.
choice /c YN /n /m "Install or repair WinGet automatically now? [Y/N] "
if errorlevel 2 goto no_winget

echo Installing or repairing WinGet...
call :install_winget
if errorlevel 1 goto winget_failed

call :ensure_process_path_entry "%LOCALAPPDATA%\Microsoft\WindowsApps"
call :find_winget
if defined WINGET_EXE goto winget_ready
goto winget_failed

:winget_ready
echo WinGet detected. Continuing with installer checks...

call :find_pwsh
call :get_pwsh_major
if not defined PWSH_EXE goto ensure_pwsh
if not defined PWSH_MAJOR goto ensure_pwsh
if %PWSH_MAJOR% GEQ 7 goto run_installer

:ensure_pwsh
echo This package requires PowerShell 7.x.
choice /c YN /n /m "Install or upgrade PowerShell automatically now? [Y/N] "
if errorlevel 2 goto no_install

echo Updating PowerShell to the latest release...
"%WINGET_EXE%" upgrade --id Microsoft.PowerShell -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity

call :find_pwsh
call :get_pwsh_major
if not defined PWSH_EXE goto install_pwsh_after_upgrade_check
if not defined PWSH_MAJOR goto install_pwsh_after_upgrade_check
if %PWSH_MAJOR% GEQ 7 goto run_installer

:install_pwsh_after_upgrade_check
echo PowerShell was not upgraded through winget. Trying a fresh install...
"%WINGET_EXE%" install --id Microsoft.PowerShell -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
if errorlevel 1 (
    echo Automatic PowerShell install or upgrade failed.
    echo Install PowerShell 7 manually, then run this file again.
    goto finish_error
)

call :ensure_process_path_entry "%LOCALAPPDATA%\Microsoft\WindowsApps"
call :ensure_process_path_entry "%ProgramW6432%\PowerShell\7"
call :ensure_process_path_entry "%ProgramFiles%\PowerShell\7"

call :find_pwsh
call :get_pwsh_major
if not defined PWSH_EXE goto pwsh_still_missing
if not defined PWSH_MAJOR goto pwsh_still_missing
if %PWSH_MAJOR% GEQ 7 goto run_installer

:pwsh_still_missing
if "%RELAUNCHED%"=="0" (
    echo PowerShell was installed or upgraded. Reopening the installer in a fresh terminal...
    start "COD4_PROMOD_SERVER_INSTALLER" "%ComSpec%" /k "\"%~f0\" --pwsh-relaunched"
    goto finish_ok
)

echo PowerShell was installed or upgraded, but the installer still could not locate pwsh.exe.
echo Close this window, open a new one, and run install_server.bat again.
goto finish_error

:winget_failed
echo Automatic WinGet install or repair failed.
echo Install or repair App Installer manually, then run install_server.bat again.
goto finish_error

:no_winget
echo The installer cannot continue without WinGet.
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

:install_winget
set "WINPS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%WINPS_EXE%" set "WINPS_EXE=powershell.exe"
"%WINPS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0installation_scripts\bootstrap_winget.ps1"
exit /b %errorlevel%

:find_winget
set "WINGET_EXE="
winget --version >nul 2>nul
if not errorlevel 1 (
    set "WINGET_EXE=winget"
    exit /b 0
)
for /f "delims=" %%I in ('where winget.exe 2^>nul') do (
    "%%~fI" --version >nul 2>nul
    if not errorlevel 1 (
        set "WINGET_EXE=%%~fI"
        exit /b 0
    )
)
if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe" (
    "%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe" --version >nul 2>nul
    if not errorlevel 1 (
        set "WINGET_EXE=%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe"
        exit /b 0
    )
)
exit /b 0

:find_pwsh
set "PWSH_EXE="
if defined ProgramW6432 if exist "%ProgramW6432%\PowerShell\7\pwsh.exe" (
    set "PWSH_EXE=%ProgramW6432%\PowerShell\7\pwsh.exe"
    goto :eof
)
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    set "PWSH_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
    goto :eof
)
for /f "delims=" %%I in ('where pwsh.exe 2^>nul') do (
    set "PWSH_EXE=%%~fI"
    goto :eof
)
if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" (
    set "PWSH_EXE=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
    goto :eof
)
exit /b 0

:get_pwsh_major
set "PWSH_MAJOR="
if not defined PWSH_EXE exit /b 0
for /f "usebackq delims=" %%I in (`""%PWSH_EXE%" -NoProfile -Command "$PSVersionTable.PSVersion.Major" 2^>nul"`) do (
    call :set_pwsh_major_if_numeric "%%I"
)
exit /b 0

:set_pwsh_major_if_numeric
if defined PWSH_MAJOR exit /b 0
set "_PWSH_MAJOR_CANDIDATE=%~1"
if not defined _PWSH_MAJOR_CANDIDATE exit /b 0
echo(%_PWSH_MAJOR_CANDIDATE%| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 exit /b 0
set "PWSH_MAJOR=%_PWSH_MAJOR_CANDIDATE%"
set "_PWSH_MAJOR_CANDIDATE="
exit /b 0

:ensure_process_path_entry
if "%~1"=="" exit /b 0
if not exist "%~1" exit /b 0
echo(;%PATH%; | find /I ";%~1;" >nul
if errorlevel 1 set "PATH=%~1;%PATH%"
exit /b 0
