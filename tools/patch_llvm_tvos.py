#!/usr/bin/env python3
"""Patch LLVM lib/Support/Unix sources so tvOS_PROHIBITED APIs do not break the build.

Handled:
  - Program.inc:   fork()/execv()/execve()  (spawn path dead on tvOS)
  - Process.inc:   task_set_exception_ports, task_get_exception_ports
  - Signals.inc:   task_set_exception_ports
and any other *.inc/*.cpp in lib/Support/Unix that references the Mach
exception-port helpers (all TVOS_PROHIBITED but present in the kernel).
"""
import glob, os, sys

unix_dir = sys.argv[1]
files = glob.glob(os.path.join(unix_dir, "*.inc")) + glob.glob(os.path.join(unix_dir, "*.cpp"))

TASK_SET_SHIM = """#if defined(__APPLE__) && defined(TARGET_OS_TV) && TARGET_OS_TV
#include <dlfcn.h>
#define task_set_exception_ports madeira_tvos_task_set_exception_ports
static inline kern_return_t madeira_tvos_task_set_exception_ports(
    mach_port_t task, exception_mask_t exception_mask, mach_port_t new_port,
    exception_behavior_t behavior, thread_state_flavor_t new_flavor)
{
    typedef kern_return_t (*fn_t)(mach_port_t, exception_mask_t, mach_port_t,
                                  exception_behavior_t, thread_state_flavor_t);
    static fn_t fn;
    if (!fn) fn = (fn_t)dlsym(RTLD_DEFAULT, "task_set_exception_ports");
    if (!fn) return KERN_FAILURE;
    return fn(task, exception_mask, new_port, behavior, new_flavor);
}
#endif
"""

TASK_GET_SHIM = """#if defined(__APPLE__) && defined(TARGET_OS_TV) && TARGET_OS_TV
#define task_get_exception_ports madeira_tvos_task_get_exception_ports
static inline kern_return_t madeira_tvos_task_get_exception_ports(
    mach_port_t task, exception_mask_t exception_mask,
    exception_mask_array_t masks, mach_msg_type_number_t *masks_count,
    exception_handler_array_t old_handlers, exception_behavior_array_t old_behaviors,
    thread_state_flavor_array_t old_flavors)
{
    typedef kern_return_t (*fn_t)(mach_port_t, exception_mask_t,
        exception_mask_array_t, mach_msg_type_number_t *,
        exception_handler_array_t, exception_behavior_array_t,
        thread_state_flavor_array_t);
    static fn_t fn;
    if (!fn) fn = (fn_t)dlsym(RTLD_DEFAULT, "task_get_exception_ports");
    if (!fn) return KERN_FAILURE;
    return fn(task, exception_mask, masks, masks_count, old_handlers, old_behaviors, old_flavors);
}
#endif
"""

def apply_shims(path, src):
    need = "task_set_exception_ports" in src or "task_get_exception_ports" in src
    for sym, shim in (("task_set_exception_ports", TASK_SET_SHIM),
                      ("task_get_exception_ports", TASK_GET_SHIM)):
        if sym in src and ("madeira_tvos_" + sym) not in src:
            anchor = "#include <mach/mach.h>\n"
            if anchor in src:
                src = src.replace(anchor, anchor + shim, 1)
            else:
                # fallback: insert before the first function definition
                lines = src.split("\n")
                src_lines = lines
                # just guard with a #define at the very top so later uses resolve
                src = "/* madeira tvos shim */\n" + shim + src
            print("  patched %s in %s" % (sym, path))
    return src

# 1) Program.inc: wrap fork/switch in !TARGET_OS_TV
prog = os.path.join(unix_dir, "Program.inc")
if os.path.exists(prog):
    with open(prog, "r", encoding="utf-8") as f:
        src = f.read()
    if "TARGET_OS_TV" not in src:
        needle = "  // Create a child process.\n  int child = fork();"
        if needle in src:
            src = src.replace(needle,
                "#if !defined(TARGET_OS_TV) || !TARGET_OS_TV\n" + needle, 1)
            after = "  PI.Pid = child;\n  PI.Process = child;\n"
            if after in src:
                src = src.replace(after,
                    after + "#else\n  MakeErrMsg(ErrMsg, \"fork unavailable on tvOS\");\n  return false;\n#endif\n", 1)
                print("  patched fork/exec in Program.inc")
            else:
                print("  WARN: PI.Pid anchor missing in Program.inc")
        else:
            print("  WARN: fork anchor missing in Program.inc")
    with open(prog, "w", encoding="utf-8") as f:
        f.write(src)

# 2) Scan every .inc/.cpp under Unix/ for the exception-port helpers.
for fp in files:
    with open(fp, "r", encoding="utf-8") as f:
        src = f.read()
    new = apply_shims(fp, src)
    if new != src:
        with open(fp, "w", encoding="utf-8") as f:
            f.write(new)

print("done")