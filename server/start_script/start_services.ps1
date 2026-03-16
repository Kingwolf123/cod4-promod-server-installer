param(
    [ValidateSet("Match", "Http", "Game", "Status")]
    [string] $Action = "Match",

    [switch] $InTerminal,

    [ValidateRange(1, 65535)]
    [int] $Port = 8000,

    [string] $Bind = "::",

    [switch] $DualStack
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
        $argumentList += @("--window", $WindowId)
    }

    # Be explicit for all launches instead of relying on wt's implicit default action.
    $argumentList += "new-tab"

    if ($Title) {
        $argumentList += @("--title", $Title)
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

function Focus-WindowsTerminalTab {
    param(
        [string] $WindowId = "0",

        [Parameter(Mandatory = $true)]
        [int] $TargetIndex
    )

    Start-Process `
        -FilePath (Get-WindowsTerminalPath) `
        -ArgumentList @("--window", $WindowId, "focus-tab", "--target", "$TargetIndex") | Out-Null
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

    $preferredAddresses = Get-NetIPAddress -AddressFamily IPv6 |
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

    $selectedPreferredAddress = $preferredAddresses | Select-Object -First 1
    if ($selectedPreferredAddress) {
        return $selectedPreferredAddress
    }

    $fallbackAddresses = Get-NetIPAddress -AddressFamily IPv6 |
        Where-Object {
            if ($PreferStableIpv6) {
                Test-IsUsableGlobalTemporaryIpv6 $_
            }
            else {
                Test-IsUsableGlobalStableIpv6 $_
            }
        } |
        Sort-Object -Property @{
            Expression = { $_.AddressState -ne "Preferred" }
            Ascending = $true
        }, @{
            Expression = {
                if ($PreferStableIpv6) {
                    return $_.SuffixOrigin -ne "Random"
                }

                return $_.SuffixOrigin -ne "Dhcp"
            }
            Ascending = $true
        }, @{
            Expression = { $_.PrefixLength }
            Ascending = $false
        }, @{
            Expression = { $_.ValidLifetime.TotalSeconds }
            Ascending = $false
        }

    return $fallbackAddresses | Select-Object -First 1
}

function Test-IsUsableUlaIpv6 {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance] $Address
    )

    if ($Address.AddressFamily -ne 23) { return $false }
    if ($Address.AddressState -notin @("Preferred", "Deprecated")) { return $false }
    if ($Address.SkipAsSource) { return $false }
    if ($Address.IPAddress -match "^(fe80|::1)") { return $false }

    return $Address.IPAddress -match "^(fd|fc)"
}

function Get-PreferredUlaIpv6Address {
    $addresses = Get-NetIPAddress -AddressFamily IPv6 |
        Where-Object { Test-IsUsableUlaIpv6 $_ } |
        Sort-Object -Property @{
            Expression = { $_.AddressState -ne "Preferred" }
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

function Test-IsUsableIpv4 {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance] $Address
    )

    if ($Address.AddressFamily -ne 2) { return $false }
    if ($Address.AddressState -notin @("Preferred", "Deprecated")) { return $false }
    if ($Address.SkipAsSource) { return $false }
    if ($Address.IPAddress -match "^(127\.|169\.254\.)") { return $false }

    return $true
}

function Test-IsUsableLanIpv4 {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Management.Infrastructure.CimInstance] $Address
    )

    if (-not (Test-IsUsableIpv4 -Address $Address)) { return $false }
    return $Address.IPAddress -match "^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)"
}

function Get-PreferredIpv4RouteInterfaceIndex {
    $defaultRoute = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DestinationPrefix -eq "0.0.0.0/0" -and
            $_.NextHop -ne "0.0.0.0"
        } |
        Sort-Object -Property @{
            Expression = { $_.RouteMetric }
            Ascending = $true
        }, @{
            Expression = { $_.ifIndex }
            Ascending = $true
        } |
        Select-Object -First 1

    if ($defaultRoute) {
        return [int] $defaultRoute.ifIndex
    }

    return $null
}

function Select-BestIpv4Address {
    param(
        [Microsoft.Management.Infrastructure.CimInstance[]] $Candidates
    )

    if (-not $Candidates) {
        return $null
    }

    $preferredInterfaceIndex = Get-PreferredIpv4RouteInterfaceIndex
    $sortedCandidates = $Candidates |
        Sort-Object -Property @{
            Expression = {
                if ($null -eq $preferredInterfaceIndex) {
                    return $false
                }

                return $_.InterfaceIndex -ne $preferredInterfaceIndex
            }
            Ascending = $true
        }, @{
            Expression = { $_.AddressState -ne "Preferred" }
            Ascending = $true
        }, @{
            Expression = { $_.PrefixLength }
            Ascending = $false
        }, @{
            Expression = {
                if ($_.ValidLifetime) {
                    return $_.ValidLifetime.TotalSeconds
                }

                return 0
            }
            Ascending = $false
        }

    return $sortedCandidates | Select-Object -First 1
}

function Get-PreferredIpv4Address {
    $lanCandidates = @(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { Test-IsUsableLanIpv4 $_ })
    $selectedLanAddress = Select-BestIpv4Address -Candidates $lanCandidates
    if ($selectedLanAddress) {
        return $selectedLanAddress
    }

    return $null
}

function Get-PreferredFastDownloadEndpoint {
    param(
        [bool] $PreferStableIpv6 = $false,

        [ValidateSet("LanIpv4", "UlaIpv6")]
        [string] $NoGlobalIpv6FastDlPreference = "LanIpv4"
    )

    $selectedIpv6 = Get-PreferredIpv6Address -PreferStableIpv6:$PreferStableIpv6
    if ($selectedIpv6) {
        return [pscustomobject]@{
            Address       = $selectedIpv6.IPAddress
            AddressFamily = "IPv6"
            EndpointType  = "GlobalIpv6"
            UseDualStack  = $false
        }
    }

    $fallbackOrder = if ($NoGlobalIpv6FastDlPreference -eq "UlaIpv6") {
        @("UlaIpv6", "LanIpv4")
    }
    else {
        @("LanIpv4", "UlaIpv6")
    }

    foreach ($fallbackType in $fallbackOrder) {
        if ($fallbackType -eq "LanIpv4") {
            $selectedIpv4 = Get-PreferredIpv4Address
            if ($selectedIpv4) {
                return [pscustomobject]@{
                    Address       = $selectedIpv4.IPAddress
                    AddressFamily = "IPv4"
                    EndpointType  = "LanIpv4"
                    UseDualStack  = $true
                }
            }
        }
        else {
            $selectedUlaIpv6 = Get-PreferredUlaIpv6Address
            if ($selectedUlaIpv6) {
                return [pscustomobject]@{
                    Address       = $selectedUlaIpv6.IPAddress
                    AddressFamily = "IPv6"
                    EndpointType  = "UlaIpv6"
                    UseDualStack  = $true
                }
            }
        }
    }

    return $null
}

function Get-FastDownloadUrl {
    param(
        [Parameter(Mandatory = $true)]
        [psobject] $Endpoint,

        [ValidateRange(1, 65535)]
        [int] $FastDlPort,

        [string] $ContentPath = "cod4/"
    )

    $normalizedContentPath = $ContentPath.TrimStart("/")
    if ($normalizedContentPath -and -not $normalizedContentPath.EndsWith("/")) {
        $normalizedContentPath += "/"
    }

    $hostAddress = if ($Endpoint.AddressFamily -eq "IPv6") {
        "[$($Endpoint.Address)]"
    }
    else {
        $Endpoint.Address
    }

    return "http://${hostAddress}:$FastDlPort/$normalizedContentPath"
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
    $noGlobalIpv6FastDlPreference = "LanIpv4"
    if ($launcherSettings.ContainsKey("PreferStableIpv6")) {
        $preferStableIpv6 = [bool] $launcherSettings.PreferStableIpv6
    }
    if ($launcherSettings.ContainsKey("NoGlobalIpv6FastDlPreference")) {
        $configuredPreference = [string] $launcherSettings.NoGlobalIpv6FastDlPreference
        if ($configuredPreference -notin @("LanIpv4", "UlaIpv6")) {
            throw "Launcher.NoGlobalIpv6FastDlPreference must be LanIpv4 or UlaIpv6."
        }

        $noGlobalIpv6FastDlPreference = $configuredPreference
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
        NoGlobalIpv6FastDlPreference = $noGlobalIpv6FastDlPreference
        PreferStableIpv6 = $preferStableIpv6
        ServerArgs       = $serverArgs
        ServerArgsConfig = $serverArgsConfig
        ServerRoot       = $serverRoot
    }
}

function Get-ConnectCommandText {
    param(
        [string] $ShareableAddress,
        [ValidateSet("IPv4", "IPv6")]
        [string] $AddressFamily = "IPv6",
        [string] $GamePort,
        [string] $GamePassword
    )

    if ([string]::IsNullOrWhiteSpace($ShareableAddress) -or [string]::IsNullOrWhiteSpace($GamePort)) {
        return ""
    }

    $connectAddress = if ($AddressFamily -eq "IPv6") {
        "[$ShareableAddress]"
    }
    else {
        $ShareableAddress
    }

    $connectCommand = "connect ${connectAddress}:$GamePort"
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

        [bool] $PreferStableIpv6 = $false,

        [ValidateSet("LanIpv4", "UlaIpv6")]
        [string] $NoGlobalIpv6FastDlPreference = "LanIpv4"
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    $selectedEndpoint = Get-PreferredFastDownloadEndpoint `
        -PreferStableIpv6:$PreferStableIpv6 `
        -NoGlobalIpv6FastDlPreference $NoGlobalIpv6FastDlPreference
    if (-not $selectedEndpoint) {
        return $null
    }

    $fastDlUrl = Get-FastDownloadUrl -Endpoint $selectedEndpoint -FastDlPort $FastDlPort -ContentPath $ContentPath
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
    return $selectedEndpoint
}
function Start-HttpServer {
    param(
        [switch] $TerminalHosted,

        [ValidateRange(1, 65535)]
        [int] $HttpPort,

        [string] $HttpBind = "::",

        [switch] $UseDualStack
    )

    $httpRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\http_fast_download_server")).Path
    $startupScript = Join-Path $httpRoot "startup_script.ps1"

    if (-not $TerminalHosted) {
        $httpArguments = @("-Action", "Http", "-InTerminal", "-Port", "$HttpPort", "-Bind", $HttpBind)
        if ($UseDualStack) {
            $httpArguments += "-DualStack"
        }

        Open-InWindowsTerminal `
            -WorkingDirectory $httpRoot `
            -Arguments $httpArguments `
            -Title "FASTDL_HTTP_SERVER" `
            -KeepOpen
        return
    }

    Set-Location -LiteralPath $httpRoot
    if ($UseDualStack) {
        & $startupScript -Port $HttpPort -Bind $HttpBind -DualStack
    }
    else {
        & $startupScript -Port $HttpPort -Bind $HttpBind
    }
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
        -ShareableAddress $shareableIpv6 `
        -AddressFamily "IPv6" `
        -GamePort $matchContext.GamePort `
        -GamePassword $matchContext.GamePassword
    $lanIpv4Address = Get-PreferredIpv4Address
    $lanIpv4 = if ($lanIpv4Address) { $lanIpv4Address.IPAddress } else { "" }
    $ipv4CommandText = Get-ConnectCommandText `
        -ShareableAddress $lanIpv4 `
        -AddressFamily "IPv4" `
        -GamePort $matchContext.GamePort `
        -GamePassword $matchContext.GamePassword
    $ulaIpv6Address = Get-PreferredUlaIpv6Address
    $ulaIpv6 = if ($ulaIpv6Address) { $ulaIpv6Address.IPAddress } else { "" }
    $ulaCommandText = Get-ConnectCommandText `
        -ShareableAddress $ulaIpv6 `
        -AddressFamily "IPv6" `
        -GamePort $matchContext.GamePort `
        -GamePassword $matchContext.GamePassword

    Write-Host ""
    Write-Host "SHARE THIS WITH PLAYERS:"
    if ([string]::IsNullOrWhiteSpace($commandText)) {
        Write-Host "NO PUBLIC IPV6 WAS DETECTED."
        Write-Host "The server still started."
        if (-not [string]::IsNullOrWhiteSpace($ipv4CommandText)) {
            Write-Host "LAN IPv4 connect command:"
            Write-Host $ipv4CommandText
            Write-Host "That IPv4 is local/private, so remote players still need your public IPv4 and port forwarding."
        }

        if (-not [string]::IsNullOrWhiteSpace($ulaCommandText)) {
            $ulaLabel = if (-not [string]::IsNullOrWhiteSpace($ipv4CommandText)) {
                "For same-LAN players, you can also try this ULA connect command:"
            }
            else {
                "For same-LAN players, you can try this ULA connect command:"
            }

            Write-Host $ulaLabel
            Write-Host $ulaCommandText
        }
        elseif ([string]::IsNullOrWhiteSpace($ipv4CommandText)) {
            Write-Host "No ULA IPv6 address was detected for LAN-only sharing."
        }
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
            -Title "COD4_MATCH_SERVER"
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
        $fastDlEndpoint = Update-FastDownloadUrl `
            -ConfigPath $matchContext.ModConfig `
            -FastDlPort 8000 `
            -ContentPath "cod4/" `
            -PreferStableIpv6:$matchContext.PreferStableIpv6 `
            -NoGlobalIpv6FastDlPreference $matchContext.NoGlobalIpv6FastDlPreference
        $httpArguments = @("-Action", "Http", "-InTerminal", "-Port", "8000", "-Bind", "::")
        if (-not $fastDlEndpoint -or $fastDlEndpoint.UseDualStack) {
            $httpArguments += "-DualStack"
        }

        Open-InWindowsTerminal `
            -WorkingDirectory $serverRoot `
            -Arguments @("-Action", "Game", "-InTerminal") `
            -Title "COD4_MATCH_SERVER"

        Start-Sleep -Milliseconds 500

        Open-InWindowsTerminal `
            -WorkingDirectory $httpRoot `
            -Arguments $httpArguments `
            -NewTab `
            -WindowId 0 `
            -Title "FASTDL_HTTP_SERVER" `
            -KeepOpen

        Start-Sleep -Milliseconds 250

        Open-InWindowsTerminal `
            -WorkingDirectory $serverRoot `
            -Arguments @("-Action", "Status", "-InTerminal") `
            -NewTab `
            -WindowId 0 `
            -Title "CONNECT_COMMAND" `
            -KeepOpen

        Start-Sleep -Milliseconds 250
        Focus-WindowsTerminalTab -WindowId 0 -TargetIndex 2
        return
    }

    Set-Location -LiteralPath $serverRoot
    $fastDlEndpoint = Update-FastDownloadUrl `
        -ConfigPath $matchContext.ModConfig `
        -FastDlPort 8000 `
        -ContentPath "cod4/" `
        -PreferStableIpv6:$matchContext.PreferStableIpv6 `
        -NoGlobalIpv6FastDlPreference $matchContext.NoGlobalIpv6FastDlPreference
    $httpArguments = @("-Action", "Http", "-InTerminal", "-Port", "8000", "-Bind", "::")
    if (-not $fastDlEndpoint -or $fastDlEndpoint.UseDualStack) {
        $httpArguments += "-DualStack"
    }

    Open-InWindowsTerminal `
        -WorkingDirectory $serverRoot `
        -Arguments @("-Action", "Game", "-InTerminal") `
        -NewTab `
        -WindowId 0 `
        -Title "COD4_MATCH_SERVER"

    Start-Sleep -Milliseconds 250

    Open-InWindowsTerminal `
        -WorkingDirectory $httpRoot `
        -Arguments $httpArguments `
        -NewTab `
        -WindowId 0 `
        -Title "FASTDL_HTTP_SERVER" `
        -KeepOpen

    Start-Sleep -Milliseconds 250

    Open-InWindowsTerminal `
        -WorkingDirectory $serverRoot `
        -Arguments @("-Action", "Status", "-InTerminal") `
        -NewTab `
        -WindowId 0 `
        -Title "CONNECT_COMMAND" `
        -KeepOpen

    Start-Sleep -Milliseconds 250
    Focus-WindowsTerminalTab -WindowId 0 -TargetIndex 3

    exit 0
}
switch ($Action) {
    "Match" {
        Start-MatchServer -TerminalHosted:$InTerminal
    }
    "Http" {
        Start-HttpServer -TerminalHosted:$InTerminal -HttpPort $Port -HttpBind $Bind -UseDualStack:$DualStack
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





