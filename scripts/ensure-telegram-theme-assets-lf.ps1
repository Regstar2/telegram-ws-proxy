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

# Remove the obsolete local attribute rule from the earlier in-place approach.
$attributesPath = Join-Path $gitDir 'info/attributes'
if (Test-Path $attributesPath) {
    $attributeLines = @([System.IO.File]::ReadAllLines($attributesPath))
    $filteredAttributeLines = @(
        $attributeLines | Where-Object { $_.Trim() -ne '*.attheme text eol=lf' }
    )
    if ($filteredAttributeLines.Count -ne $attributeLines.Count) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($attributesPath, $filteredAttributeLines, $utf8NoBom)
    }
}

$themeAssets = @(
    & git -C $telegram ls-files -- ':(glob)TMessagesProj/src/main/assets/*.attheme' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to enumerate Telegram built-in .attheme assets.'
}
if ($themeAssets.Count -eq 0) {
    throw 'Telegram checkout contains no tracked built-in .attheme assets.'
}

# Clean up only the line-ending-only modifications produced by the previous helper.
foreach ($asset in $themeAssets) {
    $statusLine = @(& git -C $telegram status --porcelain -- $asset)
    if ($statusLine.Count -eq 0) {
        continue
    }

    & git -C $telegram diff --quiet --ignore-space-at-eol -- $asset
    $lineEndingOnly = $LASTEXITCODE -eq 0
    if (-not $lineEndingOnly) {
        throw "Refusing to overwrite a semantic local change in Telegram theme asset: $asset"
    }

    & git -C $telegram checkout HEAD -- $asset
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to restore tracked Telegram theme asset: $asset"
    }
}

$remainingTrackedChanges = @(
    & git -C $telegram status --porcelain -- $themeAssets |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to verify tracked Telegram theme asset status.'
}
if ($remainingTrackedChanges.Count -gt 0) {
    throw "Tracked Telegram theme assets must remain untouched: $($remainingTrackedChanges -join ', ')"
}

function Convert-CrlfBytesToLf([byte[]]$Bytes) {
    $stream = New-Object System.IO.MemoryStream
    try {
        for ($index = 0; $index -lt $Bytes.Length; $index++) {
            $current = $Bytes[$index]
            if (
                $current -eq [byte]13 -and
                ($index + 1) -lt $Bytes.Length -and
                $Bytes[$index + 1] -eq [byte]10
            ) {
                continue
            }
            $stream.WriteByte($current)
        }
        return $stream.ToArray()
    }
    finally {
        $stream.Dispose()
    }
}

$generatedRoot = Join-Path $telegram '.tgwsproxy/theme-assets'
if (Test-Path $generatedRoot) {
    Remove-Item -Recurse -Force $generatedRoot
}
New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null

$normalizedCount = 0
foreach ($asset in $themeAssets) {
    $sourcePath = Join-Path $telegram ($asset -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
    $generatedBytes = Convert-CrlfBytesToLf $sourceBytes

    if ($generatedBytes.Length -ne $sourceBytes.Length) {
        $normalizedCount++
    }

    if ($generatedBytes -contains [byte]13) {
        throw "Generated Telegram theme asset still contains CR bytes: $asset"
    }

    $targetPath = Join-Path $generatedRoot ([System.IO.Path]::GetFileName($asset))
    [System.IO.File]::WriteAllBytes($targetPath, $generatedBytes)
}

$generatedAssets = @(Get-ChildItem $generatedRoot -File -Filter '*.attheme')
if ($generatedAssets.Count -ne $themeAssets.Count) {
    throw "Generated Telegram theme overlay count mismatch: $($generatedAssets.Count) != $($themeAssets.Count)"
}

Write-Host "Prepared LF Telegram theme asset overlay: $($generatedAssets.Count) file(s)"
Write-Host "Source assets requiring CRLF normalization: $normalizedCount"
Write-Host "Generated overlay: $generatedRoot"
