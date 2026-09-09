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
        throw "Unexpected checkout HEAD at ${RepositoryPath}: $actual != $Expected"
    }
}

function Get-SubmoduleCommit {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string]$SubmodulePath
    )

    $treeLine = (& git -C $RepositoryPath ls-tree HEAD -- $SubmodulePath).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($treeLine)) {
        throw "Could not resolve Telegram submodule gitlink: $SubmodulePath"
    }

    $parts = @($treeLine -split '\s+')
    if ($parts.Count -lt 3 -or $parts[0] -ne '160000') {
        throw "Unexpected Telegram submodule gitlink metadata: $treeLine"
    }

    $commit = [string]$parts[2]
    if ($commit -notmatch '^[0-9a-f]{40}$') {
        throw "Invalid Telegram submodule commit for ${SubmodulePath}: $commit"
    }
    return $commit
}

Assert-Head -RepositoryPath $telegram -Expected ([string]$upstream.pinnedCommit)
Assert-Head -RepositoryPath $core -Expected ([string]$coreConfig.pinnedCommit)

$submoduleConfigLines = @(
    & git -C $telegram config -f .gitmodules --get-regexp '^submodule\..*\.path$'
)
if ($LASTEXITCODE -ne 0) {
    throw 'Could not enumerate Telegram submodules for Corresponding Source.'
}

$submodulePaths = @(
    $submoduleConfigLines |
        ForEach-Object {
            $parts = @($_ -split '\s+', 2)
            if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[1])) {
                throw "Unexpected Telegram submodule path metadata: $_"
            }
            $parts[1].Trim()
        }
)

if ($submodulePaths.Count -eq 0) {
    throw 'Pinned Telegram checkout declares no submodules.'
}

$telegramArchive = Join-Path $output ("Telegram-upstream-source-{0}-{1}.zip" -f $upstream.telegramVersion, $upstream.telegramBuild)
$coreArchive = Join-Path $output ("tgwsproxy-core-source-{0}.zip" -f ([string]$coreConfig.pinnedCommit).Substring(0, 12))
$overlayArchive = Join-Path $output ("Telegram-WSP-overlay-source-{0}.zip" -f $upstream.telegramVersion)

& git -C $telegram archive --format=zip -o $telegramArchive HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not archive Telegram upstream source.' }

$telegramSubmodules = @()
$submoduleArchives = @()
$jlatexmathCommit = $null

foreach ($submodulePath in $submodulePaths) {
    $submoduleCommit = Get-SubmoduleCommit -RepositoryPath $telegram -SubmodulePath $submodulePath
    $submoduleRepositoryPath = Join-Path $telegram $submodulePath
    Assert-Head -RepositoryPath $submoduleRepositoryPath -Expected $submoduleCommit

    $leafName = Split-Path $submodulePath -Leaf
    $safeName = $leafName -replace '[^A-Za-z0-9._-]', '-'
    $archiveName = if ($submodulePath -eq 'TMessagesProj/lib/jlatexmath') {
        "jlatexmath-source-$($submoduleCommit.Substring(0, 12)).zip"
    } else {
        "telegram-submodule-$safeName-source-$($submoduleCommit.Substring(0, 12)).zip"
    }
    $archivePath = Join-Path $output $archiveName

    & git -C $submoduleRepositoryPath archive --format=zip -o $archivePath HEAD
    if ($LASTEXITCODE -ne 0) {
        throw "Could not archive Telegram submodule source: $submodulePath"
    }

    if ($submodulePath -eq 'TMessagesProj/lib/jlatexmath') {
        $jlatexmathCommit = $submoduleCommit
    }

    $submoduleArchives += $archivePath
    $telegramSubmodules += [ordered]@{
        path = $submodulePath
        commit = $submoduleCommit
        archive = $archiveName
    }
}

if ([string]::IsNullOrWhiteSpace($jlatexmathCommit)) {
    throw 'Telegram jlatexmath submodule was not present in the pinned .gitmodules.'
}

& git -C $core archive --format=zip -o $coreArchive HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not archive tgwsproxy-core source.' }

& git -C $root archive --format=zip -o $overlayArchive HEAD
if ($LASTEXITCODE -ne 0) { throw 'Could not archive Telegram-WSP overlay source.' }

$projectCommit = (& git -C $root rev-parse HEAD).Trim()
$componentNames = @(
    [System.IO.Path]::GetFileName($telegramArchive)
)
$componentNames += @($submoduleArchives | ForEach-Object { [System.IO.Path]::GetFileName($_) })
$componentNames += @(
    [System.IO.Path]::GetFileName($coreArchive),
    [System.IO.Path]::GetFileName($overlayArchive)
)

$manifest = [ordered]@{
    project = 'Telegram-WSP'
    projectCommit = $projectCommit
    telegramRepository = [string]$upstream.repository
    telegramCommit = [string]$upstream.pinnedCommit
    telegramVersion = [string]$upstream.telegramVersion
    telegramBuild = [int]$upstream.telegramBuild
    jlatexmathCommit = $jlatexmathCommit
    telegramSubmodules = $telegramSubmodules
    coreRepository = [string]$coreConfig.repository
    coreCommit = [string]$coreConfig.pinnedCommit
    license = 'GPL-3.0-only'
    reproduction = './scripts/prepare-integration.ps1 -Force'
    components = $componentNames
}

$manifestPath = Join-Path $output 'SOURCE_MANIFEST.json'
[System.IO.File]::WriteAllText(
    $manifestPath,
    ($manifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine
)

Write-Host "Corresponding Source assets ready: $output"
Get-ChildItem $output -File | ForEach-Object { Write-Host " - $($_.Name)" }
