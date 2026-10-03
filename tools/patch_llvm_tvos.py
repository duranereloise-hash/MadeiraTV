#!/usr/bin/env python3
"""Patch LLVM Program.inc so fork/execv/execve do not compile on tvOS.

On Apple TV, fork()/execv()/execve() are marked unavailable and LLVM's
Unix Program.inc still compiles the fork-fallback branch even when
HAVE_POSIX_SPAWN is set (the posix_spawn path returns early, but the fork
code is not inside #else). Wrap it in !TARGET_OS_TV and return failure.
Usages in LLVM are all "run program in subprocess" (for tools like clang -cc1
or the test runner) -- dead on tvOS, where nothing can spawn processes.
"""
import re, sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

if "TARGET_OS_TV" in src:
    print("already patched")
    sys.exit(0)

needle = "  // Create a child process.\n  int child = fork();"
insert = (
    "#if !defined(TARGET_OS_TV) || !TARGET_OS_TV\n"
    "  // Create a child process.\n"
    "  int child = fork();"
)
if needle not in src:
    print("ERROR: cannot find fork block")
    sys.exit(1)
src = src.replace(needle, insert, 1)

# After the end of the fork switch (find the parent-wait break), insert
# the #else that keeps the fork code out of tvOS builds.
parent_anchor = "\n  // Parent process: Break out of the switch to do our processing."
if parent_anchor in src:
    src = src.replace(parent_anchor, "\n#else\n  MakeErrMsg(ErrMsg, \"fork unavailable on tvOS\");\n  return false;\n#endif" + parent_anchor, 1)
else:
    print("ERROR: cannot find parent anchor")
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("patched fork/exec out for tvOS")