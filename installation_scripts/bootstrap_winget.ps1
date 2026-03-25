Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Get-WindowsAppsPath {
    return (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps")
}

function Test-WingetAvailable {
    try {
        & winget --version *> $null
        if ($LASTEXITCODE -eq 0) {
            return $true
        }
    }
    catch {
    }

    $wingetPath = Join-Path (Get-WindowsAppsPath) "winget.exe"
    if (Test-Path -LiteralPath $wingetPath) {
        try {
            & $wingetPath --version *> $null
            return ($LASTEXITCODE -eq 0)
        }
        catch {
        }
    }

    return $false
}

function Request-WingetRegistration {
    $desktopAppInstaller = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
    if (-not $desktopAppInstaller) {
        return
    }

    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe" -ErrorAction Stop
    }
    catch {
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if (Test-WingetAvailable) {
    Write-Host "WinGet is already available."
    exit 0
}

Write-Host "Requesting WinGet registration..."
Request-WingetRegistration
Start-Sleep -Seconds 2

if (Test-WingetAvailable) {
    Write-Host "WinGet registration completed."
    exit 0
}

Write-Host "Installing Microsoft.WinGet.Client from PSGallery..."
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null

$psGallery = Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue
if (-not $psGallery) {
    Register-PSRepository -Default -ErrorAction SilentlyContinue
    $psGallery = Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue
}
if ($psGallery -and $psGallery.InstallationPolicy -ne "Trusted") {
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
}

Install-Module -Name "Microsoft.WinGet.Client" -Force -Repository "PSGallery" -Scope AllUsers -AllowClobber | Out-Null
Import-Module Microsoft.WinGet.Client -Force

Write-Host "Bootstrapping WinGet..."
Repair-WinGetPackageManager -AllUsers | Out-Null

Start-Sleep -Seconds 2
Request-WingetRegistration

if (-not (Test-WingetAvailable)) {
    throw "WinGet is still unavailable after automatic repair."
}

Write-Host "WinGet is installed and ready."
