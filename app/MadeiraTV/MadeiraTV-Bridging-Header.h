// MadeiraTV-Bridging-Header.h
// Phase 1: only the C shims SwiftSteam needs (chunk_zip/lzma/zstd).
// Phase 2 adds JITAllocator/FEX/Wine/DXMT headers when those link into tvOS.

#import "SwiftSteam/chunk_zip.h"
#import "SwiftSteam/lzma_shim.h"
#import "SwiftSteam/zstd_edu.h"

#include <stdint.h>