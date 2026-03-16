Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$serverRoot = Join-Path $root "server"
$httpRoot = Join-Path $root "http_fast_download_server"
$config = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot "install_config.psd1")
$cod4xServerZipUrl = "https://cod4x.ovh/uploads/short-url/kDLPuAqzAQvrQHSbLtCnl9EE9Ec.zip"
$pythonManagerWingetId = "9NQ7512CXL7T"

function Write-Step {
    param([string] $Text)
    Write-Host ""
    Write-Host "==> $Text"
}

function Read-DefaultValue {
    param(
        [string] $Prompt,
        [string] $DefaultValue
    )

    $suffix = if ($DefaultValue -ne "") { " [$DefaultValue]" } else { "" }
    $value = Read-Host "$Prompt$suffix"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return $value.Trim()
}

function Read-YesNo {
    param(
        [string] $Prompt,
        [bool] $DefaultYes = $true
    )

    $defaultLabel = if ($DefaultYes) { "Y" } else { "N" }
    while ($true) {
        $answer = Read-Host "$Prompt (Y/N) [$defaultLabel]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $DefaultYes
        }

        switch ($answer.Trim().ToUpperInvariant()) {
            "Y" { return $true }
            "YES" { return $true }
            "N" { return $false }
            "NO" { return $false }
            default { Write-Host "Please enter Y or N." }
        }
    }
}

function Assert-PathExists {
    param(
        [string] $Path,
        [string] $HelpText
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$HelpText`nMissing path: $Path"
    }
}

function Assert-LastExitCode {
    param([string] $Operation)

    $exitCodeVar = Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue
    if ($exitCodeVar -and [int] $exitCodeVar.Value -ne 0) {
        throw "$Operation failed with exit code $($exitCodeVar.Value)."
    }
}

function Backup-FileIfNeeded {
    param([string] $Path)

    $backupPath = "$Path.bak"
    if ((Test-Path -LiteralPath $Path) -and -not (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $Path -Destination $backupPath
    }
}
function Convert-ToPowerShellDoubleQuotedStringValue {
    param([string] $Value)

    return $Value.Replace("`r", " ").Replace("`n", " ").Replace('`', '``').Replace('$', '`$').Replace('"', '`"')
}

function Convert-ToCod4CfgQuotedStringValue {
    param([string] $Value)

    return $Value.Replace("`r", " ").Replace("`n", " ").Replace('"', '\"')
}

function Set-QuotedSetting {
    param(
        [string] $Content,
        [string] $Directive,
        [string] $Value
    )

    $escaped = [regex]::Escape($Directive)
    $pattern = "(?im)^([ \t]*$escaped[ \t]+)`"[^`"\r\n]*`"([ \t]*(?://.*)?)(\r?)$"
    $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $regex.IsMatch($Content)) {
        throw "Could not find $Directive in server_match.cfg"
    }

    $escapedValue = Convert-ToCod4CfgQuotedStringValue -Value $Value
    $updated = $regex.Replace($Content, [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return $match.Groups[1].Value + '"' + $escapedValue + '"' + $match.Groups[2].Value + $match.Groups[3].Value
    }, 1)
    return $updated
}

function Set-ServerArgsValue {
    param(
        [string] $Content,
        [string] $Name,
        [string] $Value
    )

    $pattern = '(?m)^(\s*"\+set",\s*"' + [regex]::Escape($Name) + '",\s*")[^"]*(".*)$'
    $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $regex.IsMatch($Content)) {
        throw "Could not find +set $Name in server_args.psd1"
    }

    $escapedValue = Convert-ToPowerShellDoubleQuotedStringValue -Value $Value
    $updated = $regex.Replace($Content, [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return $match.Groups[1].Value + $escapedValue + $match.Groups[2].Value
    }, 1)
    return $updated
}

function Set-DirectCommandValue {
    param(
        [string] $Content,
        [string] $Command,
        [string] $Value
    )

    $pattern = '(?m)^(\s*"' + [regex]::Escape($Command) + '",\s*")[^"]*(".*)$'
    $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $regex.IsMatch($Content)) {
        throw "Could not find $Command in server_args.psd1"
    }

    $escapedValue = Convert-ToPowerShellDoubleQuotedStringValue -Value $Value
    $updated = $regex.Replace($Content, [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return $match.Groups[1].Value + $escapedValue + $match.Groups[2].Value
    }, 1)
    return $updated
}

function Get-DefaultCod4InstallPath {
    $candidates = @(
        (Join-Path $root "Call of Duty Modern Warfare"),
        (Join-Path (Split-Path $root -Parent) "Call of Duty Modern Warfare")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return ""
}

function Get-WindowsAppsPath {
    return (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps")
}

function Add-ProcessPathEntryIfMissing {
    param([string] $Entry)

    if ([string]::IsNullOrWhiteSpace($Entry)) {
        return
    }

    $trimmedEntry = $Entry.TrimEnd('\\')
    $processParts = @()
    if ($env:PATH) {
        $processParts = $env:PATH -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $hasProcessEntry = $processParts | Where-Object { $_.TrimEnd('\\') -ieq $trimmedEntry } | Select-Object -First 1
    if (-not $hasProcessEntry) {
        $env:PATH = if ($env:PATH) { "$Entry;$env:PATH" } else { $Entry }
    }
}

function Get-CommandSourceIfAvailable {
    param([string] $Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $null
}

function Get-PyCommandPath {
    $candidates = @()

    $windowsAppsPy = Join-Path (Get-WindowsAppsPath) "py.exe"
    if (Test-Path -LiteralPath $windowsAppsPy) {
        $candidates += $windowsAppsPy
    }

    $pythonManagerDirs = Get-ChildItem -LiteralPath (Get-WindowsAppsPath) -Directory -Filter "PythonSoftwareFoundation.PythonManager_*" -ErrorAction SilentlyContinue
    foreach ($dir in $pythonManagerDirs) {
        $candidate = Join-Path $dir.FullName "py.exe"
        if (Test-Path -LiteralPath $candidate) {
            $candidates += $candidate
        }
    }

    $existingPy = Get-CommandSourceIfAvailable -Name "py"
    if ($existingPy) {
        $candidates += $existingPy
    }

    return $candidates | Select-Object -Unique | Select-Object -First 1
}

function Test-PythonInstallManagerAvailable {
    param([string] $PyCommand)

    if ([string]::IsNullOrWhiteSpace($PyCommand)) {
        return $false
    }

    try {
        & $PyCommand install --help *> $null
        $exitCodeVar = Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue
        return ($exitCodeVar -and [int] $exitCodeVar.Value -eq 0)
    }
    catch {
        return $false
    }
}

function Get-PythonRuntimeStatus {
    $bestStatus = [pscustomobject]@{
        Available  = $false
        Launcher   = ""
        Major      = 0
        Is64Bit    = $false
        Executable = ""
    }

    $statusScript = 'import json, platform, sys; print(json.dumps({"major": sys.version_info[0], "bits": platform.architecture()[0], "executable": sys.executable}))'
    $candidates = @()

    $pythonCommand = Get-CommandSourceIfAvailable -Name "python"
    if ($pythonCommand) {
        $candidates += [pscustomobject]@{
            Launcher  = "python"
            FilePath  = $pythonCommand
            Arguments = @()
            Operation = "python runtime check"
        }
    }

    $pyCommand = Get-PyCommandPath
    if ($pyCommand) {
        $candidates += [pscustomobject]@{
            Launcher  = "py"
            FilePath  = $pyCommand
            Arguments = @("-V:3")
            Operation = "py runtime check"
        }
    }

    foreach ($candidate in $candidates) {
        try {
            $details = (& $candidate.FilePath @($candidate.Arguments + @("-c", $statusScript))) | ConvertFrom-Json
            Assert-LastExitCode -Operation $candidate.Operation

            $currentStatus = [pscustomobject]@{
                Available  = $true
                Launcher   = [string] $candidate.Launcher
                Major      = [int] $details.major
                Is64Bit    = ($details.bits -eq "64bit")
                Executable = [string] $details.executable
            }

            $currentScore = 0
            if ($currentStatus.Major -ge 3) { $currentScore += 2 }
            if ($currentStatus.Is64Bit) { $currentScore += 1 }

            $bestScore = 0
            if ($bestStatus.Major -ge 3) { $bestScore += 2 }
            if ($bestStatus.Is64Bit) { $bestScore += 1 }

            if (-not $bestStatus.Available -or $currentScore -gt $bestScore) {
                $bestStatus = $currentStatus
            }
        }
        catch {
        }
    }

    return $bestStatus
}

function Ensure-PythonInstalled {
    Write-Step "Python prerequisite"

    Add-ProcessPathEntryIfMissing -Entry (Get-WindowsAppsPath)

    $pythonStatus = Get-PythonRuntimeStatus
    if ($pythonStatus.Available -and $pythonStatus.Major -ge 3 -and $pythonStatus.Is64Bit) {
        Write-Host "A usable 64-bit Python 3 runtime is already installed."
        return
    }

    if ($pythonStatus.Available) {
        Write-Host "Detected Python launcher '$($pythonStatus.Launcher)' at $($pythonStatus.Executable), but it is not a usable 64-bit Python 3 runtime."
    }

    if (-not (Read-YesNo -Prompt "Python is required for the FastDL HTTP server. Install the latest stable 64-bit Python automatically now?" -DefaultYes $true)) {
        throw "Python is required for the FastDL HTTP server. Install Python manually, then rerun install_server.bat."
    }

    $wingetCommand = Get-CommandSourceIfAvailable -Name "winget"
    if (-not $wingetCommand) {
        throw "WinGet was not found. Install Python manually, then rerun install_server.bat."
    }

    $pyCommand = Get-PyCommandPath
    if (-not (Test-PythonInstallManagerAvailable -PyCommand $pyCommand)) {
        Write-Host "Installing or updating the Python Install Manager..."
        & $wingetCommand upgrade --id $pythonManagerWingetId -e --accept-package-agreements --accept-source-agreements --disable-interactivity
        $wingetExitCode = Get-NativeExitCodeOrZero
        if ($wingetExitCode -ne 0) {
            & $wingetCommand install $pythonManagerWingetId -e --accept-package-agreements --accept-source-agreements --disable-interactivity
            Assert-LastExitCode -Operation "Installing the Python Install Manager"
        }

        Start-Sleep -Seconds 2
        Add-ProcessPathEntryIfMissing -Entry (Get-WindowsAppsPath)
        $pyCommand = Get-PyCommandPath
    }

    if (-not (Test-PythonInstallManagerAvailable -PyCommand $pyCommand)) {
        throw "Python Install Manager is unavailable. Open 'Manage app execution aliases', enable the Python aliases, then rerun install_server.bat."
    }

    Write-Host "Configuring the Python Install Manager..."
    & $pyCommand install --configure -y
    Assert-LastExitCode -Operation "Configuring the Python Install Manager"

    $env:PYTHON_MANAGER_DEFAULT_PLATFORM = "-64"

    Write-Host "Installing the latest stable 64-bit Python runtime..."
    & $pyCommand install default
    Assert-LastExitCode -Operation "Installing the latest stable 64-bit Python runtime"

    Write-Host "Refreshing Python command aliases..."
    & $pyCommand install --refresh
    Assert-LastExitCode -Operation "Refreshing Python command aliases"

    Start-Sleep -Seconds 2
    $pythonStatus = Get-PythonRuntimeStatus
    if (-not ($pythonStatus.Available -and $pythonStatus.Major -ge 3 -and $pythonStatus.Is64Bit)) {
        throw "Python was installed, but a usable 64-bit Python 3 runtime is still unavailable. Restart Windows Terminal. If it still fails, open 'Manage app execution aliases' and enable the Python aliases."
    }

    Write-Host "Python is installed and ready for the FastDL HTTP server."
}

function Copy-BaseGameFiles {
    Write-Step "Step 1 - Base game files"
    if (-not (Read-YesNo -Prompt "Copy the base game files from an existing COD4 install now?" -DefaultYes $true)) {
        Write-Host "Skipping automatic base game copy. Make sure server\main and server\zone are copied manually."
        return
    }

    $sourcePath = Read-DefaultValue -Prompt "Enter the COD4 install folder path" -DefaultValue (Get-DefaultCod4InstallPath)
    Assert-PathExists -Path $sourcePath -HelpText "The COD4 install folder was not found."
    Assert-PathExists -Path (Join-Path $sourcePath "main") -HelpText "The COD4 install folder must contain a main folder."
    Assert-PathExists -Path (Join-Path $sourcePath "zone") -HelpText "The COD4 install folder must contain a zone folder."

    Copy-Item -LiteralPath (Join-Path $sourcePath "main") -Destination $serverRoot -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $sourcePath "zone") -Destination $serverRoot -Recurse -Force
    Write-Host "Copied base game files into server\main and server\zone."
}

function Install-Cod4xServerFiles {
    Write-Step "Step 2 - COD4X server files"
    if (-not (Read-YesNo -Prompt "Download and install COD4X server files automatically now?" -DefaultYes $true)) {
        Write-Host "Skipping automatic COD4X download. Make sure the COD4X server files are copied manually into server\."
        return
    }

    $tempRoot = Join-Path $env:TEMP "cod4_promod_server_installer"
    $extractRoot = Join-Path $tempRoot "expanded"
    try {
        $zipPath = Join-Path $tempRoot "cod4x_server.zip"
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        Write-Host "Downloading the full CoD4X server package..."
        Invoke-WebRequest -Uri $cod4xServerZipUrl -OutFile $zipPath

        Write-Host "Extracting COD4X server files..."
        if (Test-Path -LiteralPath $extractRoot) {
            Remove-Item -LiteralPath $extractRoot -Recurse -Force
        }

        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

        $serverExe = Get-ChildItem -LiteralPath $extractRoot -Recurse -Filter "cod4x18_dedrun.exe" -File | Select-Object -First 1
        if (-not $serverExe) {
            throw "COD4X download or extraction failed. cod4x18_dedrun.exe was not found in the extracted package."
        }

        $packageRoot = $serverExe.Directory.FullName
        Write-Host "Copying COD4X server files into server\ ..."
        Get-ChildItem -LiteralPath $packageRoot -Force | Copy-Item -Destination $serverRoot -Recurse -Force

        Assert-PathExists -Path (Join-Path $serverRoot "cod4x18_dedrun.exe") -HelpText "COD4X install failed after extraction."
        Write-Host "COD4X server files installed successfully."
    }
    catch {
        throw "Automatic COD4X install failed: $($_.Exception.Message)`nRerun install_server.bat and answer N for manual COD4X install."
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Ensure-DirectoryExists {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Test-IsLikelyServerModAssetFile {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory = $true)]
        [string] $ServerModPath
    )

    if ($File.Name -match '^PUT_PROMOD.*_HERE\.txt$') {
        return $false
    }

    if ($File.Name -ieq "server_match.cfg") {
        return $false
    }

    $relativePath = $File.FullName.Substring($ServerModPath.Length).TrimStart('\')
    $isRootLevelFile = ($relativePath -notlike "*\*")
    $extension = $File.Extension.ToLowerInvariant()
    $junkExtensions = @(
        ".txt", ".md", ".zip", ".rar", ".7z", ".bak", ".old", ".tmp",
        ".pdf", ".doc", ".docx", ".log", ".cfg",
        ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tga", ".psd",
        ".mp3", ".wav", ".ogg", ".mp4", ".avi", ".mkv"
    )
    if ($extension -in $junkExtensions) {
        return $false
    }

    $knownModExtensions = @(
        ".iwd", ".ff", ".gsc", ".csc", ".menu", ".csv", ".str", ".atr",
        ".vision", ".sun", ".weapon", ".shader", ".hlsl"
    )
    if ($extension -in $knownModExtensions) {
        return $true
    }

    # Allow uncommon custom mod assets only at the mod root.
    return $isRootLevelFile
}

function Get-Step3ValidationErrors {
    param(
        [string] $ModFolder,
        [string] $ServerModPath,
        [string] $HttpModPath
    )

    $validationMessages = @()
    $requiredPaths = @(
        @{
            Path = (Join-Path $serverRoot "cod4x18_dedrun.exe")
            HelpText = "Copy your COD4X dedicated server files into the server folder first."
        },
        @{
            Path = (Join-Path $serverRoot "main")
            HelpText = "Copy the base Call of Duty 4 game files into server\\main first."
        },
        @{
            Path = (Join-Path $serverRoot "zone")
            HelpText = "Copy the base Call of Duty 4 game files into server\\zone first."
        },
        @{
            Path = (Join-Path $httpRoot "cod4")
            HelpText = "The http_fast_download_server\\cod4 folder is missing."
        },
        @{
            Path = (Join-Path $serverRoot "start_script\\server_args.psd1")
            HelpText = "The startup scripts are missing from server\\start_script."
        }
    )

    foreach ($requiredPath in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $requiredPath.Path)) {
            $validationMessages += "$($requiredPath.HelpText) Missing path: $($requiredPath.Path)"
        }
    }

    $serverMatchCfg = Join-Path $ServerModPath "server_match.cfg"

    if (-not (Test-Path -LiteralPath $ServerModPath)) {
        $validationMessages += "Expected the Promod game server folder at server\\mods\\$ModFolder\\. Copy your Promod files there before running the installer."
    }
    else {
        if (-not (Test-Path -LiteralPath $serverMatchCfg)) {
            $validationMessages += "server_match.cfg is missing from server\\mods\\$ModFolder\\. Copy or create it there first."
        }

        $serverModFiles = @(Get-ChildItem -LiteralPath $ServerModPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            Test-IsLikelyServerModAssetFile -File $_ -ServerModPath $ServerModPath
        })
        if ($serverModFiles.Count -eq 0) {
            $validationMessages += "Expected actual mod files in server\\mods\\$ModFolder\\. The folder currently only contains placeholders or non-mod files."
        }

        $serverDemoFolders = @(Get-ChildItem -LiteralPath $ServerModPath -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -ieq "demo" -or $_.Name -ieq "demos"
        })
        if ($serverDemoFolders.Count -gt 0) {
            $validationMessages += "Remove demo folders from server\\mods\\$ModFolder\\ before continuing."
        }
    }

    if (-not (Test-Path -LiteralPath $HttpModPath)) {
        $validationMessages += "Expected the FastDL Promod folder at http_fast_download_server\\cod4\\mods\\$ModFolder\\. Copy the same Promod files there before running the installer."
    }
    else {
        $fastDlAssets = @(Get-ChildItem -LiteralPath $HttpModPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -in @(".iwd", ".ff")
        })
        if ($fastDlAssets.Count -eq 0) {
            $validationMessages += "Expected downloadable mod assets (.iwd or .ff) in http_fast_download_server\\cod4\\mods\\$ModFolder\\."
        }

        $fastDlCfgFiles = @(Get-ChildItem -LiteralPath $HttpModPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -eq ".cfg"
        })
        if ($fastDlCfgFiles.Count -gt 0) {
            $validationMessages += "Remove .cfg files from http_fast_download_server\\cod4\\mods\\$ModFolder\\. FastDL should not contain server cfg files."
        }

        $fastDlDemoFolders = @(Get-ChildItem -LiteralPath $HttpModPath -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -ieq "demo" -or $_.Name -ieq "demos"
        })
        if ($fastDlDemoFolders.Count -gt 0) {
            $validationMessages += "Remove demo folders from http_fast_download_server\\cod4\\mods\\$ModFolder\\ before continuing."
        }
    }

    return @($validationMessages)
}

function Assert-ValidModFolderName {
    param([string] $Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "The Promod mod folder name cannot be empty."
    }

    if ($Name -in @(".", "..")) {
        throw "The Promod mod folder name must be a folder name, not . or ..."
    }

    if ($Name.IndexOfAny([char[]]"\\/:*?`"<>|") -ge 0) {
        throw "The Promod mod folder name cannot contain path separators or reserved characters."
    }
}

function Assert-ValidPortValue {
    param([string] $PortText)

    $portNumber = 0
    if (-not [int]::TryParse($PortText, [ref] $portNumber) -or $portNumber -lt 1 -or $portNumber -gt 65535) {
        throw "Game port must be a number from 1 to 65535."
    }
}

function Assert-ValidRconPassword {
    param([string] $Password)

    if ([string]::IsNullOrWhiteSpace($Password)) {
        throw "RCON password cannot be empty. It must be at least 8 characters long."
    }

    if ($Password.Trim().Length -lt 8) {
        throw "RCON password must be at least 8 characters long."
    }
}

function Assert-ValidMaxClientsValue {
    param([string] $ValueText)

    $maxClients = 0
    if (-not [int]::TryParse($ValueText, [ref] $maxClients) -or $maxClients -lt 1 -or $maxClients -gt 64) {
        throw "sv_maxclients must be a number from 1 to 64."
    }
}

function Wait-ForPromodFiles {
    param([string] $ModFolder)

    Write-Step "Promod files"
    Write-Host "Now copy the Promod/ mod folder into both of the following folders below."
    Write-Host "Use the same folder name in both places: $ModFolder"
    Write-Host ""
    Write-Step "1. Game server mod folder:"
    Write-Host "- server\mods\$ModFolder\"
    Write-Host ""
    Write-Host "2. FastDL mod folder:"
    Write-Host "- http_fast_download_server\cod4\mods\$ModFolder\"
    Write-Host ""
    Write-Step "Important TODO:"
    Write-Host "-If ur using any standard promod like pml220 or fps_promod_xxx:  Copy already provided server_match.cfg from server/mods/fps_promod_285 folder into your mod folder."
    Write-Host "This is a clean simple tested CFG, ensuring everything JUST WORKS."
    Write-Host ""
    Write-Host "- server_match.cfg must be inside server\mods\$ModFolder\ but not in the http_fast_download directory. People dont want to download ur server cfg!"
    Write-Host "Delete any demo folder in both /server and /http_fast_download_server. We dont want your demos hogging space"
    Write-Host ""
    Write-Step "Additional Notes"
    Write-Host "If your using your own cfg and mod, ur responsible for that. Make sure fast downloading commands are present and enabled in your cfg for everything to work normally."
    Write-Host ""
    Write-Host "Read BEGINNER_GUIDE.txt if you need the exact file list to put in http_fast_download mod directory.Generally only .iwd and .ff of your mod are needed. We dont want any demo folders or .cfg files"
    Write-Host ""
    Write-Host "Phew, all done on this"
    Read-Host "Press Enter after you have copied the Promod/mod folder into both directories and copied server_match.cfg"
}

Ensure-PythonInstalled
Copy-BaseGameFiles
Install-Cod4xServerFiles

Write-Step "Step 3 : Copy Promod or Mod files and enter Mod name"
Write-Host "Please write the exact folder name of  your Promod/mod folder   e.g fps_promod_285 OR pml220 "
Write-Host ""
$serverModsRoot = Join-Path $serverRoot "mods"
$httpModsRoot = Join-Path $httpRoot "cod4\\mods"
Ensure-DirectoryExists -Path $serverModsRoot
Ensure-DirectoryExists -Path $httpModsRoot
$modFolder = Read-DefaultValue -Prompt "Mod directory name: " -DefaultValue $config.DefaultModFolder
Assert-ValidModFolderName -Name $modFolder

$step3ValidationPassed = $false
while (-not $step3ValidationPassed) {
    $serverModPath = Join-Path $serverModsRoot $modFolder
    $httpModPath = Join-Path $httpModsRoot $modFolder

    Wait-ForPromodFiles -ModFolder $modFolder

    while ($true) {
        Write-Step "Checking required folders and files"
        $step3ValidationMessages = @(Get-Step3ValidationErrors `
            -ModFolder $modFolder `
            -ServerModPath $serverModPath `
            -HttpModPath $httpModPath)
        if ($step3ValidationMessages.Count -eq 0) {
            $step3ValidationPassed = $true
            break
        }

        Write-Step "Promod validation failed"
        foreach ($validationMessage in $step3ValidationMessages) {
            Write-Host "- $validationMessage"
        }
        Write-Host ""

        if (Read-YesNo -Prompt "Do you want to change the mod directory name?" -DefaultYes $false) {
            Write-Host ""
            $modFolder = Read-DefaultValue -Prompt "Mod directory name: " -DefaultValue $modFolder
            Assert-ValidModFolderName -Name $modFolder
            break
        }

        Read-Host "Fix the items above, then press Enter to recheck the prerequisites and Promod/mod files"
    }
}

$serverModPath = Join-Path $serverModsRoot $modFolder
$httpModPath = Join-Path $httpModsRoot $modFolder
$serverMatchCfg = Join-Path $serverModPath "server_match.cfg"

Write-Step "Server setup"
$serverName = Read-DefaultValue -Prompt "Server name" -DefaultValue $config.DefaultServerName
$gamePassword = Read-DefaultValue -Prompt "Game password" -DefaultValue $config.DefaultGamePassword
$rconPassword = Read-DefaultValue -Prompt "RCON password (minimum 8 characters)" -DefaultValue $config.DefaultRconPassword
Assert-ValidRconPassword -Password $rconPassword
$adminName = Read-DefaultValue -Prompt "Admin name" -DefaultValue $config.DefaultAdminName
$email = Read-DefaultValue -Prompt "Admin email" -DefaultValue $config.DefaultEmail
$location = Read-DefaultValue -Prompt "Server location" -DefaultValue $config.DefaultLocation
$gamePort = Read-DefaultValue -Prompt "Game port" -DefaultValue $config.DefaultGamePort
Assert-ValidPortValue -PortText $gamePort
$maxClients = Read-DefaultValue -Prompt "Max clients (sv_maxclients)" -DefaultValue $config.DefaultMaxClients
Assert-ValidMaxClientsValue -ValueText $maxClients
$startupMap = Read-DefaultValue -Prompt "Startup map" -DefaultValue $config.DefaultStartupMap

Write-Step "Updating server_args.psd1"
$serverArgsPath = Join-Path $serverRoot "start_script\\server_args.psd1"
Backup-FileIfNeeded -Path $serverArgsPath
$serverArgsContent = Get-Content -LiteralPath $serverArgsPath -Raw
$serverArgsContent = Set-ServerArgsValue -Content $serverArgsContent -Name "fs_game" -Value ("mods/" + $modFolder)
$serverArgsContent = Set-ServerArgsValue -Content $serverArgsContent -Name "net_port" -Value $gamePort
$serverArgsContent = Set-ServerArgsValue -Content $serverArgsContent -Name "sv_maxclients" -Value $maxClients
$serverArgsContent = Set-ServerArgsValue -Content $serverArgsContent -Name "rcon_password" -Value $rconPassword
$serverArgsContent = Set-DirectCommandValue -Content $serverArgsContent -Command "+map" -Value $startupMap
Set-Content -LiteralPath $serverArgsPath -Value $serverArgsContent -Encoding ASCII
try {
    Import-PowerShellDataFile -LiteralPath $serverArgsPath | Out-Null
}
catch {
    $serverArgsBackupPath = "$serverArgsPath.bak"
    if (Test-Path -LiteralPath $serverArgsBackupPath) {
        Copy-Item -LiteralPath $serverArgsBackupPath -Destination $serverArgsPath -Force
    }

    throw "server_args.psd1 was written with invalid syntax. $($_.Exception.Message)"
}


Write-Step "Updating server_match.cfg"
Backup-FileIfNeeded -Path $serverMatchCfg
$serverCfgContent = Get-Content -LiteralPath $serverMatchCfg -Raw
$serverCfgContent = Set-QuotedSetting -Content $serverCfgContent -Directive "sets _Admin" -Value $adminName
$serverCfgContent = Set-QuotedSetting -Content $serverCfgContent -Directive "sets _Email" -Value $email
$serverCfgContent = Set-QuotedSetting -Content $serverCfgContent -Directive "sets _Location" -Value $location
$serverCfgContent = Set-QuotedSetting -Content $serverCfgContent -Directive "sets sv_hostname" -Value $serverName
$serverCfgContent = Set-QuotedSetting -Content $serverCfgContent -Directive "set g_password" -Value $gamePassword
Set-Content -LiteralPath $serverMatchCfg -Value $serverCfgContent -Encoding ASCII

Write-Step "Done"
Write-Host "Installation successful."
Write-Host "Open server\start_match.bat to start the server."
Write-Host "When the server starts, copy the printed /connect automatically generated for you in the terminal ."

