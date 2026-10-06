// MadeiraTV-Bridging-Header.h
// Phase 1: only the C shims SwiftSteam needs (chunk_zip/lzma/zstd).
// Phase 2 adds JITAllocator/FEX/Wine/DXMT headers when those link into tvOS.

#import "SwiftSteam/chunk_zip.h"
#import "SwiftSteam/lzma_shim.h"
#import "SwiftSteam/zstd_edu.h"

// Wine bootstrap bridges (used by TVSessionModel to start a real session).
#import "WineServerBridge.h"
#import "WineProcessBridge.h"

// Display bridge: registers the CAMetalLayer DXMT renders into.
#import "IOSDisplayShim.h"

// FEX bridge: log callback + init helpers.
#import "FEXBridge.h"

// DXMT present counter (defined in libdxmt) — for diagnosing black screens.
uint64_t madeira_get_present_count(void);

// Wineserver lifecycle stages (set by build/wineserver/main_ios.c)
extern int g_ws_main_entered;
extern int g_ws_in_mainloop;

#include <stdint.h>