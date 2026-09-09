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
    'integration/branding/README.md',
    'integration/branding/res/drawable-nodpi/tgwsproxy_launcher_source.png',
    'integration/branding/res/values/tgwsproxy_launcher.xml',
    'integration/branding/res/mipmap-anydpi-v26/tgwsproxy_launcher.xml',
    'patches/README.md',
    'scripts/fetch-upstream.ps1',
    'scripts/fetch-core.ps1',
    'scripts/build-core.ps1',
    'scripts/apply-integration.ps1',
    'scripts/prepare-integration.ps1',
    'scripts/build-apk.ps1',
    'scripts/build-release.ps1',
    'scripts/create-release-keystore.ps1',
    'scripts/sync-upstream.ps1',
    'scripts/package-release-source.ps1',
    'scripts/bootstrap-release-actions.ps1',
    'scripts/diagnose-xiaomi-dark-mode.ps1',
    'scripts/ensure-telegram-theme-assets-lf.ps1',
    '.github/workflows/release.yml',
    '.github/workflows/upstream-sync.yml'
)

foreach ($path in $required) {
    if (-not (Test-Path (Join-Path $root $path))) {
        throw "Required project file is missing: $path"
    }
}

$powerShellScripts = @(Get-ChildItem (Join-Path $root 'scripts') -File -Filter '*.ps1')
foreach ($scriptFile in $powerShellScripts) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null

    if ($parseErrors.Count -gt 0) {
        $details = @(
            $parseErrors | ForEach-Object {
                "{0}:{1} {2}" -f $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message
            }
        )
        throw "PowerShell syntax error in $($scriptFile.Name): $($details -join '; ')"
    }
}

$diagnosticScript = Get-Content (Join-Path $root 'scripts/diagnose-xiaomi-dark-mode.ps1') -Raw
if ($diagnosticScript -match '\[string\[\]\]\$Args') {
    throw 'diagnose-xiaomi-dark-mode.ps1 must not shadow the PowerShell automatic $Args variable.'
}
if ($diagnosticScript -match '@Args') {
    throw 'diagnose-xiaomi-dark-mode.ps1 must not splat the PowerShell automatic @Args variable.'
}
if ($diagnosticScript -notmatch '\$AdbArguments' -or $diagnosticScript -notmatch '@AdbArguments') {
    throw 'diagnose-xiaomi-dark-mode.ps1 must use an explicit ADB argument array for native invocation.'
}

$themeLfScript = Get-Content (Join-Path $root 'scripts/ensure-telegram-theme-assets-lf.ps1') -Raw
if ($themeLfScript -notmatch '\.tgwsproxy/theme-assets') {
    throw 'Theme normalization must generate an untracked LF asset overlay.'
}
if ($themeLfScript -notmatch 'Convert-CrlfBytesToLf') {
    throw 'Theme normalization must convert CRLF bytes in generated copies.'
}
if ($themeLfScript -notmatch 'WriteAllBytes') {
    throw 'Theme normalization must write generated theme bytes explicitly.'
}
if ($themeLfScript -notmatch 'ignore-space-at-eol') {
    throw 'Theme normalization must only clean up line-ending-only changes from the previous helper.'
}
if ($themeLfScript -match '\$attributeRule\s*=') {
    throw 'Theme normalization must not add a local Git attribute rule for upstream assets.'
}
if ($themeLfScript -notmatch "Trim\(\) -ne '\*\.attheme text eol=lf'") {
    throw 'Theme normalization must remove the obsolete local Git attribute rule left by earlier diagnostics.'
}

$buildApkScript = Get-Content (Join-Path $root 'scripts/build-apk.ps1') -Raw
if ($buildApkScript -notmatch 'assembleAfatPrototype') {
    throw 'scripts/build-apk.ps1 must default to the fast afatPrototype variant.'
}
if ($buildApkScript -notmatch 'assembleAfatStandalone') {
    throw 'scripts/build-apk.ps1 must preserve the full afatStandalone variant.'
}
if ($buildApkScript -notmatch '\[switch\]\$Full') {
    throw 'scripts/build-apk.ps1 must expose the -Full standalone build switch.'
}
if ($buildApkScript -notmatch '--build-cache') {
    throw 'scripts/build-apk.ps1 must enable the Gradle build cache.'
}
if ($buildApkScript -notmatch '--daemon') {
    throw 'scripts/build-apk.ps1 must keep the Gradle daemon enabled for iterative builds.'
}
if ($buildApkScript -notmatch 'TGWS_PROXY_ARM64_ONLY=true') {
    throw 'scripts/build-apk.ps1 must restrict fast prototype builds to ARM64.'
}
if ($buildApkScript -match '--no-daemon') {
    throw 'scripts/build-apk.ps1 must not disable the Gradle daemon.'
}
if ($buildApkScript -match 'assembleAfatDebug') {
    throw 'scripts/build-apk.ps1 must not use the Telegram debug/private variant.'
}
if ($buildApkScript -notmatch "prepare-integration\.ps1") {
    throw 'scripts/build-apk.ps1 must refresh the overlay incrementally before building.'
}
if ($buildApkScript -notmatch '--parallel') {
    throw 'scripts/build-apk.ps1 must keep Gradle parallel execution enabled.'
}
if ($buildApkScript -notmatch '\[switch\]\$Offline') {
    throw 'scripts/build-apk.ps1 must expose offline repeat builds.'
}
if ($buildApkScript -notmatch 'ensure-telegram-theme-assets-lf\.ps1') {
    throw 'scripts/build-apk.ps1 must enforce LF Telegram theme assets before Gradle.'
}
if ($buildApkScript -notmatch 'Remove-Item -Force \$apk') {
    throw 'scripts/build-apk.ps1 must remove stale APK output before invoking Gradle.'
}
if ($buildApkScript -notmatch 'System\.IO\.Compression\.ZipFile') {
    throw 'scripts/build-apk.ps1 must inspect the packaged APK theme assets.'
}
if ($buildApkScript -notmatch "assets/\[\^/\]\+\\\.attheme") {
    throw 'scripts/build-apk.ps1 must validate packaged Telegram .attheme entries.'
}
if ($buildApkScript -notmatch 'themeBytes -contains \[byte\]13') {
    throw 'scripts/build-apk.ps1 must reject packaged Telegram theme assets containing CR bytes.'
}

$buildCoreScript = Get-Content (Join-Path $root 'scripts/build-core.ps1') -Raw
if ($buildCoreScript -notmatch 'TGWSP_CORE_GRADLE') {
    throw 'Core build script must support a dedicated Gradle 8.2.1 executable for release CI.'
}

$syncUpstreamScript = Get-Content (Join-Path $root 'scripts/sync-upstream.ps1') -Raw
if ($syncUpstreamScript -notmatch 'git ls-remote' -or $syncUpstreamScript -notmatch 'APP_VERSION_NAME' -or $syncUpstreamScript -notmatch 'APP_VERSION_CODE') {
    throw 'Upstream sync script must resolve the Telegram master commit and version metadata.'
}
if ($syncUpstreamScript -notmatch 'master-ahead-without-version-bump') {
    throw 'Upstream sync must avoid publishing arbitrary master commits without a Telegram version bump.'
}

if ($syncUpstreamScript -match '\$LASTEXITCODE\s+-ne\s+0\s+-or\s+\[string\]::IsNullOrWhiteSpace\(\$remoteLine\)') {
    throw 'Upstream sync must not depend on an uninitialized LASTEXITCODE under StrictMode.'
}
if ($syncUpstreamScript -notmatch '\$gitSucceeded\s*=\s*\$\?') {
    throw 'Upstream sync must capture native git success through the automatic $? status.'
}

$sourcePackageScript = Get-Content (Join-Path $root 'scripts/package-release-source.ps1') -Raw
if ($sourcePackageScript -notmatch 'Telegram-upstream-source' -or $sourcePackageScript -notmatch 'tgwsproxy-core-source' -or $sourcePackageScript -notmatch 'SOURCE_MANIFEST.json') {
    throw 'Release source packaging must include Telegram, tgwsproxy-core, overlay source and a source manifest.'
}

$releaseWorkflow = Get-Content (Join-Path $root '.github/workflows/release.yml') -Raw
if ($releaseWorkflow -notmatch 'RELEASE_KEYSTORE_BASE64' -or $releaseWorkflow -notmatch 'build-release\.ps1' -or $releaseWorkflow -notmatch 'gh release create') {
    throw 'Release workflow must restore the signing key, build the APK and publish a GitHub Release.'
}
if ($releaseWorkflow -notmatch 'latest\.json' -or $releaseWorkflow -notmatch 'package-release-source\.ps1') {
    throw 'Release workflow must publish the update feed and Corresponding Source assets.'
}

if ($releaseWorkflow -notmatch 'telegramBuild \* 1000' -or $releaseWorkflow -notmatch 'TELEGRAM_WSP_RELEASE_REVISION') {
    throw 'Release workflow must build and publish the same revision-aware Android versionCode.'
}

$upstreamWorkflow = Get-Content (Join-Path $root '.github/workflows/upstream-sync.yml') -Raw
if ($upstreamWorkflow -notmatch 'schedule:' -or $upstreamWorkflow -notmatch 'sync-upstream\.ps1 -Apply' -or $upstreamWorkflow -notmatch 'uses: \./\.github/workflows/release\.yml') {
    throw 'Upstream workflow must check Telegram on a schedule and call the reusable release workflow.'
}

if ($upstreamWorkflow -notmatch 'Validate release secrets before changing main' -or $upstreamWorkflow -notmatch 'RELEASE_KEYSTORE_BASE64') {
    throw 'Upstream workflow must fail before changing main when release secrets are not configured.'
}

if (-not $upstreamWorkflow.Contains('$releaseExists = $?')) {
    throw 'Upstream release decision must capture whether the GitHub Release exists.'
}
if (-not $upstreamWorkflow.Contains('exit 0')) {
    throw 'Upstream release decision must clear the expected missing-release native exit code.'
}

$releaseBootstrapScript = Get-Content (Join-Path $root 'scripts/bootstrap-release-actions.ps1') -Raw
if ($releaseBootstrapScript -notmatch 'gh secret set' -or $releaseBootstrapScript -notmatch 'gh workflow run') {
    throw 'Release bootstrap script must configure GitHub Secrets and dispatch the production upstream workflow.'
}
if ($releaseBootstrapScript -notmatch 'keytool\.Source' -or $releaseBootstrapScript -notmatch 'gh run watch') {
    throw 'Release bootstrap script must verify the local keystore and wait for the dispatched Actions run.'
}

if ($releaseBootstrapScript -match '--jq') {
    throw 'Release bootstrap must parse GitHub CLI JSON with ConvertFrom-Json instead of shell-sensitive --jq expressions.'
}
if ($releaseBootstrapScript -notmatch 'ConvertFrom-Json') {
    throw 'Release bootstrap must parse GitHub CLI JSON natively in PowerShell.'
}

if ($releaseBootstrapScript -notmatch 'ConvertFrom-Json -InputObject' -or $releaseBootstrapScript -notmatch '-join \[Environment\]::NewLine') {
    throw 'Release bootstrap must join GitHub CLI JSON output before parsing arrays.'
}

$prepareScript = Get-Content (Join-Path $root 'scripts/prepare-integration.ps1') -Raw
if ($prepareScript -notmatch 'Reusing pinned Telegram checkout') {
    throw 'prepare-integration.ps1 must preserve the pinned Telegram checkout for incremental builds.'
}
if ($prepareScript -notmatch 'Reusing core AAR') {
    throw 'prepare-integration.ps1 must reuse an existing pinned core AAR.'
}

$brandingIconPath = Join-Path $root 'integration/branding/res/drawable-nodpi/tgwsproxy_launcher_source.png'
$brandingBlob = (& git hash-object $brandingIconPath).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Failed to hash launcher icon source.' }
if ($brandingBlob -ne '7c943f64d8beb01df6e5dd16128fc0ca0a56e863') {
    throw "Launcher icon source does not match tg-ws-proxy-android/icon.png: $brandingBlob"
}

$legacyLauncher = Get-Content (Join-Path $root 'integration/branding/res/values/tgwsproxy_launcher.xml') -Raw
if ($legacyLauncher -notmatch 'type="mipmap" name="tgwsproxy_launcher"') {
    throw 'Legacy launcher mipmap alias is missing.'
}
if ($legacyLauncher -notmatch '@drawable/tgwsproxy_launcher_source') {
    throw 'Legacy launcher alias must point to the tracked TgWsProxy artwork.'
}

$adaptiveLauncher = Get-Content (Join-Path $root 'integration/branding/res/mipmap-anydpi-v26/tgwsproxy_launcher.xml') -Raw
if ($adaptiveLauncher -notmatch '<adaptive-icon') {
    throw 'API 26+ adaptive launcher resource is missing.'
}
if ($adaptiveLauncher -notmatch '@drawable/tgwsproxy_launcher_source') {
    throw 'Adaptive launcher resource must use the tracked TgWsProxy artwork.'
}

$applyScript = Get-Content (Join-Path $root 'scripts/apply-integration.ps1') -Raw
if ($applyScript -notmatch '\.tgwsproxy/branding/AndroidManifest_standalone\.xml') {
    throw 'Integration script must generate and use the branded standalone manifest.'
}
if ($applyScript -notmatch '\.tgwsproxy/branding/res') {
    throw 'Integration script must attach generated branding resources to the app source sets.'
}
if ($applyScript -notmatch 'android:label="Telegram-WSP"') {
    throw 'Integration script must set the Telegram-WSP application label.'
}
if ($applyScript -notmatch '\.tgwsproxy/theme-assets') {
    throw 'Integration script must attach the generated LF Telegram theme overlay.'
}
if ($applyScript -notmatch 'sourceSets\.standalone\.assets\.srcDir' -or $applyScript -notmatch 'sourceSets\.prototype\.assets\.srcDir') {
    throw 'Integration script must attach LF theme assets to standalone and prototype source sets.'
}

if ($applyScript -notmatch 'appAfatStandaloneBrandingBlock') {
    throw 'Integration script must override the afat product-flavor standalone manifest with Telegram-WSP branding.'
}

if ($applyScript -notmatch 'TELEGRAM_WSP_RELEASE_REVISION' -or $applyScript -notmatch 'defaultConfig\.versionCode \* 1000') {
    throw 'Integration script must encode the Telegram-WSP release revision into Android versionCode.'
}

$releaseBuildScript = Get-Content (Join-Path $root 'scripts/build-release.ps1') -Raw
if ($releaseBuildScript -notmatch 'build-apk\.ps1' -or $releaseBuildScript -notmatch 'Full\s*=\s*\$true') {
    throw 'Release build script must delegate to the full afatStandalone build.'
}
if ($releaseBuildScript -match '\$buildArgs\s*=\s*@\(''-Full''') {
    throw 'Release build script must not pass named PowerShell switches through positional array splatting.'
}
if ($releaseBuildScript -notmatch 'SkipPrepare\s*=\s*\$true') {
    throw 'Release build script must call build-apk.ps1 with named SkipPrepare=true.'
}
if ($releaseBuildScript -notmatch 'TELEGRAM_WSP_KEYSTORE_PASSWORD') {
    throw 'Release build script must inject signing credentials only through the process environment.'
}

if ($releaseBuildScript -notmatch '\$password\s*=\s*\$env:TELEGRAM_WSP_KEYSTORE_PASSWORD') {
    throw 'Release build script must support non-interactive signing in GitHub Actions.'
}

if ($releaseBuildScript -notmatch 'managedKeystoreCount' -or $releaseBuildScript -notmatch 'existing Telegram-WSP keystore configuration reused') {
    throw 'Release build script must accept an already managed Telegram-WSP signing block in an incremental worktree.'
}
if ($releaseBuildScript -notmatch 'apksigner\.bat' -or $releaseBuildScript -notmatch 'verify --verbose --print-certs') {
    throw 'Release build script must verify the produced APK signature.'
}
if ($releaseBuildScript -notmatch "application-label:'Telegram-WSP'") {
    throw 'Release build script must verify Telegram-WSP branding in the final APK.'
}
if ($releaseBuildScript -notmatch 'Remove-Item Env:TELEGRAM_WSP_KEYSTORE_PASSWORD') {
    throw 'Release build script must clear the signing password from the process environment.'
}

if ($releaseBuildScript -notmatch '\[ValidateRange\(1, 99\)\]\[int\]\$ReleaseRevision' -or $releaseBuildScript -notmatch 'expectedVersionCode') {
    throw 'Release build script must validate and verify revision-aware Android versionCode.'
}
if ($releaseBuildScript -notmatch 'Remove-Item Env:TELEGRAM_WSP_RELEASE_REVISION') {
    throw 'Release build script must clear the WSP revision environment variable.'
}

$keystoreScript = Get-Content (Join-Path $root 'scripts/create-release-keystore.ps1') -Raw
if ($keystoreScript -notmatch 'PKCS12' -or $keystoreScript -notmatch '4096' -or $keystoreScript -notmatch 'SHA256withRSA') {
    throw 'Release keystore script must create the expected PKCS12 RSA signing key.'
}
if ($keystoreScript -notmatch 'minimum 12 characters') {
    throw 'Release keystore script must enforce the minimum password length.'
}

$gitIgnoreText = Get-Content (Join-Path $root '.gitignore') -Raw
if (-not $gitIgnoreText.Contains('/.signing/')) {
    throw 'Release signing directory must be ignored by Git.'
}
if (-not $gitIgnoreText.Contains('*.p12')) {
    throw 'PKCS12 release keys must be ignored by Git.'
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
        (& git ls-files 'AGENTS.md' '.project-rules/**' '.work/**' 'dist/**' '.signing/**' '*.p12') |
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

    $preparedBuildVarsPath = Join-Path $telegramWorktree 'TMessagesProj/src/main/java/org/telegram/messenger/BuildVars.java'
    $preparedBuildVars = Get-Content $preparedBuildVarsPath -Raw
    if ($preparedBuildVars -notmatch 'public static boolean SUPPORTS_PASSKEYS = false;') {
        throw 'Prepared Telegram fork still enables official-app-only passkeys.'
    }
    if ($preparedBuildVars -notmatch 'BuildConfig\.TELEGRAM_API_ID') {
        throw 'Prepared Telegram BuildVars does not use injected API credentials.'
    }

    $preparedCoreBuild = Get-Content (Join-Path $telegramWorktree 'TMessagesProj/build.gradle') -Raw
    if ($preparedCoreBuild -notmatch '(?m)^        prototype \{') {
        throw 'Prepared Telegram core is missing the fast prototype build type.'
    }
    if ($preparedCoreBuild -notmatch 'prototype \{[\s\S]*?minifyEnabled false[\s\S]*?DEBUG_VERSION", "false"[\s\S]*?DEBUG_PRIVATE_VERSION", "false"') {
        throw 'Prepared Telegram core prototype must be non-minified with debug/private flags disabled.'
    }
    if ($preparedCoreBuild -notmatch 'TGWS_PROXY_ARM64_ONLY') {
        throw 'Prepared Telegram core is missing the ARM64-only prototype filter.'
    }
    if ($preparedCoreBuild -notmatch '\.tgwsproxy/theme-assets') {
        throw 'Prepared Telegram core does not use the generated LF theme asset overlay.'
    }

    $generatedThemeRoot = Join-Path $telegramWorktree '.tgwsproxy/theme-assets'
    $generatedThemeFiles = @(Get-ChildItem $generatedThemeRoot -File -Filter '*.attheme' -ErrorAction SilentlyContinue)
    if ($generatedThemeFiles.Count -eq 0) {
        throw 'Prepared Telegram LF theme overlay is missing.'
    }
    foreach ($generatedThemeFile in $generatedThemeFiles) {
        $generatedThemeBytes = [System.IO.File]::ReadAllBytes($generatedThemeFile.FullName)
        if ($generatedThemeBytes -contains [byte]13) {
            throw "Prepared Telegram LF theme overlay contains CR bytes: $($generatedThemeFile.Name)"
        }
    }

    $preparedAppBuild = Get-Content (Join-Path $telegramWorktree 'TMessagesProj_AppStandalone/build.gradle') -Raw
    if ($preparedAppBuild -notmatch '(?m)^        prototype \{') {
        throw 'Prepared Telegram app is missing the fast prototype build type.'
    }
    if ($preparedAppBuild -notmatch 'prototype \{[\s\S]*?minifyEnabled false') {
        throw 'Prepared Telegram app prototype must disable minification.'
    }
    if ($preparedAppBuild -notmatch 'sourceSets\.prototype') {
        throw 'Prepared Telegram app prototype must use the standalone manifest.'
    }
    if ($preparedAppBuild -notmatch 'TGWS_PROXY_ARM64_ONLY') {
        throw 'Prepared Telegram app is missing the ARM64-only prototype filter.'
    }
    if ($preparedAppBuild -notmatch '\.tgwsproxy/branding/AndroidManifest_standalone\.xml') {
        throw 'Prepared Telegram app does not use the generated branded standalone manifest.'
    }
    if ($preparedAppBuild -notmatch '\.tgwsproxy/branding/res') {
        throw 'Prepared Telegram app does not include generated launcher branding resources.'
    }

    $generatedBrandingRoot = Join-Path $telegramWorktree '.tgwsproxy/branding'
    $generatedBrandingManifestPath = Join-Path $generatedBrandingRoot 'AndroidManifest_standalone.xml'
    $generatedBrandingIconPath = Join-Path $generatedBrandingRoot 'res/drawable-nodpi/tgwsproxy_launcher_source.png'
    $generatedLegacyLauncherPath = Join-Path $generatedBrandingRoot 'res/values/tgwsproxy_launcher.xml'
    $generatedAdaptiveLauncherPath = Join-Path $generatedBrandingRoot 'res/mipmap-anydpi-v26/tgwsproxy_launcher.xml'
    foreach ($brandingPath in @($generatedBrandingManifestPath, $generatedBrandingIconPath, $generatedLegacyLauncherPath, $generatedAdaptiveLauncherPath)) {
        if (-not (Test-Path $brandingPath)) {
            throw "Prepared Telegram branding file is missing: $brandingPath"
        }
    }

    $generatedBrandingManifest = Get-Content $generatedBrandingManifestPath -Raw
    if ($generatedBrandingManifest -notmatch 'android:icon="@mipmap/tgwsproxy_launcher"') {
        throw 'Prepared standalone manifest does not use TgWsProxy as the launcher icon.'
    }
    if ($generatedBrandingManifest -notmatch 'android:roundIcon="@mipmap/tgwsproxy_launcher"') {
        throw 'Prepared standalone manifest does not use TgWsProxy as the round launcher icon.'
    }
    if ($generatedBrandingManifest -notmatch 'android:label="Telegram-WSP"') {
        throw 'Prepared standalone manifest does not use Telegram-WSP as the application label.'
    }

    $generatedBrandingBlob = (& git hash-object $generatedBrandingIconPath).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Failed to hash generated launcher icon.' }
    if ($generatedBrandingBlob -ne $brandingBlob) {
        throw "Generated launcher icon differs from tracked source: $generatedBrandingBlob != $brandingBlob"
    }

    $preparedBootstrap = Get-Content (Join-Path $telegramWorktree 'TMessagesProj_AppStandalone/src/main/java/org/telegram/messenger/TgWsProxyBootstrap.java') -Raw
    if ($preparedBootstrap -notmatch '@connection_mode=cf_first') {
        throw 'Prepared Telegram bootstrap must prefer the Cloudflare proxy route.'
    }
    if ($preparedBootstrap -match 'TelegramWSPTheme' -or $preparedBootstrap -match 'scheduleThemeDiagnostics') {
        throw 'Release bootstrap must not contain temporary theme diagnostics.'
    }

    if ($preparedBootstrap -notmatch 'releases/latest/download/latest\.json') {
        throw 'Prepared Telegram bootstrap must check the stable Telegram-WSP update feed.'
    }
    if ($preparedBootstrap -notmatch 'hasSameSigningCertificate' -or $preparedBootstrap -notmatch 'MessageDigest\.getInstance\("SHA-256"\)') {
        throw 'Prepared Telegram updater must verify both APK signing certificate and SHA-256 before installation.'
    }
    if ($preparedBootstrap -notmatch 'FileProvider\.getUriForFile' -or $preparedBootstrap -notmatch 'ACTION_MANAGE_UNKNOWN_APP_SOURCES') {
        throw 'Prepared Telegram updater must use the Android FileProvider/install-permission flow.'
    }
    if ($preparedBootstrap -notmatch 'remoteVersionCode <= currentVersionCode') {
        throw 'Prepared Telegram updater must compare Android versionCode before offering an update.'
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
