[CmdletBinding()]
param(
    [string]$Package = 'org.telegram.messenger.web'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AdbPath = (Get-Command adb -CommandType Application -ErrorAction Stop).Path

function Invoke-AdbCapture {
    param([string[]]$AdbArguments)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 can surface native stderr as NativeCommandError when
        # ErrorActionPreference=Stop. ADB legitimately writes daemon startup messages
        # to stderr even when it exits successfully, so capture first and judge by
        # the native exit code instead.
        $ErrorActionPreference = 'Continue'
        $rawOutput = @(& $script:AdbPath @AdbArguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $output = @(
        $rawOutput | Where-Object {
            $line = [string]$_
            $line -notmatch '^\* daemon not running; starting now at tcp:\d+$' -and
            $line -notmatch '^\* daemon started successfully$'
        }
    )

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
        RawOutput = $rawOutput
    }
}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArguments)

    $result = Invoke-AdbCapture -AdbArguments $AdbArguments
    if ($result.ExitCode -ne 0) {
        throw "adb $($AdbArguments -join ' ') failed:`n$($result.RawOutput -join [Environment]::NewLine)"
    }

    return @($result.Output)
}

function Get-Prop {
    param([string]$Name)

    return ((Invoke-Adb shell getprop $Name) -join '').Trim()
}

$startServer = Invoke-AdbCapture -AdbArguments @('start-server')
if ($startServer.ExitCode -ne 0) {
    throw "adb start-server failed:`n$($startServer.RawOutput -join [Environment]::NewLine)"
}

$state = ((Invoke-Adb get-state) -join '').Trim()
if ($state -ne 'device') {
    throw "ADB device is not ready: $state"
}

Write-Host '=== Device ==='
Write-Host ('manufacturer=' + (Get-Prop 'ro.product.manufacturer'))
Write-Host ('model=' + (Get-Prop 'ro.product.model'))
Write-Host ('android=' + (Get-Prop 'ro.build.version.release'))
Write-Host ('sdk=' + (Get-Prop 'ro.build.version.sdk'))

$miui = Get-Prop 'ro.miui.ui.version.name'
if ($miui) {
    Write-Host ('miui=' + $miui)
}

$hyper = Get-Prop 'ro.mi.os.version.name'
if ($hyper) {
    Write-Host ('hyperos=' + $hyper)
}

Write-Host ''
Write-Host '=== Android night configuration ==='
$uiMode = Invoke-Adb shell cmd uimode night
$uiMode | ForEach-Object { Write-Host $_ }

$config = (Invoke-Adb shell am get-config) -join ' '
if ($config -match '(^|-)night($|-)') {
    Write-Host 'resourceQualifier=night'
} elseif ($config -match '(^|-)notnight($|-)') {
    Write-Host 'resourceQualifier=notnight'
} else {
    Write-Host 'resourceQualifier=unknown'
}
Write-Host ('rawConfig=' + $config)

Write-Host ''
Write-Host '=== Telegram-WSP package ==='
$packageDump = Invoke-Adb shell dumpsys package $Package
$versionName = $packageDump | Select-String -Pattern 'versionName=' | Select-Object -First 1
$versionCode = $packageDump | Select-String -Pattern 'versionCode=' | Select-Object -First 1

if ($versionName) {
    Write-Host $versionName.Line.Trim()
}
if ($versionCode) {
    Write-Host $versionCode.Line.Trim()
}

Write-Host ''
Write-Host '=== Telegram theme preferences ==='
$prefResult = Invoke-AdbCapture -AdbArguments @(
    'shell', 'run-as', $Package, 'cat', 'shared_prefs/mainconfig.xml'
)
if ($prefResult.ExitCode -ne 0) {
    Write-Host 'runAs=unavailable'
    Write-Host 'Build/install the debuggable afatPrototype variant and run this script again.'
    exit 2
}

$xml = ($prefResult.Output -join [Environment]::NewLine)

$selectedAutoNightType = $null
if ($xml -match '<int name="selectedAutoNightType" value="(?<v>\d+)"\s*/>') {
    $selectedAutoNightType = [int]$Matches.v
}

$theme = $null
if ($xml -match '<string name="theme">(?<v>[^<]*)</string>') {
    $theme = $Matches.v
}

$nightTheme = $null
if ($xml -match '<string name="nighttheme">(?<v>[^<]*)</string>') {
    $nightTheme = $Matches.v
}

if ($null -eq $selectedAutoNightType) {
    Write-Host 'selectedAutoNightType=<missing> (Telegram default on Android 10+ is SYSTEM=3)'
} else {
    $modeName = switch ($selectedAutoNightType) {
        0 { 'NONE' }
        1 { 'SCHEDULED' }
        2 { 'AUTOMATIC' }
        3 { 'SYSTEM' }
        default { 'UNKNOWN' }
    }
    Write-Host ("selectedAutoNightType={0} ({1})" -f $selectedAutoNightType, $modeName)
}

if ($null -eq $theme -or $theme -eq '') {
    Write-Host 'theme=<default>'
} else {
    Write-Host ('theme=' + $theme)
}

if ($null -eq $nightTheme -or $nightTheme -eq '') {
    Write-Host 'nighttheme=<default Dark Blue>'
} else {
    Write-Host ('nighttheme=' + $nightTheme)
}

Write-Host ''
Write-Host '=== Telegram Dark Blue asset ==='
$darkBlueResult = Invoke-AdbCapture -AdbArguments @(
    'shell', 'run-as', $Package, 'cat', 'files/darkblue.attheme'
)
if ($darkBlueResult.ExitCode -ne 0) {
    Write-Host 'darkblueAsset=unavailable'
} else {
    $darkBlueText = ($darkBlueResult.Output -join [Environment]::NewLine)
    $themeKeys = @(
        'windowBackgroundWhite',
        'windowBackgroundWhiteBlackText',
        'windowBackgroundWhiteGrayText',
        'windowBackgroundWhiteBlueText4'
    )

    foreach ($themeKey in $themeKeys) {
        $pattern = '(?m)^' + [regex]::Escape($themeKey) + '=(?<v>-?\d+)\s*$'
        if ($darkBlueText -match $pattern) {
            $raw = [int64]$Matches.v
            $unsigned = [uint32]($raw -band 0xffffffffL)
            Write-Host ("{0}={1} (0x{2:x8})" -f $themeKey, $raw, $unsigned)
        } else {
            Write-Host ($themeKey + '=<missing>')
        }
    }
}

Write-Host ''
Write-Host '=== Telegram theme accent state ==='
$themeConfigResult = Invoke-AdbCapture -AdbArguments @(
    'shell', 'run-as', $Package, 'cat', 'shared_prefs/themeconfig.xml'
)
if ($themeConfigResult.ExitCode -ne 0) {
    Write-Host 'themeConfig=unavailable'
} else {
    $themeConfigXml = ($themeConfigResult.Output -join [Environment]::NewLine)
    $accentPattern = '<int name="accent_current_darkblue\.attheme" value="(?<v>-?\d+)"\s*/>'
    if ($themeConfigXml -match $accentPattern) {
        Write-Host ('darkBlueCurrentAccentId=' + $Matches.v)
    } else {
        Write-Host 'darkBlueCurrentAccentId=<missing> (upstream default is 0)'
    }
}

Write-Host ''
Write-Host '=== Runtime Telegram theme ==='
$runtimeResult = Invoke-AdbCapture -AdbArguments @(
    'logcat', '-d', '-v', 'brief', 'TelegramWSPTheme:I', '*:S'
)
if ($runtimeResult.ExitCode -ne 0) {
    Write-Host 'runtimeThemeLog=unavailable'
} else {
    $runtimeLines = @(
        $runtimeResult.Output |
            Where-Object { $_ -match 'TelegramWSPTheme' } |
            Select-Object -Last 10
    )

    if ($runtimeLines.Count -eq 0) {
        Write-Host 'runtimeThemeLog=<missing>'
        Write-Host 'Install the latest diagnostic prototype, relaunch it, wait 8 seconds, and run this script again.'
    } else {
        $runtimeLines | ForEach-Object { Write-Host $_ }
    }
}

Write-Host ''
Write-Host '=== Interpretation ==='
Write-Host 'AUTO_NIGHT_TYPE constants: NONE=0, SCHEDULED=1, AUTOMATIC=2, SYSTEM=3.'
Write-Host 'For the system-dark acceptance case we expect:'
Write-Host '  Android resourceQualifier=night'
Write-Host '  selectedAutoNightType=3 (SYSTEM), or the preference absent so Telegram uses SYSTEM by default.'
Write-Host 'If Android is night but Telegram stores NONE=0, the fork is intentionally staying on its day theme.'
Write-Host 'Dark Blue asset should provide opaque colors; runtime values should not unexpectedly become transparent.'
Write-Host 'Do not paste the full preferences XML; this script prints only theme-related values and diagnostic log lines.'
