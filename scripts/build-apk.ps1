[CmdletBinding()]
param(
    [string]$TelegramPath = '.work/telegram',
    [switch]$Full,
    [switch]$Offline,
    [switch]$SkipPrepare
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

if (-not $SkipPrepare) {
    & (Join-Path $PSScriptRoot 'prepare-integration.ps1')
}

$telegram = [System.IO.Path]::GetFullPath((Join-Path $root $TelegramPath))

if (-not (Test-Path (Join-Path $telegram '.git'))) {
    throw "Telegram checkout not found: $telegram"
}

$variant = if ($Full) { 'standalone' } else { 'prototype' }
$apk = Join-Path $telegram "TMessagesProj_AppStandalone/build/outputs/apk/afat/$variant/app.apk"

# A failed build must never leave a stale APK that can be installed by mistake.
Remove-Item -Force $apk -ErrorAction SilentlyContinue

& (Join-Path $PSScriptRoot 'ensure-telegram-theme-assets-lf.ps1') -TelegramPath $telegram

if ($env:TELEGRAM_API_ID -notmatch '^\d+$') {
    throw 'TELEGRAM_API_ID must be set in the current process and contain decimal digits only.'
}
if ($env:TELEGRAM_API_HASH -notmatch '^[0-9a-fA-F]{32}$') {
    throw 'TELEGRAM_API_HASH must be set in the current process and contain exactly 32 hexadecimal characters.'
}

$buildVarsPath = Join-Path $telegram 'TMessagesProj/src/main/java/org/telegram/messenger/BuildVars.java'
if (-not (Test-Path $buildVarsPath)) {
    throw "Prepared BuildVars.java not found: $buildVarsPath"
}

$buildVars = Get-Content $buildVarsPath -Raw
if ($buildVars -notmatch 'BuildConfig\.TELEGRAM_API_ID') {
    throw 'Telegram API credential overlay is not applied.'
}
if ($buildVars -notmatch 'public static boolean SUPPORTS_PASSKEYS = false;') {
    throw 'Fork passkey guard is not applied.'
}

$bootstrapPath = Join-Path $telegram 'TMessagesProj_AppStandalone/src/main/java/org/telegram/messenger/TgWsProxyBootstrap.java'
$bootstrap = Get-Content $bootstrapPath -Raw
if ($bootstrap -notmatch '@connection_mode=cf_first') {
    throw 'Embedded TgWsProxy runtime is not configured for cf_first.'
}

$gradle = Get-Command gradle -ErrorAction SilentlyContinue
if ($null -eq $gradle) {
    throw 'Gradle was not found in PATH.'
}

$jlatexAar = Join-Path $telegram 'TMessagesProj/lib/jlatexmath/jlatexmath/build/outputs/aar/jlatexmath-release.aar'
$jlatexGradleArgs = @(':jlatexmath:assembleRelease', '--daemon', '--build-cache')
if ($Offline) {
    $jlatexGradleArgs += '--offline'
}

Write-Host 'Building Telegram jlatexmath AAR dependency...'
Push-Location $telegram
try {
    & $gradle.Source @jlatexGradleArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Telegram jlatexmath AAR build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path $jlatexAar)) {
    throw "Telegram jlatexmath AAR was not produced: $jlatexAar"
}
Write-Host "Telegram jlatexmath AAR ready: $jlatexAar"

if ($Full) {
    $task = ':TMessagesProj_AppStandalone:assembleAfatStandalone'
    $mode = 'full standalone'
    $gradleArgs = @($task, '--daemon', '--build-cache', '--parallel')
} else {
    $task = ':TMessagesProj_AppStandalone:assembleAfatPrototype'
    $mode = 'fast ARM64 prototype'
    $gradleArgs = @($task, '--daemon', '--build-cache', '--parallel', '-PTGWS_PROXY_ARM64_ONLY=true')
}
if ($Offline) {
    $gradleArgs += '--offline'
}

Write-Host "Building Telegram APK mode: $mode"
Write-Host "Gradle task: $task"
Write-Host "Offline dependency resolution: $Offline"

Push-Location $telegram
try {
    & $gradle.Source @gradleArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Telegram APK build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path $apk)) {
    throw "Telegram APK was not produced at the expected path: $apk"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$apkArchive = [System.IO.Compression.ZipFile]::OpenRead($apk)
try {
    $themeEntries = @(
        $apkArchive.Entries |
            Where-Object { $_.FullName -match '^assets/[^/]+\.attheme$' }
    )
    if ($themeEntries.Count -eq 0) {
        throw 'Built APK contains no top-level Telegram .attheme assets.'
    }

    foreach ($themeEntry in $themeEntries) {
        $entryStream = $themeEntry.Open()
        $memory = New-Object System.IO.MemoryStream
        try {
            $entryStream.CopyTo($memory)
            $themeBytes = $memory.ToArray()
        }
        finally {
            $memory.Dispose()
            $entryStream.Dispose()
        }

        if ($themeBytes -contains [byte]13) {
            throw "Built APK Telegram theme asset still contains CR bytes: $($themeEntry.FullName)"
        }
    }
}
finally {
    $apkArchive.Dispose()
}

$apkItem = Get-Item $apk
Write-Host 'Telegram APK built successfully.'
Write-Host "Mode: $mode"
Write-Host "APK: $($apkItem.FullName)"
Write-Host "Size: $($apkItem.Length) bytes"
Write-Host "APK LF theme assets verified: $($themeEntries.Count) file(s)"
