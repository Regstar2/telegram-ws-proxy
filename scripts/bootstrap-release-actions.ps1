[CmdletBinding()]
param(
    [string]$Repository = 'Regstar2/telegram-wsp',
    [string]$Keystore = '.signing/telegram-wsp-release.p12',
    [string]$LocalProperties = '.work/telegram/local.properties',
    [ValidateRange(1, 99)][int]$Revision = 1,
    [switch]$NoWatch
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

function Get-LocalProperty {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path $File)) {
        return $null
    }

    $pattern = '^' + [regex]::Escape($Name) + '='
    $line = Get-Content $File |
        Where-Object { $_ -match $pattern } |
        Select-Object -First 1

    if (-not $line) {
        return $null
    }

    return $line.Substring($Name.Length + 1).Trim()
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

function Set-RepositorySecret {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Secret $Name is empty."
    }

    $Value | & gh secret set $Name --repo $Repository
    if ($LASTEXITCODE -ne 0) {
        throw "Could not configure GitHub Actions secret $Name."
    }
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    throw 'GitHub CLI (gh) was not found in PATH.'
}

& gh auth status
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub CLI is not authenticated. Run: gh auth login'
}

$keystorePath = Resolve-ProjectPath $Keystore
$localPropertiesPath = Resolve-ProjectPath $LocalProperties

if (-not (Test-Path $keystorePath)) {
    throw "Release keystore not found: $keystorePath"
}
if (-not (Test-Path $localPropertiesPath)) {
    throw "Telegram local.properties not found: $localPropertiesPath"
}

$apiId = if ($env:TELEGRAM_API_ID -match '^\d+$') {
    $env:TELEGRAM_API_ID
} else {
    Get-LocalProperty -File $localPropertiesPath -Name 'TELEGRAM_API_ID'
}
$apiHash = if ($env:TELEGRAM_API_HASH -match '^[0-9a-fA-F]{32}$') {
    $env:TELEGRAM_API_HASH
} else {
    Get-LocalProperty -File $localPropertiesPath -Name 'TELEGRAM_API_HASH'
}

if ($apiId -notmatch '^\d+$') {
    throw 'TELEGRAM_API_ID is missing or invalid.'
}
if ($apiHash -notmatch '^[0-9a-fA-F]{32}$') {
    throw 'TELEGRAM_API_HASH is missing or invalid.'
}

$keytool = Get-Command keytool.exe -ErrorAction SilentlyContinue
if (-not $keytool) {
    throw 'keytool.exe was not found in PATH. Use the same JDK that created the release key.'
}

$securePassword = Read-Host 'Release keystore password' -AsSecureString
$password = Convert-SecureStringToPlainText $securePassword
if ([string]::IsNullOrEmpty($password)) {
    throw 'Release keystore password cannot be empty.'
}

$env:TELEGRAM_WSP_BOOTSTRAP_KEYSTORE_PASSWORD = $password

try {
    & $keytool.Source `
        -list `
        -keystore $keystorePath `
        -alias 'telegram-wsp-release' `
        '-storepass:env' TELEGRAM_WSP_BOOTSTRAP_KEYSTORE_PASSWORD |
        Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw 'Release keystore password or alias is invalid.'
    }

    Write-Host 'Release keystore verified.'

    $keystoreBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystorePath))
    try {
        Write-Host 'Configuring GitHub Actions release secrets...'
        Set-RepositorySecret -Name 'RELEASE_KEYSTORE_BASE64' -Value $keystoreBase64
        Set-RepositorySecret -Name 'RELEASE_KEYSTORE_PASSWORD' -Value $password
        Set-RepositorySecret -Name 'TELEGRAM_API_ID' -Value $apiId
        Set-RepositorySecret -Name 'TELEGRAM_API_HASH' -Value $apiHash
    }
    finally {
        $keystoreBase64 = $null
    }

    $secretNames = @(
        & gh secret list --repo $Repository --json name --jq '.[].name'
    )
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not verify configured GitHub Actions secret names.'
    }

    foreach ($required in @(
        'RELEASE_KEYSTORE_BASE64',
        'RELEASE_KEYSTORE_PASSWORD',
        'TELEGRAM_API_ID',
        'TELEGRAM_API_HASH'
    )) {
        if ($secretNames -notcontains $required) {
            throw "GitHub Actions secret is still missing: $required"
        }
    }

    Write-Host 'GitHub Actions release secrets: OK'

    $existingRuns = @(
        & gh run list `
            --repo $Repository `
            --workflow 'upstream-sync.yml' `
            --limit 20 `
            --json databaseId `
            --jq '.[].databaseId'
    )

    Write-Host "Starting Telegram-WSP release revision $Revision through upstream-sync.yml..."
    & gh workflow run 'upstream-sync.yml' `
        --repo $Repository `
        --ref main `
        -f 'force_release=true' `
        -f "revision=$Revision"

    if ($LASTEXITCODE -ne 0) {
        throw 'Could not dispatch upstream-sync.yml.'
    }

    $runId = $null
    for ($attempt = 0; $attempt -lt 20 -and -not $runId; $attempt++) {
        Start-Sleep -Seconds 3

        $candidates = @(
            & gh run list `
                --repo $Repository `
                --workflow 'upstream-sync.yml' `
                --limit 20 `
                --json databaseId,event,status,createdAt `
                --jq '.[] | select(.event == "workflow_dispatch") | .databaseId'
        )

        foreach ($candidate in $candidates) {
            if ($existingRuns -notcontains $candidate) {
                $runId = $candidate
                break
            }
        }
    }

    if (-not $runId) {
        throw 'The dispatched upstream-sync workflow run could not be located.'
    }

    Write-Host "GitHub Actions run: $runId"

    if ($NoWatch) {
        Write-Host "Watch later with: gh run watch $runId --repo $Repository --exit-status"
        exit 0
    }

    & gh run watch $runId --repo $Repository --exit-status
    if ($LASTEXITCODE -ne 0) {
        throw "Release workflow run $runId failed."
    }

    $upstreamConfig = Get-Content (Join-Path $root 'config/upstream.json') -Raw | ConvertFrom-Json
    $tag = "v$($upstreamConfig.telegramVersion)-wsp.$Revision"

    Write-Host ''
    Write-Host "Verifying GitHub Release $tag..."
    & gh release view $tag --repo $Repository
    if ($LASTEXITCODE -ne 0) {
        throw "Expected GitHub Release was not published: $tag"
    }

    Write-Host ''
    Write-Host 'Telegram-WSP release bootstrap completed.'
    Write-Host "Release: $tag"
    Write-Host "Update feed: https://github.com/$Repository/releases/latest/download/latest.json"
}
finally {
    $password = $null
    $apiId = $null
    $apiHash = $null
    Remove-Item Env:TELEGRAM_WSP_BOOTSTRAP_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
}
