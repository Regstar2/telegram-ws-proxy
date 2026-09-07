[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if ($Force) {
    & (Join-Path $PSScriptRoot 'fetch-upstream.ps1') -Force
    & (Join-Path $PSScriptRoot 'fetch-core.ps1') -Force
} else {
    & (Join-Path $PSScriptRoot 'fetch-upstream.ps1')
    & (Join-Path $PSScriptRoot 'fetch-core.ps1')
}

& (Join-Path $PSScriptRoot 'build-core.ps1')
& (Join-Path $PSScriptRoot 'apply-integration.ps1')

Write-Host "Prepared Telegram integration under $(Join-Path $root '.work/telegram')"
