[CmdletBinding()]
param(
    [string]$Package = 'org.telegram.messenger.web'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $output = & adb @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "adb $($Args -join ' ') failed:
$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

function Get-Prop {
    param([string]$Name)
    return ((Invoke-Adb shell getprop $Name) -join '').Trim()
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
if ($miui) { Write-Host ('miui=' + $miui) }
$hyper = Get-Prop 'ro.mi.os.version.name'
if ($hyper) { Write-Host ('hyperos=' + $hyper) }

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
if ($versionName) { Write-Host $versionName.Line.Trim() }
if ($versionCode) { Write-Host $versionCode.Line.Trim() }

Write-Host ''
Write-Host '=== Telegram theme preferences ==='
$prefOutput = & adb shell run-as $Package cat shared_prefs/mainconfig.xml 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'runAs=unavailable'
    Write-Host 'Build/install the debuggable afatPrototype variant and run this script again.'
    exit 2
}

$xml = ($prefOutput -join [Environment]::NewLine)

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

Write-Host ('theme=' + $(if ($null -eq $theme -or $theme -eq '') { '<default>' } else { $theme }))
Write-Host ('nighttheme=' + $(if ($null -eq $nightTheme -or $nightTheme -eq '') { '<default Dark Blue>' } else { $nightTheme }))

Write-Host ''
Write-Host '=== Telegram Dark Blue asset ==='
$darkBlueOutput = & adb shell run-as $Package cat files/darkblue.attheme 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'darkblueAsset=unavailable'
} else {
    $darkBlueText = ($darkBlueOutput -join [Environment]::NewLine)
    foreach ($themeKey in @(
        'windowBackgroundWhite',
        'windowBackgroundWhiteBlackText',
        'windowBackgroundWhiteGrayText',
        'windowBackgroundWhiteBlueText4'
    )) {
        if ($darkBlueText -match ('(?m)^' + [regex]::Escape($themeKey) + '=(?<v>-?\d+)\s*$runtimeLog = & adb logcat -d -v brief "TelegramWSPTheme:I" "*:S" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'runtimeThemeLog=unavailable'
} else {
    $runtimeLines = @(
        $runtimeLog |
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
Write-Host 'Runtime diagnostics should show activeTheme/currentThemeDark and the actual Telegram background/text colors.'
Write-Host 'Do not paste the full mainconfig.xml; this script prints only theme-related values and diagnostic log lines.'
)) {
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
$themeConfigOutput = & adb shell run-as $Package cat shared_prefs/themeconfig.xml 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'themeConfig=unavailable'
} else {
    $themeConfigXml = ($themeConfigOutput -join [Environment]::NewLine)
    if ($themeConfigXml -match '<int name="accent_current_darkblue\.attheme" value="(?<v>-?\d+)"\s*/>') {
        Write-Host ('darkBlueCurrentAccentId=' + $Matches.v)
    } else {
        Write-Host 'darkBlueCurrentAccentId=<missing> (upstream default is 0)'
    }
}

Write-Host ''
Write-Host '=== Runtime Telegram theme ==='
$runtimeLog = & adb logcat -d -v brief "TelegramWSPTheme:I" "*:S" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'runtimeThemeLog=unavailable'
} else {
    $runtimeLines = @(
        $runtimeLog |
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
Write-Host 'Runtime diagnostics should show activeTheme/currentThemeDark and the actual Telegram background/text colors.'
Write-Host 'Do not paste the full mainconfig.xml; this script prints only theme-related values and diagnostic log lines.'
