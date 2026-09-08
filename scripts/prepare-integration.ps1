[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$RebuildCore,
    [switch]$VerifyCore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$telegramPath = Join-Path $root '.work/telegram'
$corePath = Join-Path $root '.work/tgwsproxy-core'
$coreAar = Join-Path $corePath 'core/build/outputs/aar/core-release.aar'

$upstream = Get-Content (Join-Path $root 'config/upstream.json') -Raw | ConvertFrom-Json
$coreConfig = Get-Content (Join-Path $root 'config/core.json') -Raw | ConvertFrom-Json
$telegramCommit = [string]$upstream.pinnedCommit
$coreCommit = [string]$coreConfig.pinnedCommit

function Get-Head([string]$path) {
    if (-not (Test-Path (Join-Path $path '.git'))) {
        return $null
    }
    $head = (& git -C $path rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return $head.Trim()
}

if ($Force) {
    & (Join-Path $PSScriptRoot 'fetch-upstream.ps1') -Force
    & (Join-Path $PSScriptRoot 'fetch-core.ps1') -Force
    $RebuildCore = $true
} else {
    $telegramHead = Get-Head $telegramPath
    if ($telegramHead -ne $telegramCommit) {
        Write-Host 'Telegram checkout is missing or not pinned; refreshing upstream checkout.'
        & (Join-Path $PSScriptRoot 'fetch-upstream.ps1')
    } else {
        Write-Host "Reusing pinned Telegram checkout: $telegramCommit"
    }

    $coreHead = Get-Head $corePath
    if ($coreHead -ne $coreCommit) {
        Write-Host 'tgwsproxy-core checkout is missing or not pinned; refreshing core checkout.'
        & (Join-Path $PSScriptRoot 'fetch-core.ps1')
        $RebuildCore = $true
    } else {
        Write-Host "Reusing pinned tgwsproxy-core checkout: $coreCommit"
    }
}

if ($RebuildCore -or -not (Test-Path $coreAar)) {
    if ($VerifyCore) {
        & (Join-Path $PSScriptRoot 'build-core.ps1') -WithTests
    } else {
        & (Join-Path $PSScriptRoot 'build-core.ps1')
    }
} else {
    Write-Host "Reusing core AAR: $coreAar"
}

& (Join-Path $PSScriptRoot 'apply-integration.ps1')

Write-Host "Prepared Telegram integration under $telegramPath"
