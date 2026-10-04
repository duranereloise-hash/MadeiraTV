// MadeiraIntegrations.mm - tvOS host implementations for symbols that the
// FEX / DXMT / Wine tvOS builds reference but that the app must provide.
//
// These mirror the integrations the iOS target carries. Where a subsystem
// (rpmalloc, madeira-d3d12) is not built into this tvOS IPA, the safest no-op
// / identity implementation is provided so the static libs link and run.

#include <cstdint>
#include <cstdlib>
#include <cstring>

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <malloc/malloc.h>
#include <stdlib.h>

// ---------------------------------------------------------------------------
// FEX mono / dual-map JIT bridge hooks (FEXCore and arm64ec reference these).
// Returning the "bridge not armed" / empty answers is valid: when the bridge
// is never installed the real implementations behave exactly this way.
// ---------------------------------------------------------------------------
extern "C" {

uintptr_t ios_fex_band_base = 0;
uintptr_t ios_fex_band_end = 0;

int ios_fex_mono_bridge_armed(void) { return 0; }
uint64_t ios_fex_mono_captured_count(void) { return 0; }
void ios_fex_mono_count_activated(void) {}
void ios_fex_mono_count_helper(int Miss) { (void)Miss; }
int ios_fex_mono_take_pending(uint64_t *BlockBegin, uint64_t *HostPC, uint64_t *FaultAddr) {
  (void)BlockBegin; (void)HostPC; (void)FaultAddr;
  return 0;
}

uint64_t IosMonoResolveRW(uint64_t GuestAddr, uint64_t Size) {
  (void)GuestAddr; (void)Size;
  return 0;
}

uint64_t IosSubfloorToReal(uint64_t Addr) { return Addr; }

// rpmalloc CAS snapshot telemetry (FEXCore/Core.cpp references it; rpmalloc is
// not built into this tvOS IPA, so report "no snapshot").
struct rpm_cas_snapshot {
  unsigned long long page_addr, block_addr, heap_addr, owner_teb;
  unsigned long long prev_token, cur_token, ret_addr, atomic_addr;
  unsigned int size_class, page_type, block_index, list_size;
  unsigned int fail_changed, fail_unchanged, fail_invalid, quarantined;
  unsigned int block_count, block_used, is_full, which_loop;
};
int rpm_cas_snapshot_take(struct rpm_cas_snapshot *out) {
  if (!out) return 0;
  memset(out, 0, sizeof(*out));
  return 0;
}

// DXMT winemetal unix table slot for IR conversion (D3D12). The madeira-d3d12
// component is not in this build; return "not implemented" so the call fails
// cleanly instead of crashing.
int madeira_ir_convert(void *args) {
  (void)args;
  return 0x80004001; // E_NOTIMPL
}

} // extern "C"

// ---------------------------------------------------------------------------
// FEXCore::Allocator hooks (AllocatorHooks.cpp is compiled out of libFEXCore.a
// because the tvOS FEX build passes -DENABLE_FEX_ALLOCATOR=OFF). Provide a
// straight-to-CRT allocator so JITSymbols/Context allocations succeed.
// ---------------------------------------------------------------------------
namespace FEXCore::Allocator {

void *malloc(size_t size) { return ::malloc(size); }
void *calloc(size_t n, size_t size) { return ::calloc(n, size); }
void *memalign(size_t align, size_t s) {
#if defined(__APPLE__)
  void *p = nullptr;
  if (posix_memalign(&p, align, s) == 0) return p;
  return nullptr;
#else
  return ::memalign(align, s);
#endif
}
void *valloc(size_t size) { return ::valloc(size); }
int posix_memalign(void **r, size_t a, size_t s) { return ::posix_memalign(r, a, s); }
void *realloc(void *ptr, size_t size) { return ::realloc(ptr, size); }
void free(void *ptr) { ::free(ptr); }
size_t malloc_usable_size(void *ptr) { return ::malloc_size(ptr); }
void *aligned_alloc(size_t a, size_t s) {
#if defined(__APPLE__)
  void *p = nullptr;
  if (posix_memalign(&p, a, s) == 0) return p;
  return nullptr;
#else
  return ::aligned_alloc(a, s);
#endif
}
void aligned_free(void *ptr) { ::free(ptr); }

} // namespace FEXCore::Allocator