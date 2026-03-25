param(
    [Parameter(Position = 0)]
    [ValidateRange(1,65535)]
    [int] $Port = 8000,

    [Parameter(Position = 1)]
    [string] $Bind = "::",

    [switch] $DualStack
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

function Get-PythonExecutablePaths {
    $candidates = @()
    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")

    $pythonCommand = Get-CommandSourceIfAvailable -Name "python"
    if ($pythonCommand) {
        $candidates += $pythonCommand
    }

    $searchRoots = @()
    if ($env:LOCALAPPDATA) {
        $searchRoots += (Join-Path $env:LOCALAPPDATA "Programs\Python")
    }
    if ($env:ProgramFiles) {
        $searchRoots += (Join-Path $env:ProgramFiles "Python")
    }
    if ($programFilesX86) {
        $searchRoots += (Join-Path $programFilesX86 "Python")
    }

    foreach ($root in $searchRoots | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        $pythonDirs = Get-ChildItem -LiteralPath $root -Directory -Filter "Python*" -ErrorAction SilentlyContinue
        foreach ($pythonDir in $pythonDirs) {
            $candidate = Join-Path $pythonDir.FullName "python.exe"
            if (Test-Path -LiteralPath $candidate) {
                $candidates += $candidate
            }
        }
    }

    return $candidates | Select-Object -Unique
}

function Get-PyCommandPath {
    $candidates = @()
    $programFilesX86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")

    if ($env:WINDIR) {
        $candidates += (Join-Path $env:WINDIR "py.exe")
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Programs\Python\Launcher\py.exe")
    }
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles "Python Launcher\py.exe")
    }
    if ($programFilesX86) {
        $candidates += (Join-Path $programFilesX86 "Python Launcher\py.exe")
    }
    $candidates += (Join-Path (Get-WindowsAppsPath) "py.exe")

    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return (Get-CommandSourceIfAvailable -Name "py")
}

function Get-PythonInvocation {
    foreach ($pythonCommand in Get-PythonExecutablePaths) {
        return [pscustomobject]@{
            FilePath = $pythonCommand
            Arguments = @()
        }
    }

    $pyCommand = Get-PyCommandPath
    if ($pyCommand) {
        return [pscustomobject]@{
            FilePath = $pyCommand
            Arguments = @("-V:3")
        }
    }

    return $null
}

function Get-DisplayHttpAddress {
    param(
        [string] $BindAddress,
        [int] $BindPort
    )

    if ($BindAddress -match ":") {
        return "http://[$BindAddress]:$BindPort/"
    }

    return "http://${BindAddress}:$BindPort/"
}

$pythonInvocation = Get-PythonInvocation
if (-not $pythonInvocation) {
    throw "Python is not installed or not available in PATH. Run install_server.bat first, or install Python manually."
}

$address = Get-DisplayHttpAddress -BindAddress $Bind -BindPort $Port
if ($DualStack -and $Bind -eq "::") {
    Write-Host "Starting dual-stack Python HTTP server..."
    Write-Host "Bind: $address"
    Write-Host "This listener accepts both IPv6 and IPv4 connections."
}
elseif ($Bind -match ":") {
    Write-Host "Starting IPv6 Python HTTP server..."
    Write-Host "Address: $address"
}
else {
    Write-Host "Starting IPv4 Python HTTP server..."
    Write-Host "Address: $address"
}
Write-Host ""
Write-Host "DO NOT CLOSE THIS WINDOW OR TERMINAL."
Write-Host "FASTDL WILL STOP WORKING IF YOU CLOSE IT."
Write-Host ""
Write-Host "Press Ctrl+C to stop.`n"

if ($DualStack -and $Bind -eq "::") {
    $dualStackServerScript = @"
import functools
import http.server
import os
import socket
import sys

port = int(sys.argv[1])
bind = sys.argv[2]

class DualStackHTTPServer(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6
    allow_reuse_address = True

    def server_bind(self):
        try:
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        except OSError:
            pass
        super().server_bind()

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=os.getcwd())
with DualStackHTTPServer((bind, port), handler) as httpd:
    httpd.serve_forever()
"@

    $dualStackServerScript | & $pythonInvocation.FilePath @($pythonInvocation.Arguments + @('-', "$Port", $Bind))
}
else {
    & $pythonInvocation.FilePath @($pythonInvocation.Arguments + @("-m", "http.server", "$Port", "--bind", $Bind))
}
