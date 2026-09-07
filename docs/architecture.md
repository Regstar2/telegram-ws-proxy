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

Upstream Telegram содержит GNU GPL v2 license. Текущий `Regstar2/tg-ws-proxy-android` заявляет GNU GPL v3.

До распространения объединённого APK необходимо определить точное лицензирование каждого интегрируемого компонента и допустимость их объединения. До завершения аудита проект остаётся Prototype без публичного бинарного релиза.
