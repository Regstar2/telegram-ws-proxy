[CmdletBinding()]
param(
    [string]$Destination = '.work/telegram',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$configPath = Join-Path $root 'config/upstream.json'
if (-not (Test-Path $configPath)) {
    throw "Upstream config was not found: $configPath"
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$repository = [string]$config.repository
$commit = [string]$config.pinnedCommit

if ([string]::IsNullOrWhiteSpace($repository)) {
    throw 'config/upstream.json: repository is empty.'
}

if ($commit -notmatch '^[0-9a-f]{40}$') {
    throw "config/upstream.json: invalid pinnedCommit '$commit'."
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git was not found in PATH.'
}

$destinationPath = [System.IO.Path]::GetFullPath((Join-Path $root $Destination))
$gitDir = Join-Path $destinationPath '.git'
$existingRepo = Test-Path $gitDir

if (-not (Test-Path $destinationPath)) {
    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
    & git -C $destinationPath init
    if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }

    & git -C $destinationPath remote add origin $repository
    if ($LASTEXITCODE -ne 0) { throw 'git remote add origin failed.' }
} elseif (-not (Test-Path $gitDir)) {
    throw "Destination exists but is not a Git repository: $destinationPath"
} else {
    $status = (& git -C $destinationPath status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw 'git status failed.' }

    if ($status -and -not $Force) {
        throw "Upstream worktree has local changes. Re-run with -Force only if those changes may be discarded: $destinationPath"
    }

    $origin = (& git -C $destinationPath remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0) {
        & git -C $destinationPath remote add origin $repository
        if ($LASTEXITCODE -ne 0) { throw 'git remote add origin failed.' }
    } elseif ($origin.Trim() -ne $repository) {
        throw "Unexpected origin '$origin'. Expected '$repository'."
    }
}

if ($Force -and $existingRepo) {
    & git -C $destinationPath reset --hard
    if ($LASTEXITCODE -ne 0) { throw 'git reset --hard failed.' }
    & git -C $destinationPath clean -fd
    if ($LASTEXITCODE -ne 0) { throw 'git clean failed.' }
}

Write-Host "Fetching Telegram commit $commit..."
& git -C $destinationPath fetch --depth 1 origin $commit
if ($LASTEXITCODE -ne 0) { throw "Failed to fetch Telegram commit $commit." }

& git -C $destinationPath checkout --detach FETCH_HEAD
if ($LASTEXITCODE -ne 0) { throw 'Failed to checkout fetched Telegram commit.' }

& (Join-Path $PSScriptRoot 'ensure-telegram-theme-assets-lf.ps1') -TelegramPath $destinationPath

$actual = (& git -C $destinationPath rev-parse HEAD).Trim()
if ($actual -ne $commit) {
    throw "Unexpected HEAD '$actual'. Expected '$commit'."
}

Write-Host "Telegram upstream ready: $destinationPath"
Write-Host "HEAD: $actual"
