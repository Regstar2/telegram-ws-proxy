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
    'scripts/build-apk.ps1'
)

foreach ($path in $required) {
    if (-not (Test-Path (Join-Path $root $path))) {
        throw "Required project file is missing: $path"
    }
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

    $generatedBrandingBlob = (& git hash-object $generatedBrandingIconPath).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Failed to hash generated launcher icon.' }
    if ($generatedBrandingBlob -ne $brandingBlob) {
        throw "Generated launcher icon differs from tracked source: $generatedBrandingBlob != $brandingBlob"
    }

    $preparedBootstrap = Get-Content (Join-Path $telegramWorktree 'TMessagesProj_AppStandalone/src/main/java/org/telegram/messenger/TgWsProxyBootstrap.java') -Raw
    if ($preparedBootstrap -notmatch '@connection_mode=cf_first') {
        throw 'Prepared Telegram bootstrap must prefer the Cloudflare proxy route.'
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
