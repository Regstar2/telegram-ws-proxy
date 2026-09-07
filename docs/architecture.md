# Architecture

## Цель архитектуры

Минимизировать стоимость сопровождения при обновлениях `DrKLO/Telegram`. Telegram должен оставаться upstream-owned кодовой базой, а собственная логика — жить вне неё.

## Компоненты

```text
DrKLO/Telegram (clean upstream checkout)
        |
        | minimal patch / overlay
        v
Telegram integration adapter
        |
        v
tgwsproxy-core
        |
        v
libtgwsproxy.so
        |
        +-- cf_proxy_ws
        +-- direct_ws
        +-- cf_worker_ws
        +-- tcp_fallback
```

## 1. Upstream Telegram

Telegram не хранится в этом репозитории. `scripts/fetch-upstream.ps1` получает точный commit из `config/upstream.json` в `.work/telegram`.

Все изменения Telegram должны быть воспроизводимы как patch/overlay. Ручное редактирование `.work/telegram` не считается долговечным состоянием проекта.

## 2. tgwsproxy-core

Целевой reusable модуль не должен зависеть от классов Telegram.

Ответственность core:

- запуск/остановка native runtime;
- listener на localhost;
- конфигурация route policy;
- статус runtime;
- минимальный lifecycle API;
- native bridge к `libtgwsproxy.so`.

Core не должен:

- импортировать Telegram UI;
- изменять Telegram SharedPreferences напрямую;
- знать о `ConnectionsManager`;
- содержать собственный Telegram fork logic.

## 3. Telegram integration adapter

Это единственный слой, которому разрешено знать одновременно о Telegram и `tgwsproxy-core`.

Минимальная ответственность:

1. запустить core;
2. получить local port/secret;
3. вызвать штатный `ConnectionsManager.setProxySettings(...)` либо эквивалентный официальный внутренний proxy path Telegram;
4. корректно остановить/перезапустить runtime по lifecycle.

Если upstream меняет proxy API, исправляться должен этот adapter, а не core.

## 4. Startup hook

Предпочтительный Prototype-вариант — один небольшой hook в application layer Telegram, например в app-specific `ApplicationLoaderImpl`, плюс подключение зависимости в Gradle.

Целевой budget:

```text
1 файл build configuration
1 startup hook
0 изменений tgnet
```

Дополнительные upstream-файлы допускаются только при доказанной необходимости.

## 5. Proxy path

Telegram должен видеть обычный локальный proxy:

```text
Telegram -> 127.0.0.1:<port> -> tgwsproxy-core -> WebSocket/Cloudflare -> Telegram infrastructure
```

Telegram не обязан знать, что за localhost находится WebSocket transport.

## 6. Запрещённая зона

До отдельного архитектурного решения запрещено патчить:

```text
TMessagesProj/jni/tgnet/
```

Причина: это резко увеличивает конфликтность upstream sync и превращает проект в самостоятельную реализацию Telegram networking.

## 7. Upstream update model

Текущая модель:

```text
config/upstream.json
       |
       v
fetch exact commit
       |
       v
apply patches/overlay
       |
       v
build + smoke
```

После рабочего Prototype можно автоматизировать проверку нового `master`: workflow обновляет pin в отдельной ветке/PR, применяет overlay и запускает CI. Автоматический merge/release не является частью первого Prototype.

## 8. Diff budget

После появления первого рабочего APK CI должен проверять:

- отсутствие изменений `TMessagesProj/jni/tgnet/`;
- количество изменённых upstream-файлов;
- успешное применение patch/overlay без fuzzy/manual resolution;
- сборку Telegram на pinned upstream.

Ориентир — не более 1–5 собственных upstream-файлов.

## 9. Лицензии

Лицензионный аудит завершён и зафиксирован в [licensing.md](licensing.md).

Принятая модель:

- Telegram for Android используется по его официальной лицензии GNU GPL v2 or later с
  выбором GPLv3 для объединённого клиента;
- integration/overlay и TgWsProxy-derived combined code — GNU GPL-3.0-only;
- third-party компоненты сохраняют собственные совместимые лицензии и notices;
- публичный APK сопровождается точным полным Corresponding Source собранной версии.

Архитектурное следствие: runtime и integration source должны оставаться воспроизводимыми
из публичного release source bundle; бинарная `libtgwsproxy.so` без соответствующего
исходного кода не является допустимым release input.


## 10. Реализованный Prototype overlay

Текущий integration layer использует pinned `tgwsproxy-core` и изменяет только:

```text
TMessagesProj_AppStandalone/build.gradle
TMessagesProj_AppStandalone/src/main/java/org/telegram/messenger/ApplicationLoaderImpl.java
TMessagesProj_AppStandalone/src/main/java/org/telegram/messenger/TgWsProxyBootstrap.java
```

AAR собирается из `config/core.json` и копируется только в локальную
`.work/telegram/.tgwsproxy/`. Generated binary не входит в source diff.

`TgWsProxyBootstrap`:

1. генерирует и сохраняет локальный 16-byte MTProto secret;
2. запускает `TgWsProxyCore` на `127.0.0.1:1443`;
3. сохраняет штатные Telegram proxy preferences;
4. вызывает `ConnectionsManager.setProxySettings(...)`;
5. при ошибке core отключает только ранее управляемый localhost proxy.

Overlay применяется `scripts/apply-integration.ps1` через точные anchor-замены.
Если upstream изменит anchor, процесс завершается ошибкой вместо fuzzy merge.
