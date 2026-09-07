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
- TgWsProxy runtime: [Regstar2/tg-ws-proxy-android](https://github.com/Regstar2/tg-ws-proxy-android)

Полная копия Telegram намеренно не хранится в этом репозитории. Скрипты получают upstream отдельно в локальную рабочую директорию.

## Структура

```text
config/
  upstream.json          зафиксированный upstream Telegram

LICENSE                  GNU GPL v3.0
NOTICE.md                third-party notices и правила атрибуции

docs/
  architecture.md        границы интеграции и правила минимального diff
  licensing.md           аудит лицензий и модель распространения
  product/
    mvp-scope.md         scope Prototype/MVP

integration/
  README.md              будущий Telegram adapter / Android integration layer

patches/
  README.md              минимальные патчи поверх upstream Telegram

scripts/
  fetch-upstream.ps1     получение зафиксированного Telegram
  ci.ps1                 проверки репозитория
```

Локальный checkout upstream создаётся в `.work/telegram` и не коммитится.

## Быстрый старт

Требуется Git и PowerShell 7+.

```powershell
git clone https://github.com/Regstar2/telegram-ws-proxy.git
cd telegram-ws-proxy

./scripts/fetch-upstream.ps1
./scripts/ci.ps1
```

После выполнения Telegram будет подготовлен в:

```text
.work/telegram/
```

На текущей стадии скрипт только получает точный upstream commit. Наложение интеграции и сборка APK появятся в следующих implementation issues.

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
| Trusted CI | Добавлен, первый workflow run не выполнен |
| Лицензионный аудит Telegram ↔ TgWsProxy | Решён: GPL-3.0-only + third-party notices |
| Выделение `tgwsproxy-core` | Не начато |
| Telegram integration layer | Не начато |
| Первый APK | Не начато |
| Device smoke test | Не начато |
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

- [Regstar2/tg-ws-proxy-android](https://github.com/Regstar2/tg-ws-proxy-android) — существующее отдельное Android-приложение.
- [Flowseal/tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy) — upstream WebSocket runtime.
- [DrKLO/Telegram](https://github.com/DrKLO/Telegram) — официальный open-source Android-клиент Telegram.

## Обратная связь

Ошибки и задачи фиксируются через [GitHub Issues](https://github.com/Regstar2/telegram-ws-proxy/issues).
