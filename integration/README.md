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
