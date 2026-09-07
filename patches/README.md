# Upstream patches

Для текущего Prototype отдельный `.patch`-файл не используется.

Интеграция применяется детерминированным overlay-скриптом:

```text
scripts/apply-integration.ps1
```

Он использует точные upstream anchors и падает, если они изменились. Это сохраняет те же свойства, которые требовались от patch-файла:

- применяется только к commit из `config/upstream.json`;
- не затрагивает `TMessagesProj/jni/tgnet/`;
- не содержит generated/binary artifacts;
- не использует fuzzy/manual resolution;
- проверяет diff budget.

Если в будущем overlay перестанет быть удобнее unified patch, эта директория может снова использоваться для минимальных patch-файлов.
