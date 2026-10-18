#!/usr/bin/env python3
"""Deterministic Xcode project generation, no third-party build dependency."""
from pathlib import Path
from hashlib import sha1
import json

root = Path(__file__).resolve().parent.parent
def uid(name): return sha1(name.encode()).hexdigest()[:24].upper()
def q(value): return json.dumps(str(value), ensure_ascii=False)
sources = sorted(list(root.glob('HeadControl/**/*.swift')) + list(root.glob('Core/Sources/**/*.swift')))
entries=[]
def obj(name, body):
    entries.append(f'{uid(name)} = {{ {body} }};')
    return uid(name)
refs=[];builds=[]
for source in sources:
    path=source.relative_to(root).as_posix()
    ref=obj('ref:'+path,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    builds.append(obj('build:'+path,f'isa = PBXBuildFile; fileRef = {ref};'))
assets=obj('assets','isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = HeadControl/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;')
assetbuild=obj('assetbuild',f'isa = PBXBuildFile; fileRef = {assets};')
notice=obj('notice','isa = PBXFileReference; lastKnownFileType = text; path = HeadControl/Resources/ThirdPartyNotices.txt; sourceTree = SOURCE_ROOT;')
noticebuild=obj('noticebuild',f'isa = PBXBuildFile; fileRef = {notice};')
product=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = HeadControl.app; sourceTree = BUILT_PRODUCTS_DIR;')
products=obj('products',f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
main=obj('main',f'isa = PBXGroup; children = ({",".join(refs+[assets,notice,products])},); sourceTree = "<group>";')
sourcephase=obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
resourcephase=obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({assetbuild},{noticebuild},); runOnlyForDeploymentPostprocessing = 0;')
frameworkphase=obj('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
projectconfigs=[];targetconfigs=[]
for config in ['Debug','Release']:
    projectconfigs.append(obj('proj:'+config,f'isa = XCBuildConfiguration; buildSettings = {{ CLANG_ENABLE_MODULES = YES; MACOSX_DEPLOYMENT_TARGET = 15.3; SDKROOT = macosx; }}; name = {config};'))
    settings={
        'PRODUCT_NAME':'HeadControl','PRODUCT_BUNDLE_IDENTIFIER':'com.keyknock.HeadControl.Debug' if config=='Debug' else 'com.keyknock.HeadControl',
        'INFOPLIST_FILE':'HeadControl/Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO',
        'SWIFT_VERSION':'5.0','MACOSX_DEPLOYMENT_TARGET':'15.3','ARCHS':'arm64',
        # Developer ID gives a stable designated requirement, so TCC grants survive rebuilds (ad-hoc pins a cdhash).
        'CODE_SIGN_STYLE':'Manual','CODE_SIGN_IDENTITY':'Developer ID Application','DEVELOPMENT_TEAM':'MR285FSGSG','ENABLE_HARDENED_RUNTIME':'YES',
        'ENABLE_APP_SANDBOX':'NO','MARKETING_VERSION':'2.1.0','CURRENT_PROJECT_VERSION':'4',
        'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config=='Debug' else '-O',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if config=='Debug' else '',
        'COMBINE_HIDPI_IMAGES':'YES','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks',
        'SWIFT_EMIT_LOC_STRINGS':'YES','DEBUG_INFORMATION_FORMAT':'dwarf' if config=='Debug' else 'dwarf-with-dsym',
    }
    body=' '.join(f'{k} = {q(v)};' for k,v in settings.items())
    targetconfigs.append(obj('target:'+config,f'isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {config};'))
projlist=obj('projconfigs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(projectconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
targetlist=obj('targetconfigs',f'isa = XCConfigurationList; buildConfigurations = ({",".join(targetconfigs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target=obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {targetlist}; buildPhases = ({sourcephase},{frameworkphase},{resourcephase},); buildRules = (); dependencies = (); name = HeadControl; productName = HeadControl; productReference = {product}; productType = "com.apple.product-type.application";')
proj=obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1640; }}; buildConfigurationList = {projlist}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans",en,Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
directory=root/'HeadControl.xcodeproj';directory.mkdir(exist_ok=True)
(directory/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(entries)+f'\n}}; rootObject = {proj}; }}\n')
schemes=directory/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
buildable=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="HeadControl.app" BlueprintName="HeadControl" ReferencedContainer="container:HeadControl.xcodeproj"/>'
(schemes/'HeadControl.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print(f'Generated {directory.name}: {len(sources)} Swift files')
