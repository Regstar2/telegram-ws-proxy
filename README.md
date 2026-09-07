# Telegram WS Proxy

Экспериментальный Android-клиент Telegram с интегрированным WebSocket/Cloudflare transport из [Regstar2/tg-ws-proxy-android](https://github.com/Regstar2/tg-ws-proxy-android).

> [!IMPORTANT]
> Проект находится на стадии **Prototype**. Сейчас репозиторий содержит инфраструктуру для воспроизводимой интеграции поверх чистого upstream Telegram; готового APK и рабочего встроенного прокси ещё нет.

## Цель

Проверить, можно ли встроить существующий TgWsProxy runtime в Telegram Android так, чтобы:

- Telegram оставался максимально близким к upstream;
- `tgnet` не модифицировался;
- Telegram подключался к локальному MTProto/SOCKS5 frontend обычным штатным способом;
- WebSocket/Cloudflare transport находился в отдельном переиспользуемом модуле;
- обновление upstream требовало минимального собственного diff.

Целевая схема:

```text
Telegram Android
      |
      | штатный proxy API
      v
127.0.0.1:<port>
      |
      v
tgwsproxy-core
      |
      +-- cf_proxy_ws
      +-- direct_ws
      +-- cf_worker_ws
      +-- tcp_fallback
```

## Prototype scope

Основной сценарий:

1. получить чистый исходный код `DrKLO/Telegram` на зафиксированном commit;
2. подключить минимальный integration layer;
3. встроить TgWsProxy runtime без изменений `tgnet`;
4. собрать APK;
5. запустить Telegram и подтвердить работу через локальный proxy runtime.

Подробный scope: [docs/product/mvp-scope.md](docs/product/mvp-scope.md).

## Upstream

- Telegram Android: [DrKLO/Telegram](https://github.com/DrKLO/Telegram)
- ветка: `master`
- исходная точка Prototype: `62b56a07ca7e30e39f7fd00a6728d6bbd716ca1c` — Telegram 12.10.1 (7038), 25 августа 2026 года
- TgWsProxy core: [Regstar2/tgwsproxy-core](https://github.com/Regstar2/tgwsproxy-core), pinned через `config/core.json`
- исходный standalone runtime: [Regstar2/tg-ws-proxy-android](https://github.com/Regstar2/tg-ws-proxy-android)

Полная копия Telegram намеренно не хранится в этом репозитории. Скрипты получают upstream отдельно в локальную рабочую директорию.

## Структура

```text
config/
  upstream.json          зафиксированный upstream Telegram
  core.json              зафиксированный tgwsproxy-core

LICENSE                  GNU GPL v3.0
NOTICE.md                third-party notices и правила атрибуции

docs/
  architecture.md        границы интеграции и правила минимального diff
  licensing.md           аудит лицензий и модель распространения
  product/
    mvp-scope.md         scope Prototype/MVP

integration/
  README.md              описание integration layer
  telegram/
    TgWsProxyBootstrap.java

patches/
  README.md              минимальные патчи поверх upstream Telegram

scripts/
  fetch-upstream.ps1     получение зафиксированного Telegram
  fetch-core.ps1         получение зафиксированного tgwsproxy-core
  build-core.ps1         сборка release AAR
  apply-integration.ps1  применение deterministic overlay
  prepare-integration.ps1 полный fetch → build → apply
  build-apk.ps1          сборка canonical afatStandalone prototype APK
  ci.ps1                 проверки репозитория
```

Локальный checkout upstream создаётся в `.work/telegram` и не коммитится.

## Быстрый старт

Для базовых проверок требуется Git и PowerShell 7+. Для полной подготовки интеграции нужны JDK 17, Go 1.25, Android SDK/NDK и Gradle 8.2.1.

```powershell
git clone https://github.com/Regstar2/telegram-ws-proxy.git
cd telegram-ws-proxy

./scripts/prepare-integration.ps1 -Force
./scripts/ci.ps1
```

После выполнения Telegram будет подготовлен в:

```text
.work/telegram/
```

После `prepare-integration.ps1` чистый pinned Telegram получает reproducible overlay и локально собранный `tgwsproxy-core` AAR. Prototype APK собирается через `./scripts/build-apk.ps1`, который использует Telegram `afatStandalone`, а не internal debug/private variant.

Для локальной сборки с собственными Telegram `api_id` / `api_hash` используйте переменные `TELEGRAM_API_ID` и `TELEGRAM_API_HASH` либо локальный `.work/telegram/local.properties`; значения не должны попадать в Git. Подробности: [integration/README.md](integration/README.md).

## Архитектурные ограничения

Для Prototype действуют жёсткие ограничения:

- не изменять `TMessagesProj/jni/tgnet/`;
- не добавлять WebSocket/Cloudflare transport непосредственно в Telegram networking;
- держать собственные изменения Telegram в минимальном количестве файлов;
- не копировать весь `tg-ws-proxy-android` внутрь Telegram;
- reusable runtime должен быть отделён от UI самостоятельного приложения;
- любой upstream-specific код должен находиться в небольшом adapter/integration layer.

Целевой ориентир после первого рабочего прототипа — **не более 1–5 изменённых upstream-файлов Telegram**.

Подробнее: [docs/architecture.md](docs/architecture.md).

## Что не входит в Prototype

Пока не входят:

- собственные функции Telegram, не связанные с прокси;
- изменение `tgnet`;
- полноценный новый proxy UI;
- автоматическая публикация каждого upstream update;
- Google Play / RuStore;
- несколько ABI;
- полная локализация;
- updater;
- расширенная диагностика;
- глубокий ребрендинг.

Сначала должен быть подтверждён основной сценарий.

## Статус

| Область | Статус |
|---|---|
| Репозиторий и scope | Готово |
| Upstream fetch script | Реализован, первый локальный запуск не выполнен |
| GitHub-hosted CI | Добавлен: `ubuntu-latest`, без self-hosted runner |
| Лицензионный аудит Telegram ↔ TgWsProxy | Решён: GPL-3.0-only + third-party notices |
| Выделение `tgwsproxy-core` | Готово: отдельный repo/AAR, Android API 21+ |
| Telegram integration layer | Реализован: 5 upstream-файлов, собственные API credentials без хранения секретов, CI воспроизводимости |
| Первый APK | Собирается локально; canonical variant переведён на `afatStandalone` |
| Device smoke test | В процессе: предыдущий debug APK имел unusable login UI; требуется повторная проверка standalone APK |
| Upstream auto-sync | Post-MVP |

## Лицензирование

Проект использует **GNU GPL-3.0-only** для собственного integration/overlay и
TgWsProxy-derived combined code.

Telegram for Android официально распространяется по **GNU GPL v2 or later**. Для
объединённого клиента используется возможность выбрать GPLv3. Flowseal runtime origin
(MIT), Go/`x/crypto` (BSD 3-Clause) и JNA при выборе Apache-2.0 совместимы с GPLv3.

Для публичного APK обязательно публиковать точный полный Corresponding Source той же
сборки и сохранять third-party notices. Разработка может оставаться overlay-based, но
release не должен полагаться только на внешний upstream + patch.

Подробности и зафиксированные ревизии: [docs/licensing.md](docs/licensing.md).  
Third-party notices: [NOTICE.md](NOTICE.md).

## Связанные проекты

- [Regstar2/tgwsproxy-core](https://github.com/Regstar2/tgwsproxy-core) — переиспользуемый Android AAR/native runtime.
- [Regstar2/tg-ws-proxy-android](https://github.com/Regstar2/tg-ws-proxy-android) — существующее отдельное Android-приложение; пока не мигрировано на core.
- [Flowseal/tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy) — upstream WebSocket runtime.
- [DrKLO/Telegram](https://github.com/DrKLO/Telegram) — официальный open-source Android-клиент Telegram.

## Обратная связь

Ошибки и задачи фиксируются через [GitHub Issues](https://github.com/Regstar2/telegram-ws-proxy/issues).
