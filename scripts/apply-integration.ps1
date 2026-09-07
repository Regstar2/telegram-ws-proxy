[CmdletBinding()]
param(
    [string]$TelegramPath = '.work/telegram',
    [string]$CoreAar = '.work/tgwsproxy-core/core/build/outputs/aar/core-release.aar'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$telegram = [System.IO.Path]::GetFullPath((Join-Path $root $TelegramPath))
$coreAarPath = [System.IO.Path]::GetFullPath((Join-Path $root $CoreAar))
$upstream = Get-Content (Join-Path $root 'config/upstream.json') -Raw | ConvertFrom-Json

if (-not (Test-Path (Join-Path $telegram '.git'))) { throw "Telegram checkout not found: $telegram" }
if (-not (Test-Path $coreAarPath)) { throw "Core AAR not found: $coreAarPath" }

$actual = (& git -C $telegram rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Failed to read Telegram HEAD.' }
if ($actual -ne [string]$upstream.pinnedCommit) { throw "Telegram HEAD '$actual' does not match pinned upstream '$($upstream.pinnedCommit)'." }

$generatedDir = Join-Path $telegram '.tgwsproxy'
New-Item -ItemType Directory -Path $generatedDir -Force | Out-Null
Copy-Item -Force $coreAarPath (Join-Path $generatedDir 'tgwsproxy-core.aar')

$excludePath = Join-Path $telegram '.git/info/exclude'
$exclude = if (Test-Path $excludePath) { Get-Content $excludePath -Raw } else { '' }
if ($exclude -notmatch '(?m)^\.tgwsproxy/$') {
    Add-Content -Path $excludePath -Value '.tgwsproxy/'
}

$buildPath = Join-Path $telegram 'TMessagesProj_AppStandalone/build.gradle'
$build = Get-Content $buildPath -Raw
$dependencyMarker = "    implementation project(':TMessagesProj')"
$dependencyBlock = @"
    implementation project(':TMessagesProj')
    implementation files('../.tgwsproxy/tgwsproxy-core.aar')
    implementation 'net.java.dev.jna:jna:5.14.0@aar'
    implementation 'org.jetbrains.kotlin:kotlin-stdlib:1.9.22'
"@.TrimEnd()
if ($build -notmatch [regex]::Escape("tgwsproxy-core.aar")) {
    $count = ([regex]::Matches($build, [regex]::Escape($dependencyMarker))).Count
    if ($count -ne 1) { throw "Gradle dependency anchor count is $count; expected 1." }
    $build = $build.Replace($dependencyMarker, $dependencyBlock)
    Set-Content -Path $buildPath -Value $build -NoNewline
}

$coreBuildPath = Join-Path $telegram 'TMessagesProj/build.gradle'
$coreBuild = Get-Content $coreBuildPath -Raw
$apiGradleMarker = @'
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 36
'@.TrimEnd()
$apiGradleBlock = @'
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 36

        def telegramApiId = System.getenv('TELEGRAM_API_ID') ?: getProps('TELEGRAM_API_ID')
        def telegramApiHash = System.getenv('TELEGRAM_API_HASH') ?: getProps('TELEGRAM_API_HASH')
        if (!telegramApiId) {
            telegramApiId = '4'
        }
        if (!telegramApiHash) {
            telegramApiHash = '014b35b6184100b085b0d0572f9b5103'
        }
        if (!(telegramApiId ==~ /\d+/)) {
            throw new GradleException('TELEGRAM_API_ID must contain decimal digits only.')
        }
        if (!(telegramApiHash ==~ /[0-9a-fA-F]{32}/)) {
            throw new GradleException('TELEGRAM_API_HASH must contain exactly 32 hexadecimal characters.')
        }
        buildConfigField "int", "TELEGRAM_API_ID", telegramApiId
        buildConfigField "String", "TELEGRAM_API_HASH", "\"${telegramApiHash}\""
'@.TrimEnd()
if ($coreBuild -notmatch [regex]::Escape('TELEGRAM_API_ID')) {
    $count = ([regex]::Matches($coreBuild, [regex]::Escape($apiGradleMarker))).Count
    if ($count -ne 1) { throw "Telegram API Gradle anchor count is $count; expected 1." }
    $coreBuild = $coreBuild.Replace($apiGradleMarker, $apiGradleBlock)
    Set-Content -Path $coreBuildPath -Value $coreBuild -NoNewline
}

$buildVarsPath = Join-Path $telegram 'TMessagesProj/src/main/java/org/telegram/messenger/BuildVars.java'
$buildVars = Get-Content $buildVarsPath -Raw
$apiVarsMarker = @'
    public static int APP_ID = 4;
    public static String APP_HASH = "014b35b6184100b085b0d0572f9b5103";
'@.TrimEnd()
$apiVarsBlock = @'
    public static int APP_ID = BuildConfig.TELEGRAM_API_ID;
    public static String APP_HASH = BuildConfig.TELEGRAM_API_HASH;
'@.TrimEnd()
if ($buildVars -notmatch [regex]::Escape('BuildConfig.TELEGRAM_API_ID')) {
    $count = ([regex]::Matches($buildVars, [regex]::Escape($apiVarsMarker))).Count
    if ($count -ne 1) { throw "Telegram BuildVars API anchor count is $count; expected 1." }
    $buildVars = $buildVars.Replace($apiVarsMarker, $apiVarsBlock)
    Set-Content -Path $buildVarsPath -Value $buildVars -NoNewline
}

$loaderPath = Join-Path $telegram 'TMessagesProj_AppStandalone/src/main/java/org/telegram/messenger/ApplicationLoaderImpl.java'
$loader = Get-Content $loaderPath -Raw
$classMarker = 'public class ApplicationLoaderImpl extends ApplicationLoader {'
$classBlock = @"
public class ApplicationLoaderImpl extends ApplicationLoader {
    @Override
    public void onCreate() {
        super.onCreate();
        TgWsProxyBootstrap.start(this);
    }
"@.TrimEnd()
if ($loader -notmatch [regex]::Escape('TgWsProxyBootstrap.start(this);')) {
    $count = ([regex]::Matches($loader, [regex]::Escape($classMarker))).Count
    if ($count -ne 1) { throw "ApplicationLoaderImpl anchor count is $count; expected 1." }
    $loader = $loader.Replace($classMarker, $classBlock)
    Set-Content -Path $loaderPath -Value $loader -NoNewline
}

$overlay = Join-Path $root 'integration/telegram/TgWsProxyBootstrap.java'
$bootstrapPath = Join-Path $telegram 'TMessagesProj_AppStandalone/src/main/java/org/telegram/messenger/TgWsProxyBootstrap.java'
Copy-Item -Force $overlay $bootstrapPath

& git -C $telegram diff --check
if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed after applying integration.' }

$tgnet = @(& git -C $telegram status --porcelain -- 'TMessagesProj/jni/tgnet/**')
if ($tgnet.Count -gt 0) { throw "Integration modified forbidden tgnet paths: $($tgnet -join ', ')" }

$changed = @(
    & git -C $telegram status --porcelain |
        ForEach-Object { if ($_.Length -ge 4) { $_.Substring(3).Trim('"') } } |
        Where-Object { $_ -and -not $_.StartsWith('.tgwsproxy/') }
)
$expected = @(
    'TMessagesProj/build.gradle',
    'TMessagesProj/src/main/java/org/telegram/messenger/BuildVars.java',
    'TMessagesProj_AppStandalone/build.gradle',
    'TMessagesProj_AppStandalone/src/main/java/org/telegram/messenger/ApplicationLoaderImpl.java',
    'TMessagesProj_AppStandalone/src/main/java/org/telegram/messenger/TgWsProxyBootstrap.java'
)
foreach ($path in $expected) {
    if ($changed -notcontains $path) { throw "Expected integration change is missing: $path" }
}
if ($changed.Count -gt 5) { throw "Integration diff budget exceeded: $($changed.Count) upstream files." }

Write-Host "Integration applied to Telegram $actual"
Write-Host "Upstream source diff: $($changed.Count) files"
$changed | ForEach-Object { Write-Host " - $_" }
