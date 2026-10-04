#!/bin/bash
# Build LLVM (headers + static libs) for **tvOS** arm64 — needed by DXMT's
# airconv (DXBC->IR compiler). Mirrors the iOS recipe from BUILDING.md with
# the sysroot swapped to appletvos. The full LLVM build is heavy (~30-60min);
# we only need libLLVM + a few tools airconv links against.
#
# Recipe (from docs/BUILDING.md, iOS form):
#   cmake -S llvm-project/llvm -B llvm-tvos-build \
#     -DCMAKE_SYSTEM_NAME=tvOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
#     -DCMAKE_OSX_SYSROOT=appletvos -DCMAKE_BUILD_TYPE=Release \
#     -DLLVM_HOST_TRIPLE=arm64-apple-tvos17.0 \
#     -DLLVM_DEFAULT_TARGET_TRIPLE=arm64-apple-tvos17.0 \
#     -DLLVM_TARGET_ARCH=host -DLLVM_TARGETS_TO_BUILD= \
#     -DLLVM_ENABLE_PROJECTS= -DLLVM_BUILD_TOOLS=Off \
#     -DLLVM_INCLUDE_TESTS=Off -DLLVM_ENABLE_ZLIB=Off
set -e

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$BUILD_DIR/../.." && pwd)"
LLVM_SRC="$REPO_ROOT/toolchains/llvm-project"
LLVM_BUILD="$REPO_ROOT/toolchains/llvm-tvos-build"
LLVM_VERSION=18

if [ ! -d "$LLVM_SRC/llvm" ]; then
    echo "=== cloning llvm-project (release/$LLVM_VERSION) ==="
    mkdir -p "$REPO_ROOT/toolchains"
    git clone --depth 1 --branch "release/$LLVM_VERSION.x" \
        https://github.com/llvm/llvm-project.git "$LLVM_SRC" 2>&1 | tail -3
fi

mkdir -p "$LLVM_BUILD"
cd "$LLVM_BUILD"
cmake -S "$LLVM_SRC/llvm" -B . \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_OSX_SYSROOT="$(xcrun --sdk appletvos --show-sdk-path)" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_TABLEGEN="$HOST_BUILD/bin/llvm-tblgen" \
    -DLLVM_TARGETS_TO_BUILD="AArch64" \
    -DLLVM_ENABLE_PROJECTS="" \
    -DLLVM_BUILD_TOOLS=Off \
    -DLLVM_BUILD_UTILS=Off \
    -DLLVM_INSTALL_UTILS=Off \
    -DLLVM_BUILD_LLVM_DYLIB=Off \
    -DLLVM_INCLUDE_TESTS=Off \
    -DLLVM_INCLUDE_BENCHMARKS=Off \
    -DLLVM_INCLUDE_EXAMPLES=Off \
    -DLLVM_ENABLE_ZLIB=Off \
    -DLLVM_ENABLE_ZSTD=Off \
    -DLLVM_ENABLE_TERMINFO=Off \
    -DLLVM_NATIVE_ARCH=AArch64 2>&1 | tail -30

echo "=== building LLVM (tvOS) ==="
# fork()/execv/execve and task_{set,get}_exception_ports are TVOS_PROHIBITED;
# patch the Unix support sources so they do not break the build on tvOS.
python3 "$REPO_ROOT/tools/patch_llvm_tvos.py" "$LLVM_SRC/llvm/lib/Support/Unix" || true
# 'llvm-libs' target does not exist in this configuration; the default target
# builds every static library (tools/tests are off).
cmake --build . -j$(sysctl -n hw.ncpu) 2>&1 | tail -25

echo "=== result ==="
ls -la lib/libLLVM* 2>/dev/null | head
echo "LLVM_BUILD=$LLVM_BUILD"