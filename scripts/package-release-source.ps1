[CmdletBinding()]
param(
    [string]$OutputDirectory = 'dist/source'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$telegram = Join-Path $root '.work/telegram'
$core = Join-Path $root '.work/tgwsproxy-core'
$output = [System.IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
New-Item -ItemType Directory -Path $output -Force | Out-Null

$upstream = Get-Content (Join-Path $root 'config/upstream.json') -Raw | ConvertFrom-Json
$coreConfig = Get-Content (Join-Path $root 'config/core.json') -Raw | ConvertFrom-Json

function Assert-Head {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    if (-not (Test-Path (Join-Path $RepositoryPath '.git'))) {
        throw "Git checkout is missing: $RepositoryPath"
    }

    $actual = (& git -C $RepositoryPath rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actual -ne $Expected) {
        throw "Unexpected checkout HEAD at $RepositoryPath: $actual != $Expected"
    }
}

Assert-Head -RepositoryPath $telegram -Expected ([string]$upstream.pinnedCommit)
Assert-Head -RepositoryPath $core -Expected ([string]$coreConfig.pinnedCommit)

$telegramArchive = Join-Path $output ("Telegram-upstream-source-{0}-{1}.zip" -f $upstream.telegramVersion, $upstream.telegramBuild)
$coreArchive = Join-Path $output ("tgwsproxy-core-source-{0}.zip" -f ([string]$coreConfig.pinnedCommit).Substring(0, 12))
$overlayArchive = Join-Path $output ("Telegram-WSP-overlay-source-{0}.zip" -f $upstream.telegramVersion)

& git -C $telegram archive --format=zip -o $telegramArchive HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not archive Telegram upstream source.' }

& git -C $core archive --format=zip -o $coreArchive HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not archive tgwsproxy-core source.' }

& git -C $root archive --format=zip -o $overlayArchive HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not archive Telegram-WSP overlay source.' }

$projectCommit = (& git -C $root rev-parse HEAD).Trim()
$manifest = [ordered]@{
    project = 'Telegram-WSP'
    projectCommit = $projectCommit
    telegramRepository = [string]$upstream.repository
    telegramCommit = [string]$upstream.pinnedCommit
    telegramVersion = [string]$upstream.telegramVersion
    telegramBuild = [int]$upstream.telegramBuild
    coreRepository = [string]$coreConfig.repository
    coreCommit = [string]$coreConfig.pinnedCommit
    license = 'GPL-3.0-only'
    reproduction = './scripts/prepare-integration.ps1 -Force'
    components = @(
        [System.IO.Path]::GetFileName($telegramArchive),
        [System.IO.Path]::GetFileName($coreArchive),
        [System.IO.Path]::GetFileName($overlayArchive)
    )
}

$manifestPath = Join-Path $output 'SOURCE_MANIFEST.json'
[System.IO.File]::WriteAllText(
    $manifestPath,
    ($manifest | ConvertTo-Json -Depth 4) + [Environment]::NewLine
)

Write-Host "Corresponding Source assets ready: $output"
Get-ChildItem $output -File | ForEach-Object { Write-Host " - $($_.Name)" }
