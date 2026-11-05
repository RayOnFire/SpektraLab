#!/usr/bin/env python3
"""Generate the iOS project with the upstream's deterministic PBX helpers."""
import importlib.util
import os
from pathlib import Path
import plistlib
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
spec = importlib.util.spec_from_file_location("upstream_project", REPO / "modern_UI/Spektrafilm/Tools/gen-project.py")
up = importlib.util.module_from_spec(spec)
spec.loader.exec_module(up)
up.ROOT = ROOT
p = up.Project()
uid = up.uid
appfiles, testfiles = [], []
appgroup = p.group(ROOT / "Grainroom", appfiles)
testgroup = p.group(ROOT / "GrainroomTests", testfiles)
shared = [REPO / "modern_UI/Spektrafilm/Spektrafilm" / f for f in ["Import/ImageDecoder.swift", "Model/DecodeSettings.swift"]]
engine = up.engine_sources()
references = []
for path in shared + engine:
    name = os.path.relpath(path, ROOT)
    fid = uid("shared:" + name)
    kind = "sourcecode.swift" if path.suffix == ".swift" else "sourcecode.cpp.cpp"
    p.add(fid, f'{{isa = PBXFileReference; lastKnownFileType = {kind}; name = "{path.name}"; path = "{name}"; sourceTree = SOURCE_ROOT; }}')
    references.append((fid, path))
sharedgroup = uid("sharedgroup")
p.add(sharedgroup, '{isa = PBXGroup; name = "Shared engine and decoder"; children = (' + ','.join(x[0] for x in references) + '); sourceTree = "<group>"; }')

def phase(tag, kind, files):
    ids = []
    for fid, path in files:
        bid = uid(tag + str(path.relative_to(REPO)))
        p.add(bid, f'{{isa = PBXBuildFile; fileRef = {fid}; }}')
        ids.append(bid)
    pid = uid(tag)
    p.add(pid, f'{{isa = {kind}; buildActionMask = 2147483647; files = (' + ','.join(ids) + '); runOnlyForDeploymentPostprocessing = 0; }')
    return pid

sources = phase("app-sources", "PBXSourcesBuildPhase", [(f,q) for f,q in appfiles + references if q.suffix in (".swift", ".cpp")])
resources = phase("app-resources", "PBXResourcesBuildPhase", [(f,q) for f,q in appfiles if q.suffix == ".xcassets"])
frameworks = phase("frameworks", "PBXFrameworksBuildPhase", [])
testsrc = phase("test-sources", "PBXSourcesBuildPhase", [(f,q) for f,q in testfiles if q.suffix == ".swift"])
bundle = uid("bundle-engine")
p.add(bundle, '{isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); alwaysOutOfDate = 1; name = "Build safe-math engine and bundle licenses"; shellPath = /bin/bash; shellScript = "bash \\\"$SRCROOT/Tools/build-engine.sh\\\"\\n"; runOnlyForDeploymentPostprocessing = 0; }'.replace('\\\"', '\\"'))

appTarget, testTarget, project = uid("app-target"), uid("tests-target"), uid("project")
appProduct, testProduct = uid("app-product"), uid("test-product")
p.add(appProduct, '{isa = PBXFileReference; explicitFileType = wrapper.application; path = Grainroom.app; sourceTree = BUILT_PRODUCTS_DIR; includeInIndex = 0; }')
p.add(testProduct, '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = GrainroomTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; includeInIndex = 0; }')
products, main = uid("products"), uid("main")
p.add(products, f'{{isa = PBXGroup; name = Products; children = ({appProduct},{testProduct}); sourceTree = "<group>"; }}')
p.add(main, f'{{isa = PBXGroup; children = ({appgroup},{sharedgroup},{testgroup},{products}); sourceTree = "<group>"; }}')

common = {
    "SDKROOT": "iphoneos", "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator"', "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete", "CLANG_ENABLE_MODULES": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": '"c++20"', "CLANG_CXX_LIBRARY": '"libc++"', "CLANG_ENABLE_OBJC_ARC": "NO",
    "OTHER_CPLUSPLUSFLAGS": '"$(inherited) -fblocks"', "OTHER_LDFLAGS": '"$(inherited) -lc++ -framework Metal -framework Foundation -framework QuartzCore -framework CoreText -framework CoreGraphics -framework Accelerate"',
    "HEADER_SEARCH_PATHS": '(' + ','.join(f'"$(SRCROOT)/../engine/{d}"' for d in ["include","src","src/core","third_party/metal-cpp"]) + ')',
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO", "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": '""',
    "TARGETED_DEVICE_FAMILY": '"1,2"', "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1",
    "SUPPORTS_MACCATALYST": "NO", "GCC_OPTIMIZATION_LEVEL": "2", "SWIFT_EMIT_LOC_STRINGS": "NO",
    "LD_RUNPATH_SEARCH_PATHS": '"$(inherited) @executable_path/Frameworks @loader_path/Frameworks"',
}

def configurations(tag, extra):
    ids = []
    for name in ["Debug", "Release"]:
        settings = {**common, **extra, "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"' if name == "Debug" else '"-O"',
                    "ENABLE_TESTABILITY": "YES" if name == "Debug" else "NO", "DEBUG_INFORMATION_FORMAT": '"dwarf"'}
        if name == "Debug": settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        body = '\n'.join(f'{key} = {value};' for key,value in sorted(settings.items()))
        cid = uid(tag + name); ids.append(cid)
        p.add(cid, f'{{isa = XCBuildConfiguration; buildSettings = {{\n{body}\n}}; name = {name}; }}')
    lid = uid(tag + "list")
    p.add(lid, f'{{isa = XCConfigurationList; buildConfigurations = ({",".join(ids)}); defaultConfigurationName = Release; defaultConfigurationIsVisible = 0; }}')
    return lid

acfg = configurations("app", {"PRODUCT_NAME": "Grainroom", "PRODUCT_BUNDLE_IDENTIFIER": "org.grainroom.editor",
    "INFOPLIST_FILE": '"Grainroom/Info.plist"', "SWIFT_OBJC_BRIDGING_HEADER": '"Grainroom/Grainroom-Bridging-Header.h"',
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "GENERATE_INFOPLIST_FILE": "NO"})
tcfg = configurations("test", {"PRODUCT_NAME": "GrainroomTests", "PRODUCT_BUNDLE_IDENTIFIER": "org.grainroom.editor.tests",
    "GENERATE_INFOPLIST_FILE": "YES", "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/Grainroom.app/Grainroom"',
    "BUNDLE_LOADER": '"$(TEST_HOST)"', "TEST_TARGET_NAME": "Grainroom"})
pcfg = configurations("project", {})
proxy, dependency = uid("testproxy"), uid("testdependency")
p.add(proxy, f'{{isa = PBXContainerItemProxy; containerPortal = {project}; proxyType = 1; remoteGlobalIDString = {appTarget}; remoteInfo = Grainroom; }}')
p.add(dependency, f'{{isa = PBXTargetDependency; target = {appTarget}; targetProxy = {proxy}; }}')
p.add(appTarget, f'{{isa = PBXNativeTarget; name = Grainroom; productName = Grainroom; productReference = {appProduct}; productType = "com.apple.product-type.application"; buildConfigurationList = {acfg}; buildPhases = ({sources},{frameworks},{resources},{bundle}); buildRules = (); dependencies = (); }}')
p.add(testTarget, f'{{isa = PBXNativeTarget; name = GrainroomTests; productName = GrainroomTests; productReference = {testProduct}; productType = "com.apple.product-type.bundle.unit-test"; buildConfigurationList = {tcfg}; buildPhases = ({testsrc}); buildRules = (); dependencies = ({dependency}); }}')
p.add(project, f'{{isa = PBXProject; attributes = {{LastUpgradeCheck = 2700; TargetAttributes = {{{testTarget} = {{TestTargetID = {appTarget}; }}; }}; }}; buildConfigurationList = {pcfg}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({appTarget},{testTarget}); }}')
text = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(p.objects) + f'\n}}; rootObject = {project}; }}\n'
out = ROOT / "Grainroom.xcodeproj/project.pbxproj"
if "--check" in sys.argv:
    if not out.exists() or out.read_text() != text: raise SystemExit("Stale project; run ios/Tools/gen-project.py")
else:
    out.parent.mkdir(exist_ok=True); out.write_text(text)
    scheme = out.parent / "xcshareddata/xcschemes/Grainroom.xcscheme"
    scheme.parent.mkdir(parents=True, exist_ok=True)
    appRef = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appTarget}" BuildableName="Grainroom.app" BlueprintName="Grainroom" ReferencedContainer="container:Grainroom.xcodeproj"/>'
    testRef = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{testTarget}" BuildableName="GrainroomTests.xctest" BlueprintName="GrainroomTests" ReferencedContainer="container:Grainroom.xcodeproj"/>'
    scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appRef}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{testRef}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appRef}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{appRef}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print("Grainroom project is current")
