#!/usr/bin/env python3
"""Patch DXMT winemetal_unix.c for tvOS.

tvOS sets TARGET_OS_IOS=0, so DXMT's #if TARGET_OS_IOS branches (UIKit,
no-ColorSync, etc) lose and the Cocoa/ColorSync macOS paths compile —
Cocoa/Cocoa.h is unavailable on tvOS. Rewrite the guards so tvOS is treated
like iOS (Apple TV uses UIKit, has no Cocoa, no ColorSync).
"""
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# Guard against double-application.
if "TARGET_OS_TV" in src.replace("TARGET_OS_TVOS", ""):
    print("winemetal_unix.c already patched")
    sys.exit(0)

orig = src

# ... (iOS-rewrite of guards)
import re
src = re.sub(r"#if\s+(!?)\s*TARGET_OS_IOS\b",
             lambda m: "#if %s(TARGET_OS_IOS || TARGET_OS_TV)" % m.group(1), src)

# CAMetalLayer.wantsExtendedDynamicRangeContent does not exist on tvOS;
# guard the three places that touch it so tvOS builds skip the property.
# 1) assignment in _MetalLayer_setColorSpace
src = src.replace(
    "layer.wantsExtendedDynamicRangeContent = WMT_COLORSPACE_IS_HDR(colorspace);",
    "#if !TARGET_OS_TV\n    layer.wantsExtendedDynamicRangeContent = WMT_COLORSPACE_IS_HDR(colorspace);\n#endif", 1)
# 2&3) ternary reads near maximumExtendedDynamicRangeColorComponentValue
src = re.sub(
    r"(layer\.wantsExtendedDynamicRangeContent \? screen\.maximumExtendedDynamicRangeColorComponentValue : 1\.0;)",
    r"#if !TARGET_OS_TV\n  \1\n#else\n  1.0\n#endif", src)

if src != orig:
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("patched TARGET_OS_IOS -> (TARGET_OS_IOS || TARGET_OS_TV) + EDR guards")
else:
    print("no changes; maybe already patched differently")
    sys.exit(0)