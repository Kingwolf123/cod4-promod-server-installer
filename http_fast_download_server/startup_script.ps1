param(
    [Parameter(Position = 0)]
    [ValidateRange(1,65535)]
    [int] $Port = 8000,

    [Parameter(Position = 1)]
    [string] $Bind = "::"
)

Set-StrictMode -Version Latest

function Get-CommandSourceIfAvailable {
    param([string] $Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Get-WindowsAppsPath {
    return (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps")
}

function Get-PythonInvocation {
    $pythonCommand = Get-CommandSourceIfAvailable -Name "python"
    if ($pythonCommand) {
        return [pscustomobject]@{
            FilePath = $pythonCommand
            Arguments = @()
        }
    }

    $pyCommand = Get-CommandSourceIfAvailable -Name "py"
    if (-not $pyCommand) {
        $windowsAppsPy = Join-Path (Get-WindowsAppsPath) "py.exe"
        if (Test-Path -LiteralPath $windowsAppsPy) {
            $pyCommand = $windowsAppsPy
        }
    }

    if ($pyCommand) {
        return [pscustomobject]@{
            FilePath = $pyCommand
            Arguments = @("-V:3")
        }
    }

    return $null
}

$pythonInvocation = Get-PythonInvocation
if (-not $pythonInvocation) {
    throw "Python is not installed or not available in PATH. Run install_server.bat first, or install Python manually."
}

$address = "http://[$Bind]:$Port/"
Write-Host "Starting IPv6 Python HTTP server..."
Write-Host "Address: $address"
Write-Host ""
Write-Host "DO NOT CLOSE THIS WINDOW OR TERMINAL."
Write-Host "FASTDL WILL STOP WORKING IF YOU CLOSE IT."
Write-Host ""
Write-Host "Press Ctrl+C to stop.`n"

& $pythonInvocation.FilePath @($pythonInvocation.Arguments + @("-m", "http.server", "$Port", "--bind", $Bind))

