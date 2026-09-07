[CmdletBinding()]
param(
    [string]$TelegramPath = '.work/telegram'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$telegram = [System.IO.Path]::GetFullPath((Join-Path $root $TelegramPath))

if (-not (Test-Path (Join-Path $telegram '.git'))) {
    throw "Telegram checkout not found: $telegram"
}

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
    throw 'Telegram API credential overlay is not applied. Run prepare-integration.ps1 first.'
}
if ($buildVars -notmatch 'public static boolean SUPPORTS_PASSKEYS = false;') {
    throw 'Fork passkey guard is not applied. Run prepare-integration.ps1 from the current branch first.'
}

$gradle = Get-Command gradle -ErrorAction SilentlyContinue
if ($null -eq $gradle) {
    throw 'Gradle was not found in PATH.'
}

Push-Location $telegram
try {
    & $gradle.Source ':TMessagesProj_AppStandalone:assembleAfatStandalone' '--no-daemon'
    if ($LASTEXITCODE -ne 0) {
        throw "Telegram standalone APK build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$apk = Join-Path $telegram 'TMessagesProj_AppStandalone/build/outputs/apk/afat/standalone/app.apk'
if (-not (Test-Path $apk)) {
    throw "Standalone APK was not produced at the expected path: $apk"
}

$apkItem = Get-Item $apk
Write-Host 'Standalone Telegram prototype APK built successfully.'
Write-Host "APK: $($apkItem.FullName)"
Write-Host "Size: $($apkItem.Length) bytes"
