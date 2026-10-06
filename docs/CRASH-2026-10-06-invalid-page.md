# Crash: code-signing "Invalid Page" SIGKILL on guest execute

Date: 2026-10-06 · Device: Apple TV 4K (AppleTV14,1) · OS: tvOS 27.0 (24J361)
App: MadeiraTV `com.madeira.tvos.5G33ZSZ4G5` (sideloaded), game: BounceMasters.

## The report

From MadeiraTV.ips (`incident_id D06F34AB-...`):

```
exception   : EXC_BAD_ACCESS
signal      : SIGKILL
subtype     : KERN_PROTECTION_FAILURE at 0x000000717fd32d18
termination : namespace CODESIGNING   indicator "Invalid Page"   code 2
faultingThread : 7
  esr = 0x82000007  -> "Instruction Abort" / Translation fault
  pc  = far = 0x717fd32d18             (fetch of an instruction from this address)
  frames = []                           (native thread executing FEX-translated x86)
ktriageinfo : "mach_vm_allocate_kernel failed within call to vm_map_enter" (x5)
vmRegionInfo: 0x717fd32d18 is in a 576K "mapped file ... SM=COW r--/rw-" region
```

## Reading it

This is a tvOS code-signing enforcement kill, **not** memory pressure:

- Thread 7 is a guest (Wine/FEX-translated x86) thread. Neighbouring thread
  registers show `dxmt::g_buf_sites`, `madeira_cell_next`, `g_injected_client_fd` —
  Wine + DXMT were loaded, i.e. the guest was in early Wine/DXMT boot, still at
  0 presents.
- It did an **instruction fetch from a file-backed, non-executable page**
  (region is `mapped file … SM=COW r--/rw-`, no X). On Apple Silicon such a fetch
  trips the code-signing monitor → the process is killed under
  `CODESIGNING/"Invalid Page"` with SIGKILL (cannot be caught by the app's
  CrashCatcher, hence the previous "dead silence then SIGKILL" and 0 presents).
- The kernel had just failed `mach_vm_allocate_kernel` inside `vm_map_enter`
  (x5) — it could not back/validate an executable mapping, which is the direct
  trigger for a module running later from an un-validated page.

## Root cause: JIT-pool exhaustion leaves a module's .text un-pooled

This matches the loader's own documented failure mode (JITAllocator.c ml1040 /
ml1135): when the guest's early boot transcribes enough code, the JIT pool
fills; a module's `.text` is then left running from its **un-pooled file-backed
address**; the kernel rejects it (AV EXEC / KERN_PROTECTION_FAILURE) and tvOS
kills the process as an invalid page. The FEXCore JIT pool in `FEXBridge.mm` was
hard-coded at **64 MB** — far too small for a normal game boot.

## Fix applied

`app/Madeira/FEXBridge.mm`: JIT pool is now configurable and much larger by
default.

- New env knob `MADEIRA_JIT_POOL_MB` (64…4096), default **512**.
- Old hard-coded `JIT_POOL_SIZE = 64 MB` removed; `jit_pool_init()` allocates
  `jit_pool_size_mb() << 20`.

The pool is a MAP_JIT anonymous reserve (PROT_NONE-backed parts), so enlarging it
is cheap in footprint and does not change semantics.

## Verify

1. Build and sideload.
2. Launch a game; if the crash is gone, the pool exhaustion was the cause.
3. If it still crashes, set `MADEIRA_JIT_POOL_MB` larger (up to 4096) via
   `madeira.cfg` (`env.MADEIRA_JIT_POOL_MB = 1024`) or the env file and retry —
   the knob exists so this can be tuned without a rebuild.
4. For any new or unexplained fault, grab the `.ips` again: a
   `KERN_PROTECTION_FAILURE` at instruction fetch in a `mapped file` region is
   always the same "module executing from an un-validated file page" class.