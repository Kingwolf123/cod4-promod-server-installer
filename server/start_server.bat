@echo off
setlocal EnableExtensions
REM To edit COD4 launch arguments, open server\start_script\server_args.psd1 with notepad / text editor

call :find_pwsh
call :get_pwsh_major
if not defined PWSH_EXE goto need_pwsh
if not defined PWSH_MAJOR goto need_pwsh
if %PWSH_MAJOR% LSS 7 goto need_pwsh

"%PWSH_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_script\start_services.ps1" -Action Match %*
set "START_EXIT=%errorlevel%"
if not "%START_EXIT%"=="0" (
    echo.
    pause
)
exit /b %START_EXIT%

:need_pwsh
echo PowerShell 7 is required to start this server.
echo Run ..\install_server.bat first.
exit /b 1

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
