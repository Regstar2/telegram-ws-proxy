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

function Convert-CrlfToLf([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $stream = New-Object System.IO.MemoryStream

    try {
        for ($index = 0; $index -lt $bytes.Length; $index++) {
            $current = $bytes[$index]

            if (
                $current -eq [byte]13 -and
                ($index + 1) -lt $bytes.Length -and
                $bytes[$index + 1] -eq [byte]10
            ) {
                continue
            }

            $stream.WriteByte($current)
        }

        [System.IO.File]::WriteAllBytes($Path, $stream.ToArray())
    }
    finally {
        $stream.Dispose()
    }
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
        $assetPath = Join-Path $telegram ($asset -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        Convert-CrlfToLf $assetPath
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
    throw "Telegram .attheme assets still contain CR bytes after CRLF normalization: $($invalidAssets -join ', ')"
}

$unexpectedChanges = @(
    & git -C $telegram status --porcelain -- $themeAssets |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to verify Telegram theme asset Git status.'
}
if ($unexpectedChanges.Count -gt 0) {
    throw "LF normalization changed tracked Telegram theme content: $($unexpectedChanges -join ', ')"
}

Write-Host "Telegram theme assets use LF line endings: $($themeAssets.Count) file(s)"
