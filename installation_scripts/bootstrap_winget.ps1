Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Get-WindowsAppsPath {
    return (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps")
}

function Add-ProcessPathEntryIfMissing {
    param([string] $Entry)

    if ([string]::IsNullOrWhiteSpace($Entry) -or -not (Test-Path -LiteralPath $Entry)) {
        return
    }

    $trimmedEntry = $Entry.TrimEnd('\')
    $processParts = @()
    if ($env:PATH) {
        $processParts = $env:PATH -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $hasProcessEntry = $processParts | Where-Object { $_.TrimEnd('\') -ieq $trimmedEntry } | Select-Object -First 1
    if (-not $hasProcessEntry) {
        $env:PATH = if ($env:PATH) { "$Entry;$env:PATH" } else { $Entry }
    }
}

function Add-PersistentPathEntryIfMissing {
    param([string] $Entry)

    if ([string]::IsNullOrWhiteSpace($Entry) -or -not (Test-Path -LiteralPath $Entry)) {
        return
    }

    $trimmedEntry = $Entry.TrimEnd('\')
    foreach ($scope in @("Machine", "User")) {
        $scopePath = [Environment]::GetEnvironmentVariable("Path", $scope)
        $scopePathParts = @()
        if ($scopePath) {
            $scopePathParts = $scopePath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        }

        $hasScopeEntry = $scopePathParts | Where-Object { $_.TrimEnd('\') -ieq $trimmedEntry } | Select-Object -First 1
        if ($hasScopeEntry) {
            return
        }
    }

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $updatedMachinePath = if ($machinePath) { "$Entry;$machinePath" } else { $Entry }
    try {
        [Environment]::SetEnvironmentVariable("Path", $updatedMachinePath, "Machine")
        return
    }
    catch {
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $updatedUserPath = if ($userPath) { "$Entry;$userPath" } else { $Entry }
    [Environment]::SetEnvironmentVariable("Path", $updatedUserPath, "User")
}

function Ensure-PathEntryIfMissing {
    param([string] $Entry)

    Add-ProcessPathEntryIfMissing -Entry $Entry
    Add-PersistentPathEntryIfMissing -Entry $Entry
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

Ensure-PathEntryIfMissing -Entry (Get-WindowsAppsPath)

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
Ensure-PathEntryIfMissing -Entry (Get-WindowsAppsPath)
Request-WingetRegistration

if (-not (Test-WingetAvailable)) {
    throw "WinGet is still unavailable after automatic repair."
}

Write-Host "WinGet is installed and ready."
