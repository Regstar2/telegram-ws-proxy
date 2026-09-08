[CmdletBinding()]
param(
    [string]$Keystore = '.signing/telegram-wsp-release.p12',
    [string]$Alias = 'telegram-wsp-release',
    [string]$DistinguishedName = 'CN=Telegram-WSP, OU=Release, O=Regstar2',
    [int]$ValidityDays = 10000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$keystorePath = if ([System.IO.Path]::IsPathRooted($Keystore)) {
    [System.IO.Path]::GetFullPath($Keystore)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $root $Keystore))
}

if (Test-Path $keystorePath) {
    Write-Host "Release keystore already exists: $keystorePath"
    Write-Host 'Refusing to replace it because changing the signing key breaks APK update compatibility.'
    exit 0
}

$keytoolPath = $null
$keytoolCommand = Get-Command keytool.exe -ErrorAction SilentlyContinue
if ($keytoolCommand) {
    $keytoolPath = $keytoolCommand.Source
}

if (-not $keytoolPath -and $env:JAVA_HOME) {
    $candidate = Join-Path $env:JAVA_HOME 'bin/keytool.exe'
    if (Test-Path $candidate) {
        $keytoolPath = $candidate
    }
}

if (-not $keytoolPath) {
    foreach ($candidate in @(
        'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe',
        'C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot\bin\keytool.exe',
        'C:\Program Files\Java\jdk-21\bin\keytool.exe',
        'C:\Program Files\Java\jdk-17\bin\keytool.exe'
    )) {
        if (Test-Path $candidate) {
            $keytoolPath = $candidate
            break
        }
    }
}

if (-not $keytoolPath) {
    throw 'keytool.exe was not found. Install JDK 17+ or set JAVA_HOME.'
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

$password = $null
while (-not $password -or $password.Length -lt 12) {
    $securePassword = Read-Host 'New release keystore password (minimum 12 characters)' -AsSecureString
    $password = Convert-SecureStringToPlainText $securePassword
    if ($password.Length -lt 12) {
        Write-Host 'Password is too short.'
        $password = $null
    }
}

$confirmed = $false
while (-not $confirmed) {
    $secureConfirmation = Read-Host 'Repeat release keystore password' -AsSecureString
    $confirmation = Convert-SecureStringToPlainText $secureConfirmation
    $confirmed = $password -ceq $confirmation
    $confirmation = $null
    if (-not $confirmed) {
        Write-Host 'Passwords do not match.'
    }
}

New-Item -ItemType Directory -Path (Split-Path -Parent $keystorePath) -Force | Out-Null
$env:TELEGRAM_WSP_KEYSTORE_PASSWORD = $password

try {
    & $keytoolPath -genkeypair -v -storetype PKCS12 -keystore $keystorePath -alias $Alias -keyalg RSA -keysize 4096 -sigalg SHA256withRSA -validity $ValidityDays -dname $DistinguishedName '-storepass:env' TELEGRAM_WSP_KEYSTORE_PASSWORD '-keypass:env' TELEGRAM_WSP_KEYSTORE_PASSWORD
    if ($LASTEXITCODE -ne 0) {
        throw 'keytool failed to create the release keystore.'
    }

    & $keytoolPath -list -keystore $keystorePath -alias $Alias '-storepass:env' TELEGRAM_WSP_KEYSTORE_PASSWORD | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'The newly created release keystore could not be verified.'
    }

    Write-Host ''
    Write-Host 'Telegram-WSP release keystore created.'
    Write-Host "Keystore: $keystorePath"
    Write-Host "Alias: $Alias"
    Write-Host 'Back up this file and its password. Do not create a different key for future updates.'
}
finally {
    $password = $null
    Remove-Item Env:TELEGRAM_WSP_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
}
