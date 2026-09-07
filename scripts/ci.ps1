[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$required = @(
    'README.md',
    'LICENSE',
    'NOTICE.md',
    '.gitignore',
    'config/upstream.json',
    'config/core.json',
    'docs/architecture.md',
    'docs/licensing.md',
    'docs/product/mvp-scope.md',
    'integration/README.md',
    'integration/telegram/TgWsProxyBootstrap.java',
    'patches/README.md',
    'scripts/fetch-upstream.ps1',
    'scripts/fetch-core.ps1',
    'scripts/build-core.ps1',
    'scripts/apply-integration.ps1',
    'scripts/prepare-integration.ps1'
)

foreach ($path in $required) {
    if (-not (Test-Path (Join-Path $root $path))) {
        throw "Required project file is missing: $path"
    }
}

$licenseText = Get-Content (Join-Path $root 'LICENSE') -Raw
if ($licenseText -notmatch 'GNU GENERAL PUBLIC LICENSE\s+Version 3') {
    throw 'Project LICENSE is expected to contain GNU GPL version 3.'
}

$licensingText = Get-Content (Join-Path $root 'docs/licensing.md') -Raw
if ($licensingText -notmatch 'GPL-3\.0-only') {
    throw 'docs/licensing.md does not record the GPL-3.0-only project policy.'
}
if ($licensingText -notmatch 'Corresponding Source') {
    throw 'docs/licensing.md does not record the Corresponding Source release gate.'
}

$upstream = Get-Content (Join-Path $root 'config/upstream.json') -Raw | ConvertFrom-Json
$core = Get-Content (Join-Path $root 'config/core.json') -Raw | ConvertFrom-Json
$telegramCommit = [string]$upstream.pinnedCommit
$coreCommit = [string]$core.pinnedCommit

if ([string]::IsNullOrWhiteSpace([string]$upstream.repository)) {
    throw 'Upstream repository is empty.'
}
if ($telegramCommit -notmatch '^[0-9a-f]{40}$') {
    throw "Invalid pinned Telegram commit: '$telegramCommit'"
}
if ([string]::IsNullOrWhiteSpace([string]$core.repository)) {
    throw 'Core repository is empty.'
}
if ($coreCommit -notmatch '^[0-9a-f]{40}$') {
    throw "Invalid pinned core commit: '$coreCommit'"
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    $forbiddenTracked = @(
        (& git ls-files 'AGENTS.md' '.project-rules/**' '.work/**' 'dist/**') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
    if ($forbiddenTracked.Count -gt 0) {
        throw "Forbidden private/generated files are tracked: $($forbiddenTracked -join ', ')"
    }
}

$patchFiles = @(Get-ChildItem (Join-Path $root 'patches') -File -Filter '*.patch' -ErrorAction SilentlyContinue)
foreach ($patch in $patchFiles) {
    $patchContent = Get-Content $patch.FullName -Raw
    if ($patchContent -match 'TMessagesProj/jni/tgnet/') {
        throw "Patch modifies forbidden tgnet path: $($patch.Name)"
    }
}

$telegramWorktree = Join-Path $root '.work/telegram'
if (Test-Path (Join-Path $telegramWorktree '.git')) {
    $actual = (& git -C $telegramWorktree rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Failed to read Telegram worktree HEAD.' }
    if ($actual -ne $telegramCommit) {
        throw "Local Telegram checkout is not pinned: $actual != $telegramCommit"
    }

    $tgnetChanges = @(& git -C $telegramWorktree status --porcelain -- 'TMessagesProj/jni/tgnet/')
    if ($tgnetChanges.Count -gt 0) {
        throw "Prepared integration modified forbidden tgnet paths: $($tgnetChanges -join ', ')"
    }

    $changes = @(
        & git -C $telegramWorktree status --porcelain |
            ForEach-Object { if ($_.Length -ge 4) { $_.Substring(3).Trim('"') } } |
            Where-Object { $_ -and -not $_.StartsWith('.tgwsproxy/') }
    )
    if ($changes.Count -gt 5) {
        throw "Prepared integration exceeds the 5-file source diff budget: $($changes.Count)"
    }
}

$coreWorktree = Join-Path $root '.work/tgwsproxy-core'
if (Test-Path (Join-Path $coreWorktree '.git')) {
    $actualCore = (& git -C $coreWorktree rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Failed to read core worktree HEAD.' }
    if ($actualCore -ne $coreCommit) {
        throw "Local core checkout is not pinned: $actualCore != $coreCommit"
    }
}

Write-Host 'Repository checks passed.'
Write-Host "Pinned Telegram commit: $telegramCommit"
Write-Host "Pinned tgwsproxy-core commit: $coreCommit"
