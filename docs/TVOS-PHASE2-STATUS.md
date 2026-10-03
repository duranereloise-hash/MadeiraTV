# MadeiraTV — Phase 2 status (Wine under tvOS)

## What builds today under the Apple TV SDK (all in GitHub Actions, macos-15)

| Component | Status | Notes |
|---|---|---|
| **FEX-Emu** (x86→arm64 JIT) | ✅ builds | `libFEXCore.a` + FEXCore_Base + External (fmt/cephes/xxhash/softfloat) |
| **Wine ntdll-unix** | ✅ 32/37 modules | all core modules compile under `appletvos` SDK |
| — loader, server, signal_arm64, system, file | ✅ | patched for `TVOS_PROHIBITED` APIs |
| — crypto/network unixlibs | ✅ | ws2_32, nsi_*, dnsapi, madsync... |
| — bcrypt/secur32/crypt32 | ⏳ | need GnuTLS toolchain (build/gnutls-ios/, appletvos) |
| — dwrite | ⏳ | needs freetype (build/freetype-ios/, appletvos) |
| — winegstreamer | ⏳ | needs FFmpeg (build/ffmpeg/, appletvos) |
| **DXMT** (D3D9/10/11→Metal) | ⏳ | not started yet |

## tvOS-specific patches (fork-only, kept out of upstream)

### Repository `MadeiraTV` — `build/ntdll-unix/`
- `shims/IOKit/IOKitLib.h` — tvOS SDK has **no IOKit.framework**; minimal compile shim
  (SMBIOS/battery probes return empty, which Wine already tolerates)
- `loader_ios.c` — `execv` is `TVOS_PROHIBITED`; the preloader path is dead on tvOS
  (single-process model), stubbed
- `signal_arm64_ios.c` — dlsym shims for `mach_msg`, `task_swap_exception_ports`,
  `thread_set_exception_ports` (all `TVOS_PROHIBITED` in SDK but present in kernel)
- `server_ios.c` — dlsym shims for `task_get_bootstrap_port`, `task_get_special_port`,
  `mach_msg_send`; guard `sigaltstack`; `#include <dispatch/dispatch.h>`

### Fork `duranereloise-hash/wine` (branch `madeira-lgpl`)
- `dlls/ntdll/unix/system.c` — `TargetConditionals.h`; `host_info` dlsym shim;
  IOKit includes unconditional (shim provides types on tvOS)
- `dlls/ntdll/unix/file.c` — `kCFURLVolumeAvailableCapacityForImportantUsageKey`
  is `TVOS_PROHIBITED`; skip free-space probe on tvOS

### Fork `duranereloise-hash/FEX` (branch `ios-port-2607`)
- `CMakeLists.txt` — accept `CMAKE_SYSTEM_NAME=tvOS`
- `FEXCore/Source/Utils/ArchHelpers/Arm64.cpp` — guard Win32 `VirtualQuery` diagnostic
  with `#ifdef _WIN32`

## How CI builds Wine unix for tvOS
1. clone patched wine fork (`--depth 1 --branch madeira-lgpl`)
2. host `configure` for `build-macos` (tools + config.h): needs bison3 via brew,
   llvm-mingw (PE cross compiler), and `wine/build -> $PWD/build` symlink for
   `madeira_cfg.h`
3. compile each unix .c with:
   `xcrun --sdk appletvos clang -arch arm64 -mtvos-version-min=17.0 -DWINE_IOS=1 -I build/ntdll-unix/shims`
4. `ar rcs libntdll_unix.a`

## Next steps
- build GnuTLS/Nettle/GMP under appletvos (build/gnutls-ios, sysroot swap)
- build FFmpeg LGPL under appletvos (build/ffmpeg)
- build freetype under appletvos (or point dwrite at the shim)
- DXMT (winemetal/d3d11 → Metal) under appletvos
- link everything into `MadeiraTV.xcodeproj`