[CmdletBinding()]
param(
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root 'config/upstream.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json

$repository = [string]$config.repository
$branch = [string]$config.branch
if ([string]::IsNullOrWhiteSpace($repository)) { throw 'Upstream repository is empty.' }
if ([string]::IsNullOrWhiteSpace($branch)) { throw 'Upstream branch is empty.' }

$remoteLine = (& git ls-remote $repository "refs/heads/$branch" | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteLine)) {
    throw "Could not resolve upstream branch $branch."
}
$latestCommit = ($remoteLine -split '\s+')[0].Trim()
if ($latestCommit -notmatch '^[0-9a-f]{40}$') {
    throw "Invalid upstream commit returned by git ls-remote: $latestCommit"
}

if ($repository -notmatch '^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$') {
    throw "Only public github.com upstream repositories are supported: $repository"
}
$owner = $Matches[1]
$name = $Matches[2]
$propertiesUri = "https://raw.githubusercontent.com/$owner/$name/$latestCommit/gradle.properties"
$propertiesText = (Invoke-WebRequest -Uri $propertiesUri -UseBasicParsing).Content

function Get-PropertyValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $match = [regex]::Match($propertiesText, "(?m)^$([regex]::Escape($Name))=(.+)$")
    if (-not $match.Success) {
        throw "Upstream gradle.properties does not contain $Name."
    }
    return $match.Groups[1].Value.Trim()
}

$latestVersion = Get-PropertyValue 'APP_VERSION_NAME'
$latestBuildText = Get-PropertyValue 'APP_VERSION_CODE'
if ($latestBuildText -notmatch '^\d+$') {
    throw "Invalid upstream APP_VERSION_CODE: $latestBuildText"
}
$latestBuild = [int]$latestBuildText

$currentCommit = [string]$config.pinnedCommit
$currentVersion = [string]$config.telegramVersion
$currentBuild = [int]$config.telegramBuild

$commitChanged = $latestCommit -ne $currentCommit
$versionChanged = $latestVersion -ne $currentVersion -or $latestBuild -ne $currentBuild
$updateAvailable = $commitChanged -and $versionChanged
$reason = if (-not $commitChanged) {
    'already-current'
} elseif (-not $versionChanged) {
    'master-ahead-without-version-bump'
} else {
    'new-telegram-version'
}

if ($Apply -and $updateAvailable) {
    $updated = [ordered]@{
        repository = $repository
        branch = $branch
        pinnedCommit = $latestCommit
        telegramVersion = $latestVersion
        telegramBuild = $latestBuild
        pinnedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    }
    [System.IO.File]::WriteAllText(
        $configPath,
        ($updated | ConvertTo-Json) + [Environment]::NewLine
    )
}

$result = [ordered]@{
    updateAvailable = $updateAvailable
    applied = [bool]($Apply -and $updateAvailable)
    reason = $reason
    currentCommit = $currentCommit
    currentVersion = $currentVersion
    currentBuild = $currentBuild
    latestCommit = $latestCommit
    latestVersion = $latestVersion
    latestBuild = $latestBuild
}
$result | ConvertTo-Json -Compress
