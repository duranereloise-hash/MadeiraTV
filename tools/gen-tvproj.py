# Generates MadeiraTV.xcodeproj for tvOS (Phase 1: portable Swift-only shell).
import os, uuid

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..'))
APP_SRC = os.path.join(ROOT, 'app', 'Madeira')
TV_SRC = os.path.join(ROOT, 'app', 'MadeiraTV')

def uid(seed):
    return 'A' + uuid.uuid5(uuid.NAMESPACE_DNS, seed).hex[:23].upper()

# Portable SwiftSteam files (Foundation-only; no UIKit/AppKit, no C/Wine calls).
portable = [
    'SwiftSteam/Auth/SteamAuthAPI.swift',
    'SwiftSteam/Auth/SteamCredentialAuth.swift',
    'SwiftSteam/Auth/SteamTokenStore.swift',
    'SwiftSteam/Content/ContentDecryptor.swift',
    'SwiftSteam/Content/DepotDownloader.swift',
    'SwiftSteam/Content/DepotManifest.swift',
    'SwiftSteam/Core/CMServerList.swift',
    'SwiftSteam/Core/LicenseListBox.swift',
    'SwiftSteam/Core/SteamCMSession.swift',
    'SwiftSteam/Core/SteamConnection.swift',
    'SwiftSteam/Core/SteamError.swift',
    'SwiftSteam/Core/SteamMessageCodec.swift',
    'SwiftSteam/Core/SteamProtocol.swift',
    'SwiftSteam/Core/SteamSession.swift',
    'SwiftSteam/Helpers/SteamLog.swift',
    'SwiftSteam/Helpers/SteamDevice.swift',
    'SwiftSteam/Auth/SteamQRAuth.swift',
    'SwiftSteam/Install/AppManifestWriter.swift',
    'SwiftSteam/Library/SteamAppInfo.swift',
    'SwiftSteam/Library/SteamLibraryFetcher.swift',
    'SwiftSteam/Proto/SteamProtoMessages.swift',
    'SwiftSteam/SteamSignIn.swift',
    'MadeiraConfig.swift',
    'SteamKeyValues.swift',
    'SteamInstall.swift',
]

# C shims used by ContentDecryptor (chunk_zip/lzma/zstd). chunk_zip.c needs zlib.
winios_sources = [
    ('Winios/Winios.m', 'sourcecode.c.objc'),
    ('Winios/WiniosCursor.c', 'sourcecode.c.c'),
    ('Winios/WiniosGamepad.c', 'sourcecode.c.c'),
]
# Platform integration bridges (ObjC/ObjC++/C) — same set the iOS app links.
platform_objc_sources = [
    ('IOSDisplayShim.m', 'sourcecode.c.objc'),
    ('WineServerBridge.m', 'sourcecode.c.objc'),
    ('WineProcessBridge.m', 'sourcecode.c.objc'),
]
platform_mm_sources = [
    ('FEXBridge.mm', 'sourcecode.cpp.objcpp'),
]
platform_c_sources = [
    ('JITAllocator.c', 'sourcecode.c.c'),
    ('PrefixExtractor.c', 'sourcecode.c.c'),
    ('wine_stubs.c', 'sourcecode.c.c'),
]
# SoftFloat-3e internals that FEX's vendored copy does not build (F16 helpers,
# f128 mulAdd, roundToUI32) but libFEXCore's thinlto objects reference.
softfloat_fix_sources = [
    ('SoftFloat/s_commonNaNToF16UI.c', 'sourcecode.c.c'),
    ('SoftFloat/s_roundPackToF16.c', 'sourcecode.c.c'),
    ('SoftFloat/s_roundToUI32.c', 'sourcecode.c.c'),
    ('SoftFloat/s_mulAddF128.c', 'sourcecode.c.c'),
]
platform_mm_sources = [
    ('FEXBridge.mm', 'sourcecode.cpp.objcpp'),
    ('MadeiraIntegrations.mm', 'sourcecode.cpp.objcpp'),
]
c_files = [
    ('SwiftSteam/chunk_zip.c', 'sourcecode.c.c'),
    ('SwiftSteam/lzma_shim.c', 'sourcecode.c.c'),
    ('SwiftSteam/zstd_edu.c', 'sourcecode.c.c'),
]

tv_files = [
    'MadeiraTVApp.swift',
    'TVSessionModel.swift',
    'LogStore.swift',
]

# Verify all referenced files exist.
all_src = [os.path.join(APP_SRC, f) for f in portable] + [os.path.join(TV_SRC, f) for f in tv_files]
all_src += [os.path.join(APP_SRC, f) for f, _ in c_files]
all_src += [os.path.join(APP_SRC, f) for f, _ in winios_sources]
all_src += [os.path.join(APP_SRC, f) for f, _ in platform_objc_sources]
all_src += [os.path.join(APP_SRC, f) for f, _ in platform_mm_sources]
all_src += [os.path.join(APP_SRC, f) for f, _ in platform_c_sources]
missing = [f for f in all_src if not os.path.exists(f)]
if missing:
    for m in missing:
        print(f'MISSING: {m}')
    raise SystemExit(f'{len(missing)} missing files')

# Build pbxproj.
proj = []
proj.append('// !$*UTF8*$!')
proj.append('{')
proj.append('\tarchiveVersion = 1;')
proj.append('\tclasses = {')
proj.append('\t};')
proj.append('\tobjectVersion = 56;')
proj.append('\tobjects = {')

# --- PBXBuildFile ---
proj.append('\n/* Begin PBXBuildFile section */')
build_files = {}
file_refs = {}
libz_bf = uid('bf-libz')
libz_fr = uid('fr-libz')
proj.append(f'\t\t{libz_bf} /* libz.tbd in Frameworks */ = {{isa = PBXBuildFile; fileRef = {libz_fr} /* libz.tbd */; }};')
liblzma_bf = uid('bf-liblzma')
liblzma_fr = uid('fr-liblzma')
proj.append(f'\t\t{liblzma_bf} /* liblzma.tbd in Frameworks */ = {{isa = PBXBuildFile; fileRef = {liblzma_fr} /* liblzma.tbd */; }};')


# Static libraries built by the Phase 2 toolchain, staged in app/Madeira/.
static_libs = [
    'libntdll_unix.a', 'libwineserver.a', 'libwin32u_unix.a',
    'libdxmt_combined_tvos.a', 'libllvm_tvos.a',
    'libFEXCore.a', 'libFEXCore_Base.a',
    'libfmt.a', 'libcephes_128bit.a', 'libxxhash.a', 'libsoftfloat_3e.a',
    'libgnutls.a', 'libhogweed.a', 'libnettle.a', 'libgmp.a',
    'libfreetype.a',
    'libavformat.a', 'libavcodec.a', 'libswresample.a', 'libavutil.a',
]
static_bf = {}
static_fr = {}
for lib in static_libs:
    bf = uid('bf-lib-' + lib)
    fr = uid('fr-lib-' + lib)
    static_bf[lib] = bf
    static_fr[lib] = fr
    proj.append(f'\t\t{bf} /* {lib} in Frameworks */ = {{isa = PBXBuildFile; fileRef = {fr} /* {lib} */; }};')

for f in portable:
    name = os.path.basename(f)
    bf = uid('bf-' + f)
    fr = uid('fr-' + f)
    build_files[f] = bf
    file_refs[f] = fr
    proj.append(f'\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};')
for f in tv_files:
    bf = uid('bf-tv-' + f)
    fr = uid('fr-tv-' + f)
    build_files[f] = bf
    file_refs[f] = fr
    proj.append(f'\t\t{bf} /* {f} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {f} */; }};')
for f, _ in c_files:
    name = os.path.basename(f)
    bf = uid('bf-c-' + f)
    fr = uid('fr-c-' + f)
    build_files[f] = bf
    file_refs[f] = fr
    proj.append(f'\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};')
assets_build = uid('bf-assets')
assets_ref = uid('fr-assets')
proj.append(f'\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};')
proj.append('/* End PBXBuildFile section */')
for f, lft in winios_sources:
    name = os.path.basename(f)
    wbf = uid('bf-w-' + f)
    wfr = uid('fr-w-' + f)
    build_files['w_' + f] = wbf
    file_refs['w_' + f] = wfr
    proj.append(f'\t\t{wbf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {wfr} /* {name} */; }};')

for f, lft in platform_objc_sources + platform_mm_sources + platform_c_sources + softfloat_fix_sources:
    name = os.path.basename(f)
    pbf = uid('bf-p-' + f)
    pfr = uid('fr-p-' + f)
    build_files['p_' + f] = pbf
    file_refs['p_' + f] = pfr
    proj.append(f'\t\t{pbf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {pfr} /* {name} */; }};')


# --- PBXFileReference ---
proj.append('\n/* Begin PBXFileReference section */')
for f in portable:
    name = os.path.basename(f)
    fr = file_refs[f]
    # Inside group Madeira (path=Madeira, i.e. app/Madeira), so relative to it.
    proj.append(f'\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = "{name}"; path = "{f}"; sourceTree = "<group>"; }};')
for f in tv_files:
    fr = file_refs[f]
    proj.append(f'\t\t{fr} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{f}"; sourceTree = "<group>"; }};')
for f, lft in c_files:
    name = os.path.basename(f)
    fr = file_refs[f]
    proj.append(f'\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {lft}; name = "{name}"; path = "{f}"; sourceTree = "<group>"; }};')
proj.append(f'\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};')
info_ref = uid('fr-info')
proj.append(f'\t\t{info_ref} /* Info-TVP.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info-TVP.plist; sourceTree = "<group>"; }};')
product_ref = uid('fr-app')
proj.append(f'\t\t{product_ref} /* MadeiraTV.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MadeiraTV.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
proj.append(f'\t\t{libz_fr} /* libz.tbd */ = {{isa = PBXFileReference; lastKnownFileType = "sourcecode.text-based-dylib-definition"; name = libz.tbd; path = usr/lib/libz.tbd; sourceTree = SDKROOT; }};')
proj.append(f'\t\t{liblzma_fr} /* liblzma.tbd */ = {{isa = PBXFileReference; lastKnownFileType = "sourcecode.text-based-dylib-definition"; name = liblzma.tbd; path = usr/lib/liblzma.tbd; sourceTree = SDKROOT; }};')
for lib in static_libs:
    fr = static_fr[lib]
    proj.append(f'\t\t{fr} /* {lib} */ = {{isa = PBXFileReference; lastKnownFileType = archive.ar; name = "{lib}"; path = "Madeira/{lib}"; sourceTree = "<group>"; }};')
proj.append('/* End PBXFileReference section */')
for f, lft in winios_sources:
    name = os.path.basename(f)
    wfr = file_refs['w_' + f]
    proj.append(f'\t\t{wfr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {lft}; name = "{name}"; path = "{f}"; sourceTree = "<group>"; }};')
for f, lft in platform_objc_sources + platform_mm_sources + platform_c_sources + softfloat_fix_sources:
    name = os.path.basename(f)
    pfr = file_refs['p_' + f]
    proj.append(f'\t\t{pfr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {lft}; name = "{name}"; path = "{f}"; sourceTree = "<group>"; }};')


# --- PBXFrameworksBuildPhase ---
frameworks_phase = uid('phase-fw')
proj.append('\n/* Begin PBXFrameworksBuildPhase section */')
proj.append(f'\t\t{frameworks_phase} /* Frameworks */ = {{')
proj.append('\t\t\tisa = PBXFrameworksBuildPhase;')
proj.append('\t\t\tbuildActionMask = 2147483647;')
proj.append('\t\t\tfiles = (')
proj.append(f'\t\t\t\t{libz_bf} /* libz.tbd in Frameworks */,')
proj.append(f'\t\t\t\t{liblzma_bf} /* liblzma.tbd in Frameworks */,')
for lib in static_libs:
    proj.append(f'\t\t\t\t{static_bf[lib]} /* {lib} in Frameworks */,')
proj.append('\t\t\t);')
proj.append('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
proj.append('\t\t};')
proj.append('/* End PBXFrameworksBuildPhase section */')

# --- PBXGroup ---
main_group = uid('grp-main')
grp_root = uid('grp-root')
grp_madeira = uid('grp-madeira')
grp_tv = uid('grp-tv')
grp_products = uid('grp-products')

proj.append('\n/* Begin PBXGroup section */')
proj.append(f'\t\t{main_group} = {{')
proj.append('\t\t\tisa = PBXGroup;')
proj.append('\t\t\tchildren = (')
proj.append(f'\t\t\t\t{grp_madeira} /* Madeira */,')
proj.append(f'\t\t\t\t{grp_tv} /* MadeiraTV */,')
proj.append(f'\t\t\t\t{grp_products} /* Products */,')
proj.append('\t\t\t);')
proj.append('\t\t\tsourceTree = "<group>";')
proj.append('\t\t};')

proj.append(f'\t\t{grp_madeira} /* Madeira */ = {{')
proj.append('\t\t\tisa = PBXGroup;')
proj.append('\t\t\tchildren = (')
for f in portable:
    name = os.path.basename(f)
    proj.append(f'\t\t\t\t{file_refs[f]} /* {name} */,')
for f, _ in c_files:
    name = os.path.basename(f)
    proj.append(f'\t\t\t\t{file_refs[f]} /* {name} */,')
for f, _ in winios_sources:
    name = os.path.basename(f)
    proj.append(f'\t\t\t\t{file_refs["w_" + f]} /* {name} */,')
for f, _ in platform_objc_sources + platform_mm_sources + platform_c_sources + softfloat_fix_sources:
    name = os.path.basename(f)
    proj.append(f'\t\t\t\t{file_refs["p_" + f]} /* {name} */,')
proj.append('\t\t\t);')
proj.append('\t\t\tpath = Madeira;')
proj.append('\t\t\tsourceTree = "<group>";')
proj.append('\t\t};')

proj.append(f'\t\t{grp_tv} /* MadeiraTV */ = {{')
proj.append('\t\t\tisa = PBXGroup;')
proj.append('\t\t\tchildren = (')
for f in tv_files:
    proj.append(f'\t\t\t\t{file_refs[f]} /* {f} */,')
proj.append(f'\t\t\t\t{assets_ref} /* Assets.xcassets */,')
proj.append(f'\t\t\t\t{info_ref} /* Info-TVP.plist */,')
proj.append('\t\t\t);')
proj.append('\t\t\tpath = MadeiraTV;')
proj.append('\t\t\tsourceTree = "<group>";')
proj.append('\t\t};')

proj.append(f'\t\t{grp_products} /* Products */ = {{')
proj.append('\t\t\tisa = PBXGroup;')
proj.append('\t\t\tchildren = (')
proj.append(f'\t\t\t\t{product_ref} /* MadeiraTV.app */,')
proj.append('\t\t\t);')
proj.append('\t\t\tname = Products;')
proj.append('\t\t\tsourceTree = "<group>";')
proj.append('\t\t};')
proj.append('/* End PBXGroup section */')

# --- PBXNativeTarget ---
native_target = uid('target')
proj.append('\n/* Begin PBXNativeTarget section */')
proj.append(f'\t\t{native_target} /* MadeiraTV */ = {{')
proj.append('\t\t\tisa = PBXNativeTarget;')
proj.append(f'\t\t\tbuildConfigurationList = {uid("clist-target")} /* Build configuration list for PBXNativeTarget "MadeiraTV" */;')
proj.append('\t\t\tbuildPhases = (')
proj.append(f'\t\t\t\t{sources_phase_id if False else None}',)  # placeholder not used
proj.pop()
sources_phase = uid('phase-src')
proj.append(f'\t\t\t\t{sources_phase} /* Sources */,')
proj.append(f'\t\t\t\t{frameworks_phase} /* Frameworks */,')
resources_phase = uid('phase-res')
proj.append(f'\t\t\t\t{resources_phase} /* Resources */,')
proj.append('\t\t\t);')
proj.append('\t\t\tbuildRules = (')
proj.append('\t\t\t);')
proj.append('\t\t\tdependencies = (')
proj.append('\t\t\t);')
proj.append('\t\t\tname = MadeiraTV;')
proj.append('\t\t\tproductName = MadeiraTV;')
proj.append(f'\t\t\tproductReference = {product_ref} /* MadeiraTV.app */;')
proj.append('\t\t\tproductType = "com.apple.product-type.application";')
proj.append('\t\t};')
proj.append('/* End PBXNativeTarget section */')

# --- PBXProject ---
proj_obj = uid('proj')
proj.append('\n/* Begin PBXProject section */')
proj.append(f'\t\t{proj_obj} /* Project object */ = {{')
proj.append('\t\t\tisa = PBXProject;')
proj.append('\t\t\tattributes = {')
proj.append('\t\t\t\tBuildIndependentTargetsInParallel = 1;')
proj.append('\t\t\t\tLastSwiftUpdateCheck = 1600;')
proj.append('\t\t\t\tLastUpgradeCheck = 1600;')
proj.append('\t\t\t\tTargetAttributes = {')
proj.append(f'\t\t\t\t\t{native_target} = {{')
proj.append('\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;')
proj.append('\t\t\t\t\t};')
proj.append('\t\t\t\t};')
proj.append('\t\t\t};')
proj.append(f'\t\t\tbuildConfigurationList = {uid("clist-proj")} /* Build configuration list for PBXProject "MadeiraTV" */;')
proj.append('\t\t\tcompatibilityVersion = "Xcode 14.0";')
proj.append('\t\t\tdevelopmentRegion = en;')
proj.append('\t\t\thasScannedForEncodings = 0;')
proj.append('\t\t\tknownRegions = (')
proj.append('\t\t\t\ten,')
proj.append('\t\t\t\tBase,')
proj.append('\t\t\t);')
proj.append(f'\t\t\tmainGroup = {main_group};')
proj.append(f'\t\t\tproductRefGroup = {grp_products} /* Products */;')
proj.append('\t\t\tprojectDirPath = "";')
proj.append('\t\t\tprojectRoot = "";')
proj.append('\t\t\ttargets = (')
proj.append(f'\t\t\t\t{native_target} /* MadeiraTV */,')
proj.append('\t\t\t);')
proj.append('\t\t};')
proj.append('/* End PBXProject section */')

# --- PBXResourcesBuildPhase ---
proj.append('\n/* Begin PBXResourcesBuildPhase section */')
proj.append(f'\t\t{resources_phase} /* Resources */ = {{')
proj.append('\t\t\tisa = PBXResourcesBuildPhase;')
proj.append('\t\t\tbuildActionMask = 2147483647;')
proj.append('\t\t\tfiles = (')
proj.append(f'\t\t\t\t{assets_build} /* Assets.xcassets in Resources */,')
proj.append('\t\t\t);')
proj.append('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
proj.append('\t\t};')
proj.append('/* End PBXResourcesBuildPhase section */')

# --- PBXSourcesBuildPhase ---
proj.append('\n/* Begin PBXSourcesBuildPhase section */')
proj.append(f'\t\t{sources_phase} /* Sources */ = {{')
proj.append('\t\t\tisa = PBXSourcesBuildPhase;')
proj.append('\t\t\tbuildActionMask = 2147483647;')
proj.append('\t\t\tfiles = (')
for f in portable:
    name = os.path.basename(f)
    proj.append(f'\t\t\t\t{build_files[f]} /* {name} in Sources */,')
for f in tv_files:
    proj.append(f'\t\t\t\t{build_files[f]} /* {f} in Sources */,')
for f, _ in c_files:
    name = os.path.basename(f)
    proj.append(f'\t\t\t\t{build_files[f]} /* {name} in Sources */,')

for f, lft in winios_sources:
    name = os.path.basename(f)
    proj.append(f'\t\t\t\t{build_files["w_" + f]} /* {name} in Sources */,')
for f, lft in platform_objc_sources + platform_mm_sources + platform_c_sources + softfloat_fix_sources:
    name = os.path.basename(f)
    proj.append(f'\t\t\t\t{build_files["p_" + f]} /* {name} in Sources */,')
proj.append('\t\t\t);')
proj.append('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
proj.append('\t\t};')
proj.append('/* End PBXSourcesBuildPhase section */')

# --- XCBuildConfiguration ---
proj.append('\n/* Begin XCBuildConfiguration section */')
# Project-level Debug
cfg_proj_debug = uid('cfg-proj-debug')
proj.append(f'\t\t{cfg_proj_debug} /* Debug */ = {{')
proj.append('\t\t\tisa = XCBuildConfiguration;')
proj.append('\t\t\tbuildSettings = {')
proj.append('\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;')
proj.append('\t\t\t\tCLANG_ANALYZER_NONNULL = YES;')
proj.append('\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";')
proj.append('\t\t\t\tCLANG_ENABLE_MODULES = YES;')
proj.append('\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;')
proj.append('\t\t\t\tCOPY_PHASE_STRIP = NO;')
proj.append('\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;')
proj.append('\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;')
proj.append('\t\t\t\tENABLE_TESTABILITY = YES;')
proj.append('\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;')
proj.append('\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;')
proj.append('\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;')
proj.append('\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (')
proj.append('\t\t\t\t\t"DEBUG=1",')
proj.append('\t\t\t\t\t"FEXCORE_PRESERVE_ALL_ATTR=",')
proj.append('\t\t\t\t\t"$(inherited)",')
proj.append('\t\t\t\t);')
proj.append('\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;')
proj.append('\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;')
proj.append('\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;')
proj.append('\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;')
proj.append('\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;')
proj.append('\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;')
proj.append('\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;')
proj.append('\t\t\t\tMTL_FAST_MATH = YES;')
proj.append('\t\t\t\tONLY_ACTIVE_ARCH = YES;')
proj.append('\t\t\t\tSDKROOT = appletvos;')
proj.append('\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";')
proj.append('\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";')
proj.append('\t\t\t\tTVOS_DEPLOYMENT_TARGET = 17.0;')
proj.append('\t\t\t};')
proj.append('\t\t\tname = Debug;')
proj.append('\t\t};')
# Project-level Release
cfg_proj_rel = uid('cfg-proj-rel')
proj.append(f'\t\t{cfg_proj_rel} /* Release */ = {{')
proj.append('\t\t\tisa = XCBuildConfiguration;')
proj.append('\t\t\tbuildSettings = {')
proj.append('\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;')
proj.append('\t\t\t\tCLANG_ANALYZER_NONNULL = YES;')
proj.append('\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";')
proj.append('\t\t\t\tCLANG_ENABLE_MODULES = YES;')
proj.append('\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;')
proj.append('\t\t\t\tCOPY_PHASE_STRIP = NO;')
proj.append('\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
proj.append('\t\t\t\tENABLE_NS_ASSERTIONS = NO;')
proj.append('\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;')
proj.append('\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;')
proj.append('\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;')
proj.append('\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;')
proj.append('\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;')
proj.append('\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;')
proj.append('\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;')
proj.append('\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;')
proj.append('\t\t\t\tMTL_FAST_MATH = YES;')
proj.append('\t\t\t\tSDKROOT = appletvos;')
proj.append('\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;')
proj.append('\t\t\t\tTVOS_DEPLOYMENT_TARGET = 17.0;')
proj.append('\t\t\t\tVALIDATE_PRODUCT = YES;')
proj.append('\t\t\t};')
proj.append('\t\t\tname = Release;')
proj.append('\t\t};')
# Target-level Debug
cfg_target_debug = uid('cfg-target-debug')
proj.append(f'\t\t{cfg_target_debug} /* Debug */ = {{')
proj.append('\t\t\tisa = XCBuildConfiguration;')
proj.append('\t\t\tbuildSettings = {')
proj.append('\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;')
proj.append('\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;')
proj.append('\t\t\t\tCODE_SIGN_STYLE = Automatic;')
proj.append('\t\t\t\tCURRENT_PROJECT_VERSION = 1;')
proj.append('\t\t\t\tGENERATE_INFOPLIST_FILE = NO;')
proj.append('\t\t\t\tINFOPLIST_FILE = MadeiraTV/Info-TVP.plist;')
proj.append('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");')
proj.append('\t\t\t\tMARKETING_VERSION = 0.1.0;')
proj.append('\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.madeira.tvos;')
proj.append('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
proj.append('\t\t\t\tOTHER_LDFLAGS = ("$(inherited)", "-force_load \\"$(SRCROOT)/Madeira/libntdll_unix.a\\" -force_load \\"$(SRCROOT)/Madeira/libwineserver.a\\" -force_load \\"$(SRCROOT)/Madeira/libwin32u_unix.a\\" -force_load \\"$(SRCROOT)/Madeira/libdxmt_combined_tvos.a\\" -force_load \\"$(SRCROOT)/Madeira/libFEXCore.a\\" -force_load \\"$(SRCROOT)/Madeira/libFEXCore_Base.a\\" -force_load \\"$(SRCROOT)/Madeira/libfmt.a\\" -force_load \\"$(SRCROOT)/Madeira/libcephes_128bit.a\\" -force_load \\"$(SRCROOT)/Madeira/libxxhash.a\\" -force_load \\"$(SRCROOT)/Madeira/libsoftfloat_3e.a\\" -force_load \\"$(SRCROOT)/Madeira/libgnutls.a\\" -force_load \\"$(SRCROOT)/Madeira/libhogweed.a\\" -force_load \\"$(SRCROOT)/Madeira/libnettle.a\\" -force_load \\"$(SRCROOT)/Madeira/libgmp.a\\" -force_load \\"$(SRCROOT)/Madeira/libfreetype.a\\" -force_load \\"$(SRCROOT)/Madeira/libavformat.a\\" -force_load \\"$(SRCROOT)/Madeira/libavcodec.a\\" -force_load \\"$(SRCROOT)/Madeira/libswresample.a\\" -force_load \\"$(SRCROOT)/Madeira/libavutil.a\\" -lc++ -lc++abi -Wl,-allow_multiple_definition -framework Metal -framework QuartzCore -framework MetalFX -framework VideoToolbox -framework CoreMedia -framework AudioToolbox -framework CoreFoundation -lsqlite3");')
proj.append('\t\t\t\tSUPPORTED_PLATFORMS = "appletvos appletvsimulator";')
proj.append('\t\t\t\tSUPPORTS_MACCATALYST = NO;')
proj.append('\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;')
proj.append('\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "MadeiraTV/MadeiraTV-Bridging-Header.h";')
proj.append('\t\t\t\tSWIFT_VERSION = 5.0;')
proj.append('\t\t\t\tTARGETED_DEVICE_FAMILY = 3;')
proj.append('\t\t\t\tHEADER_SEARCH_PATHS = ("$(inherited)", "$(SRCROOT)/Madeira", "$(SRCROOT)/MadeiraTV", "$(SRCROOT)/../FEX/FEXCore/include", "$(SRCROOT)/../FEX/FEXHeaderUtils", "$(SRCROOT)/../FEX/CodeEmitter", "$(SRCROOT)/../FEX/External/fmt/include", "$(SRCROOT)/../FEX/External/range-v3/include", "$(SRCROOT)/../FEX/External/unordered_dense/include", "$(SRCROOT)/../FEX/build-ios", "$(SRCROOT)/../FEX/build-ios/include", "$(SRCROOT)/../FEX/build-ios/FEXCore/Source", "$(SRCROOT)/../FEX", "$(SRCROOT)/../FEX/External/SoftFloat-3e/src", "$(SRCROOT)/../FEX/External/SoftFloat-3e/include/SoftFloat-3e");')
proj.append('\t\t\t\tLIBRARY_SEARCH_PATHS = ("$(inherited)", "$(SRCROOT)/Madeira");')
proj.append('\t\t\t};')
proj.append('\t\t\tname = Debug;')
proj.append('\t\t};')
# Target-level Release
cfg_target_rel = uid('cfg-target-rel')
proj.append(f'\t\t{cfg_target_rel} /* Release */ = {{')
proj.append('\t\t\tisa = XCBuildConfiguration;')
proj.append('\t\t\tbuildSettings = {')
proj.append('\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;')
proj.append('\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;')
proj.append('\t\t\t\tCODE_SIGN_STYLE = Automatic;')
proj.append('\t\t\t\tCURRENT_PROJECT_VERSION = 1;')
proj.append('\t\t\t\tGENERATE_INFOPLIST_FILE = NO;')
proj.append('\t\t\t\tINFOPLIST_FILE = MadeiraTV/Info-TVP.plist;')
proj.append('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/Frameworks");')
proj.append('\t\t\t\tMARKETING_VERSION = 0.1.0;')
proj.append('\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.madeira.tvos;')
proj.append('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
proj.append('\t\t\t\tOTHER_LDFLAGS = ("$(inherited)", "-force_load \\"$(SRCROOT)/Madeira/libntdll_unix.a\\" -force_load \\"$(SRCROOT)/Madeira/libwineserver.a\\" -force_load \\"$(SRCROOT)/Madeira/libwin32u_unix.a\\" -force_load \\"$(SRCROOT)/Madeira/libdxmt_combined_tvos.a\\" -force_load \\"$(SRCROOT)/Madeira/libFEXCore.a\\" -force_load \\"$(SRCROOT)/Madeira/libFEXCore_Base.a\\" -force_load \\"$(SRCROOT)/Madeira/libfmt.a\\" -force_load \\"$(SRCROOT)/Madeira/libcephes_128bit.a\\" -force_load \\"$(SRCROOT)/Madeira/libxxhash.a\\" -force_load \\"$(SRCROOT)/Madeira/libsoftfloat_3e.a\\" -force_load \\"$(SRCROOT)/Madeira/libgnutls.a\\" -force_load \\"$(SRCROOT)/Madeira/libhogweed.a\\" -force_load \\"$(SRCROOT)/Madeira/libnettle.a\\" -force_load \\"$(SRCROOT)/Madeira/libgmp.a\\" -force_load \\"$(SRCROOT)/Madeira/libfreetype.a\\" -force_load \\"$(SRCROOT)/Madeira/libavformat.a\\" -force_load \\"$(SRCROOT)/Madeira/libavcodec.a\\" -force_load \\"$(SRCROOT)/Madeira/libswresample.a\\" -force_load \\"$(SRCROOT)/Madeira/libavutil.a\\" -lc++ -lc++abi -Wl,-allow_multiple_definition -framework Metal -framework QuartzCore -framework MetalFX -framework VideoToolbox -framework CoreMedia -framework AudioToolbox -framework CoreFoundation -lsqlite3");')
proj.append('\t\t\t\tSUPPORTED_PLATFORMS = "appletvos appletvsimulator";')
proj.append('\t\t\t\tSUPPORTS_MACCATALYST = NO;')
proj.append('\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;')
proj.append('\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "MadeiraTV/MadeiraTV-Bridging-Header.h";')
proj.append('\t\t\t\tSWIFT_VERSION = 5.0;')
proj.append('\t\t\t\tTARGETED_DEVICE_FAMILY = 3;')
proj.append('\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (')
proj.append('\t\t\t\t\t"FEXCORE_PRESERVE_ALL_ATTR=",')
proj.append('\t\t\t\t\t"$(inherited)",')
proj.append('\t\t\t\t);')
proj.append('\t\t\t\tHEADER_SEARCH_PATHS = ("$(inherited)", "$(SRCROOT)/Madeira", "$(SRCROOT)/MadeiraTV", "$(SRCROOT)/../FEX/FEXCore/include", "$(SRCROOT)/../FEX/FEXHeaderUtils", "$(SRCROOT)/../FEX/CodeEmitter", "$(SRCROOT)/../FEX/External/fmt/include", "$(SRCROOT)/../FEX/External/range-v3/include", "$(SRCROOT)/../FEX/External/unordered_dense/include", "$(SRCROOT)/../FEX/build-ios", "$(SRCROOT)/../FEX/build-ios/include", "$(SRCROOT)/../FEX/build-ios/FEXCore/Source", "$(SRCROOT)/../FEX", "$(SRCROOT)/../FEX/External/SoftFloat-3e/src", "$(SRCROOT)/../FEX/External/SoftFloat-3e/include/SoftFloat-3e");')
proj.append('\t\t\t\tLIBRARY_SEARCH_PATHS = ("$(inherited)", "$(SRCROOT)/Madeira");')
proj.append('\t\t\t};')
proj.append('\t\t\tname = Release;')
proj.append('\t\t};')
proj.append('/* End XCBuildConfiguration section */')

# --- XCConfigurationList ---
proj.append('\n/* Begin XCConfigurationList section */')
proj.append(f'\t\t{uid("clist-proj")} /* Build configuration list for PBXProject "MadeiraTV" */ = {{')
proj.append('\t\t\tisa = XCConfigurationList;')
proj.append('\t\t\tbuildConfigurations = (')
proj.append(f'\t\t\t\t{cfg_proj_debug} /* Debug */,')
proj.append(f'\t\t\t\t{cfg_proj_rel} /* Release */,')
proj.append('\t\t\t);')
proj.append('\t\t\tdefaultConfigurationIsVisible = 0;')
proj.append('\t\t\tdefaultConfigurationName = Release;')
proj.append('\t\t};')
proj.append(f'\t\t{uid("clist-target")} /* Build configuration list for PBXNativeTarget "MadeiraTV" */ = {{')
proj.append('\t\t\tisa = XCConfigurationList;')
proj.append('\t\t\tbuildConfigurations = (')
proj.append(f'\t\t\t\t{cfg_target_debug} /* Debug */,')
proj.append(f'\t\t\t\t{cfg_target_rel} /* Release */,')
proj.append('\t\t\t);')
proj.append('\t\t\tdefaultConfigurationIsVisible = 0;')
proj.append('\t\t\tdefaultConfigurationName = Release;')
proj.append('\t\t};')
proj.append('/* End XCConfigurationList section */')

proj.append('\t};')
proj.append(f'\trootObject = {proj_obj} /* Project object */;')
proj.append('}')

pbx = os.path.join(ROOT, 'app', 'MadeiraTV.xcodeproj', 'project.pbxproj')
os.makedirs(os.path.dirname(pbx), exist_ok=True)
with open(pbx, 'w', encoding='utf-8', newline='\n') as f:
    f.write('\n'.join(proj) + '\n')
print(f'Wrote {pbx}')
print(f'portable files: {len(portable)}, tv files: {len(tv_files)}')