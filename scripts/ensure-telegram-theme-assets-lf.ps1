[CmdletBinding()]
param(
    [string]$TelegramPath = '.work/telegram'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$telegram = if ([System.IO.Path]::IsPathRooted($TelegramPath)) {
    [System.IO.Path]::GetFullPath($TelegramPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $root $TelegramPath))
}
$gitDir = Join-Path $telegram '.git'

if (-not (Test-Path $gitDir)) {
    throw "Telegram checkout not found: $telegram"
}

$attributeRule = '*.attheme text eol=lf'
$attributesPath = Join-Path $gitDir 'info/attributes'
$attributesDir = Split-Path -Parent $attributesPath
New-Item -ItemType Directory -Path $attributesDir -Force | Out-Null

$attributesText = if (Test-Path $attributesPath) {
    [System.IO.File]::ReadAllText($attributesPath)
} else {
    ''
}

if ($attributesText -notmatch '(?m)^\*\.attheme text eol=lf\s*$') {
    if ($attributesText.Length -gt 0 -and -not $attributesText.EndsWith("`n")) {
        $attributesText += "`n"
    }
    $attributesText += $attributeRule + "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($attributesPath, $attributesText, $utf8NoBom)
}

$themeAssets = @(
    & git -C $telegram ls-files -- ':(glob)**/*.attheme' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to enumerate Telegram .attheme assets.'
}
if ($themeAssets.Count -eq 0) {
    throw 'Telegram checkout contains no tracked .attheme assets.'
}

function Test-ContainsCarriageReturn([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return $bytes -contains [byte]13
}

$crlfAssets = @(
    foreach ($asset in $themeAssets) {
        $assetPath = Join-Path $telegram ($asset -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (Test-ContainsCarriageReturn $assetPath) {
            $asset
        }
    }
)

if ($crlfAssets.Count -gt 0) {
    Write-Host "Normalizing Telegram theme assets to LF: $($crlfAssets.Count) file(s)"
    foreach ($asset in $crlfAssets) {
        & git -C $telegram checkout HEAD -- $asset
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to restore LF line endings for Telegram theme asset: $asset"
        }
    }
}

$invalidAssets = @(
    foreach ($asset in $themeAssets) {
        $assetPath = Join-Path $telegram ($asset -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        if (Test-ContainsCarriageReturn $assetPath) {
            $asset
        }
    }
)

if ($invalidAssets.Count -gt 0) {
    throw "Telegram .attheme assets still contain CR bytes: $($invalidAssets -join ', ')"
}

Write-Host "Telegram theme assets use LF line endings: $($themeAssets.Count) file(s)"
