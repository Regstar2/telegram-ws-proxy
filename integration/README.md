# Integration layer

Telegram-specific интеграция связывает чистый upstream Telegram с отдельным `tgwsproxy-core`.

## Текущая реализация

Overlay состоит из одного собственного Java-файла:

```text
integration/telegram/TgWsProxyBootstrap.java
```

и четырёх точечных изменений upstream:

```text
TMessagesProj/build.gradle
TMessagesProj/src/main/java/org/telegram/messenger/BuildVars.java
TMessagesProj_AppStandalone/build.gradle
TMessagesProj_AppStandalone/src/main/java/org/telegram/messenger/ApplicationLoaderImpl.java
```

Итого source-level diff: **5 upstream-файлов**, `tgnet` не изменяется.

## Startup path

```text
ApplicationLoaderImpl.onCreate()
        ↓
TgWsProxyBootstrap.start()
        ↓
TgWsProxyCore.start()
        ↓
127.0.0.1:1443
        ↓
ConnectionsManager.setProxySettings(...)
```

Bootstrap генерирует локальный 16-byte MTProto secret при первом запуске, сохраняет его только в application SharedPreferences и использует один и тот же secret для локального listener и штатного Telegram proxy API. Встроенный runtime по умолчанию использует `connection_mode=cf_first`: сначала `cf_proxy_ws`, затем разрешённые fallback-маршруты.

Если core не запускается, managed localhost proxy не включается. Если ранее управляемый proxy был активен, bootstrap отключает только собственную конфигурацию и не сбрасывает произвольный сторонний proxy.

## Применение

Обычная подготовка теперь инкрементальная:

```powershell
./scripts/prepare-integration.ps1
```

Скрипт переиспользует pinned Telegram checkout и уже собранный AAR, если их commit совпадает с конфигурацией. Это сохраняет Gradle/CMake outputs Telegram между итерациями.

`-Force` предназначен только для полного сброса generated worktree:

```powershell
./scripts/prepare-integration.ps1 -Force
```

`-RebuildCore` принудительно пересобирает AAR без сброса Telegram checkout. `-VerifyCore` дополнительно запускает unit tests core.

`.tgwsproxy/` исключается только локально через `.git/info/exclude` и не является частью upstream source diff.

## Launcher branding

Launcher artwork хранится в integration layer и воспроизводимо добавляется в generated overlay:

```text
integration/branding/res/drawable-nodpi/tgwsproxy_launcher_source.png
integration/branding/res/values/tgwsproxy_launcher.xml
integration/branding/res/mipmap-anydpi-v26/tgwsproxy_launcher.xml
```

Исходный PNG скопирован byte-for-byte из `Regstar2/tg-ws-proxy-android/icon.png`; provenance и исходный Git blob SHA зафиксированы в `integration/branding/README.md`.

При применении overlay скрипт:

1. копирует branding resources в `.tgwsproxy/branding/res`;
2. создаёт generated standalone manifest на основе pinned Telegram manifest;
3. заменяет только default `android:icon` / `android:roundIcon` на `@mipmap/tgwsproxy_launcher`;
4. подключает generated manifest/resources через уже изменяемый `TMessagesProj_AppStandalone/build.gradle`.

Для API < 26 используется legacy mipmap alias. Для API 26+ используется adaptive icon resource. Дополнительные Telegram resource-файлы не попадают в upstream source diff, поэтому лимит **5 upstream-файлов** сохраняется.

## Xiaomi / HyperOS dark-mode compatibility

Цель compatibility layer — **сохранить штатную тёмную тему Telegram**, а не запрещать dark mode.

Pinned Telegram уже реализует системный режим самостоятельно:

- на Android 10+ `selectedAutoNightType` по умолчанию равен `AUTO_NIGHT_TYPE_SYSTEM`;
- `Theme.needSwitchToTheme()` читает `Configuration.UI_MODE_NIGHT_MASK`;
- при `UI_MODE_NIGHT_YES` Telegram применяет собственный `currentNightTheme`.

Также upstream themes уже содержат:

```xml
<item name="android:forceDarkAllowed">false</item>
```

в релевантных `values-v21`, `values-v31` и `values-night`. Поэтому Telegram styles, `LaunchActivity` и theme-selection logic **не патчатся**.

Проблема Xiaomi возникает, когда MIUI/HyperOS поверх уже отрисованной Telegram light/dark theme применяет дополнительную algorithmic Force Dark inversion к fork package. Это даёт двойное преобразование цветов/контролов и ломает интерфейс.

Compatibility layer делает две вещи, не меняя системный `uiMode` и не переключая Telegram в светлый режим:

1. сохраняет Xiaomi manifest hint:

```xml
<meta-data android:name="force_dark_google" android:value="true" />
```

2. на Android 10+ регистрирует lifecycle callback и для каждого Activity вызывает:

```java
activity.getWindow().getDecorView().setForceDarkAllowed(false);
```

Это запрещает **только алгоритмическую вторичную инверсию**. Нативная тёмная тема Telegram продолжает включаться через `AUTO_NIGHT_TYPE_SYSTEM`.

Compat source хранится в integration layer:

```text
integration/telegram/TelegramWspDarkModeCompat.java
```

и копируется в generated `.tgwsproxy/compat/java`, подключённый через уже изменяемый `TMessagesProj_AppStandalone/build.gradle`. Новый upstream-файл Telegram не появляется: общий source diff остаётся **5 файлов**, `tgnet` не затрагивается.

Для device diagnostics в лог выводятся только безопасные состояния:

```text
systemNight=<true|false>
autoNightType=<n>
telegramThemeDark=<true|false>
forceDarkAllowed=<true|false>
```

Это позволяет отличить две проблемы: Telegram не переключился на native night theme или Xiaomi повторно инвертирует уже тёмный UI.

Reference: Xiaomi HyperOS dark-mode adaptation documentation: https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1595

## Telegram API credentials

Для локального device smoke-test можно использовать собственные `api_id` / `api_hash` без изменения tracked-файлов.

Перед APK-сборкой задайте process environment variables:

```powershell
$env:TELEGRAM_API_ID = Read-Host 'Telegram API ID'
$env:TELEGRAM_API_HASH = Read-Host 'Telegram API hash'
```

Либо добавьте значения только в локальный `.work/telegram/local.properties`:

```properties
TELEGRAM_API_ID=<your-api-id>
TELEGRAM_API_HASH=<your-api-hash>
```

`TMessagesProj/build.gradle` читает сначала environment variables, затем `local.properties`. Если оба источника пусты, используется публичный Telegram sample ID/hash, чтобы CI мог воспроизводить overlay без пользовательских секретов.

Значения credentials не выводятся скриптами в лог. Не добавляйте реальные `api_id` / `api_hash` в Issue, PR, commit или tracked-файлы.

Для стороннего клиента overlay также устанавливает `BuildVars.SUPPORTS_PASSKEYS = false`. Upstream помечает passkey support как функцию только для official app IDs; оставлять её включённой в fork нельзя.


## Сборка APK

Для итеративного device smoke-test используется отдельный быстрый build type `prototype`:

```powershell
./scripts/build-apk.ps1
```

Команда сама выполняет инкрементальный `prepare-integration.ps1`; повторно вызывать `-Force` перед каждой сборкой не нужно.

Он вызывает `:TMessagesProj_AppStandalone:assembleAfatPrototype` со следующими свойствами:

- `DEBUG_VERSION=false`;
- `DEBUG_PRIVATE_VERSION=false`;
- `minifyEnabled=false` — R8 не запускается;
- только `arm64-v8a`;
- Gradle daemon включён;
- Gradle build cache включён;
- Gradle parallel execution включён;
- pinned Telegram checkout и core AAR переиспользуются между сборками.

Ожидаемый быстрый APK:

```text
.work/telegram/TMessagesProj_AppStandalone/build/outputs/apk/afat/prototype/app.apk
```

После первой успешной сборки зависимости уже находятся в локальном Gradle cache. Для максимально быстрого повторного цикла можно запретить сетевое разрешение зависимостей:

```powershell
./scripts/build-apk.ps1 -Offline
```

Если локального dependency cache недостаточно, повторите без `-Offline`.

Полная acceptance-сборка сохраняется отдельно:

```powershell
./scripts/build-apk.ps1 -Full
```

Она вызывает исходный Telegram `:TMessagesProj_AppStandalone:assembleAfatStandalone` с R8/minification и всеми ABI. Это более медленный gate перед финальной проверкой, а не команда для каждой итерации.

`afatDebug` не используется: соответствующий library build включает `DEBUG_VERSION=true` и `DEBUG_PRIVATE_VERSION=true`.

## Правила

- reusable runtime не зависит от Telegram;
- `TMessagesProj/jni/tgnet/` не патчится;
- integration source находится только здесь;
- изменение upstream anchor должно приводить к явному failure;
- максимум 5 source-level upstream-файлов;
- бинарный AAR всегда воспроизводится из pinned `tgwsproxy-core` source.
