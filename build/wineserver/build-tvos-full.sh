#!/bin/bash
# Full Wine server build for **tvOS** arm64. Unlike build.sh (which patches a
# prebuilt base archive), this compiles every server/*.c from scratch with the
# same flags/patches, then does the ws_* symbol-rename sweep. It is the
# reproducible form for CI.
set -e

BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$BUILD_DIR/../.." && pwd)"
WINE_SRC="$REPO_ROOT/wine"
SDK=$(xcrun --sdk appletvos --show-sdk-path)
APP_LIB="$REPO_ROOT/app/Madeira/libwineserver.a"
SHIMS_DIR="$REPO_ROOT/build/ntdll-unix/shims"
OBJ_DIR="$BUILD_DIR/obj-tvos"
mkdir -p "$OBJ_DIR"

CC_FLAGS=(
    -arch arm64 -isysroot "$SDK" -mtvos-version-min=17.0 -O2
    -I"$WINE_SRC/include" -I"$WINE_SRC/include/wine"
    -I"$WINE_SRC/build-macos/include"
    -I"$BUILD_DIR" -I"$WINE_SRC/server"
    -I"$SHIMS_DIR"
    -I"$BUILD_DIR/../madsync" -DHAVE_LINUX_NTSYNC_H=1
    -include "$BUILD_DIR/config_ios.h"
    -include stdarg.h
    -include "$BUILD_DIR/unicode_fix.h"
    -include "$BUILD_DIR/wineserver_ios_kill.h"
    -DBINDIR=\"/usr/local/bin\" -DDATADIR=\"/usr/local/share\"
    -D__WINESRC__ -DWINE_IOS=1
    -Dmain=wineserver_main
    -Wno-implicit-function-declaration
)

compile_one() {
    local src=$1 name=$2
    echo -n "  $name... "
    if xcrun -sdk appletvos clang "${CC_FLAGS[@]}" -c "$src" -o "$OBJ_DIR/$name.o" 2>"$OBJ_DIR/err-$name.txt"; then
        echo "OK"
    else
        echo "FAILED (see $OBJ_DIR/err-$name.txt)"
        tail -15 "$OBJ_DIR/err-$name.txt"
        return 1
    fi
}

echo "=== Compiling Wine server for tvOS ==="

# All upstream server source files.
for src in "$WINE_SRC"/server/*.c; do
    base=$(basename "$src" .c)
    # Upstream main.c -> main_ios.c override (keeps wineserver_main entry).
    case "$base" in
        main)   compile_one "$BUILD_DIR/main_ios.c" "$base" ;;
        request) compile_one "$BUILD_DIR/request_ios.c" "$base" ;;
        mach)   compile_one "$BUILD_DIR/mach_ios.c" "$base" ;;
        unicode) compile_one "$BUILD_DIR/unicode_ios.c" "$base" ;;
        fd)     compile_one "$BUILD_DIR/fd_ios.c" "$base" ;;
        window) compile_one "$BUILD_DIR/window_ios.c" "$base" ;;
        mapping) compile_one "$BUILD_DIR/mapping_ios.c" "$base" ;;
        queue)  compile_one "$BUILD_DIR/queue_ios.c" "$base" ;;
        *)      compile_one "$src" "$base" ;;
    esac
done

# Extra contributed objects.
compile_one "$BUILD_DIR/wine_log_ios.c" "wine_log_ios" || true
compile_one "$BUILD_DIR/wineserver_ios_kill.c" "wineserver_ios_kill" || true
compile_one "$BUILD_DIR/wineserver_missing.c" "wineserver_missing" || true

# Fail if any object is missing.
objs=()
while IFS= read -r f; do objs+=("$f"); done < <(find "$OBJ_DIR" -maxdepth 1 -name "*.o" | sort)
echo "=== objects: ${#objs[@]} ==="

echo "=== Building libwineserver.a ==="
rm -f "$OBJ_DIR/libwineserver.a"
ar rcs "$OBJ_DIR/libwineserver.a" "$OBJ_DIR"/*.o

echo "=== Renaming colliding symbols (objcopy sweep) ==="
OBJCOPY=$(command -v llvm-objcopy || echo /opt/homebrew/opt/llvm/bin/llvm-objcopy)
[ -x "$OBJCOPY" ] || OBJCOPY=/opt/homebrew/Cellar/llvm/22.1.0/bin/llvm-objcopy
COLLISIONS=(
    alloc_user_handle free_user_handle get_virtual_screen_rect
    destroy_thread_windows get_window_thread is_desktop_class
    is_message_class is_window_visible mirror_region send_notify_message
    shared_session user_shared_data
)
RENAME_ARGS=()
for s in "${COLLISIONS[@]}"; do
    RENAME_ARGS+=(--redefine-sym "_${s}=_ws_${s}")
done
TMP_RENAME_DIR="$OBJ_DIR/rename"
rm -rf "$TMP_RENAME_DIR" && mkdir -p "$TMP_RENAME_DIR"
(cd "$TMP_RENAME_DIR" && ar x "$OBJ_DIR/libwineserver.a")
for f in "$TMP_RENAME_DIR"/*.o; do
    "$OBJCOPY" "${RENAME_ARGS[@]}" "$f"
done
rm "$OBJ_DIR/libwineserver.a"
ar rcs "$OBJ_DIR/libwineserver.a" "$TMP_RENAME_DIR"/*.o
rm -rf "$TMP_RENAME_DIR"
echo "  symbol rename + repack OK"

echo "Copying to app..."
cp "$OBJ_DIR/libwineserver.a" "$APP_LIB"
echo "Done! libwineserver.a: $(wc -c < "$APP_LIB" | tr -d ' ') bytes"