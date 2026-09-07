# Integration layer

Здесь будет храниться Telegram-specific интеграция, которая связывает чистый upstream Telegram с reusable `tgwsproxy-core`.

Правила:

- Telegram-specific код должен быть минимальным;
- reusable runtime не должен зависеть от Telegram;
- `TMessagesProj/jni/tgnet/` не патчится;
- интеграция должна применяться воспроизводимо;
- любые изменения upstream API локализуются здесь.

До выделения `tgwsproxy-core` директория намеренно не содержит implementation-кода.
