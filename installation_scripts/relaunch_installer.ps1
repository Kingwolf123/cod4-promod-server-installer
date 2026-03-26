Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$installerPath = $env:COD4_INSTALLER_PATH
$flags = $env:COD4_INSTALLER_FLAGS
$elevatedText = $env:COD4_INSTALLER_ELEVATED

if ([string]::IsNullOrWhiteSpace($installerPath)) {
    throw "COD4_INSTALLER_PATH was not provided."
}

$elevated = $false
if (-not [string]::IsNullOrWhiteSpace($elevatedText)) {
    [void] [bool]::TryParse($elevatedText, [ref] $elevated)
}

function Get-WindowsTerminalPath {
    $windowsAppsWt = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"
    if (Test-Path -LiteralPath $windowsAppsWt) {
        return $windowsAppsWt
    }

    $command = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        return $command.Source
    }

    return $null
}

$commandLine = '"' + $installerPath + '"'
if (-not [string]::IsNullOrWhiteSpace($flags)) {
    $commandLine += ' ' + $flags.Trim()
}

$startProcessParameters = $null
$wtPath = Get-WindowsTerminalPath
if ($wtPath) {
    $startProcessParameters = @{
        FilePath     = $wtPath
        ArgumentList = @("new-tab", "--title", "COD4_SERVER_INSTALLER", "cmd.exe", "/c", $commandLine)
    }
}
else {
    $startProcessParameters = @{
        FilePath     = $env:ComSpec
        ArgumentList = @("/c", $commandLine)
    }
}

if ($elevated) {
    $startProcessParameters.Verb = "RunAs"
}

Start-Process @startProcessParameters | Out-Null
