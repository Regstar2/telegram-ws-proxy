[CmdletBinding()]
param(
    [string]$CorePath = '.work/tgwsproxy-core',
    [switch]$WithTests,
    [switch]$Offline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$coreFull = [System.IO.Path]::GetFullPath((Join-Path $root $CorePath))
if (-not (Test-Path (Join-Path $coreFull 'settings.gradle.kts'))) { throw "Invalid core checkout: $coreFull" }

$gradleExecutable = $env:TGWSP_CORE_GRADLE
if ([string]::IsNullOrWhiteSpace($gradleExecutable)) {
    $gradle = Get-Command gradle -ErrorAction SilentlyContinue
    if (-not $gradle) { throw 'Gradle was not found in PATH.' }
    $gradleExecutable = $gradle.Source
} elseif (-not (Test-Path $gradleExecutable)) {
    throw "TGWSP_CORE_GRADLE does not exist: $gradleExecutable"
}

$tasks = @()
if ($WithTests) {
    $tasks += ':core:testDebugUnitTest'
}
$tasks += ':core:assembleRelease'

$gradleArgs = @($tasks) + @('--daemon', '--build-cache', '--parallel')
if ($Offline) {
    $gradleArgs += '--offline'
}

Write-Host "Building tgwsproxy-core (tests=$WithTests, offline=$Offline)"
& $gradleExecutable -p $coreFull @gradleArgs
if ($LASTEXITCODE -ne 0) { throw "tgwsproxy-core Gradle build failed with exit code $LASTEXITCODE" }

$artifact = Join-Path $coreFull 'core/build/outputs/aar/core-release.aar'
if (-not (Test-Path $artifact)) { throw "Expected core AAR was not produced: $artifact" }
Write-Host "Core AAR: $artifact"
