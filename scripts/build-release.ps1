[CmdletBinding()]
param(
    [string]$TelegramPath = '.work/telegram',
    [string]$Keystore = '.signing/telegram-wsp-release.p12',
    [string]$KeyAlias = 'telegram-wsp-release',
    [string]$Output = 'dist/Telegram-WSP-release.apk',
    [ValidateRange(1, 99)][int]$ReleaseRevision = 1,
    [switch]$Offline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Resolve-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $root $Path))
}

function Convert-SecureStringToPlainText {
    param([Parameter(Mandatory = $true)][System.Security.SecureString]$Value)

    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Get-LocalProperty {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path $File)) {
        return $null
    }

    $pattern = '^' + [regex]::Escape($Name) + '='
    $line = Get-Content $File | Where-Object { $_ -match $pattern } | Select-Object -First 1
    if (-not $line) {
        return $null
    }

    return $line.Substring($Name.Length + 1).Trim()
}

function Find-AndroidBuildTools {
    param([string]$LocalProperties)

    $sdkCandidates = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, 'C:\Android\SDK', "$env:LOCALAPPDATA\Android\Sdk")) {
        if ($candidate -and -not $sdkCandidates.Contains($candidate)) {
            $sdkCandidates.Add($candidate)
        }
    }

    $sdkProperty = Get-LocalProperty -File $LocalProperties -Name 'sdk.dir'
    if ($sdkProperty -and -not $sdkCandidates.Contains($sdkProperty)) {
        $sdkCandidates.Insert(0, $sdkProperty)
    }

    foreach ($sdkRoot in $sdkCandidates) {
        $buildToolsRoot = Join-Path $sdkRoot 'build-tools'
        if (-not (Test-Path $buildToolsRoot)) {
            continue
        }

        $buildTools = Get-ChildItem $buildToolsRoot -Directory |
            Where-Object {
                (Test-Path (Join-Path $_.FullName 'aapt.exe')) -and
                (Test-Path (Join-Path $_.FullName 'apksigner.bat'))
            } |
            Sort-Object {
                try { [version]$_.Name }
                catch { [version]'0.0' }
            } -Descending |
            Select-Object -First 1

        if ($buildTools) {
            return $buildTools
        }
    }

    throw 'Android Build Tools with aapt.exe and apksigner.bat were not found.'
}

function Remove-PathWithRetry {
    param([Parameter(Mandatory = $true)][string]$Path)

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $Path)) {
            return
        }
        Start-Sleep -Seconds 2
    }

    throw "Could not remove locked build path: $Path"
}

$telegram = Resolve-ProjectPath $TelegramPath
$keystorePath = Resolve-ProjectPath $Keystore
$outputPath = Resolve-ProjectPath $Output

if (-not (Test-Path $keystorePath)) {
    throw "Release keystore not found: $keystorePath. Run scripts/create-release-keystore.ps1 first."
}

$gradle = Get-Command gradle -ErrorAction SilentlyContinue
if ($null -eq $gradle) {
    throw 'Gradle was not found in PATH.'
}

Write-Host 'Preparing Telegram integration...'
& (Join-Path $PSScriptRoot 'prepare-integration.ps1')

$localProperties = Join-Path $telegram 'local.properties'
if ($env:TELEGRAM_API_ID -notmatch '^\d+$') {
    $env:TELEGRAM_API_ID = Get-LocalProperty -File $localProperties -Name 'TELEGRAM_API_ID'
}
if ($env:TELEGRAM_API_HASH -notmatch '^[0-9a-fA-F]{32}$') {
    $env:TELEGRAM_API_HASH = Get-LocalProperty -File $localProperties -Name 'TELEGRAM_API_HASH'
}
if ($env:TELEGRAM_API_ID -notmatch '^\d+$') {
    throw 'TELEGRAM_API_ID must be set in the environment or .work/telegram/local.properties.'
}
if ($env:TELEGRAM_API_HASH -notmatch '^[0-9a-fA-F]{32}$') {
    throw 'TELEGRAM_API_HASH must be set in the environment or .work/telegram/local.properties.'
}

$buildGradle = Join-Path $telegram 'TMessagesProj_AppStandalone/build.gradle'
$build = Get-Content $buildGradle -Raw

$afatBrandingPattern = "(?ms)productFlavors\s*\{.*?afat\s*\{.*?sourceSets\.standalone\s*\{\s*manifest\.srcFile\s+'\.\./\.tgwsproxy/branding/AndroidManifest_standalone\.xml'"
if ($build -notmatch $afatBrandingPattern) {
    throw 'Prepared afatStandalone variant does not use the generated Telegram-WSP branding manifest.'
}

$releaseSigningPattern = @'
(?ms)^[ \t]*release\s*\{\s*
[ \t]*storeFile\s+file\("\.\./TMessagesProj/config/release\.keystore"\)\s*
[ \t]*storePassword\s+RELEASE_STORE_PASSWORD\s*
[ \t]*keyAlias\s+RELEASE_KEY_ALIAS\s*
[ \t]*keyPassword\s+RELEASE_KEY_PASSWORD\s*
[ \t]*\}
'@.Trim()

$releaseSigningRegex = [regex]::new($releaseSigningPattern)
$releaseSigningMatches = $releaseSigningRegex.Matches($build)

$releaseSigningBlock = @'
        release {
            def tgwsKeystore = System.getenv('TELEGRAM_WSP_KEYSTORE')
            def tgwsPassword = System.getenv('TELEGRAM_WSP_KEYSTORE_PASSWORD')
            def tgwsAlias = System.getenv('TELEGRAM_WSP_KEY_ALIAS')

            if (!tgwsKeystore || !tgwsPassword || !tgwsAlias) {
                throw new GradleException('Telegram-WSP release signing variables are missing.')
            }

            storeFile file(tgwsKeystore)
            storePassword tgwsPassword
            keyAlias tgwsAlias
            keyPassword tgwsPassword
        }
'@

$managedKeystoreCount = ([regex]::Matches($build, [regex]::Escape("System.getenv('TELEGRAM_WSP_KEYSTORE')"))).Count
$managedPasswordCount = ([regex]::Matches($build, [regex]::Escape("System.getenv('TELEGRAM_WSP_KEYSTORE_PASSWORD')"))).Count
$managedAliasCount = ([regex]::Matches($build, [regex]::Escape("System.getenv('TELEGRAM_WSP_KEY_ALIAS')"))).Count
$managedSigningPresent = (
    $managedKeystoreCount -eq 1 -and
    $managedPasswordCount -eq 1 -and
    $managedAliasCount -eq 1
)

if ($releaseSigningMatches.Count -eq 1 -and -not $managedSigningPresent) {
    $build = $releaseSigningRegex.Replace($build, $releaseSigningBlock, 1)
    Write-Host 'Release signing configuration: applied Telegram-WSP keystore.'
}
elseif ($releaseSigningMatches.Count -eq 0 -and $managedSigningPresent) {
    Write-Host 'Release signing configuration: existing Telegram-WSP keystore configuration reused.'
}
else {
    throw "Release signing configuration is ambiguous. Upstream blocks: $($releaseSigningMatches.Count); managed env markers: keystore=$managedKeystoreCount password=$managedPasswordCount alias=$managedAliasCount."
}

$password = $env:TELEGRAM_WSP_KEYSTORE_PASSWORD
if ([string]::IsNullOrEmpty($password)) {
    $securePassword = Read-Host 'Release keystore password' -AsSecureString
    $password = Convert-SecureStringToPlainText $securePassword
}
if ([string]::IsNullOrEmpty($password)) {
    throw 'Release keystore password cannot be empty.'
}

$env:TELEGRAM_WSP_KEYSTORE = $keystorePath
$env:TELEGRAM_WSP_KEYSTORE_PASSWORD = $password
$env:TELEGRAM_WSP_KEY_ALIAS = $KeyAlias
$env:TELEGRAM_WSP_RELEASE_REVISION = [string]$ReleaseRevision

try {
    Set-Content -Path $buildGradle -Value $build -NoNewline

    $preparedBuild = Get-Content $buildGradle -Raw
    if ($preparedBuild -notmatch 'TELEGRAM_WSP_KEYSTORE') {
        throw 'Custom release signingConfig was not applied.'
    }

    Write-Host 'Stopping Gradle daemons before the R8 release build...'
    & $gradle.Source --stop | Out-Null
    Start-Sleep -Seconds 2

    $appBuild = Join-Path $telegram 'TMessagesProj_AppStandalone/build'
    foreach ($path in @(
        (Join-Path $appBuild 'intermediates/dex/afatStandalone'),
        (Join-Path $appBuild 'intermediates/global_synthetics/afatStandalone'),
        (Join-Path $appBuild 'intermediates/shrunk_java_res/afatStandalone'),
        (Join-Path $appBuild 'intermediates/optimized_processed_res/afatStandalone'),
        (Join-Path $appBuild 'outputs/apk/afat/standalone')
    )) {
        Remove-PathWithRetry $path
    }

    $buildParameters = @{
        TelegramPath = $TelegramPath
        Full = $true
        SkipPrepare = $true
        Offline = [bool]$Offline
    }

    & (Join-Path $PSScriptRoot 'build-apk.ps1') @buildParameters

    $builtApk = Join-Path $telegram 'TMessagesProj_AppStandalone/build/outputs/apk/afat/standalone/app.apk'
    if (-not (Test-Path $builtApk)) {
        throw "Release APK was not produced: $builtApk"
    }

    $outputDirectory = Split-Path -Parent $outputPath
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    Copy-Item -Force $builtApk $outputPath

    $buildTools = Find-AndroidBuildTools -LocalProperties $localProperties
    $aapt = Join-Path $buildTools.FullName 'aapt.exe'
    $apkSigner = Join-Path $buildTools.FullName 'apksigner.bat'

    $badgingLines = @(& $aapt dump badging $outputPath)
    if ($LASTEXITCODE -ne 0) {
        throw 'aapt dump badging failed.'
    }
    $badgingText = $badgingLines -join [Environment]::NewLine

    if ($badgingText -notmatch "package: name='org\.telegram\.messenger\.web'") {
        throw 'Release APK package ID is not org.telegram.messenger.web.'
    }
    if ($badgingText -notmatch "application-label:'Telegram-WSP'") {
        throw 'Release APK application label is not Telegram-WSP.'
    }

    $upstream = Get-Content (Join-Path $root 'config/upstream.json') -Raw | ConvertFrom-Json
    $expectedVersionCode = ([int]$upstream.telegramBuild * 1000) + ($ReleaseRevision * 10) + 9
    if ($badgingText -notmatch ("versionCode='" + [regex]::Escape([string]$expectedVersionCode) + "'")) {
        throw "Release APK versionCode does not match WSP revision. Expected $expectedVersionCode."
    }

    Write-Host 'APK metadata:'
    $badgingLines |
        Select-String -Pattern 'package:|application-label:|application-icon' |
        Select-Object -First 12 |
        ForEach-Object { Write-Host $_.Line }

    Write-Host 'APK signature:'
    & $apkSigner verify --verbose --print-certs $outputPath
    if ($LASTEXITCODE -ne 0) {
        throw 'APK signature verification failed.'
    }

    $hash = Get-FileHash $outputPath -Algorithm SHA256
    $apkItem = Get-Item $outputPath

    Write-Host ''
    Write-Host 'Telegram-WSP release ready.'
    Write-Host "APK: $($apkItem.FullName)"
    Write-Host "Size: $($apkItem.Length) bytes"
    Write-Host "SHA256: $($hash.Hash)"
    Write-Host "Keystore: $keystorePath"
    Write-Host "Alias: $KeyAlias"
    Write-Host "Release revision: $ReleaseRevision"
    Write-Host "Android versionCode: $expectedVersionCode"
}
finally {
    $password = $null
    Remove-Item Env:TELEGRAM_WSP_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:TELEGRAM_WSP_KEYSTORE -ErrorAction SilentlyContinue
    Remove-Item Env:TELEGRAM_WSP_KEY_ALIAS -ErrorAction SilentlyContinue
    Remove-Item Env:TELEGRAM_WSP_RELEASE_REVISION -ErrorAction SilentlyContinue
}
