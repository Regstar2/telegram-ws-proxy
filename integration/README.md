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

Bootstrap генерирует локальный 16-byte MTProto secret при первом запуске, сохраняет его только в application SharedPreferences и использует один и тот же secret для локального listener и штатного Telegram proxy API.

Если core не запускается, managed localhost proxy не включается. Если ранее управляемый proxy был активен, bootstrap отключает только собственную конфигурацию и не сбрасывает произвольный сторонний proxy.

## Применение

```powershell
./scripts/prepare-integration.ps1 -Force
```

Скрипт:

1. получает pinned Telegram;
2. получает pinned `tgwsproxy-core`;
3. собирает release AAR;
4. кладёт AAR в локальный `.work/telegram/.tgwsproxy/`;
5. применяет четыре точечных изменения и копирует bootstrap source;
6. проверяет `git diff --check`, запрет изменений `tgnet` и diff budget.

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

## Правила

- reusable runtime не зависит от Telegram;
- `TMessagesProj/jni/tgnet/` не патчится;
- integration source находится только здесь;
- изменение upstream anchor должно приводить к явному failure;
- максимум 5 source-level upstream-файлов;
- бинарный AAR всегда воспроизводится из pinned `tgwsproxy-core` source.
