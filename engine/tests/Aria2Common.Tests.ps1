#requires -Version 5.1
# Aria2Common.Tests.ps1
# Offline unit/integration tests for the aria2 engine.
#
# Guarantees:
#   - no network access
#   - no aria2 installation and no aria2 process is started
#   - no service, scheduled task or registry changes
#   - all state is written under a unique %TEMP% directory and removed afterwards
#
# Run:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File engine\tests\Aria2Common.Tests.ps1
#
# Exit code 0 = all tests passed, 1 = failures.

$ErrorActionPreference = 'Stop'
$script:EngineRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:EngineRoot 'Aria2Common.ps1')

$script:Passed = 0
$script:Failed = 0
$script:Failures = New-Object 'System.Collections.Generic.List[string]'
$script:TempRoot = Join-Path $env:TEMP ('aria2-engine-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Aria2Directory -Path $script:TempRoot
$script:Paths = Get-Aria2StatePaths -Root $script:TempRoot

function New-TestStatePaths {
    param([string]$Name)
    $root = Join-Path $script:TempRoot ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Aria2Directory -Path $root
    return (Get-Aria2StatePaths -Root $root)
}

function Test-Case {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )
    try {
        & $Body
        $script:Passed = $script:Passed + 1
        Write-Host ('PASS  ' + $Name)
    } catch {
        $script:Failed = $script:Failed + 1
        $message = ''
        if ($null -ne $_.Exception) {
            $message = $_.Exception.Message
        }
        $script:Failures.Add($Name + ' -> ' + $message)
        Write-Host ('FAIL  ' + $Name + ' -> ' + $message)
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message = '')
    if (-not $Condition) {
        throw ('Expected condition to be true. ' + $Message)
    }
}

function Assert-False {
    param([bool]$Condition, [string]$Message = '')
    if ($Condition) {
        throw ('Expected condition to be false. ' + $Message)
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message = '')
    if ($Expected -ne $Actual) {
        throw ('Expected [' + [string]$Expected + '] but got [' + [string]$Actual + ']. ' + $Message)
    }
}

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Message = '')
    if ($null -eq $Text -or $Text.IndexOf($Needle, [System.StringComparison]::Ordinal) -lt 0) {
        throw ('Expected text to contain [' + $Needle + ']. ' + $Message)
    }
}

function Assert-NotContains {
    param([string]$Text, [string]$Needle, [string]$Message = '')
    if ($null -ne $Text -and $Text.IndexOf($Needle, [System.StringComparison]::Ordinal) -ge 0) {
        throw ('Expected text NOT to contain [' + $Needle + ']. ' + $Message)
    }
}

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message = '')
    if ($null -eq $Text -or -not [regex]::IsMatch($Text, $Pattern)) {
        throw ('Expected text to match [' + $Pattern + ']. ' + $Message)
    }
}

function Assert-Throws {
    param([scriptblock]$Block, [string]$Pattern = '')
    $thrown = $false
    $message = ''
    try {
        & $Block
    } catch {
        $thrown = $true
        if ($null -ne $_.Exception) {
            $message = $_.Exception.Message
        }
    }
    if (-not $thrown) {
        throw 'Expected an exception but none was thrown.'
    }
    if ($Pattern -ne '' -and -not [regex]::IsMatch($message, $Pattern)) {
        throw ('Exception message [' + $message + '] did not match [' + $Pattern + '].')
    }
}

function Test-InvalidSetting {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Override,
        [Parameter(Mandatory = $true)][string]$ExpectedPattern
    )
    $settings = Get-Aria2DefaultSettings
    foreach ($key in $Override.Keys) {
        $settings[$key] = $Override[$key]
    }
    $validation = Test-Aria2Settings -Settings $settings
    Assert-False $validation.IsValid ('expected invalid settings for ' + $ExpectedPattern)
    $joined = $validation.Errors -join '; '
    Assert-Match $joined $ExpectedPattern
}

function Invoke-ChildPowerShell {
    param([string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    try {
        # The child's stderr is redirected into the captured output so failure
        # diagnostics can be asserted on. Continue keeps redirected native
        # stderr from becoming a terminating error in this test harness.
        $ErrorActionPreference = 'Continue'
        $output = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass @Arguments 2>&1
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = (($output | Out-String) -replace "`r", '')
    }
}

function Get-LastJsonLine {
    param([string]$Text)
    $jsonLines = @(($Text -split "`n") | Where-Object { $_.Trim().StartsWith('{') })
    if ($jsonLines.Count -eq 0) {
        return ''
    }
    return $jsonLines[$jsonLines.Count - 1].Trim()
}

try {
    # ------------------------------------------------------------------
    # 1. Engine files, ASCII-only scripts, 5.1 parser compatibility
    # ------------------------------------------------------------------
    Test-Case 'engine files exist' {
        $requiredFiles = @(
            'Aria2Common.ps1',
            'aria2.conf',
            'Initialize-Aria2.ps1',
            'Start-Aria2Rpc.ps1',
            'Stop-Aria2Rpc.ps1',
            'Get-Aria2Settings.ps1',
            'Set-Aria2Settings.ps1',
            'Notify-Aria2.ps1',
            'Watch-Aria2.ps1',
            'Aria2Hook.vbs',
            'tests\Aria2Common.Tests.ps1'
        )
        foreach ($name in $requiredFiles) {
            $path = Join-Path $script:EngineRoot $name
            Assert-True (Test-Path -LiteralPath $path -PathType Leaf) ('Missing engine file: ' + $name)
        }
    }

    Test-Case 'engine scripts are ASCII only' {
        $files = New-Object 'System.Collections.Generic.List[object]'
        foreach ($file in @(Get-ChildItem -LiteralPath $script:EngineRoot -File -Filter '*.ps1')) {
            $files.Add($file)
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $script:EngineRoot -File -Filter '*.vbs')) {
            $files.Add($file)
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $script:EngineRoot -File -Filter 'aria2.conf')) {
            $files.Add($file)
        }
        $testsDir = Join-Path $script:EngineRoot 'tests'
        foreach ($file in @(Get-ChildItem -LiteralPath $testsDir -File -Filter '*.ps1')) {
            $files.Add($file)
        }
        Assert-True ($files.Count -ge 10) ('Expected at least 10 engine script/config files, found ' + $files.Count)
        foreach ($file in $files) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            for ($index = 0; $index -lt $bytes.Length; $index++) {
                if ($bytes[$index] -gt 127) {
                    throw ('Non-ASCII byte 0x' + $bytes[$index].ToString('x2') + ' at offset ' + $index + ' in ' + $file.Name)
                }
            }
        }
    }

    Test-Case 'engine scripts parse with the Windows PowerShell 5.1 parser' {
        $scripts = New-Object 'System.Collections.Generic.List[object]'
        foreach ($file in @(Get-ChildItem -LiteralPath $script:EngineRoot -File -Filter '*.ps1')) {
            $scripts.Add($file)
        }
        foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $script:EngineRoot 'tests') -File -Filter '*.ps1')) {
            $scripts.Add($file)
        }
        foreach ($file in $scripts) {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
            $messages = @($parseErrors | ForEach-Object { 'line ' + $_.Extent.StartLineNumber + ': ' + $_.Message })
            Assert-Equal 0 $messages.Count ('Parse errors in ' + $file.Name + ': ' + ($messages -join ' | '))
        }
    }

    # ------------------------------------------------------------------
    # 2. Pinned package and exit codes
    # ------------------------------------------------------------------
    Test-Case 'pinned aria2 package matches the contract' {
        Assert-Equal '1.37.0' $script:Aria2Version
        Assert-Equal 'aria2-1.37.0-win-64bit-build1.zip' $script:Aria2PackageFileName
        Assert-Equal '67D015301EEF0B612191212D564C5BB0A14B5B9C4796B76454276A4D28D9B288' $script:Aria2PackageSha256
        Assert-Equal 'https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip' $script:Aria2PackageUrl
        Assert-Match $script:Aria2PackageUrl '^https://github\.com/aria2/aria2/releases/download/release-1\.37\.0/aria2-1\.37\.0-win-64bit-build1\.zip$'
        Assert-Match $script:Aria2PackageSha256 '^[0-9A-F]{64}$'
    }

    Test-Case 'exit codes match the contract' {
        Assert-Equal 0 $script:Aria2ExitCodes.Success
        Assert-Equal 2 $script:Aria2ExitCodes.InvalidInput
        Assert-Equal 3 $script:Aria2ExitCodes.Aria2Missing
        Assert-Equal 4 $script:Aria2ExitCodes.RpcFailure
        Assert-Equal 5 $script:Aria2ExitCodes.Busy
        Assert-Equal 6 $script:Aria2ExitCodes.InstallFailure
    }

    # ------------------------------------------------------------------
    # 3. Runtime paths
    # ------------------------------------------------------------------
    Test-Case 'state paths match the contract layout' {
        $paths = Get-Aria2StatePaths -Root $script:TempRoot
        Assert-Equal (Join-Path $script:TempRoot 'install.json') $paths.InstallFile
        Assert-Equal (Join-Path $script:TempRoot 'settings.json') $paths.SettingsFile
        Assert-Equal (Join-Path $script:TempRoot 'rpc-secret.txt') $paths.SecretFile
        Assert-Equal (Join-Path $script:TempRoot 'aria2.runtime.conf') $paths.RuntimeConfFile
        Assert-Equal (Join-Path $script:TempRoot 'session.txt') $paths.SessionFile
        Assert-Equal (Join-Path $script:TempRoot 'aria2.log') $paths.Aria2LogFile
        Assert-Equal (Join-Path $script:TempRoot 'rpc.log') $paths.RpcLogFile
        Assert-Equal (Join-Path (Join-Path $script:TempRoot 'bin') '1.37.0\aria2c.exe') $paths.Aria2cExe
        Assert-Equal (Join-Path $script:EngineRoot 'aria2.conf') $paths.TemplateFile
        Assert-Equal (Join-Path $script:EngineRoot 'Aria2Hook.vbs') $paths.HookScript
    }

    Test-Case 'state root env override and default' {
        $hadValue = Test-Path Env:LAT3NCY_ARIA2_HOME
        $previous = $env:LAT3NCY_ARIA2_HOME
        try {
            $env:LAT3NCY_ARIA2_HOME = 'C:\engine-test-root'
            Assert-Equal 'C:\engine-test-root' (Get-Aria2StateRoot)
            Remove-Item Env:LAT3NCY_ARIA2_HOME -ErrorAction SilentlyContinue
            $expectedDefault = Join-Path $env:LOCALAPPDATA 'lat3ncy-toolbox\aria2'
            Assert-Equal $expectedDefault (Get-Aria2StateRoot)
        } finally {
            if ($hadValue) {
                $env:LAT3NCY_ARIA2_HOME = $previous
            } else {
                Remove-Item Env:LAT3NCY_ARIA2_HOME -ErrorAction SilentlyContinue
            }
        }
    }

    # ------------------------------------------------------------------
    # 4. Settings defaults
    # ------------------------------------------------------------------
    Test-Case 'default settings match the schema' {
        $settings = Get-Aria2DefaultSettings
        $expectedKeys = @(
            'rpcPort', 'downloadDir', 'connections', 'split', 'minSplitSize',
            'maxConcurrentDownloads', 'fileAllocation', 'diskCache',
            'maxOverallDownloadLimit', 'maxOverallUploadLimit', 'proxyMode',
            'allProxy', 'noProxy', 'checkCertificate', 'connectTimeout',
            'timeout', 'maxTries', 'retryWait', 'lowestSpeedLimit',
            'saveSessionInterval', 'notifications', 'autoStartOnAdd', 'autoStopWhenIdle', 'listenPort', 'dhtListenPort',
            'enableDht', 'enablePeerExchange', 'btEnableLpd', 'btMaxPeers',
            'btRequireCrypto', 'seedTime', 'seedRatio', 'btSaveMetadata',
            'btLoadSavedMetadata', 'rpcSaveUploadMetadata', 'btTracker'
        )
        Assert-Equal 36 $expectedKeys.Count
        $actualKeys = @($settings.Keys | ForEach-Object { [string]$_ })
        Assert-Equal 36 $actualKeys.Count
        Assert-Equal ($expectedKeys -join ',') ($actualKeys -join ',')
        Assert-False ($actualKeys -contains 'rpcSecret')
    }

    Test-Case 'default settings values and BT defaults' {
        $settings = Get-Aria2DefaultSettings
        Assert-Equal 6800 $settings['rpcPort']
        Assert-Equal 16 $settings['connections']
        Assert-Equal 16 $settings['split']
        Assert-Equal '1M' $settings['minSplitSize']
        Assert-Equal 3 $settings['maxConcurrentDownloads']
        Assert-Equal 'none' $settings['fileAllocation']
        Assert-Equal '64M' $settings['diskCache']
        Assert-Equal '0' $settings['maxOverallDownloadLimit']
        Assert-Equal '2M' $settings['maxOverallUploadLimit']
        Assert-Equal 'system' $settings['proxyMode']
        Assert-Equal '' $settings['allProxy']
        Assert-Equal '' $settings['noProxy']
        Assert-Equal $true $settings['checkCertificate']
        Assert-Equal 30 $settings['connectTimeout']
        Assert-Equal 60 $settings['timeout']
        Assert-Equal 3 $settings['maxTries']
        Assert-Equal 5 $settings['retryWait']
        Assert-Equal '0' $settings['lowestSpeedLimit']
        Assert-Equal 30 $settings['saveSessionInterval']
        Assert-Equal $true $settings['notifications']
        Assert-Equal $true $settings['autoStartOnAdd']
        Assert-Equal $true $settings['autoStopWhenIdle']
        Assert-Equal 6881 $settings['listenPort']
        Assert-Equal 6881 $settings['dhtListenPort']
        Assert-Equal $true $settings['enableDht']
        Assert-Equal $true $settings['enablePeerExchange']
        Assert-Equal $false $settings['btEnableLpd']
        Assert-Equal 55 $settings['btMaxPeers']
        Assert-Equal $false $settings['btRequireCrypto']
        Assert-Equal 0 $settings['seedTime']
        Assert-Equal 1.0 $settings['seedRatio']
        Assert-Equal $true $settings['btSaveMetadata']
        Assert-Equal $true $settings['btLoadSavedMetadata']
        Assert-Equal $true $settings['rpcSaveUploadMetadata']
        Assert-Equal '' $settings['btTracker']
        Assert-True ($settings['rpcPort'] -is [int]) 'rpcPort must be an int'
        Assert-True ($settings['seedRatio'] -is [double]) 'seedRatio must be a double'
        Assert-True ($settings['checkCertificate'] -is [bool]) 'checkCertificate must be a bool'
        Assert-True (Test-Aria2AbsolutePath -Path ([string]$settings['downloadDir'])) 'downloadDir must be absolute'
    }

    # ------------------------------------------------------------------
    # 5. JSON serialization
    # ------------------------------------------------------------------
    Test-Case 'settings JSON round trip is ASCII only and excludes the secret' {
        $settings = Get-Aria2DefaultSettings
        $settings['downloadDir'] = 'C:\Users\Test User\Downloads'
        $json = ConvertTo-Aria2Json -Value $settings -Compress
        Assert-True ($json.StartsWith('{')) 'JSON must be an object'
        Assert-NotContains $json 'rpcSecret'
        Assert-NotContains $json 'rpc-secret'
        for ($index = 0; $index -lt $json.Length; $index++) {
            if ([int]$json[$index] -gt 126) {
                throw 'Serialized settings JSON must stay ASCII-only.'
            }
        }
        $parsed = $json | ConvertFrom-Json
        Assert-Equal 6800 $parsed.rpcPort
        Assert-Equal 'C:\Users\Test User\Downloads' $parsed.downloadDir
        Assert-Equal $true $parsed.checkCertificate
        Assert-Equal $false $parsed.btEnableLpd
        Assert-Equal 36 @($parsed.PSObject.Properties).Count
        $pretty = ConvertTo-Aria2Json -Value $settings
        Assert-True ($pretty.Contains("`n")) 'Pretty JSON should span lines'
        $prettyParsed = $pretty | ConvertFrom-Json
        Assert-Equal 6800 $prettyParsed.rpcPort
        Assert-Equal 'C:\Users\Test User\Downloads' $prettyParsed.downloadDir
    }

    Test-Case 'JSON escaping handles quotes, backslashes and non-ASCII text' {
        $chinese = [string]([char]0x4E0B) + [string]([char]0x8F7D)
        $value = [ordered]@{
            path = 'C:\a"b\c'
            label = $chinese
            control = "a`tb"
        }
        $json = ConvertTo-Aria2Json -Value $value -Compress
        for ($index = 0; $index -lt $json.Length; $index++) {
            if ([int]$json[$index] -gt 126) {
                throw 'JSON output must escape non-ASCII characters.'
            }
        }
        $parsed = $json | ConvertFrom-Json
        Assert-Equal 'C:\a"b\c' $parsed.path
        Assert-Equal $chinese $parsed.label
        Assert-Equal "a`tb" $parsed.control
    }

    # ------------------------------------------------------------------
    # 6. Settings merge and validation
    # ------------------------------------------------------------------
    Test-Case 'merge fills defaults, coerces types and ignores unknown keys' {
        $merged = Merge-Aria2Settings -InputObject ([ordered]@{
            rpcPort = '7000'
            checkCertificate = 'false'
            seedRatio = '1.5'
            connections = 8
            unknownKey = 'ignored'
        })
        Assert-Equal 7000 $merged['rpcPort']
        Assert-True ($merged['rpcPort'] -is [int]) 'rpcPort should be normalized to int'
        Assert-Equal $false $merged['checkCertificate']
        Assert-True ($merged['checkCertificate'] -is [bool]) 'checkCertificate should be normalized to bool'
        Assert-Equal 1.5 $merged['seedRatio']
        Assert-True ($merged['seedRatio'] -is [double]) 'seedRatio should be normalized to double'
        Assert-Equal 8 $merged['connections']
        Assert-Equal 16 $merged['split'] 'split keeps its default when not supplied'
        Assert-False (@($merged.Keys) -contains 'unknownKey')
        Assert-Equal 36 @($merged.Keys).Count
    }

    Test-Case 'merge rejects invalid types' {
        Assert-Throws { $null = Merge-Aria2Settings -InputObject ([ordered]@{ rpcPort = 'abc' }) } 'integer'
        Assert-Throws { $null = Merge-Aria2Settings -InputObject ([ordered]@{ rpcPort = $true }) } 'integer'
        Assert-Throws { $null = Merge-Aria2Settings -InputObject ([ordered]@{ rpcPort = 1.5 }) } 'integer'
        Assert-Throws { $null = Merge-Aria2Settings -InputObject ([ordered]@{ checkCertificate = 'yes' }) } 'true or false'
        Assert-Throws { $null = Merge-Aria2Settings -InputObject ([ordered]@{ seedRatio = 'abc' }) } 'number'
        Assert-Throws { $null = Merge-Aria2Settings -InputObject ([ordered]@{ downloadDir = '' }) } 'empty'
        Assert-Throws { $null = Merge-Aria2Settings -InputObject 'not-an-object' } 'JSON object'
    }

    Test-Case 'tracker list is normalized to a comma separated URI list' {
        $merged = Merge-Aria2Settings -InputObject ([ordered]@{
            btTracker = "udp://a.example:80/announce`r`nhttps://b.example/announce;http://c.example/announce"
        })
        Assert-Equal 'udp://a.example:80/announce,https://b.example/announce,http://c.example/announce' $merged['btTracker']
    }

    Test-Case 'default settings are valid' {
        $validation = Test-Aria2Settings -Settings (Get-Aria2DefaultSettings)
        Assert-True $validation.IsValid (($validation.Errors -join '; '))
        Assert-Equal 0 @($validation.Errors).Count
    }

    Test-Case 'validation enforces contract ranges' {
        Test-InvalidSetting @{ rpcPort = 80 } 'rpcPort'
        Test-InvalidSetting @{ rpcPort = 70000 } 'rpcPort'
        Test-InvalidSetting @{ connections = 0 } 'connections'
        Test-InvalidSetting @{ connections = 17 } 'connections'
        Test-InvalidSetting @{ split = 0 } 'split'
        Test-InvalidSetting @{ split = 17 } 'split'
        Test-InvalidSetting @{ maxConcurrentDownloads = 0 } 'maxConcurrentDownloads'
        Test-InvalidSetting @{ maxConcurrentDownloads = 11 } 'maxConcurrentDownloads'
        Test-InvalidSetting @{ minSplitSize = '512K' } 'minSplitSize'
        Test-InvalidSetting @{ minSplitSize = '2048M' } 'minSplitSize'
        Test-InvalidSetting @{ minSplitSize = 'abc' } 'minSplitSize'
        Test-InvalidSetting @{ diskCache = '8M' } 'diskCache'
        Test-InvalidSetting @{ diskCache = '2048M' } 'diskCache'
        Test-InvalidSetting @{ fileAllocation = 'always' } 'fileAllocation'
        Test-InvalidSetting @{ proxyMode = 'auto' } 'proxyMode'
        Test-InvalidSetting @{ proxyMode = 'custom'; allProxy = '' } 'allProxy'
        Test-InvalidSetting @{ proxyMode = 'custom'; allProxy = '127.0.0.1:7890' } 'allProxy'
        Test-InvalidSetting @{ listenPort = 80 } 'listenPort'
        Test-InvalidSetting @{ dhtListenPort = 70000 } 'dhtListenPort'
        Test-InvalidSetting @{ seedTime = -1 } 'seedTime'
        Test-InvalidSetting @{ seedTime = 100001 } 'seedTime'
        Test-InvalidSetting @{ seedRatio = -0.1 } 'seedRatio'
        Test-InvalidSetting @{ seedRatio = 101 } 'seedRatio'
        Test-InvalidSetting @{ btMaxPeers = 0 } 'btMaxPeers'
        Test-InvalidSetting @{ btMaxPeers = 1001 } 'btMaxPeers'
        Test-InvalidSetting @{ saveSessionInterval = 5 } 'saveSessionInterval'
        Test-InvalidSetting @{ saveSessionInterval = 301 } 'saveSessionInterval'
        Test-InvalidSetting @{ connectTimeout = 0 } 'connectTimeout'
        Test-InvalidSetting @{ timeout = 3601 } 'timeout'
        Test-InvalidSetting @{ maxTries = 0 } 'maxTries'
        Test-InvalidSetting @{ maxOverallUploadLimit = 'abc' } 'maxOverallUploadLimit'
        Test-InvalidSetting @{ lowestSpeedLimit = '-1' } 'lowestSpeedLimit'
        Test-InvalidSetting @{ downloadDir = 'Downloads' } 'downloadDir'
        Test-InvalidSetting @{ downloadDir = '' } 'downloadDir'
        Test-InvalidSetting @{ btTracker = 'not-a-tracker' } 'btTracker'
    }

    Test-Case 'valid custom proxy, tracker and boundary sizes pass validation' {
        $settings = Get-Aria2DefaultSettings
        $settings['proxyMode'] = 'custom'
        $settings['allProxy'] = 'http://127.0.0.1:7890'
        $settings['noProxy'] = 'localhost,127.0.0.1'
        $settings['btTracker'] = 'udp://tracker.example:80/announce,https://tracker2.example/announce'
        $settings['minSplitSize'] = '1024M'
        $settings['diskCache'] = '1024M'
        $settings['rpcPort'] = 65535
        $settings['listenPort'] = 1024
        $settings['seedRatio'] = 100
        $settings['btMaxPeers'] = 1000
        $settings['saveSessionInterval'] = 10
        $validation = Test-Aria2Settings -Settings $settings
        Assert-True $validation.IsValid (($validation.Errors -join '; '))
    }

    Test-Case 'size strings are parsed as aria2 sizes' {
        Assert-Equal 1048576 (Convert-Aria2SizeToBytes -Value '1M')
        Assert-Equal 1024 (Convert-Aria2SizeToBytes -Value '1K')
        Assert-Equal 1073741824 (Convert-Aria2SizeToBytes -Value '1G')
        Assert-Equal 64 (Convert-Aria2SizeToBytes -Value '64')
        Assert-Equal 33554432 (Convert-Aria2SizeToBytes -Value '32M')
        Assert-Throws { $null = Convert-Aria2SizeToBytes -Value '1.5M' } 'not a valid'
        Assert-Throws { $null = Convert-Aria2SizeToBytes -Value 'abc' } 'not a valid'
    }

    Test-Case 'absolute Windows path validation' {
        Assert-True (Test-Aria2AbsolutePath -Path 'C:\Users\me\Downloads')
        Assert-True (Test-Aria2AbsolutePath -Path 'C:/Users/me/Downloads')
        Assert-True (Test-Aria2AbsolutePath -Path '\\server\share\Downloads')
        Assert-False (Test-Aria2AbsolutePath -Path 'Downloads')
        Assert-False (Test-Aria2AbsolutePath -Path 'C:Downloads')
        Assert-False (Test-Aria2AbsolutePath -Path '')
        Assert-False (Test-Aria2AbsolutePath -Path 'C:\bad|name\Downloads')
    }

    # ------------------------------------------------------------------
    # 7. Settings files
    # ------------------------------------------------------------------
    Test-Case 'settings file atomic round trip without BOM or temp files' {
        $paths = New-TestStatePaths 'settings'
        $null = Initialize-Aria2StateLayout -Paths $paths
        $settings = Get-Aria2DefaultSettings
        $settings['downloadDir'] = 'C:\Users\Test User\Downloads'
        $settings['connections'] = 12
        $settings['proxyMode'] = 'direct'
        Save-Aria2Settings -Path $paths.SettingsFile -Settings $settings
        Assert-True (Test-Path -LiteralPath $paths.SettingsFile -PathType Leaf)
        $loaded = Read-Aria2Settings -Path $paths.SettingsFile
        Assert-Equal 12 $loaded['connections']
        Assert-Equal 'direct' $loaded['proxyMode']
        Assert-Equal 'C:\Users\Test User\Downloads' $loaded['downloadDir']
        # A second write exercises the atomic File.Replace path (Windows
        # PowerShell 5.1 coerces a literal $null backup argument to '').
        $settings['connections'] = 4
        Save-Aria2Settings -Path $paths.SettingsFile -Settings $settings
        $reloaded = Read-Aria2Settings -Path $paths.SettingsFile
        Assert-Equal 4 $reloaded['connections'] 'second atomic write must replace the file'
        $backups = @(Get-ChildItem -LiteralPath $paths.Root -Force -File | Where-Object { $_.Name -like '*.bak-*' })
        Assert-Equal 0 $backups.Count
        $leftovers = @(Get-ChildItem -LiteralPath $paths.Root -Force -File | Where-Object { $_.Name -like '.*.tmp-*' })
        Assert-Equal 0 $leftovers.Count
        $bytes = [System.IO.File]::ReadAllBytes($paths.SettingsFile)
        Assert-True ($bytes.Length -gt 3)
        Assert-False ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'settings.json must not have a BOM'
    }

    Test-Case 'settings file handles missing, invalid JSON and invalid values' {
        $paths = New-TestStatePaths 'settings-errors'
        Assert-True ($null -eq (Read-Aria2Settings -Path $paths.SettingsFile -AllowMissing))
        Assert-Throws { $null = Read-Aria2Settings -Path $paths.SettingsFile } 'not found'
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($paths.SettingsFile, '{ bad json', $encoding)
        Assert-Throws { $null = Read-Aria2Settings -Path $paths.SettingsFile } 'Invalid JSON'
        [System.IO.File]::WriteAllText($paths.SettingsFile, '{"rpcPort": 80}', $encoding)
        Assert-Throws { $null = Read-Aria2Settings -Path $paths.SettingsFile } 'Invalid settings'
        [System.IO.File]::WriteAllText($paths.SettingsFile, '{"rpcPort": 7000}', $encoding)
        $partial = Read-Aria2Settings -Path $paths.SettingsFile
        Assert-Equal 7000 $partial['rpcPort']
        Assert-Equal 16 $partial['split']
        Assert-Equal 36 @($partial.Keys).Count
    }

    Test-Case 'settings diff reports changed keys' {
        $old = Get-Aria2DefaultSettings
        $new = Merge-Aria2Settings -InputObject $old
        $diff = Compare-Aria2Settings -Old $old -New $new
        Assert-False $diff.Changed
        Assert-Equal 0 @($diff.ChangedKeys).Count
        $new['connections'] = 8
        $new['proxyMode'] = 'direct'
        $diff = Compare-Aria2Settings -Old $old -New $new
        Assert-True $diff.Changed
        $changedText = $diff.ChangedKeys -join ','
        Assert-Match $changedText 'connections'
        Assert-Match $changedText 'proxyMode'
        Assert-Equal 2 @($diff.ChangedKeys).Count
    }

    # ------------------------------------------------------------------
    # 8. Secret handling
    # ------------------------------------------------------------------
    Test-Case 'secret generation and secret file lifecycle' {
        Assert-Match (New-Aria2Secret) '^[0-9a-f]{32}$'
        Assert-True ((New-Aria2Secret) -ne (New-Aria2Secret)) 'two secrets should differ'
        $paths = New-TestStatePaths 'secret'
        $null = Initialize-Aria2StateLayout -Paths $paths
        $secret = Initialize-Aria2SecretFile -Paths $paths
        Assert-Match $secret '^[0-9a-f]{32}$'
        Assert-Equal $secret (Get-Aria2Secret -Path $paths.SecretFile)
        Assert-Equal $secret (Initialize-Aria2SecretFile -Paths $paths) 'secret must be stable'
        $text = Read-Aria2Utf8Text -Path $paths.SecretFile
        Assert-Equal $secret $text
        $bytes = [System.IO.File]::ReadAllBytes($paths.SecretFile)
        Assert-False ($bytes[0] -eq 0xEF) 'secret file must not have a BOM'
        $aclApplied = Set-Aria2SecretAcl -Path $paths.SecretFile
        Assert-True ($aclApplied -is [bool]) 'ACL helper must return a boolean'
    }

    Test-Case 'secret file rejects multi-line content' {
        $paths = New-TestStatePaths 'secret-bad'
        $null = New-Aria2Directory -Path $paths.Root
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($paths.SecretFile, "abc`r`ndef", $encoding)
        Assert-Throws { $null = Get-Aria2Secret -Path $paths.SecretFile } 'single line'
    }

    # ------------------------------------------------------------------
    # 9. Hashing
    # ------------------------------------------------------------------
    Test-Case 'SHA-256 known vectors' {
        $paths = New-TestStatePaths 'hash'
        $file = Join-Path $paths.Root 'abc.txt'
        [System.IO.File]::WriteAllBytes($file, [System.Text.Encoding]::ASCII.GetBytes('abc'))
        Assert-Equal 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD' (Get-Aria2FileSha256 -Path $file)
        Assert-True (Test-Aria2FileSha256 -Path $file -Expected 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
        Assert-False (Test-Aria2FileSha256 -Path $file -Expected ('00' * 32))
        $emptyFile = Join-Path $paths.Root 'empty.bin'
        [System.IO.File]::WriteAllBytes($emptyFile, (New-Object 'byte[]' 0))
        Assert-Equal 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855' (Get-Aria2FileSha256 -Path $emptyFile)
        Assert-Throws { $null = Get-Aria2FileSha256 -Path (Join-Path $paths.Root 'missing.bin') } 'not found'
    }

    # ------------------------------------------------------------------
    # 10. Install metadata
    # ------------------------------------------------------------------
    Test-Case 'install.json round trip and exe resolution' {
        $paths = New-TestStatePaths 'install'
        $null = Initialize-Aria2StateLayout -Paths $paths
        $info = New-Aria2InstallInfo -Version '1.37.0' -Sha256 $script:Aria2PackageSha256 -InstallPath $paths.InstallDir -InstalledAt '2026-01-01T00:00:00.0000000Z'
        Save-Aria2InstallInfo -Path $paths.InstallFile -Info $info
        $loaded = Read-Aria2InstallInfo -Path $paths.InstallFile
        Assert-Equal '1.37.0' $loaded['version']
        Assert-Equal $script:Aria2PackageSha256 $loaded['sha256']
        Assert-Equal $paths.InstallDir $loaded['installPath']
        Assert-Equal '2026-01-01T00:00:00.0000000Z' $loaded['installedAt']
        $null = New-Aria2Directory -Path $paths.InstallDir
        $fakeExe = Join-Path $paths.InstallDir 'aria2c.exe'
        [System.IO.File]::WriteAllBytes($fakeExe, (New-Object 'byte[]' 1))
        Assert-Equal $fakeExe (Get-Aria2InstalledExePath -Paths $paths)
        Assert-Equal 4 @($loaded.Keys).Count
    }

    Test-Case 'missing or corrupt install.json is tolerated' {
        $paths = New-TestStatePaths 'install-missing'
        Assert-True ($null -eq (Read-Aria2InstallInfo -Path $paths.InstallFile))
        Assert-True ($null -eq (Get-Aria2InstalledExePath -Paths $paths))
        $null = New-Aria2Directory -Path $paths.Root
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($paths.InstallFile, 'not json', $encoding)
        Assert-True ($null -eq (Read-Aria2InstallInfo -Path $paths.InstallFile))
    }

    # ------------------------------------------------------------------
    # 11. Runtime configuration generation
    # ------------------------------------------------------------------
    Test-Case 'runtime conf contains all contract options and no placeholders' {
        $paths = New-TestStatePaths 'conf'
        $null = Initialize-Aria2StateLayout -Paths $paths
        $settings = Get-Aria2DefaultSettings
        $settings['downloadDir'] = Join-Path $script:TempRoot 'downloads'
        $settings['btTracker'] = 'udp://tracker.example:80/announce'
        $secret = 'deadbeefdeadbeefdeadbeefdeadbeef'
        $confPath = New-Aria2RuntimeConf -Settings $settings -Secret $secret -Paths $paths
        Assert-Equal $paths.RuntimeConfFile $confPath
        $text = Read-Aria2Utf8Text -Path $confPath
        Assert-NotContains $text '{{'
        Assert-NotContains $text '}}'
        Assert-NotContains $text '#?'
        Assert-NotContains $text 'PLACEHOLDER'
        $requiredOptions = @(
            'dir=', 'split=', 'max-connection-per-server=', 'min-split-size=',
            'max-concurrent-downloads=', 'file-allocation=', 'disk-cache=',
            'max-overall-download-limit=', 'max-overall-upload-limit=',
            'connect-timeout=', 'timeout=', 'max-tries=', 'retry-wait=',
            'lowest-speed-limit=', 'listen-port=', 'dht-listen-port=',
            'enable-dht=', 'enable-peer-exchange=', 'bt-enable-lpd=',
            'bt-max-peers=', 'bt-require-crypto=', 'seed-time=', 'seed-ratio=',
            'bt-save-metadata=', 'bt-load-saved-metadata=',
            'rpc-save-upload-metadata=', 'save-session=', 'save-session-interval=',
            'force-save=false', 'log=', 'log-level=warn', 'console-log-level=warn',
            'summary-interval=0', 'enable-rpc=true', 'rpc-listen-all=false',
            'rpc-allow-origin-all=true', 'rpc-listen-port=', 'rpc-secret=',
            'check-certificate=', 'remote-time=true',
            'content-disposition-default-utf8=true'
        )
        foreach ($option in $requiredOptions) {
            Assert-Contains $text $option
        }
        Assert-Contains $text ('dir=' + $settings['downloadDir'])
        Assert-Contains $text 'split=16'
        Assert-Contains $text 'max-connection-per-server=16'
        Assert-Contains $text 'min-split-size=1M'
        Assert-Contains $text 'max-concurrent-downloads=3'
        Assert-Contains $text 'file-allocation=none'
        Assert-Contains $text 'disk-cache=64M'
        Assert-Contains $text 'max-overall-download-limit=0'
        Assert-Contains $text 'max-overall-upload-limit=2M'
        Assert-Contains $text 'connect-timeout=30'
        Assert-Contains $text 'max-tries=3'
        Assert-Contains $text 'retry-wait=5'
        Assert-Contains $text 'lowest-speed-limit=0'
        Assert-Contains $text 'listen-port=6881'
        Assert-Contains $text 'dht-listen-port=6881'
        Assert-Contains $text 'enable-dht=true'
        Assert-Contains $text 'enable-peer-exchange=true'
        Assert-Contains $text 'bt-enable-lpd=false'
        Assert-Contains $text 'bt-max-peers=55'
        Assert-Contains $text 'bt-require-crypto=false'
        Assert-Contains $text 'seed-time=0'
        Assert-Contains $text 'seed-ratio=1.0'
        Assert-Contains $text 'bt-save-metadata=true'
        Assert-Contains $text 'bt-load-saved-metadata=true'
        Assert-Contains $text 'rpc-save-upload-metadata=true'
        Assert-Contains $text ('save-session=' + $paths.SessionFile)
        Assert-Contains $text 'save-session-interval=30'
        Assert-Contains $text ('log=' + $paths.Aria2LogFile)
        Assert-Contains $text 'rpc-listen-port=6800'
        Assert-Contains $text ('rpc-secret=' + $secret)
        Assert-Contains $text 'check-certificate=true'
        Assert-Contains $text 'bt-tracker=udp://tracker.example:80/announce'
        Assert-NotContains $text 'Aria2Hook.vbs'
        Assert-NotContains $text 'on-download-complete='
        Assert-NotContains $text 'on-bt-download-complete='
        Assert-NotContains $text 'on-download-error='
        Assert-NotContains $text 'all-proxy='
        Assert-NotContains $text 'no-proxy='
        # Regenerate over the existing runtime conf (atomic replace path).
        $settings['connections'] = 8
        $null = New-Aria2RuntimeConf -Settings $settings -Secret $secret -Paths $paths
        $regenerated = Read-Aria2Utf8Text -Path $confPath
        Assert-Contains $regenerated 'max-connection-per-server=8'
        Assert-NotContains $regenerated '{{'
        $bytes = [System.IO.File]::ReadAllBytes($confPath)
        Assert-False ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'runtime conf must not have a BOM'
    }

    Test-Case 'runtime conf drops conditional lines for disabled features' {
        $paths = New-TestStatePaths 'conf-disabled'
        $settings = Get-Aria2DefaultSettings
        $settings['btTracker'] = ''
        $settings['notifications'] = $false
        $settings['proxyMode'] = 'direct'
        $confPath = New-Aria2RuntimeConf -Settings $settings -Secret 'abc123' -Paths $paths
        $text = Read-Aria2Utf8Text -Path $confPath
        Assert-NotContains $text 'bt-tracker='
        Assert-NotContains $text 'on-download-complete='
        Assert-NotContains $text 'on-bt-download-complete='
        Assert-NotContains $text 'on-download-error='
        Assert-NotContains $text 'all-proxy='
        Assert-NotContains $text 'no-proxy='
        Assert-Contains $text 'enable-rpc=true'
    }

    Test-Case 'runtime conf writes custom proxy options' {
        $paths = New-TestStatePaths 'conf-proxy'
        $settings = Get-Aria2DefaultSettings
        $settings['proxyMode'] = 'custom'
        $settings['allProxy'] = 'http://127.0.0.1:7890'
        $settings['noProxy'] = 'localhost,127.0.0.1'
        $confPath = New-Aria2RuntimeConf -Settings $settings -Secret 'abc123' -Paths $paths
        $text = Read-Aria2Utf8Text -Path $confPath
        Assert-Contains $text 'all-proxy=http://127.0.0.1:7890'
        Assert-Contains $text 'no-proxy=localhost,127.0.0.1'
    }

    Test-Case 'runtime conf preserves non-ASCII download paths as UTF-8' {
        $paths = New-TestStatePaths 'conf-utf8'
        $settings = Get-Aria2DefaultSettings
        $chineseDir = 'C:\Users\Test\' + [string]([char]0x4E0B) + [string]([char]0x8F7D)
        $settings['downloadDir'] = $chineseDir
        $confPath = New-Aria2RuntimeConf -Settings $settings -Secret 'abc123' -Paths $paths
        $text = Read-Aria2Utf8Text -Path $confPath
        Assert-Contains $text ('dir=' + $chineseDir)
    }

    Test-Case 'runtime conf rejects unknown placeholders and empty secrets' {
        $paths = New-TestStatePaths 'conf-errors'
        $null = Initialize-Aria2StateLayout -Paths $paths
        $templatePath = Join-Path $script:TempRoot 'bad-template.conf'
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($templatePath, ('dir={{DIR}}' + "`r`n" + 'unknown={{UNKNOWN_TOKEN}}'), $encoding)
        Assert-Throws {
            $null = New-Aria2RuntimeConf -Settings (Get-Aria2DefaultSettings) -Secret 'abc123' -Paths $paths -TemplatePath $templatePath
        } 'Unknown template placeholder'
        Assert-Throws {
            $null = New-Aria2RuntimeConf -Settings (Get-Aria2DefaultSettings) -Secret '' -Paths $paths
        } 'secret'
    }

    Test-Case 'every template placeholder is known to the generator' {
        $tokens = Get-Aria2RuntimeConfTokens -Settings (Get-Aria2DefaultSettings) -Secret 'abc123' -Paths $script:Paths
        $template = Read-Aria2Utf8Text -Path (Join-Path $script:EngineRoot 'aria2.conf')
        $matches = [regex]::Matches($template, '\{\{(?<name>[A-Z0-9_]+)\}\}')
        Assert-True ($matches.Count -ge 30) ('Expected at least 30 template placeholders, found ' + $matches.Count)
        foreach ($match in $matches) {
            $name = $match.Groups['name'].Value
            Assert-True ($tokens.ContainsKey($name)) ('Template placeholder not provided by the generator: ' + $name)
        }
    }

    Test-Case 'hook commands call the VBS shim with the event name' {
        $download = Get-Aria2HookCommand -Paths $script:Paths -EventName 'download'
        Assert-Contains $download 'Aria2Hook.vbs'
        Assert-Contains $download 'wscript'
        Assert-Match $download 'download$'
        Assert-Match (Get-Aria2HookCommand -Paths $script:Paths -EventName 'bt') 'bt$'
        Assert-Match (Get-Aria2HookCommand -Paths $script:Paths -EventName 'error') 'error$'
        Assert-Throws { $null = Get-Aria2HookCommand -Paths $script:Paths -EventName 'nope' }
    }

    # ------------------------------------------------------------------
    # 12. Start arguments / proxy modes
    # ------------------------------------------------------------------
    Test-Case 'start arguments follow the proxy mode contract' {
        $paths = New-TestStatePaths 'args'
        $null = Initialize-Aria2StateLayout -Paths $paths
        $settings = Get-Aria2DefaultSettings
        $settings['proxyMode'] = 'system'
        $arguments = Get-Aria2StartArguments -Paths $paths -Settings $settings
        Assert-Contains $arguments ('--conf-path="' + $paths.RuntimeConfFile + '"')
        Assert-NotContains $arguments '--all-proxy'
        Assert-NotContains $arguments '--input-file'
        $settings['proxyMode'] = 'direct'
        $arguments = Get-Aria2StartArguments -Paths $paths -Settings $settings
        Assert-Contains $arguments '--all-proxy='
        Assert-Contains $arguments ('--conf-path="' + $paths.RuntimeConfFile + '"')
        $settings['proxyMode'] = 'custom'
        $settings['allProxy'] = 'http://127.0.0.1:7890'
        $arguments = Get-Aria2StartArguments -Paths $paths -Settings $settings
        Assert-NotContains $arguments '--all-proxy'
    }

    Test-Case 'session restore argument is only added for non-empty sessions' {
        $paths = New-TestStatePaths 'args-session'
        $null = Initialize-Aria2StateLayout -Paths $paths
        $settings = Get-Aria2DefaultSettings
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($paths.SessionFile, '', $encoding)
        Assert-NotContains (Get-Aria2StartArguments -Paths $paths -Settings $settings) '--input-file'
        [System.IO.File]::WriteAllText($paths.SessionFile, 'http://example.com/file.bin' + "`n", $encoding)
        $arguments = Get-Aria2StartArguments -Paths $paths -Settings $settings
        Assert-Contains $arguments ('--input-file="' + $paths.SessionFile + '"')
    }

    # ------------------------------------------------------------------
    # 13. Notification dedupe
    # ------------------------------------------------------------------
    Test-Case 'BT marker suppresses the later download notification' {
        $paths = New-TestStatePaths 'notify'
        $null = Initialize-Aria2StateLayout -Paths $paths
        $gid = '0123456789abcdef'
        Assert-False (Test-Aria2ShouldSuppressDownloadNotification -Paths $paths -Gid $gid)
        $null = Set-Aria2Notified -Paths $paths -Gid $gid -EventName 'bt'
        Assert-True (Test-Aria2ShouldSuppressDownloadNotification -Paths $paths -Gid $gid)
        $marker = Get-Aria2NotifiedMarker -Paths $paths -Gid '0123456789ABCDEF'
        Assert-Equal 'bt' $marker.Event
        Assert-True (Test-Path -LiteralPath $marker.Path)
        $null = Set-Aria2Notified -Paths $paths -Gid 'fedcba9876543210' -EventName 'download'
        Assert-False (Test-Aria2ShouldSuppressDownloadNotification -Paths $paths -Gid 'fedcba9876543210')
    }

    Test-Case 'invalid GIDs are rejected and do not escape the state directory' {
        $paths = New-TestStatePaths 'notify-bad'
        Assert-Throws { $null = Get-Aria2NotifiedMarkerPath -Paths $paths -Gid '../escape' } 'Invalid GID'
        Assert-Throws { $null = Get-Aria2NotifiedMarkerPath -Paths $paths -Gid '' } 'empty'
        Assert-True ($null -eq (Get-Aria2NotifiedMarker -Paths $paths -Gid '../escape'))
    }

    Test-Case 'stale notification markers are pruned' {
        $paths = New-TestStatePaths 'notify-stale'
        $null = Initialize-Aria2StateLayout -Paths $paths
        $markerPath = Set-Aria2Notified -Paths $paths -Gid '0123456789abcdef' -EventName 'bt'
        (Get-Item -LiteralPath $markerPath).LastWriteTime = (Get-Date).AddDays(-10)
        $removed = Remove-Aria2StaleNotified -Paths $paths -Days 7
        Assert-Equal 1 $removed
        Assert-False (Test-Path -LiteralPath $markerPath)
        Assert-Equal 0 (Remove-Aria2StaleNotified -Paths $paths -Days 7)
    }

    # ------------------------------------------------------------------
    # 14. aria2 status helpers used by Notify-Aria2.ps1
    # ------------------------------------------------------------------
    Test-Case 'task names are derived from BT info, file paths or fallback' {
        $btStatus = [pscustomobject]@{
            bittorrent = [pscustomobject]@{ info = [pscustomobject]@{ name = 'ubuntu.iso' } }
            files = @()
        }
        Assert-Equal 'ubuntu.iso' (Get-Aria2TaskName -Status $btStatus)
        Assert-True (Test-Aria2StatusIsBitTorrent -Status $btStatus)
        $httpStatus = [pscustomobject]@{
            files = @([pscustomobject]@{ path = 'C:\Downloads\file.zip' })
        }
        Assert-Equal 'file.zip' (Get-Aria2TaskName -Status $httpStatus)
        Assert-False (Test-Aria2StatusIsBitTorrent -Status $httpStatus)
        Assert-Equal 'fallback.bin' (Get-Aria2TaskName -Status $null -FallbackPath 'C:\Downloads\fallback.bin')
        Assert-Equal 'aria2 download' (Get-Aria2TaskName -Status $null)
        Assert-Equal 1048576 (Get-Aria2StatusNumber -Status ([pscustomobject]@{ totalLength = '1048576' }) -Name 'totalLength')
        Assert-Equal 0 (Get-Aria2StatusNumber -Status $null -Name 'totalLength')
        Assert-Equal 'some error' (Get-Aria2StatusString -Status ([pscustomobject]@{ errorMessage = 'some error' }) -Name 'errorMessage')
    }

    Test-Case 'byte sizes are formatted for toast text' {
        Assert-Equal '0 B' (Format-Aria2ByteSize -Bytes 0)
        Assert-Equal '1.0 KB' (Format-Aria2ByteSize -Bytes 1024)
        Assert-Equal '1.00 MB' (Format-Aria2ByteSize -Bytes 1048576)
        Assert-Equal '1.00 GB' (Format-Aria2ByteSize -Bytes 1073741824)
        Assert-Equal '' (Format-Aria2ByteSize -Bytes 'not-a-number')
    }

    Test-Case 'log redaction never writes the secret' {
        $paths = New-TestStatePaths 'logging'
        $null = Initialize-Aria2StateLayout -Paths $paths
        $secret = 'deadbeefdeadbeefdeadbeefdeadbeef'
        Write-Aria2EngineLog -Paths $paths -Message ('token:' + $secret + ' secret=' + $secret) -Secret $secret
        $logText = Read-Aria2Utf8Text -Path $paths.RpcLogFile
        Assert-NotContains $logText $secret
        Assert-NotContains $logText 'token:deadbeef'
        Assert-Contains $logText 'token:***'
        $redacted = Protect-Aria2Text -Text ('token:' + $secret + ' and ' + $secret) -Secret $secret
        Assert-NotContains $redacted $secret
    }

    # ------------------------------------------------------------------
    # 15. Engine script smoke tests (dry runs only, offline)
    # ------------------------------------------------------------------
    Test-Case 'engine scripts dry-run offline without touching the real state' {
        $dryRoot = Join-Path $script:TempRoot ('dryrun-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $hadValue = Test-Path Env:LAT3NCY_ARIA2_HOME
        $previous = $env:LAT3NCY_ARIA2_HOME
        try {
            $env:LAT3NCY_ARIA2_HOME = $dryRoot
            $initialize = Invoke-ChildPowerShell -Arguments @(
                '-File', (Join-Path $script:EngineRoot 'Initialize-Aria2.ps1'), '-NoToast', '-DryRun'
            )
            Assert-Equal 0 $initialize.ExitCode ('Initialize dry run failed: ' + $initialize.Output)
            Assert-Contains $initialize.Output 'state root:'
            Assert-Contains $initialize.Output 'aria2c: not installed'
            Assert-False (Test-Path -LiteralPath $dryRoot) 'Dry run must not create the state directory'

            $start = Invoke-ChildPowerShell -Arguments @(
                '-File', (Join-Path $script:EngineRoot 'Start-Aria2Rpc.ps1'), '-NoToast', '-DryRun'
            )
            Assert-Equal 3 $start.ExitCode ('Start dry run should report missing aria2: ' + $start.Output)
            Assert-Contains $start.Output 'not installed'

            $stop = Invoke-ChildPowerShell -Arguments @(
                '-File', (Join-Path $script:EngineRoot 'Stop-Aria2Rpc.ps1'), '-NoToast', '-DryRun'
            )
            Assert-Equal 0 $stop.ExitCode ('Stop dry run failed: ' + $stop.Output)
            Assert-Contains $stop.Output 'nothing to stop'

            $watch = Invoke-ChildPowerShell -Arguments @(
                '-File', (Join-Path $script:EngineRoot 'Watch-Aria2.ps1'), '-DryRun'
            )
            Assert-Equal 0 $watch.ExitCode ('Watch dry run failed: ' + $watch.Output)
            Assert-Contains $watch.Output 'dry run'
        } finally {
            if ($hadValue) {
                $env:LAT3NCY_ARIA2_HOME = $previous
            } else {
                Remove-Item Env:LAT3NCY_ARIA2_HOME -ErrorAction SilentlyContinue
            }
        }
    }

    Test-Case 'Get-Aria2Settings -Json emits schema settings and no secret' {
        $getRoot = Join-Path $script:TempRoot ('get-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $hadValue = Test-Path Env:LAT3NCY_ARIA2_HOME
        $previous = $env:LAT3NCY_ARIA2_HOME
        try {
            $env:LAT3NCY_ARIA2_HOME = $getRoot
            $result = Invoke-ChildPowerShell -Arguments @(
                '-File', (Join-Path $script:EngineRoot 'Get-Aria2Settings.ps1'), '-Json'
            )
            Assert-Equal 0 $result.ExitCode ('Get-Aria2Settings failed: ' + $result.Output)
            $jsonLine = Get-LastJsonLine -Text $result.Output
            $parsed = $jsonLine | ConvertFrom-Json
            Assert-Equal 36 @($parsed.PSObject.Properties).Count
            Assert-Equal 6800 $parsed.rpcPort
            Assert-False (@($parsed.PSObject.Properties.Name) -contains 'rpcSecret')
            Assert-False (Test-Path -LiteralPath $getRoot) 'Read-only Get must not create state'
        } finally {
            if ($hadValue) {
                $env:LAT3NCY_ARIA2_HOME = $previous
            } else {
                Remove-Item Env:LAT3NCY_ARIA2_HOME -ErrorAction SilentlyContinue
            }
        }
    }

    Test-Case 'Set-Aria2Settings validates, writes settings and regenerates the runtime conf' {
        $setRoot = Join-Path $script:TempRoot ('set-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Aria2Directory -Path $setRoot
        $paths = Get-Aria2StatePaths -Root $setRoot
        $hadValue = Test-Path Env:LAT3NCY_ARIA2_HOME
        $previous = $env:LAT3NCY_ARIA2_HOME
        try {
            $env:LAT3NCY_ARIA2_HOME = $setRoot
            $candidate = Get-Aria2DefaultSettings
            $candidate['downloadDir'] = 'C:\Users\Test User\Downloads'
            $candidate['connections'] = 8
            $candidate['proxyMode'] = 'direct'
            $candidatePath = Join-Path $script:TempRoot ('candidate-' + [guid]::NewGuid().ToString('N') + '.json')
            Write-Aria2JsonFile -Path $candidatePath -Value $candidate

            $result = Invoke-ChildPowerShell -Arguments @(
                '-File', (Join-Path $script:EngineRoot 'Set-Aria2Settings.ps1'), '-JsonPath', $candidatePath
            )
            Assert-Equal 0 $result.ExitCode ('Set-Aria2Settings failed: ' + $result.Output)
            $jsonLine = Get-LastJsonLine -Text $result.Output
            $parsed = $jsonLine | ConvertFrom-Json
            Assert-Equal $true $parsed.ok
            Assert-Equal $false $parsed.restartRequired
            Assert-True (Test-Path -LiteralPath $paths.SettingsFile -PathType Leaf)
            Assert-True (Test-Path -LiteralPath $paths.RuntimeConfFile -PathType Leaf)
            Assert-True (Test-Path -LiteralPath $paths.SecretFile -PathType Leaf)
            $saved = Read-Aria2Settings -Path $paths.SettingsFile
            Assert-Equal 8 $saved['connections']
            Assert-Equal 'direct' $saved['proxyMode']
            $confText = Read-Aria2Utf8Text -Path $paths.RuntimeConfFile
            Assert-Contains $confText 'max-connection-per-server=8'
            Assert-NotContains $confText '{{'

            $invalid = Get-Aria2DefaultSettings
            $invalid['rpcPort'] = 80
            $invalidPath = Join-Path $script:TempRoot ('invalid-' + [guid]::NewGuid().ToString('N') + '.json')
            Write-Aria2JsonFile -Path $invalidPath -Value $invalid
            $failed = Invoke-ChildPowerShell -Arguments @(
                '-File', (Join-Path $script:EngineRoot 'Set-Aria2Settings.ps1'), '-JsonPath', $invalidPath
            )
            Assert-Equal 2 $failed.ExitCode ('Invalid settings should exit 2: ' + $failed.Output)
            $failedLine = Get-LastJsonLine -Text $failed.Output
            $failedJson = $failedLine | ConvertFrom-Json
            Assert-Equal $false $failedJson.ok
            $stillSaved = Read-Aria2Settings -Path $paths.SettingsFile
            Assert-Equal 8 $stillSaved['connections'] 'invalid settings must not overwrite settings.json'
        } finally {
            if ($hadValue) {
                $env:LAT3NCY_ARIA2_HOME = $previous
            } else {
                Remove-Item Env:LAT3NCY_ARIA2_HOME -ErrorAction SilentlyContinue
            }
        }
    }
} finally {
    if (Test-Path -LiteralPath $script:TempRoot) {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host ('Tests passed: ' + $script:Passed)
Write-Host ('Tests failed: ' + $script:Failed)
if ($script:Failed -gt 0) {
    Write-Host 'Failures:'
    foreach ($failure in $script:Failures) {
        Write-Host ('  - ' + $failure)
    }
    exit 1
}
Write-Host 'All aria2 engine tests passed.'
exit 0
