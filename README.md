# MadeiraTV

**Windows PC-игры на Apple TV** — порт [Madeira](https://github.com/willfaust/Madeira)
(Wine + FEX-Emu + DXMT) с iOS на **tvOS**.

Madeira оригинально запускает немодифицированные x86-64 Windows-игры на iPhone
в одном Mach-процессе. Этот репозиторий переносит тот же стек на Apple TV.

## Статус

### Фаза 1 (текущая) — каркас tvOS
- ✅ `MadeiraTV.xcodeproj` — нативный tvOS-таргет (tvOS 17.0, `appletvos`/`appletvsimulator`)
- ✅ SwiftUI-интерфейс, заточенный под Siri Remote и геймпад
- ✅ Portable-модули SwiftSteam (без iOS UIKit/AppKit-зависимостей) — входят в таргет
- ✅ CI: GitHub Actions `build-tvos.yml` собирает .app для симулятора и устройства
- ⏳ Линковка с Wine/FEX/DXMT под tvOS — Фаза 2

### Фаза 2 — полный стек
- Сборка FEX-Emu под tvOS (`appletvos` SDK)
- Сборка Wine-форка (unix + ARM64EC PE) под tvOS
- Сборка DXMT (D3D9/10/11 → Metal) под tvOS
- Подключение C-библиотек к `MadeiraTV.xcodeproj`
- JIT на Apple TV (через отладчик / StikDebug-аналог)
- Ввод с геймпада в Windows-гостевую ОС (XInput)

## Сборка

### Фаза 1 (только каркас)

```bash
xcodebuild -project app/MadeiraTV.xcodeproj \
  -scheme MadeiraTV \
  -destination 'generic/platform=tvOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Или запустить workflow **Build tvOS (Phase 1)** в Actions — артефакт `.app` выгружается.

## Структура

| Путь | Что это |
|---|---|
| `app/MadeiraTV.xcodeproj` | tvOS-проект |
| `app/MadeiraTV/` | tvOS SwiftUI-каркас |
| `app/Madeira/` | исходники Madeira (iOS), включая portable SwiftSteam |
| `tools/gen-tvproj.py` | генератор pbxproj |
| `.github/workflows/build-tvos.yml` | CI-сборка |

## Лицензия

GPL-3.0-or-later (как и Madeira). Компоненты — см. `LICENSE-EXCEPTION.md` и
`COPYING`.