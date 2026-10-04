#!/usr/bin/env python3
"""Patch LLVM Program.inc so fork/execv/execve do not compile on tvOS.

On Apple TV, fork()/execv()/execve() are marked unavailable and LLVM's
Unix Program.inc still compiles the fork-fallback branch even when
HAVE_POSIX_SPAWN is set (the posix_spawn path returns early, but the fork
code is not inside #else). Wrap the fork/switch block in !TARGET_OS_TV and
return failure on tvOS instead (LLVM never spawns subprocesses embedded on
Apple TV).
"""
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

if "TARGET_OS_TV" in src:
    print("already patched")
    sys.exit(0)

# Open the guard right before declaring the child process.
needle = "  // Create a child process.\n  int child = fork();"
repl = (
    "#if !defined(TARGET_OS_TV) || !TARGET_OS_TV\n"
    "  // Create a child process.\n"
    "  int child = fork();"
)
if needle not in src:
    print("ERROR: cannot find fork block")
    sys.exit(1)
src = src.replace(needle, repl, 1)

# Close the guard after the child PID is recorded, so the whole
# fork/switch/PI code is excluded on tvOS and the function returns false there.
after = "  PI.Pid = child;\n  PI.Process = child;\n"
close = (
    "  PI.Pid = child;\n"
    "  PI.Process = child;\n"
    "#else\n"
    "  MakeErrMsg(ErrMsg, \"fork unavailable on tvOS\");\n"
    "  return false;\n"
    "#endif\n"
)
if after not in src:
    print("ERROR: cannot find PI.Pid anchor")
    sys.exit(1)
src = src.replace(after, close, 1)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("patched fork/exec out for tvOS")

# Also patch Process.inc: task_set_exception_ports is TVOS_PROHIBITED in
# lib/Support/Unix/Process.inc (LLVM's crash reporter / profiling path).
import os
proc_inc = os.path.join(os.path.dirname(path), "Process.inc")
if os.path.exists(proc_inc):
    with open(proc_inc, "r", encoding="utf-8") as f:
        psrc = f.read()
    if "task_set_exception_ports" in psrc and "madeira_tvos_task_set_exception_ports" not in psrc:
        repl = (
            "#if defined(__APPLE__) && defined(TARGET_OS_TV) && TARGET_OS_TV\n"
            "#include <dlfcn.h>\n"
            "#define task_set_exception_ports madeira_tvos_task_set_exception_ports\n"
            "static inline kern_return_t madeira_tvos_task_set_exception_ports(\n"
            "    mach_port_t task, exception_mask_t exception_mask, mach_port_t new_port,\n"
            "    exception_behavior_t behavior, thread_state_flavor_t new_flavor)\n"
            "{\n"
            "    typedef kern_return_t (*fn_t)(mach_port_t, exception_mask_t, mach_port_t,\n"
            "                                  exception_behavior_t, thread_state_flavor_t);\n"
            "    static fn_t fn;\n"
            "    if (!fn) fn = (fn_t)dlsym(RTLD_DEFAULT, \"task_set_exception_ports\");\n"
            "    if (!fn) return KERN_FAILURE;\n"
            "    return fn(task, exception_mask, new_port, behavior, new_flavor);\n"
            "}\n"
            "#endif\n"
        )
        # Align the shim right below the mach includes.
        anchor = "#include <mach/mach.h>\n"
        if anchor in psrc:
            psrc = psrc.replace(anchor, anchor + repl, 1)
            with open(proc_inc, "w", encoding="utf-8") as f:
                f.write(psrc)
            print("patched task_set_exception_ports out for tvOS")
        else:
            print("WARN: mach/mach.h include not found in Process.inc")
    elif "madeira_tvos_task_set_exception_ports" in psrc:
        print("Process.inc already patched")
    else:
        print("Process.inc: no task_set_exception_ports reference")
else:
    print("WARN: Process.inc not found")