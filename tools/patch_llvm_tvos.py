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