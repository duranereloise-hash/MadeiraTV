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
    -DCMAKE_SYSTEM_NAME=tvOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_SYSROOT="$(xcrun --sdk appletvos --show-sdk-path)" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_HOST_TRIPLE=arm64-apple-tvos17.0 \
    -DLLVM_DEFAULT_TARGET_TRIPLE=arm64-apple-tvos17.0 \
    -DLLVM_TARGET_ARCH=host \
    -DLLVM_TARGETS_TO_BUILD= \
    -DLLVM_ENABLE_PROJECTS= \
    -DLLVM_BUILD_TOOLS=Off \
    -DLLVM_INCLUDE_TESTS=Off \
    -DLLVM_ENABLE_ZLIB=Off

echo "=== building LLVM (tvOS) ==="
cmake --build . -j$(sysctl -n hw.ncpu) 2>&1 | tail -20

echo "=== result ==="
ls -la lib/libLLVM* 2>/dev/null | head
echo "LLVM_BUILD=$LLVM_BUILD"