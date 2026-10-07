// JITProbeCore.c — sequential JIT matrix for tvOS 27 / free-provisioning.
// fork() is forbidden in the iOS/tvOS sandbox (returns ENOSYS), so the tests
// run sequentially IN-PROCESS, with every result appended to a partial log
// (Caches/jitprobe-partial.log) that SURVIVES the SIGKILL of a fatal test.
// The known-fatal test (D: SHM executable exec) runs LAST.
//
// rc (per test):
//   EXEC_OK=0  exec returned 42 (JIT execution works here)
//   EXEC_WRONGRES=1  exec ran but returned non-42 (page mapped+exec but wrong)
//   MAP_FAIL=2  mapping/protect syscall failed (EPERM etc.)
//   INTERNAL_ERR=3  unexpected
// If the process is SIGKILLed on test D, everything before it is in the file.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <mach/mach.h>
#include <dlfcn.h>

#ifndef MAP_JIT
#define MAP_JIT 0x800
#endif

#define EXEC_OK         0
#define EXEC_WRONGRES   1
#define MAP_FAIL        2
#define INTERNAL_ERR    3

typedef void (*icache_fn)(char *start, size_t len);

static void icache_flush(char *p, size_t len) {
    // sys_icache_invalidate lives in libSystem; dlsym to avoid a direct
    // dependency on the compiler-rt builtin (___clear_cache isn't linked).
    static icache_fn fn = NULL;
    if (!fn) {
        void *h = dlopen(NULL, RTLD_LAZY);
        if (h) {
            fn = (icache_fn)dlsym(h, "sys_icache_invalidate");
        }
    }
    if (fn) fn(p, len);
    // Also flush dcache (PIPT on ARM, cheap if no-op).
    static icache_fn dfn = NULL;
    if (!dfn) {
        void *h = dlopen(NULL, RTLD_LAZY);
        if (h) dfn = (icache_fn)dlsym(h, "sys_dcache_flush");
    }
    if (dfn) dfn(p, len);
}

// ---- report + partial-log infrastructure -------------------------------
static char *g_out = NULL;
static size_t g_outsz = 0;
static size_t g_used = 0;
static int g_partial_fd = -1;

static void partial(const char *s) {
    if (g_partial_fd < 0) return;
    size_t l = strlen(s);
    (void)!write(g_partial_fd, s, l);
    fsync(g_partial_fd);
}

static void partialf(const char *f, int v) {
    char buf[256];
    int w = snprintf(buf, sizeof(buf), f, v);
    if (w < 0 || (size_t)w >= sizeof(buf)) return;
    partial(buf);
}

static int add(const char *s) {
    size_t l = strlen(s);
    if (g_used + l + 1 > g_outsz) return 1;
    memcpy(g_out + g_used, s, l);
    g_used += l;
    g_out[g_used] = 0;
    return 0;
}

static int snout(const char *f, int v) {
    char buf[512];
    int w = snprintf(buf, sizeof(buf), f, v);
    if (w < 0 || (size_t)w >= sizeof(buf)) return 1;
    return add(buf);
}

static void open_partial(const char *path) {
    g_partial_fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_TRUNC, 0644);
}

// ---- test core ----------------------------------------------------------
static void write_bytes(volatile uint32_t *p) {
    p[0] = 0xD2800540;  // mov x0, #42
    p[1] = 0xD65F03C0;  // ret
    icache_flush((char*)p, 8);
}

static int run_one_mode(int mode) {
    const size_t size = 16 * 1024;
    void *mem = NULL;
    void *exec = NULL;
    volatile uint32_t *pw = NULL;

    switch (mode) {
    case 1: { // A: anonymous RWX + exec
        void *p = mmap(NULL, size, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_ANON|MAP_PRIVATE, -1, 0);
        if (p == MAP_FAILED) return MAP_FAIL;
        mem = p; exec = p; pw = (volatile uint32_t*)p;
        break;
    }
    case 2: { // B: anonymous RW -> write -> mprotect(RX) -> exec
        void *p = mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_ANON|MAP_PRIVATE, -1, 0);
        if (p == MAP_FAILED) return MAP_FAIL;
        pw = (volatile uint32_t*)p;
        write_bytes(pw);
        if (mprotect(p, size, PROT_READ|PROT_EXEC) != 0) return MAP_FAIL;
        mem = p; exec = p;
        break;
    }
    case 3: { // C: MAP_JIT RWX + exec
        void *p = mmap(NULL, size, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_ANON|MAP_PRIVATE|MAP_JIT, -1, 0);
        if (p == MAP_FAILED) return MAP_FAIL;
        mem = p; exec = p; pw = (volatile uint32_t*)p;
        break;
    }
    case 4: { // D: SHM dual-map, RX pre-set + exec (control, known fatal)
        mach_port_t task = mach_task_self();
        mach_port_t entry = MACH_PORT_NULL;
        memory_object_size_t es = size;
        kern_return_t kr = mach_make_memory_entry_64(task, &es, 0,
                            MAP_MEM_NAMED_CREATE|VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE,
                            &entry, MACH_PORT_NULL);
        if (kr != KERN_SUCCESS || entry == MACH_PORT_NULL) return MAP_FAIL;
        vm_address_t rwAddr = 0;
        kr = vm_map(task, &rwAddr, size, 0, VM_FLAGS_ANYWHERE, entry, 0, FALSE,
                    VM_PROT_READ|VM_PROT_WRITE, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE, VM_INHERIT_DEFAULT);
        if (kr != KERN_SUCCESS) return MAP_FAIL;
        vm_address_t rxAddr = 0;
        kr = vm_map(task, &rxAddr, size, 0, VM_FLAGS_ANYWHERE, entry, 0, FALSE,
                    VM_PROT_READ|VM_PROT_EXECUTE, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE, VM_INHERIT_DEFAULT);
        if (kr != KERN_SUCCESS) return MAP_FAIL;
        pw = (volatile uint32_t*)(uintptr_t)rwAddr;
        write_bytes(pw);
        mem = (void*)(uintptr_t)rwAddr;
        exec = (void*)(uintptr_t)rxAddr;
        break;
    }
    case 5: { // E: SHM single RW -> write -> mprotect(RX) -> exec
        mach_port_t task = mach_task_self();
        mach_port_t entry = MACH_PORT_NULL;
        memory_object_size_t es = size;
        kern_return_t kr = mach_make_memory_entry_64(task, &es, 0,
                            MAP_MEM_NAMED_CREATE|VM_PROT_READ|VM_PROT_WRITE, &entry, MACH_PORT_NULL);
        if (kr != KERN_SUCCESS || entry == MACH_PORT_NULL) return MAP_FAIL;
        vm_address_t addr = 0;
        kr = vm_map(task, &addr, size, 0, VM_FLAGS_ANYWHERE, entry, 0, FALSE,
                    VM_PROT_READ|VM_PROT_WRITE, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE, VM_INHERIT_DEFAULT);
        if (kr != KERN_SUCCESS) return MAP_FAIL;
        pw = (volatile uint32_t*)(uintptr_t)addr;
        write_bytes(pw);
        if (mprotect((void*)(uintptr_t)addr, size, PROT_READ|PROT_EXEC) != 0) return MAP_FAIL;
        mem = (void*)(uintptr_t)addr;
        exec = (void*)(uintptr_t)addr;
        break;
    }
    case 6: { // F: SHM RW-only + write/read (no exec)
        mach_port_t task = mach_task_self();
        mach_port_t entry = MACH_PORT_NULL;
        memory_object_size_t es = size;
        kern_return_t kr = mach_make_memory_entry_64(task, &es, 0,
                            MAP_MEM_NAMED_CREATE|VM_PROT_READ|VM_PROT_WRITE, &entry, MACH_PORT_NULL);
        if (kr != KERN_SUCCESS || entry == MACH_PORT_NULL) return MAP_FAIL;
        vm_address_t addr = 0;
        kr = vm_map(task, &addr, size, 0, VM_FLAGS_ANYWHERE, entry, 0, FALSE,
                    VM_PROT_READ|VM_PROT_WRITE, VM_PROT_READ|VM_PROT_WRITE, VM_INHERIT_DEFAULT);
        if (kr != KERN_SUCCESS) return MAP_FAIL;
        volatile uint32_t *p = (volatile uint32_t*)(uintptr_t)addr;
        p[0] = 0xCAFEBABE;
        return p[0] == 0xCAFEBABE ? EXEC_OK : EXEC_WRONGRES;
    }
    default:
        return INTERNAL_ERR;
    }

    if (mode != 2 && mode != 5) write_bytes((volatile uint32_t*)mem);
    icache_flush((char*)exec, 8);
    typedef uint64_t (*fn_t)(void);
    fn_t fn = (fn_t)(uintptr_t)exec;
    uint64_t r = fn();
    return r == 42 ? EXEC_OK : EXEC_WRONGRES;
}

// ---- matrix runner ------------------------------------------------------
int jitprobe_run_matrix(char *out, size_t outsz) {
    const char *names[] = {
        "A anon-RWX-exec", "B anon-RW->RX-exec", "C MAP_JIT-exec",
        "E SHM-RW->RX-exec", "F SHM-RW-only", "D SHM-dual-RX-exec"
    };
    int n = (int)(sizeof(names)/sizeof(names[0]));
    int modes[] = { 1, 2, 3, 5, 6, 4 };   // D last
    g_out = out; g_outsz = outsz; g_used = 0;

    add("=== JITProbe v2 matrix (sequential; partial-log survives death) ===\n");
    snout("%s %d\n", getpid());
    partial("=== start ===\n");

    for (int i = 0; i < n; i++) {
        // Give the HTTP server time to bind before a possibly-fatal test.
        partialf("--- %s ---\n", modes[i]);
        partial("  (test begins)\n");
        char line[256];
        int rc = run_one_mode(modes[i]);
        snprintf(line, sizeof(line), "--- %s --- rc=%d\n", names[i], rc);
        add(line);
        partial(line);
        partialf("  desc=%d\n", rc);
        // If the test did not kill us, pause so the PC can read the partial.
        usleep(3 * 1000000);   // 3s — readable via :9091 between tests
    }
    add("=== DONE ===\n");
    partial("=== done ===\n");
    return 0;
}

// ---- exports ------------------------------------------------------------
int jitprobe_compile_flags(void) {
    uint32_t flags = 0;
    extern int csops(int, unsigned int, void *, size_t);
    if (csops(getpid(), 0, &flags, sizeof(flags)) == 0) return (int)flags;
    return -1;
}

void jitprobe_open_partial(const char *path) {
    open_partial(path);
}