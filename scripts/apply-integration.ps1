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

& (Join-Path $PSScriptRoot 'ensure-telegram-theme-assets-lf.ps1') -TelegramPath $telegram
$themeAssetsGenerated = Join-Path $generatedDir 'theme-assets'

$brandingSource = Join-Path $root 'integration/branding'
$brandingResSource = Join-Path $brandingSource 'res'
$brandingGenerated = Join-Path $generatedDir 'branding'
$brandingResGenerated = Join-Path $brandingGenerated 'res'
$brandingManifestSource = Join-Path $telegram 'TMessagesProj/config/release/AndroidManifest_standalone.xml'
$brandingManifestGenerated = Join-Path $brandingGenerated 'AndroidManifest_standalone.xml'

if (-not (Test-Path $brandingResSource)) { throw "Branding resources not found: $brandingResSource" }
if (-not (Test-Path $brandingManifestSource)) { throw "Standalone manifest not found: $brandingManifestSource" }

if (Test-Path $brandingGenerated) {
    Remove-Item -Recurse -Force $brandingGenerated
}
New-Item -ItemType Directory -Path $brandingResGenerated -Force | Out-Null
Copy-Item -Path (Join-Path $brandingResSource '*') -Destination $brandingResGenerated -Recurse -Force

$brandingManifest = Get-Content $brandingManifestSource -Raw
$iconMarker = '        android:icon="@mipmap/ic_launcher_sa"'
$roundIconMarker = '        android:roundIcon="@mipmap/ic_launcher_sa"'
$labelMarker = '        android:label="@string/AppName"'
$managedIcon = '        android:icon="@mipmap/tgwsproxy_launcher"'
$managedRoundIcon = '        android:roundIcon="@mipmap/tgwsproxy_launcher"'
$managedLabel = '        android:label="Telegram-WSP"'

$iconCount = ([regex]::Matches($brandingManifest, [regex]::Escape($iconMarker))).Count
if ($iconCount -ne 1) { throw "Standalone launcher icon anchor count is $iconCount; expected 1." }
$roundIconCount = ([regex]::Matches($brandingManifest, [regex]::Escape($roundIconMarker))).Count
if ($roundIconCount -ne 1) { throw "Standalone round launcher icon anchor count is $roundIconCount; expected 1." }
$labelCount = ([regex]::Matches($brandingManifest, [regex]::Escape($labelMarker))).Count
if ($labelCount -ne 1) { throw "Standalone application label anchor count is $labelCount; expected 1." }

$brandingManifest = $brandingManifest.Replace($iconMarker, $managedIcon)
$brandingManifest = $brandingManifest.Replace($roundIconMarker, $managedRoundIcon)
$brandingManifest = $brandingManifest.Replace($labelMarker, $managedLabel)
Set-Content -Path $brandingManifestGenerated -Value $brandingManifest -NoNewline

$buildPath = Join-Path $telegram 'TMessagesProj_AppStandalone/build.gradle'
$build = Get-Content $buildPath -Raw

$dependencyMarker = "    implementation project(':TMessagesProj')"
$dependencyBlock = @"
    implementation project(':TMessagesProj')
    implementation files('../.tgwsproxy/tgwsproxy-core.aar')
    implementation 'net.java.dev.jna:jna:5.14.0@aar'
    implementation 'org.jetbrains.kotlin:kotlin-stdlib:1.9.22'
"@.TrimEnd()
if ($build -notmatch [regex]::Escape('tgwsproxy-core.aar')) {
    $count = ([regex]::Matches($build, [regex]::Escape($dependencyMarker))).Count
    if ($count -ne 1) { throw "Gradle dependency anchor count is $count; expected 1." }
    $build = $build.Replace($dependencyMarker, $dependencyBlock)
}

$appStandaloneMarker = @'
        standalone {
            matchingFallbacks = ['release']
            debuggable false
            jniDebuggable false
            signingConfig signingConfigs.release
            applicationIdSuffix ".web"
            minifyEnabled true
            multiDexEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), '../TMessagesProj/proguard-rules.pro'
            ndk.debugSymbolLevel = 'FULL'
        }
'@.TrimEnd()
$appPrototypeBlock = @'
        standalone {
            matchingFallbacks = ['release']
            debuggable false
            jniDebuggable false
            signingConfig signingConfigs.release
            applicationIdSuffix ".web"
            minifyEnabled true
            multiDexEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), '../TMessagesProj/proguard-rules.pro'
            ndk.debugSymbolLevel = 'FULL'
        }
        prototype {
            matchingFallbacks = ['release']
            debuggable true
            jniDebuggable false
            signingConfig signingConfigs.debug
            applicationIdSuffix ".web"
            minifyEnabled false
            multiDexEnabled true
            ndk.debugSymbolLevel = 'FULL'
        }
'@.TrimEnd()
if ($build -notmatch '(?m)^        prototype \{') {
    $count = ([regex]::Matches($build, [regex]::Escape($appStandaloneMarker))).Count
    if ($count -ne 1) { throw "Telegram app standalone build-type anchor count is $count; expected 1." }
    $build = $build.Replace($appStandaloneMarker, $appPrototypeBlock)
}

$appSourceSetMarker = @'
    sourceSets.standalone {
        manifest.srcFile '../TMessagesProj/config/release/AndroidManifest_standalone.xml'
    }
'@.TrimEnd()
$appSourceSetPrototypeBlock = @'
    sourceSets.standalone {
        manifest.srcFile '../TMessagesProj/config/release/AndroidManifest_standalone.xml'
    }
    sourceSets.prototype {
        manifest.srcFile '../TMessagesProj/config/release/AndroidManifest_standalone.xml'
    }
'@.TrimEnd()
$appSourceSetBrandingBlock = @'
    sourceSets.standalone {
        manifest.srcFile '../.tgwsproxy/branding/AndroidManifest_standalone.xml'
        res.srcDir '../.tgwsproxy/branding/res'
    }
    sourceSets.prototype {
        manifest.srcFile '../.tgwsproxy/branding/AndroidManifest_standalone.xml'
        res.srcDir '../.tgwsproxy/branding/res'
    }
'@.TrimEnd()
if ($build -notmatch [regex]::Escape('../.tgwsproxy/branding/AndroidManifest_standalone.xml')) {
    if ($build -match 'sourceSets\.prototype') {
        $count = ([regex]::Matches($build, [regex]::Escape($appSourceSetPrototypeBlock))).Count
        if ($count -ne 1) { throw "Telegram app existing prototype source-set anchor count is $count; expected 1." }
        $build = $build.Replace($appSourceSetPrototypeBlock, $appSourceSetBrandingBlock)
    } else {
        $count = ([regex]::Matches($build, [regex]::Escape($appSourceSetMarker))).Count
        if ($count -ne 1) { throw "Telegram app standalone source-set anchor count is $count; expected 1." }
        $build = $build.Replace($appSourceSetMarker, $appSourceSetBrandingBlock)
    }
}

$appAbiMarker = '                abiFilters "armeabi-v7a", "arm64-v8a", "x86", "x86_64"'
$appAbiBlock = @'
                if (project.findProperty("TGWS_PROXY_ARM64_ONLY")?.toBoolean()) {
                    abiFilters "arm64-v8a"
                } else {
                    abiFilters "armeabi-v7a", "arm64-v8a", "x86", "x86_64"
                }
'@.TrimEnd()
if ($build -notmatch 'TGWS_PROXY_ARM64_ONLY') {
    $count = ([regex]::Matches($build, [regex]::Escape($appAbiMarker))).Count
    if ($count -ne 1) { throw "Telegram app ABI filter anchor count is $count; expected 1." }
    $build = $build.Replace($appAbiMarker, $appAbiBlock)
}

Set-Content -Path $buildPath -Value $build -NoNewline

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
}

$coreAbiMarker = '        targetSdkVersion 36'
$coreAbiBlock = @'
        targetSdkVersion 36

        if (project.findProperty("TGWS_PROXY_ARM64_ONLY")?.toBoolean()) {
            ndk {
                abiFilters "arm64-v8a"
            }
        }
'@.TrimEnd()
if ($coreBuild -notmatch 'TGWS_PROXY_ARM64_ONLY') {
    $count = ([regex]::Matches($coreBuild, [regex]::Escape($coreAbiMarker))).Count
    if ($count -ne 1) { throw "Telegram core ABI filter anchor count is $count; expected 1." }
    $coreBuild = $coreBuild.Replace($coreAbiMarker, $coreAbiBlock)
}

$coreStandaloneMarker = @'
        standalone {
            matchingFallbacks = ['release']
            jniDebuggable false
            minifyEnabled true
            multiDexEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), '../TMessagesProj/proguard-rules.pro'
            ndk.debugSymbolLevel = 'FULL'
            buildConfigField "String", "BUILD_VERSION_STRING", "\"" + APP_VERSION_NAME + "\""
            buildConfigField "String", "APP_CENTER_HASH", "\"\""
            buildConfigField "String", "BETA_URL", "\"\""
            buildConfigField "boolean", "DEBUG_VERSION", "false"
            buildConfigField "boolean", "DEBUG_PRIVATE_VERSION", "false"
            buildConfigField "boolean", "BUNDLE", "false"
            buildConfigField "int", "VERSION_NUM", "6"
        }
'@.TrimEnd()
$corePrototypeBlock = @'
        standalone {
            matchingFallbacks = ['release']
            jniDebuggable false
            minifyEnabled true
            multiDexEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt'), '../TMessagesProj/proguard-rules.pro'
            ndk.debugSymbolLevel = 'FULL'
            buildConfigField "String", "BUILD_VERSION_STRING", "\"" + APP_VERSION_NAME + "\""
            buildConfigField "String", "APP_CENTER_HASH", "\"\""
            buildConfigField "String", "BETA_URL", "\"\""
            buildConfigField "boolean", "DEBUG_VERSION", "false"
            buildConfigField "boolean", "DEBUG_PRIVATE_VERSION", "false"
            buildConfigField "boolean", "BUNDLE", "false"
            buildConfigField "int", "VERSION_NUM", "6"
        }

        prototype {
            matchingFallbacks = ['release']
            jniDebuggable false
            minifyEnabled false
            multiDexEnabled true
            ndk.debugSymbolLevel = 'FULL'
            buildConfigField "String", "BUILD_VERSION_STRING", "\"" + APP_VERSION_NAME + "\""
            buildConfigField "String", "APP_CENTER_HASH", "\"\""
            buildConfigField "String", "BETA_URL", "\"\""
            buildConfigField "boolean", "DEBUG_VERSION", "false"
            buildConfigField "boolean", "DEBUG_PRIVATE_VERSION", "false"
            buildConfigField "boolean", "BUNDLE", "false"
            buildConfigField "int", "VERSION_NUM", "6"
        }
'@.TrimEnd()
if ($coreBuild -notmatch '(?m)^        prototype \{') {
    $count = ([regex]::Matches($coreBuild, [regex]::Escape($coreStandaloneMarker))).Count
    if ($count -ne 1) { throw "Telegram core standalone build-type anchor count is $count; expected 1." }
    $coreBuild = $coreBuild.Replace($coreStandaloneMarker, $corePrototypeBlock)
}

$coreThemeAssetMarker = "    namespace 'org.telegram.messenger'"
$coreThemeAssetBlock = @'
    sourceSets.standalone.assets.srcDir '../.tgwsproxy/theme-assets'
    sourceSets.prototype.assets.srcDir '../.tgwsproxy/theme-assets'

    namespace 'org.telegram.messenger'
'@.TrimEnd()
if ($coreBuild -notmatch [regex]::Escape('../.tgwsproxy/theme-assets')) {
    $count = ([regex]::Matches($coreBuild, [regex]::Escape($coreThemeAssetMarker))).Count
    if ($count -ne 1) { throw "Telegram core namespace anchor count is $count; expected 1." }
    $coreBuild = $coreBuild.Replace($coreThemeAssetMarker, $coreThemeAssetBlock)
}

Set-Content -Path $coreBuildPath -Value $coreBuild -NoNewline

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
}

$passkeyMarker = '    public static boolean SUPPORTS_PASSKEYS = true;'
$passkeyBlock = '    public static boolean SUPPORTS_PASSKEYS = false;'
if ($buildVars -notmatch [regex]::Escape($passkeyBlock)) {
    $count = ([regex]::Matches($buildVars, [regex]::Escape($passkeyMarker))).Count
    if ($count -ne 1) { throw "Telegram passkey anchor count is $count; expected 1." }
    $buildVars = $buildVars.Replace($passkeyMarker, $passkeyBlock)
}

Set-Content -Path $buildVarsPath -Value $buildVars -NoNewline

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

$generatedThemeAssets = @(Get-ChildItem $themeAssetsGenerated -File -Filter '*.attheme')
if ($generatedThemeAssets.Count -eq 0) {
    throw 'Generated LF Telegram theme asset overlay is missing.'
}
foreach ($themeAsset in $generatedThemeAssets) {
    $themeBytes = [System.IO.File]::ReadAllBytes($themeAsset.FullName)
    if ($themeBytes -contains [byte]13) {
        throw "Generated Telegram theme overlay contains CR bytes: $($themeAsset.Name)"
    }
}

$generatedIcon = Join-Path $brandingResGenerated 'drawable-nodpi/tgwsproxy_launcher_source.png'
$generatedLegacyAlias = Join-Path $brandingResGenerated 'values/tgwsproxy_launcher.xml'
$generatedAdaptiveIcon = Join-Path $brandingResGenerated 'mipmap-anydpi-v26/tgwsproxy_launcher.xml'
foreach ($brandingPath in @($generatedIcon, $generatedLegacyAlias, $generatedAdaptiveIcon, $brandingManifestGenerated)) {
    if (-not (Test-Path $brandingPath)) { throw "Generated branding file is missing: $brandingPath" }
}
$generatedManifestText = Get-Content $brandingManifestGenerated -Raw
if ($generatedManifestText -notmatch 'android:icon="@mipmap/tgwsproxy_launcher"') {
    throw 'Generated standalone manifest does not use the TgWsProxy launcher icon.'
}
if ($generatedManifestText -notmatch 'android:roundIcon="@mipmap/tgwsproxy_launcher"') {
    throw 'Generated standalone manifest does not use the TgWsProxy round launcher icon.'
}
if ($generatedManifestText -notmatch 'android:label="Telegram-WSP"') {
    throw 'Generated standalone manifest does not use the Telegram-WSP application label.'
}

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
