#!/bin/bash
# Build freetype static for **tvOS** arm64 — consumed by build/ntdll-unix
# build.sh (dwrite_unixlib) and win32u-unix. Same recipe as build.sh (iOS),
# but builds from the tracked tarball instead of research/freetype clone.
# Output prefix: toolchains/freetype-tvos/.
set -e

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$BUILD_DIR/../.." && pwd)"
SRC_DIR="$BUILD_DIR/src"
OBJ_DIR="$BUILD_DIR/obj-tvos"
PREFIX="$REPO_ROOT/toolchains/freetype-tvos"

FREETYPE_VER=2.13.3
TARBALL="$SRC_DIR/freetype-${FREETYPE_VER}.tar.gz"
SRC="$OBJ_DIR/freetype-${FREETYPE_VER}"

mkdir -p "$OBJ_DIR" "$PREFIX"

if [ ! -f "$TARBALL" ]; then
    echo "missing $TARBALL (tracked; checkout incomplete?)" >&2
    exit 1
fi
if [ ! -d "$SRC" ]; then
    echo "=== extracting freetype-$FREETYPE_VER ==="
    mkdir -p "$OBJ_DIR"
    tar -C "$OBJ_DIR" -xzf "$TARBALL"
    # tarball root dir is freetype-VER-2-13-3
    if [ ! -d "$SRC" ] && [ -d "$OBJ_DIR/freetype-VER-2-13-3" ]; then
        mv "$OBJ_DIR/freetype-VER-2-13-3" "$SRC"
    fi
fi

cmake -S "$SRC" -B "$BUILD_DIR/build-tvos" -G "Unix Makefiles" \
  -DCMAKE_SYSTEM_NAME=tvOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_OSX_SYSROOT="$(xcrun --sdk appletvos --show-sdk-path)" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DFT_DISABLE_ZLIB=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON \
  -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON \
  -DCMAKE_C_FLAGS="-fno-stack-protector"

cmake --build "$BUILD_DIR/build-tvos" -j8
cmake --install "$BUILD_DIR/build-tvos"
# FreeType installs ft2build.h under include/freetype2/; expose it at the
# include root too so `-I$PREFIX/include` finds it (Wine does #include <ft2build.h>).
if [ -f "$PREFIX/include/freetype2/ft2build.h" ] && [ ! -e "$PREFIX/include/ft2build.h" ]; then
    ln -s freetype2/ft2build.h "$PREFIX/include/ft2build.h"
fi
echo "Done: $PREFIX/lib/libfreetype.a"
ls -la "$PREFIX/lib/"*.a