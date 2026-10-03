# MadeiraTV

**Windows PC-игры на Apple TV** — порт [Madeira](https://github.com/willfaust/Madeira)
(Wine + FEX-Emu + DXMT) с iOS на **tvOS**.

Madeira запускает немодифицированные x86-64 Windows-игры на iPhone в одном
Mach-процессе. Этот репозиторий переносит тот же стек на Apple TV (tvOS 17+).

> ⚠️ Исследовательский проект. Многие игры будут работать, некоторые — нет.
> Производительность и совместимость варьируются от игры к игре.

## Статус

### ✅ Фаза 1 — tvOS-каркас приложения (готово)
- `MadeiraTV.xcodeproj` — нативный tvOS-таргет (tvOS 17.0, `appletvos`/`appletvsimulator`)
- SwiftUI-интерфейс под Siri Remote и геймпад
- Portable-модули SwiftSteam (Foundation-only, без iOS UI) — в таргете
- CI: `build-tvos.yml` собирает `.app` для симулятора и устройства, артефакт заливается

### ✅ Фаза 2 — стек Wine + FEX (большая часть готовa)

| Компонент | Статус | Заметки |
|---|---|---|
| **FEX-Emu** (x86→ARM64 JIT) | ✅ собран | `libFEXCore.a` + External (fmt/cephes/xxhash/softfloat) |
| **Wine ntdll-unix** | ✅ **37/37 модулей** | полная `libntdll_unix.a` (2 МБ) под `appletvos` |
| **Wine wineserver** | ✅ собран | `libwineserver.a` (1.3 МБ) |
| **Wine win32u-unix** | ✅ **46/46 модулей** | `libwin32u_unix.a` (2.6 МБ) |
| — GnuTLS-стек (bcrypt/secur32/crypt32) | ✅ | gmp+nettle+gnutls под tvOS |
| — freetype (dwrite) | ✅ | freetype 2.13.3 из tracked tarball |
| — FFmpeg (winegstreamer) | ✅ | LGPL-конфиг под tvOS |

### ⏳ Фаза 2 — остаток
- Wine **PE-сторона** (ARM64EC DLL: ntdll.dll и др.) через llvm-mingw
- **DXMT** (D3D9/10/11 → Metal) под tvOS
- Слинковать весь стек в `MadeiraTV.xcodeproj`
- JIT-запуск на Apple TV (через отладчик / StikDebug-аналог)
- Ввод с геймпада в Windows-гостевую ОС (XInput)

## Сборка

### Фаза 1 (только каркас)

```bash
xcodebuild -project app/MadeiraTV.xcodeproj \
  -scheme MadeiraTV \
  -destination 'generic/platform=tvOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

### Фаза 2 (компоненты) — все через GitHub Actions на macos-15 (Xcode)

| Workflow | Что делает | Артефакт |
|---|---|---|
| `build-tvos.yml` | каркас app | `MadeiraTV.app` |
| `build-fex-tvos.yml` | FEXCore под tvOS | `libFEXCore*.a`, External libs |
| `build-toolchains-tvos.yml` | GnuTLS + FFmpeg (+ freetype) под tvOS | `toolchains/*-tvos` |
| `build-wine-tvos.yml` | все toolchains + unix Wine | `libntdll_unix.a` |

## tvOS-специфичные патчи

tvOS SDK помечает ряд Darwin/Mach API как `TVOS_PROHIBITED` (хотя они есть в
ядре), и не содержит `IOKit.framework`. Решения:

- **dlsym-обёртки** для `mach_msg`, `task_swap_exception_ports`,
  `thread_set_exception_ports`, `host_info`, `task_get_bootstrap_port`,
  `task_get_special_port`, `mach_msg_send` — в `build/ntdll-unix/`
- **IOKit shim** — `build/ntdll-unix/shims/IOKit/IOKitLib.h`
- guards для `execv`, `sigaltstack`, `TARGET_OS_TV`-специфичных фрагментов

Форки с патчами:
- `duranereloise-hash/wine` (ветка `madeira-lgpl`)
- `duranereloise-hash/FEX` (ветка `ios-port-2607`)

## Структура

| Путь | Что это |
|---|---|
| `app/MadeiraTV.xcodeproj` | tvOS-проект (каркас) |
| `app/MadeiraTV/` | tvOS SwiftUI-каркас |
| `app/Madeira/` | исходники Madeira (iOS), portable SwiftSteam |
| `build/` | скрипты сборки (iOS + tvOS), shims |
| `docs/TVOS-PHASE2-STATUS.md` | детальный статус Фазы 2 |
| `.github/workflows/` | CI-сборки компонентов |

## Лицензия

GPL-3.0-or-later (как и Madeira). Компоненты — см. `LICENSE-EXCEPTION.md` и
`COPYING`.