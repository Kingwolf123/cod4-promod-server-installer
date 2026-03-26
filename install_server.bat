@echo off
setlocal EnableExtensions
title COD4_SERVER_INSTALLER

set "RELAUNCHED=0"
set "ELEVATED_REQUESTED=0"
set "WT_RELAUNCHED=0"
for %%A in (%*) do (
    if /i "%%~A"=="--pwsh-relaunched" set "RELAUNCHED=1"
    if /i "%%~A"=="--elevated" set "ELEVATED_REQUESTED=1"
    if /i "%%~A"=="--wt-relaunched" set "WT_RELAUNCHED=1"
)

call :is_elevated
if "%IS_ELEVATED%"=="1" goto continue_install
if "%ELEVATED_REQUESTED%"=="1" goto elevation_failed

echo Administrator access is required so the installer can configure PATH for future use.
echo Click Yes on the Windows prompt to continue. The installer will reopen in Windows Terminal.
echo Press any key to show the Windows admin prompt . . .
pause >nul
call :elevate_self
if errorlevel 1 goto elevation_failed
echo Installer relaunched with administrator access.
exit /b 0

:continue_install

call :ensure_process_path_entry "%LOCALAPPDATA%\Microsoft\WindowsApps"
call :find_winget
if defined WINGET_EXE goto winget_ready

echo WinGet is required before installation can continue.
echo This installer uses winget for Windows Terminal, PowerShell 7, and Python setup.
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

call :find_wt
if defined WT_EXE goto wt_ready

:ensure_wt
echo This package uses Windows Terminal for the installer and server launcher.
choice /c YN /n /m "Install or upgrade Windows Terminal automatically now? [Y/N] "
if errorlevel 2 goto no_wt

echo Updating Windows Terminal to the latest release...
"%WINGET_EXE%" upgrade --id Microsoft.WindowsTerminal -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity

call :ensure_process_path_entry "%LOCALAPPDATA%\Microsoft\WindowsApps"
call :find_wt
if defined WT_EXE goto wt_ready

echo Windows Terminal was not upgraded through winget. Trying a fresh install...
"%WINGET_EXE%" install --id Microsoft.WindowsTerminal -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
if errorlevel 1 goto wt_failed

call :ensure_process_path_entry "%LOCALAPPDATA%\Microsoft\WindowsApps"
call :find_wt
if defined WT_EXE goto wt_ready
goto wt_failed

:wt_ready
if defined WT_SESSION goto wt_session_ready
if "%WT_RELAUNCHED%"=="1" goto wt_session_ready

echo Windows Terminal is ready. Reopening the installer there...
call :relaunch_self_in_fresh_terminal "--wt-relaunched"
if errorlevel 1 goto relaunch_failed
goto finish_ok

:wt_session_ready

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
echo PowerShell was not upgraded through winget. No Prior PowerShell 7 installation was detected. Trying a fresh install...
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
    echo PowerShell was installed or upgraded. Reopening the installer in a fresh Windows Terminal window...
    call :relaunch_self_in_fresh_terminal "--pwsh-relaunched"
    if errorlevel 1 goto relaunch_failed
    goto finish_ok
)

echo PowerShell was installed or upgraded, but the installer still could not locate pwsh.exe.
echo Close this window, open a new one, and run install_server.bat again.
goto finish_error

:relaunch_failed
echo The installer could not reopen itself in a fresh terminal window.
echo Close this window, open a new one, and run install_server.bat again.
goto finish_error

:winget_failed
echo Automatic WinGet install or repair failed.
echo Install or repair App Installer manually, then run install_server.bat again.
goto finish_error

:no_winget
echo The installer cannot continue without WinGet.
goto finish_error

:wt_failed
echo Automatic Windows Terminal install or upgrade failed.
echo Install Windows Terminal manually, then run install_server.bat again.
goto finish_error

:no_wt
echo The installer cannot continue without Windows Terminal.
goto finish_error

:no_install
echo The installer cannot continue without PowerShell 7.x.
goto finish_error

:elevation_failed
echo Administrator access was not granted.
echo Click Yes on the Windows prompt next time, then run install_server.bat again if needed.
goto finish_error

:run_installer
"%PWSH_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0installation_scripts\install_server.ps1"
set "INSTALL_EXIT=%errorlevel%"
goto finish_install

:finish_install
echo.
if not "%INSTALL_EXIT%"=="0" (
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

:elevate_self
set "ELEVATION_FLAGS=--elevated"
if "%RELAUNCHED%"=="1" set "ELEVATION_FLAGS=%ELEVATION_FLAGS% --pwsh-relaunched"
call :run_relaunch_helper "%ELEVATION_FLAGS%" "1"
exit /b %errorlevel%

:is_elevated
set "IS_ELEVATED=0"
fltmc >nul 2>nul
if not errorlevel 1 set "IS_ELEVATED=1"
exit /b 0

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

:find_wt
set "WT_EXE="
for /f "delims=" %%I in ('where wt.exe 2^>nul') do (
    set "WT_EXE=%%~fI"
    goto :eof
)
if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe" (
    set "WT_EXE=%LOCALAPPDATA%\Microsoft\WindowsApps\wt.exe"
    goto :eof
)
exit /b 0

:find_pwsh
set "PWSH_EXE="
pwsh.exe -NoProfile -Command "$PSVersionTable.PSVersion.Major" >nul 2>nul
if not errorlevel 1 (
    set "PWSH_EXE=pwsh.exe"
    goto :eof
)
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

:relaunch_self_in_fresh_terminal
call :run_relaunch_helper "%~1" "0"
exit /b %errorlevel%

:run_relaunch_helper
set "WINPS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%WINPS_EXE%" set "WINPS_EXE=powershell.exe"
set "COD4_INSTALLER_PATH=%~f0"
set "COD4_INSTALLER_FLAGS=%~1"
set "COD4_INSTALLER_ELEVATED=False"
if "%~2"=="1" set "COD4_INSTALLER_ELEVATED=True"
"%WINPS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0installation_scripts\relaunch_installer.ps1"
set "COD4_INSTALLER_PATH="
set "COD4_INSTALLER_FLAGS="
set "COD4_INSTALLER_ELEVATED="
exit /b %errorlevel%