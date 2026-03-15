param(
    [ValidateSet("Match", "Http", "Game", "Status")]
    [string] $Action = "Match",

    [switch] $InTerminal,

    [ValidateRange(1, 65535)]
    [int] $Port = 8000,

    [string] $Bind = "::"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NativeExitCodeOrZero {
    $exitCodeVar = Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue
    if ($exitCodeVar) {
        return [int] $exitCodeVar.Value
    }

    return 0
}

function Get-WindowsTerminalPath {
    $wtPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"
    if (Test-Path -LiteralPath $wtPath) {
        return $wtPath
    }

    return "wt.exe"
}

function Open-InWindowsTerminal {
    param(
        [Parameter(Mandatory = $true)]
        [string] $WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,

        [switch] $NewTab,

        [string] $WindowId,

        [string] $Title,

        [switch] $KeepOpen
    )

    $resolvedWorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
    $scriptPath = Join-Path $PSScriptRoot "start_services.ps1"

    $argumentList = @()
    if ($WindowId) {
        $argumentList += @("-w", $WindowId)
    }

    if ($NewTab) {
        $argumentList += "new-tab"
    }

    if ($Title) {
        $argumentList += @("--title", "`"$Title`"")
    }

    $pwshArgs = @()
    if ($KeepOpen) {
        $pwshArgs += "-NoExit"
    }

    $pwshArgs += @(
        "-ExecutionPolicy", "Bypass",
        "-File", $scriptPath
    ) + $Arguments

    $argumentList += @(
        "-d", $resolvedWorkingDirectory,
        "pwsh.exe"
    ) + $pwshArgs

    Start-Process -FilePath (Get-WindowsTerminalPath) -ArgumentList $argumentList | Out-Null
}

function Test-IsUsableGlobalIpv6 {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance] $Address
    )

    if ($Address.AddressFamily -ne 23) { return $false }
    if ($Address.AddressState -notin @("Preferred", "Deprecated")) { return $false }
    if ($Address.SkipAsSource) { return $false }
    if ($Address.IPAddress -match "^(fe80|fd|fc|::1)") { return $false }

    return $Address.IPAddress -match "^[23][0-9a-fA-F]{3}:"
}

function Test-IsUsableGlobalTemporaryIpv6 {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance] $Address
    )

    if (-not (Test-IsUsableGlobalIpv6 -Address $Address)) { return $false }
    return $Address.SuffixOrigin -eq "Random"
}

function Test-IsUsableGlobalStableIpv6 {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance] $Address
    )

    if (-not (Test-IsUsableGlobalIpv6 -Address $Address)) { return $false }
    return $Address.SuffixOrigin -in @("Dhcp", "Manual")
}

function Get-PreferredIpv6Address {
    param(
        [bool] $PreferStableIpv6 = $false
    )

    $addresses = Get-NetIPAddress -AddressFamily IPv6 |
        Where-Object {
            if ($PreferStableIpv6) {
                Test-IsUsableGlobalStableIpv6 $_
            }
            else {
                Test-IsUsableGlobalTemporaryIpv6 $_
            }
        } |
        Sort-Object -Property @{
            Expression = { $_.AddressState -ne "Preferred" }
            Ascending = $true
        }, @{
            Expression = {
                if ($PreferStableIpv6) {
                    return $_.SuffixOrigin -ne "Dhcp"
                }

                return $_.SuffixOrigin -ne "Random"
            }
            Ascending = $true
        }, @{
            Expression = { $_.PrefixLength }
            Ascending = $false
        }, @{
            Expression = { $_.ValidLifetime.TotalSeconds }
            Ascending = $false
        }

    return $addresses | Select-Object -First 1
}

function Get-LauncherSettings {
    param(
        [hashtable] $ServerArgsConfig
    )

    if ($ServerArgsConfig.ContainsKey("Launcher") -and $ServerArgsConfig.Launcher -is [hashtable]) {
        return $ServerArgsConfig.Launcher
    }

    return @{}
}

function Get-ServerArgValue {
    param(
        [string[]] $ServerArgs,
        [string] $Name
    )

    $index = [Array]::IndexOf($ServerArgs, $Name)
    if ($index -ge 0 -and ($index + 1) -lt $ServerArgs.Count) {
        return $ServerArgs[$index + 1]
    }

    return $null
}

function Get-ConfigQuotedValue {
    param(
        [string] $ConfigPath,
        [string] $Directive
    )

    $pattern = '^[ \t]*' + [regex]::Escape($Directive) + '[ \t]+"([^"]*)"'
    foreach ($line in Get-Content -LiteralPath $ConfigPath) {
        if ($line -match $pattern) {
            return $Matches[1]
        }
    }

    return ""
}

function Get-MatchStartupContext {
    $serverRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
    $httpRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\http_fast_download_server")).Path
    $serverArgsPath = Join-Path $PSScriptRoot "server_args.psd1"

    try {
        $serverArgsConfig = Import-PowerShellDataFile -LiteralPath $serverArgsPath
    }
    catch {
        $serverArgsBackupPath = "$serverArgsPath.bak"
        if (Test-Path -LiteralPath $serverArgsBackupPath) {
            throw "server_args.psd1 could not be parsed. Restore server\start_script\server_args.psd1 from server_args.psd1.bak or rerun install_server.bat. $($_.Exception.Message)"
        }

        throw "server_args.psd1 could not be parsed. Rerun install_server.bat. $($_.Exception.Message)"
    }

    $serverArgs = @($serverArgsConfig.MatchServer)
    $launcherSettings = Get-LauncherSettings -ServerArgsConfig $serverArgsConfig
    $preferStableIpv6 = $false
    if ($launcherSettings.ContainsKey("PreferStableIpv6")) {
        $preferStableIpv6 = [bool] $launcherSettings.PreferStableIpv6
    }

    $modGame = Get-ServerArgValue -ServerArgs $serverArgs -Name "fs_game"
    if (-not $modGame) {
        throw "fs_game was not found in server_args.psd1"
    }

    $modConfig = Join-Path $serverRoot (($modGame -replace "/", "\") + "\server_match.cfg")
    $gamePort = Get-ServerArgValue -ServerArgs $serverArgs -Name "net_port"
    $gamePassword = Get-ConfigQuotedValue -ConfigPath $modConfig -Directive "set g_password"

    return @{
        HttpRoot         = $httpRoot
        ModConfig        = $modConfig
        GamePassword     = $gamePassword
        GamePort         = $gamePort
        PreferStableIpv6 = $preferStableIpv6
        ServerArgs       = $serverArgs
        ServerArgsConfig = $serverArgsConfig
        ServerRoot       = $serverRoot
    }
}

function Get-ConnectCommandText {
    param(
        [string] $ShareableIpv6,
        [string] $GamePort,
        [string] $GamePassword
    )

    if ([string]::IsNullOrWhiteSpace($ShareableIpv6) -or [string]::IsNullOrWhiteSpace($GamePort)) {
        return ""
    }

    $connectCommand = "connect [$ShareableIpv6]:$GamePort"
    if (-not [string]::IsNullOrWhiteSpace($GamePassword)) {
        $connectCommand += ";password $GamePassword"
    }

    return $connectCommand
}

function Update-FastDownloadUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ConfigPath,

        [ValidateRange(1, 65535)]
        [int] $FastDlPort,

        [string] $ContentPath = "cod4/",

        [bool] $PreferStableIpv6 = $false
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    $selectedAddress = Get-PreferredIpv6Address -PreferStableIpv6:$PreferStableIpv6
    if (-not $selectedAddress) {
        if ($PreferStableIpv6) {
            throw "No usable global DHCPv6 or static IPv6 address was found."
        }

        throw "No usable temporary global IPv6 address with SuffixOrigin=Random was found."
    }

    $normalizedContentPath = $ContentPath.TrimStart("/")
    if ($normalizedContentPath -and -not $normalizedContentPath.EndsWith("/")) {
        $normalizedContentPath += "/"
    }

    $fastDlUrl = "http://[$($selectedAddress.IPAddress)]:$FastDlPort/$normalizedContentPath"
    $configLines = Get-Content -LiteralPath $ConfigPath
    $updated = $false

    for ($i = 0; $i -lt $configLines.Count; $i++) {
        if ($configLines[$i] -match '^[ \t]*seta[ \t]+sv_wwwBaseURL\b') {
            $configLines[$i] = "seta sv_wwwBaseURL `"$fastDlUrl`" // defines url to download from"
            $updated = $true
            break
        }
    }

    if (-not $updated) {
        throw "sv_wwwBaseURL was not found in $ConfigPath"
    }

    Set-Content -LiteralPath $ConfigPath -Value $configLines -Encoding ASCII
    return $selectedAddress.IPAddress
}

function Start-HttpServer {
    param(
        [switch] $TerminalHosted,

        [ValidateRange(1, 65535)]
        [int] $HttpPort,

        [string] $HttpBind = "::"
    )

    $httpRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\http_fast_download_server")).Path
    $startupScript = Join-Path $httpRoot "startup_script.ps1"

    if (-not $TerminalHosted) {
        Open-InWindowsTerminal `
            -WorkingDirectory $httpRoot `
            -Arguments @("-Action", "Http", "-InTerminal", "-Port", "$HttpPort", "-Bind", $HttpBind) `
            -Title "FASTDL_HTTP_SERVER" `
            -KeepOpen
        return
    }

    Set-Location -LiteralPath $httpRoot
    & $startupScript -Port $HttpPort -Bind $HttpBind
    exit (Get-NativeExitCodeOrZero)
}

function Start-StatusTab {
    param(
        [switch] $TerminalHosted
    )

    $matchContext = Get-MatchStartupContext
    $serverRoot = $matchContext.ServerRoot

    if (-not $TerminalHosted) {
        Open-InWindowsTerminal `
            -WorkingDirectory $serverRoot `
            -Arguments @("-Action", "Status", "-InTerminal") `
            -NewTab `
            -WindowId 0 `
            -Title "CONNECT_COMMAND" `
            -KeepOpen
        return
    }

    $shareableIpv6Address = Get-PreferredIpv6Address -PreferStableIpv6:$matchContext.PreferStableIpv6
    $shareableIpv6 = if ($shareableIpv6Address) { $shareableIpv6Address.IPAddress } else { "" }
    $commandText = Get-ConnectCommandText `
        -ShareableIpv6 $shareableIpv6 `
        -GamePort $matchContext.GamePort `
        -GamePassword $matchContext.GamePassword

    Write-Host ""
    Write-Host "SHARE THIS WITH PLAYERS:"
    if ([string]::IsNullOrWhiteSpace($commandText)) {
        Write-Host "Connect command was not generated."
    }
    else {
        Write-Host $commandText
    }
    Write-Host ""
    return
}

function Start-GameServer {
    param(
        [switch] $TerminalHosted
    )

    $serverRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
    $serverArgsPath = Join-Path $PSScriptRoot "server_args.psd1"
    $serverArgsConfig = Import-PowerShellDataFile -LiteralPath $serverArgsPath
    $serverArgs = @($serverArgsConfig.MatchServer)
    $serverExe = Join-Path $serverRoot "cod4x18_dedrun.exe"

    if (-not $TerminalHosted) {
        Open-InWindowsTerminal `
            -WorkingDirectory $serverRoot `
            -Arguments @("-Action", "Game", "-InTerminal") `
            -NewTab `
            -WindowId 0 `
            -Title "COD4_MATCH_SERVER" `
            -KeepOpen
        return
    }

    Set-Location -LiteralPath $serverRoot
    & $serverExe @serverArgs
    exit (Get-NativeExitCodeOrZero)
}

function Start-MatchServer {
    param(
        [switch] $TerminalHosted
    )

    $matchContext = Get-MatchStartupContext
    $serverRoot = $matchContext.ServerRoot
    $httpRoot = $matchContext.HttpRoot

    if (-not $TerminalHosted) {
        Set-Location -LiteralPath $serverRoot
        $null = Update-FastDownloadUrl -ConfigPath $matchContext.ModConfig -FastDlPort 8000 -ContentPath "cod4/" -PreferStableIpv6:$matchContext.PreferStableIpv6

        Open-InWindowsTerminal `
            -WorkingDirectory $serverRoot `
            -Arguments @("-Action", "Game", "-InTerminal") `
            -Title "COD4_MATCH_SERVER" `
            -KeepOpen

        Start-Sleep -Milliseconds 300

        Open-InWindowsTerminal `
            -WorkingDirectory $httpRoot `
            -Arguments @("-Action", "Http", "-InTerminal", "-Port", "8000", "-Bind", "::") `
            -NewTab `
            -WindowId 0 `
            -Title "FASTDL_HTTP_SERVER" `
            -KeepOpen

        Open-InWindowsTerminal `
            -WorkingDirectory $serverRoot `
            -Arguments @("-Action", "Status", "-InTerminal") `
            -NewTab `
            -WindowId 0 `
            -Title "CONNECT_COMMAND" `
            -KeepOpen
        return
    }

    Set-Location -LiteralPath $serverRoot
    $null = Update-FastDownloadUrl -ConfigPath $matchContext.ModConfig -FastDlPort 8000 -ContentPath "cod4/" -PreferStableIpv6:$matchContext.PreferStableIpv6

    Open-InWindowsTerminal `
        -WorkingDirectory $serverRoot `
        -Arguments @("-Action", "Game", "-InTerminal") `
        -NewTab `
        -WindowId 0 `
        -Title "COD4_MATCH_SERVER" `
        -KeepOpen

    Open-InWindowsTerminal `
        -WorkingDirectory $httpRoot `
        -Arguments @("-Action", "Http", "-InTerminal", "-Port", "8000", "-Bind", "::") `
        -NewTab `
        -WindowId 0 `
        -Title "FASTDL_HTTP_SERVER" `
        -KeepOpen

    Open-InWindowsTerminal `
        -WorkingDirectory $serverRoot `
        -Arguments @("-Action", "Status", "-InTerminal") `
        -NewTab `
        -WindowId 0 `
        -Title "CONNECT_COMMAND" `
        -KeepOpen

    exit 0
}

switch ($Action) {
    "Match" {
        Start-MatchServer -TerminalHosted:$InTerminal
    }
    "Http" {
        Start-HttpServer -TerminalHosted:$InTerminal -HttpPort $Port -HttpBind $Bind
    }
    "Game" {
        Start-GameServer -TerminalHosted:$InTerminal
    }
    "Status" {
        Start-StatusTab -TerminalHosted:$InTerminal
    }
    default {
        throw "Unsupported action: $Action"
    }
}
