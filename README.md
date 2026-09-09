<div align="center">

# Telegram-WSP

Неофициальный форк Telegram для Android со встроенным TgWsProxy: прокси запускается внутри клиента и не требует отдельного приложения или собственного VPS. Проект сохраняет Telegram максимально близким к upstream и не изменяет `tgnet`.

[![Release](https://img.shields.io/github/v/release/Regstar2/telegram-wsp?display_name=tag&sort=semver&style=for-the-badge&logo=github&label=release)](../../releases)
[![Platform](https://img.shields.io/badge/platform-Android%205.0%2B-0A7EA4?style=for-the-badge)](#требования)
[![License](https://img.shields.io/github/license/Regstar2/telegram-wsp?style=for-the-badge&label=license)](LICENSE)

[Быстрый старт](#быстрый-старт) ·
[Документация](#документация) ·
[Релизы](../../releases) ·
[Обратная связь](../../issues)

</div>

---

## О проекте

Telegram-WSP встраивает TgWsProxy непосредственно в Telegram Android. При запуске приложение поднимает локальный proxy runtime на `127.0.0.1:1443` и подключает его через штатный proxy API Telegram.

Основная задача проекта — получить обычный Telegram-клиент с WebSocket/Cloudflare transport без отдельного TgWsProxy-приложения и без переноса собственного transport-кода в Telegram networking.

Проект построен как небольшой воспроизводимый overlay поверх [DrKLO/Telegram](https://github.com/DrKLO/Telegram). Сам исходный код Telegram целиком в этом репозитории не хранится.

### Принципы интеграции

Главный инженерный принцип Telegram-WSP — **минимально изменять оригинальный Telegram**. Интеграция вынесена в небольшой overlay, не меняет `TMessagesProj/jni/tgnet/` и на текущем pinned upstream затрагивает только **5 upstream-файлов**. Это снижает количество конфликтов и стоимость переноса на новые версии Telegram.

Telegram-WSP использует собственные название, package ID, launcher icon и release-подпись, чтобы не выдавать себя за официальный клиент. Это соответствует опубликованным требованиям Telegram для сторонних приложений: разработчик должен либо не использовать имя Telegram, либо явно показывать неофициальный статус приложения, а стандартный логотип Telegram использовать нельзя. Поэтому проект называется **Telegram-WSP**, в README явно обозначен как неофициальный форк и использует собственную иконку.

## Статус проекта

Стадия: **MVP**.

Текущий публичный релиз: **[v12.10.1-wsp.1](../../releases/tag/v12.10.1-wsp.1)**.

| Компонент | Текущее состояние |
|---|---|
| Telegram upstream | 12.10.1, build 7038 |
| Android package | `org.telegram.messenger.web` |
| Встроенный TgWsProxy | Работает через локальный listener |
| Подписанный APK | Публикуется через GitHub Releases |
| Device smoke test | Пройдены запуск, UI, вход и встроенный proxy |
| Автообновление | Реализовано через GitHub Releases |
| Upstream sync | Ежедневная автоматическая проверка `DrKLO/Telegram`, валидация overlay и автоматический выпуск совместимой версии |

Первый полностью облачный release pipeline успешно собрал и опубликовал `v12.10.1-wsp.1` через GitHub Actions. Дальнейшие обновления Telegram upstream также обслуживаются автоматизированным pipeline: новая версия принимается только после успешного воспроизведения integration overlay и прохождения CI gates.

## Возможности

- встроенный TgWsProxy runtime без отдельного Android-приложения;
- локальный MTProto proxy на `127.0.0.1:1443`;
- автоматический запуск proxy runtime вместе с Telegram-WSP;
- использование штатного `ConnectionsManager.setProxySettings(...)`, без патчей `TMessagesProj/jni/tgnet/`;
- WebSocket/Cloudflare transport с fallback-маршрутами из `tgwsproxy-core`;
- собственные название, launcher icon, package ID и постоянная release-подпись для явного отличия от официального Telegram;
- встроенная проверка обновлений через GitHub Releases;
- проверка скачанного APK по SHA-256, package ID и signing certificate;
- автоматическая проверка новых Telegram version/build и выпуск обновления после успешных integration gates;
- публикация точного Corresponding Source для каждого публичного APK.

## Быстрый старт

1. Скачайте **[последний Telegram-WSP-release.apk](https://github.com/Regstar2/telegram-wsp/releases/latest/download/Telegram-WSP-release.apk)**.
2. Разрешите Android устанавливать приложения из выбранного источника, если система запросит это.
3. Установите APK и запустите Telegram-WSP.
4. Войдите в Telegram как в обычном клиенте.

Встроенный proxy запускается автоматически; отдельное приложение TgWsProxy на устройстве не требуется.

## Требования

Для готового APK:

- Android **5.0 / API 21** или новее;
- доступ в интернет;
- разрешение Android на установку APK не из магазина.

Для сборки из исходников используются JDK 17, Go 1.25.x, Android SDK, NDK 27.2.12479018 и Gradle. Точные версии для production release зафиксированы в [release.yml](.github/workflows/release.yml).

## Установка

Актуальный APK всегда публикуется в [GitHub Releases](../../releases).

Имя пакета:

```text
org.telegram.messenger.web
```

Telegram-WSP использует постоянный release key. Новая версия может устанавливаться поверх предыдущей Telegram-WSP-сборки только при совпадении package ID и сертификата подписи.

Если на устройстве уже установлено приложение с тем же package ID, но другой подписью, Android не позволит выполнить обновление поверх него.

## Использование

После запуска Telegram-WSP:

1. `TgWsProxyBootstrap` запускает `tgwsproxy-core`;
2. core открывает локальный listener `127.0.0.1:1443`;
3. Telegram получает эту конфигурацию через штатный proxy API;
4. дальнейший трафик проходит через выбранный TgWsProxy transport.

Отдельной настройки для базового сценария не требуется.

Если встроенный runtime не запускается, Telegram-WSP не включает managed localhost proxy. Сторонняя proxy-конфигурация пользователя при этом не должна сбрасываться произвольно.

## Сеть и прокси

Базовый путь соединения:

```text
Telegram-WSP
     │
     │ штатный Telegram proxy API
     ▼
127.0.0.1:1443
     │
     ▼
tgwsproxy-core
     │
     ├─ cf_proxy_ws
     ├─ direct_ws
     ├─ cf_worker_ws
     └─ tcp_fallback
```

По умолчанию runtime использует режим `cf_first`: сначала WebSocket/Cloudflare transport, затем разрешённые fallback-маршруты.

Telegram networking не знает о реализации transport за localhost proxy. Это уменьшает собственный diff и количество конфликтов при обновлении upstream.

## Архитектура

Проект разделён на три уровня:

```text
DrKLO/Telegram
      │
      │ deterministic overlay
      ▼
Telegram integration adapter
      │
      ▼
tgwsproxy-core
      │
      ▼
libtgwsproxy.so
```

Текущий source-level integration diff ограничен **5 upstream-файлами**, а `TMessagesProj/jni/tgnet/` не изменяется.

Исходный Telegram checkout загружается по точному commit из [config/upstream.json](config/upstream.json), а `tgwsproxy-core` — из [config/core.json](config/core.json). Generated worktree создаётся в `.work/` и не коммитится.

Подробности: [docs/architecture.md](docs/architecture.md) и [integration/README.md](integration/README.md).

## Безопасность

Публичный APK подписывается постоянным Telegram-WSP release key.

Встроенный updater принимает новую сборку только после проверки:

- HTTPS URL из разрешённого GitHub Releases path;
- SHA-256 APK;
- package ID `org.telegram.messenger.web`;
- того же signing certificate, что у установленного приложения.

Финальную установку выполняет системный Android package installer, поэтому подтверждение пользователя остаётся обязательным.

Release key и Telegram API credentials не хранятся в репозитории. Для GitHub Actions они передаются через repository secrets.

## Обновление

Telegram-WSP проверяет:

```text
https://github.com/Regstar2/telegram-wsp/releases/latest/download/latest.json
```

не чаще одного раза в 12 часов.

Если `versionCode` новой сборки выше установленного, приложение предлагает обновление. После согласия APK скачивается, проверяется и передаётся системному installer.

Нумерация Telegram-WSP учитывает как Telegram build, так и WSP revision:

```text
versionCode = telegramBuild * 1000 + wspRevision * 10 + 9
```

Поэтому WSP hotfix той же версии Telegram может корректно обновляться поверх предыдущего WSP-релиза.

### Автоматическое обновление Telegram upstream

Обновление Telegram-WSP состоит из двух независимых уровней:

1. **Исходный Telegram → Telegram-WSP.** Workflow [upstream-sync.yml](.github/workflows/upstream-sync.yml) ежедневно проверяет официальный репозиторий [DrKLO/Telegram](https://github.com/DrKLO/Telegram). Если обнаружена новая version/build, workflow обновляет pinned commit в `config/upstream.json`, заново воспроизводит integration overlay и запускает проектные CI gates.
2. **Telegram-WSP → устройство пользователя.** Только после успешной проверки совместимости workflow вызывает [release.yml](.github/workflows/release.yml), который собирает полный подписанный APK, формирует metadata и Corresponding Source и публикует новый GitHub Release. Установленное приложение затем обнаруживает этот релиз через `latest.json` и предлагает обновление пользователю.

Если overlay не применяется или проверки не проходят, новый upstream pin не должен становиться публичным Telegram-WSP-релизом. Таким образом, проект автоматически подтягивает новые версии из официального репозитория Telegram, но не публикует их без проверки совместимости.

## Разработка

Рабочий Telegram checkout и core создаются локально:

```powershell
git clone https://github.com/Regstar2/telegram-wsp.git
cd telegram-wsp

./scripts/prepare-integration.ps1 -Force
./scripts/ci.ps1
```

Основные конфигурации:

- [config/upstream.json](config/upstream.json) — pinned Telegram commit и version/build;
- [config/core.json](config/core.json) — pinned `tgwsproxy-core`;
- [integration/](integration/) — собственный integration/branding layer;
- [scripts/](scripts/) — воспроизводимые fetch/build/release операции.

Для локальной сборки с собственными Telegram `api_id` / `api_hash` используйте environment variables `TELEGRAM_API_ID` и `TELEGRAM_API_HASH` либо локальный `.work/telegram/local.properties`. Реальные credentials нельзя коммитить или публиковать в Issue/PR.

## Сборка

Быстрый ARM64 prototype APK:

```powershell
./scripts/build-apk.ps1
```

Полная `afatStandalone` сборка с R8 и всеми ABI:

```powershell
./scripts/build-apk.ps1 -Full
```

Подписанный release APK:

```powershell
./scripts/build-release.ps1
```

Результат release-сборки:

```text
dist/Telegram-WSP-release.apk
```

Создание release key — одноразовая операция:

```powershell
./scripts/create-release-keystore.ps1
```

Потеря или замена этого ключа нарушит update compatibility уже установленных сборок.

Production releases собираются на GitHub-hosted Windows runner через [release.yml](.github/workflows/release.yml).

## Тестирование

Базовые проверки репозитория:

```powershell
./scripts/ci.ps1
```

Workflow [trusted-ci.yml](.github/workflows/trusted-ci.yml) на pull request:

- выполняет repository checks;
- воспроизводит Telegram overlay с чистого pinned upstream;
- повторно запускает проверки на подготовленном worktree.

Перед публичным релизом production workflow дополнительно выполняет полную подписанную `afatStandalone` сборку и проверяет package, branding и APK signature.

## Документация

- [Архитектура](docs/architecture.md) — границы Telegram/core и модель минимального diff;
- [Integration layer](integration/README.md) — startup path, credentials, branding и build variants;
- [MVP scope](docs/product/mvp-scope.md) — границы текущей стадии проекта;
- [Лицензирование](docs/licensing.md) — GPL-модель, third-party компоненты и Corresponding Source;
- [NOTICE.md](NOTICE.md) — third-party notices.

Точные исходные компоненты каждой публичной сборки также прикладываются к GitHub Release вместе с `SOURCE_MANIFEST.json` и `SHA256SUMS.txt`.

## Обратная связь

Ошибки и проблемы совместимости можно сообщать через [GitHub Issues](../../issues).

Для отчёта об ошибке полезно указать:

- модель устройства и версию Android;
- версию Telegram-WSP;
- что ожидалось и что произошло;
- воспроизводится ли проблема без сторонней proxy-конфигурации.

Не публикуйте Telegram API credentials, signing keys, access tokens и другие секреты.

## Происхождение и благодарности

Telegram-WSP основан на:

- [DrKLO/Telegram](https://github.com/DrKLO/Telegram) — официальный исходный код Telegram for Android;
- [Regstar2/tgwsproxy-core](https://github.com/Regstar2/tgwsproxy-core) — переиспользуемое Android/native ядро, извлечённое из `Regstar2/tg-ws-proxy-android`;
- [Regstar2/tg-ws-proxy-android](https://github.com/Regstar2/tg-ws-proxy-android) — форк Android-обёртки TgWsProxy и непосредственный источник runtime для первого выделения core;
- [amurcanov/tg-ws-proxy-android](https://github.com/amurcanov/tg-ws-proxy-android) — исходная Android-обёртка, от которой был создан форк `Regstar2/tg-ws-proxy-android`;
- [Flowseal/tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy) — первоначальный TgWsProxy/WebSocket runtime, на котором основана Android-ветка.

Происхождение proxy runtime можно кратко представить так:

```text
Flowseal/tg-ws-proxy
        ↓
amurcanov/tg-ws-proxy-android
        ↓
Regstar2/tg-ws-proxy-android
        ↓
Regstar2/tgwsproxy-core
        ↓
Telegram-WSP
```

Telegram-WSP является независимым неофициальным форком и не связан с Telegram и не одобрен Telegram.

## Ограничения

- проект находится на стадии MVP;
- поддерживается только Android;
- распространение сейчас выполняется через GitHub Releases, а не Google Play или RuStore;
- встроенный proxy рассчитан на основной автоматический сценарий; отдельного полноценного proxy UI пока нет;
- обновления требуют системного подтверждения установки Android;
- совместимость с новой версией Telegram принимается только после успешного применения overlay и CI/release gates;
- проект не изменяет и не открывает платные функции Telegram.

## Лицензия

Собственный integration/overlay и TgWsProxy-derived combined code распространяются по **GNU GPL-3.0-only**.

Telegram for Android распространяется по GNU GPL v2 or later; для объединённого клиента используется совместимая GPLv3-модель. Third-party компоненты сохраняют собственные лицензии и notices.

Каждый публичный APK сопровождается точным Corresponding Source использованной сборки.

Полный текст: [LICENSE](LICENSE). Подробности: [docs/licensing.md](docs/licensing.md).
