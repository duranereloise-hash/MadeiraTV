// JITProbeCore.c — fork-per-test JIT matrix for tvOS 27 / free-provisioning.
// Each probe runs in a CHILD; the parent survives SIGKILL (Invalid Page kills
// the child with SIGKILL, uncatchable in-process) and records outcome.
//
// Exit codes from child:
//   0  exec returned 42 (JIT execution works)
//   1  exec ran but returned non-42 (page mapped+executable but wrong bytes)
//   2  mapping/protect syscalls failed (EPERM etc.)
//   3  unhandled crash inside child before exec (shouldn't happen)
//   WIFSIGNALED: WTERMSIG (11=SIGSEGV caught reachable, 9=SIGKILL = kernel Invalid Page)

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
#include <sys/sysctl.h>  // for hw.machine below

#ifndef MAP_JIT
#define MAP_JIT 0x800
#endif

// EXIT codes
#define EXEC_OK         0
#define EXEC_WRONGRES   1
#define MAP_FAIL        2
#define INTERNAL_ERR    3

static int child_mode = 0;

static void write_bytes(volatile uint32_t *p) {
    p[0] = 0xD2800540;  // mov x0, #42
    p[1] = 0xD65F03C0;  // ret
    // icache flush via syscall symbol (libsystem)
    __builtin___clear_cache((char*)p, (char*)p + 8);
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
    case 4: { // D: SHM dual-map, RX pre-set at creation + exec (control)
        mach_port_t task = mach_task_self();
        mach_port_t entry = MACH_PORT_NULL;
        memory_object_size_t es = size;
        kern_return_t kr = mach_make_memory_entry_64(task, &es, 0,
                            MAP_MEM_NAMED_CREATE|VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE,
                            &entry, MACH_PORT_NULL);
        if (kr != KERN_SUCCESS || entry == MACH_PORT_NULL) return MAP_FAIL;
        mach_vm_address_t rwAddr = 0;
        kr = vm_map(task, &rwAddr, size, 0, VM_FLAGS_ANYWHERE, entry, 0, FALSE,
                    VM_PROT_READ|VM_PROT_WRITE, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE, VM_INHERIT_DEFAULT);
        if (kr != KERN_SUCCESS) return MAP_FAIL;
        mach_vm_address_t rxAddr = 0;
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
        mach_vm_address_t addr = 0;
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
    case 6: { // F: SHM RW-only creation + write/read (no exec) — is SHM itself ok?
        mach_port_t task = mach_task_self();
        mach_port_t entry = MACH_PORT_NULL;
        memory_object_size_t es = size;
        kern_return_t kr = mach_make_memory_entry_64(task, &es, 0,
                            MAP_MEM_NAMED_CREATE|VM_PROT_READ|VM_PROT_WRITE, &entry, MACH_PORT_NULL);
        if (kr != KERN_SUCCESS || entry == MACH_PORT_NULL) return MAP_FAIL;
        mach_vm_address_t addr = 0;
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

    if (mode != 2 && mode != 5) {  // modes 2/5 already wrote
        write_bytes((volatile uint32_t*)mem);
    }
    __builtin___clear_cache((char*)exec, (char*)exec + 8);

    typedef uint64_t (*fn_t)(void);
    fn_t fn = (fn_t)(uintptr_t)exec;
    uint64_t r = fn();
    return r == 42 ? EXEC_OK : EXEC_WRONGRES;
}

static void open_partial(const char *path) {
    g_partial_fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_TRUNC, 0644);
}

/// Runs the matrix SEQUENTIALLY in-process (fork is forbidden in the iOS/tvOS
/// sandbox: fork() returns ENOSYS). Tests that previously killed the process
/// (D: SHM exec) are run LAST, and every earlier result is appended to a
/// partial file that survives the SIGKILL. Returns 0 when all tests ran;
/// if the process is killed mid-way the partial file still has the prefix.
int jitprobe_run_matrix(char *out, size_t outsz) {
    const char *names[] = {
        "A anon-RWX-exec", "B anon-RW->RX-exec", "C MAP_JIT-exec",
        "E SHM-RW->RX-exec", "F SHM-RW-only", "D SHM-dual-RX-exec"
    };
    int n = (int)(sizeof(names)/sizeof(names[0]));
    g_out = out; g_outsz = outsz; g_used = 0;

    add("=== JITProbe v2 matrix (sequential, partial-log survives death) ===\n");
    sn("%s %d\n", getpid());
    partial("=== start ===\n");

    for (int i = 0; i < n; i++) {
        int mode;
        if (i == n - 1) mode = 4;      // D last (guaranteed fatal)
        else if (i == 0) mode = 1;     // A
        else if (i == 1) mode = 2;     // B
        else if (i == 2) mode = 3;     // C
        else if (i == 3) mode = 5;     // E
        else mode = 6;                 // F

        char line[256];
        int rc = run_one_mode(mode);
        snprintf(line, sizeof(line), "--- %s --- rc=%d\n", names[i], rc);
        add(line);
        partial(line);
        partialf("  %s\n", rc);
    }
    add("=== DONE ===\n");
    partial("=== done ===\n");
    return 0;
}

// Helper for Swift: report length + device info
int jitprobe_compile_flags(void) {
    uint32_t flags = 0;
    // csops(CS_OPS_STATUS=0)
    extern int csops(int, unsigned int, void *, size_t);
    if (csops(getpid(), 0, &flags, sizeof(flags)) == 0) return (int)flags;
    return -1;
}

// Opens the partial log path; Swift passes Caches/jitprobe-partial.log.
void jitprobe_open_partial(const char *path) {
    open_partial(path);
}