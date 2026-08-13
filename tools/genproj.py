#!/usr/bin/env python3
"""
Regenerate Sill.xcodeproj/project.pbxproj from the source tree.

Hand-editing a pbxproj across many milestones is a reliable way to break a build,
so the project file is derived instead. objectVersion stays pinned at 56: Xcode 16.4
opens that without ever offering "Update to recommended settings", which the
toolchain lock forbids. Do not raise it.
"""
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = "Sill"
SRC_DIR = os.path.join(ROOT, APP)

# Pinned. See CLAUDE.md. Changing any of these violates the toolchain lock.
OBJECT_VERSION = "56"
SWIFT_VERSION = "6.0"
DEPLOYMENT_TARGET = "14.0"
BUNDLE_ID = "dev.meniscus.sill"


def uid(seed: str) -> str:
    return hashlib.md5(seed.encode()).hexdigest()[:24].upper()


def swift_sources():
    out = []
    for dirpath, dirnames, filenames in os.walk(SRC_DIR):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for f in sorted(filenames):
            if f.endswith(".swift"):
                out.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
    return out


def resources():
    out = []
    for name in ("Assets.xcassets",):
        p = os.path.join(SRC_DIR, name)
        if os.path.exists(p):
            out.append(os.path.relpath(p, ROOT))
    # Bundled typefaces. The design's three faces are not installed on this machine, so
    # they ship with the app rather than being silently substituted.
    fdir = os.path.join(SRC_DIR, "Resources")
    if os.path.isdir(fdir):
        for f in sorted(os.listdir(fdir)):
            if f.endswith(".ttf") or f.endswith(".icns"):
                out.append(os.path.relpath(os.path.join(fdir, f), ROOT))
    return out


def metal_sources():
    out = []
    for dirpath, dirnames, filenames in os.walk(SRC_DIR):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for f in sorted(filenames):
            if f.endswith(".metal"):
                out.append(os.path.relpath(os.path.join(dirpath, f), ROOT))
    return out


def main():
    sources = swift_sources()
    metals = metal_sources()
    res = resources()
    if not sources:
        sys.exit("no swift sources found under %s" % SRC_DIR)

    PROJ = uid("project")
    TARGET = uid("target")
    PRODUCT = uid("product")
    MAIN_GROUP = uid("maingroup")
    SRC_GROUP = uid("srcgroup")
    PRODUCTS_GROUP = uid("productsgroup")
    SOURCES_PHASE = uid("sourcesphase")
    FRAMEWORKS_PHASE = uid("frameworksphase")
    RESOURCES_PHASE = uid("resourcesphase")
    PROJ_CFG_LIST = uid("projcfglist")
    TARGET_CFG_LIST = uid("targetcfglist")
    PROJ_DEBUG = uid("projdebug")
    PROJ_RELEASE = uid("projrelease")
    TARGET_DEBUG = uid("targetdebug")
    TARGET_RELEASE = uid("targetrelease")

    L = []
    A = L.append
    A("// !$*UTF8*$!")
    A("{")
    A("\tarchiveVersion = 1;")
    A("\tclasses = {\n\t};")
    A("\tobjectVersion = %s;" % OBJECT_VERSION)
    A("\tobjects = {")

    # ---- PBXBuildFile
    A("\n/* Begin PBXBuildFile section */")
    for p in sources + metals:
        A('\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
          % (uid("bf:" + p), os.path.basename(p), uid("fr:" + p), os.path.basename(p)))
    for p in res:
        A('\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
          % (uid("bf:" + p), os.path.basename(p), uid("fr:" + p), os.path.basename(p)))
    A("/* End PBXBuildFile section */")

    # ---- PBXFileReference
    A("\n/* Begin PBXFileReference section */")
    A('\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };'
      % (PRODUCT, APP, APP))
    for p in sources:
        A('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = %s; path = %s; sourceTree = SOURCE_ROOT; };'
          % (uid("fr:" + p), os.path.basename(p), os.path.basename(p), p))
    for p in metals:
        A('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.metal; name = %s; path = %s; sourceTree = SOURCE_ROOT; };'
          % (uid("fr:" + p), os.path.basename(p), os.path.basename(p), p))
    for p in res:
        kind = "file.ttf" if p.endswith(".ttf") else ("image.icns" if p.endswith(".icns") else "folder.assetcatalog")
        A('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; name = %s; path = %s; sourceTree = SOURCE_ROOT; };'
          % (uid("fr:" + p), os.path.basename(p), kind, os.path.basename(p), p))
    A('\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; name = Info.plist; path = %s/Info.plist; sourceTree = SOURCE_ROOT; };'
      % (uid("fr:info"), APP))
    A("/* End PBXFileReference section */")

    # ---- PBXFrameworksBuildPhase
    A("\n/* Begin PBXFrameworksBuildPhase section */")
    A("\t\t%s /* Frameworks */ = {" % FRAMEWORKS_PHASE)
    A("\t\t\tisa = PBXFrameworksBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (\n\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXFrameworksBuildPhase section */")

    # ---- PBXGroup
    A("\n/* Begin PBXGroup section */")
    A("\t\t%s = {" % MAIN_GROUP)
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    A("\t\t\t\t%s /* %s */," % (SRC_GROUP, APP))
    A("\t\t\t\t%s /* Products */," % PRODUCTS_GROUP)
    A("\t\t\t);")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    A("\t\t%s /* %s */ = {" % (SRC_GROUP, APP))
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    for p in sources + metals + res:
        A("\t\t\t\t%s /* %s */," % (uid("fr:" + p), os.path.basename(p)))
    A("\t\t\t\t%s /* Info.plist */," % uid("fr:info"))
    A("\t\t\t);")
    A("\t\t\tname = %s;" % APP)
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    A("\t\t%s /* Products */ = {" % PRODUCTS_GROUP)
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (\n\t\t\t\t%s /* %s.app */,\n\t\t\t);" % (PRODUCT, APP))
    A("\t\t\tname = Products;")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    A("/* End PBXGroup section */")

    # ---- PBXNativeTarget
    A("\n/* Begin PBXNativeTarget section */")
    A("\t\t%s /* %s */ = {" % (TARGET, APP))
    A("\t\t\tisa = PBXNativeTarget;")
    A("\t\t\tbuildConfigurationList = %s;" % TARGET_CFG_LIST)
    A("\t\t\tbuildPhases = (")
    A("\t\t\t\t%s /* Sources */," % SOURCES_PHASE)
    A("\t\t\t\t%s /* Frameworks */," % FRAMEWORKS_PHASE)
    A("\t\t\t\t%s /* Resources */," % RESOURCES_PHASE)
    A("\t\t\t);")
    A("\t\t\tbuildRules = (\n\t\t\t);")
    A("\t\t\tdependencies = (\n\t\t\t);")
    A("\t\t\tname = %s;" % APP)
    A("\t\t\tproductName = %s;" % APP)
    A("\t\t\tproductReference = %s /* %s.app */;" % (PRODUCT, APP))
    A("\t\t\tproductType = \"com.apple.product-type.application\";")
    A("\t\t};")
    A("/* End PBXNativeTarget section */")

    # ---- PBXProject
    A("\n/* Begin PBXProject section */")
    A("\t\t%s /* Project object */ = {" % PROJ)
    A("\t\t\tisa = PBXProject;")
    A("\t\t\tattributes = {")
    A("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    A("\t\t\t\tLastSwiftUpdateCheck = 1640;")
    A("\t\t\t\tLastUpgradeCheck = 1640;")
    A("\t\t\t\tTargetAttributes = {")
    A("\t\t\t\t\t%s = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.4;\n\t\t\t\t\t};" % TARGET)
    A("\t\t\t\t};")
    A("\t\t\t};")
    A("\t\t\tbuildConfigurationList = %s;" % PROJ_CFG_LIST)
    A("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    A("\t\t\tdevelopmentRegion = en;")
    A("\t\t\thasScannedForEncodings = 0;")
    A("\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);")
    A("\t\t\tmainGroup = %s;" % MAIN_GROUP)
    A("\t\t\tproductRefGroup = %s /* Products */;" % PRODUCTS_GROUP)
    A("\t\t\tprojectDirPath = \"\";")
    A("\t\t\tprojectRoot = \"\";")
    A("\t\t\ttargets = (\n\t\t\t\t%s /* %s */,\n\t\t\t);" % (TARGET, APP))
    A("\t\t};")
    A("/* End PBXProject section */")

    # ---- PBXResourcesBuildPhase
    A("\n/* Begin PBXResourcesBuildPhase section */")
    A("\t\t%s /* Resources */ = {" % RESOURCES_PHASE)
    A("\t\t\tisa = PBXResourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    for p in res:
        A("\t\t\t\t%s /* %s in Resources */," % (uid("bf:" + p), os.path.basename(p)))
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXResourcesBuildPhase section */")

    # ---- PBXSourcesBuildPhase
    A("\n/* Begin PBXSourcesBuildPhase section */")
    A("\t\t%s /* Sources */ = {" % SOURCES_PHASE)
    A("\t\t\tisa = PBXSourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    for p in sources + metals:
        A("\t\t\t\t%s /* %s in Sources */," % (uid("bf:" + p), os.path.basename(p)))
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXSourcesBuildPhase section */")

    # ---- XCBuildConfiguration
    common = [
        "ALWAYS_SEARCH_USER_PATHS = NO;",
        "CLANG_ENABLE_MODULES = YES;",
        "CLANG_ENABLE_OBJC_ARC = YES;",
        "COPY_PHASE_STRIP = NO;",
        "ENABLE_STRICT_OBJC_MSGSEND = YES;",
        "GCC_NO_COMMON_BLOCKS = YES;",
        "MACOSX_DEPLOYMENT_TARGET = %s;" % DEPLOYMENT_TARGET,
        "SDKROOT = macosx;",
        "SWIFT_VERSION = %s;" % SWIFT_VERSION,
    ]
    target_common = [
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;" if res else "",
        "CODE_SIGN_STYLE = Automatic;",
        "CODE_SIGN_IDENTITY = \"$(SILL_SIGN_IDENTITY)\";",
        "COMBINE_HIDPI_IMAGES = YES;",
        "CURRENT_PROJECT_VERSION = 1;",
        "ENABLE_HARDENED_RUNTIME = YES;",
        "CODE_SIGN_ENTITLEMENTS = %s/Sill.entitlements;" % APP,
        "GENERATE_INFOPLIST_FILE = NO;",
        "INFOPLIST_FILE = %s/Info.plist;" % APP,
        "MARKETING_VERSION = 0.1;",
        "PRODUCT_BUNDLE_IDENTIFIER = %s;" % BUNDLE_ID,
        "PRODUCT_NAME = \"$(TARGET_NAME)\";",
        "SWIFT_EMIT_LOC_STRINGS = YES;",
        "LD_RUNPATH_SEARCH_PATHS = (\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t\t\"@executable_path/../Frameworks\",\n\t\t\t\t);",
    ]
    target_common = [x for x in target_common if x]

    def cfg(cfg_id, name, extra, is_target):
        A("\t\t%s /* %s */ = {" % (cfg_id, name))
        A("\t\t\tisa = XCBuildConfiguration;")
        A("\t\t\tbuildSettings = {")
        base = target_common if is_target else common
        for line in base + extra:
            A("\t\t\t\t%s" % line)
        A("\t\t\t};")
        A("\t\t\tname = %s;" % name)
        A("\t\t};")

    A("\n/* Begin XCBuildConfiguration section */")
    cfg(PROJ_DEBUG, "Debug", [
        "DEBUG_INFORMATION_FORMAT = dwarf;",
        "ENABLE_TESTABILITY = YES;",
        "GCC_OPTIMIZATION_LEVEL = 0;",
        "ONLY_ACTIVE_ARCH = YES;",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
        "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
    ], False)
    cfg(PROJ_RELEASE, "Release", [
        "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";",
        "ENABLE_NS_ASSERTIONS = NO;",
        "SWIFT_COMPILATION_MODE = wholemodule;",
    ], False)
    cfg(TARGET_DEBUG, "Debug", [], True)
    cfg(TARGET_RELEASE, "Release", [], True)
    A("/* End XCBuildConfiguration section */")

    # ---- XCConfigurationList
    A("\n/* Begin XCConfigurationList section */")
    for list_id, d, r, label in ((PROJ_CFG_LIST, PROJ_DEBUG, PROJ_RELEASE, "PBXProject"),
                                 (TARGET_CFG_LIST, TARGET_DEBUG, TARGET_RELEASE, "PBXNativeTarget")):
        A("\t\t%s /* Build configuration list for %s */ = {" % (list_id, label))
        A("\t\t\tisa = XCConfigurationList;")
        A("\t\t\tbuildConfigurations = (\n\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);" % (d, r))
        A("\t\t\tdefaultConfigurationIsVisible = 0;")
        A("\t\t\tdefaultConfigurationName = Release;")
        A("\t\t};")
    A("/* End XCConfigurationList section */")

    A("\t};")
    A("\trootObject = %s /* Project object */;" % PROJ)
    A("}")

    out_dir = os.path.join(ROOT, "%s.xcodeproj" % APP)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "project.pbxproj"), "w") as fh:
        fh.write("\n".join(L) + "\n")
    print("wrote %s.xcodeproj/project.pbxproj  (%d swift, %d metal, %d resource)"
          % (APP, len(sources), len(metals), len(res)))


if __name__ == "__main__":
    main()
