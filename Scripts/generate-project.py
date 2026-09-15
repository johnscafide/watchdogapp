#!/usr/bin/env python3
"""Generate the checked-in Xcode project from local files, with no third-party generator.
Run after adding/removing Swift files. The output is deterministic; never alters source files.
"""
from pathlib import Path
import hashlib, json

ROOT = Path(__file__).resolve().parents[1]
objects = []
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def quote(value): return json.dumps(str(value))
def seq(values): return '(' + ', '.join(values) + (',' if values else '') + ')'
def obj(name, body):
    identifier = uid(name)
    objects.append(f'\t\t{identifier} = {{ {body} }};')
    return identifier
def config(name, settings):
    values = ' '.join(f'{k} = {v};' for k,v in settings.items())
    return obj(name, f'isa = XCBuildConfiguration; buildSettings = {{ {values} }}; name = {name.split("/")[-1]};')
def configs(name, base, debug_extra=None):
    ids=[]
    for kind in ('Debug','Release'):
        settings=base.copy()
        settings.update({'SWIFT_OPTIMIZATION_LEVEL':'"-Onone"' if kind=='Debug' else '"-O"',
                         'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'"DEBUG $(inherited)"' if kind=='Debug' else '"$(inherited)"'})
        if kind=='Debug' and debug_extra: settings.update(debug_extra)
        ids.append(config(name+'/'+kind,settings))
    return obj(name+'/configs', f'isa = XCConfigurationList; buildConfigurations = {seq(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

project_id=uid('Project')
app_id=uid('Target/Watchdog')
products=[]
groups=[]
package=obj('Package/Core','isa = XCLocalSwiftPackageReference; relativePath = WatchdogCore;')
targets=[]
common={'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SWIFT_VERSION':'5.0',
        'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','CODE_SIGN_STYLE':'Automatic',
        'DEVELOPMENT_TEAM':'""','TARGETED_DEVICE_FAMILY':'"1,2"','SUPPORTED_PLATFORMS':'"iphoneos iphonesimulator"',
        'SWIFT_STRICT_CONCURRENCY':'targeted','ENABLE_USER_SCRIPT_SANDBOXING':'YES',
        'SUPPORTS_MACCATALYST':'NO','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO'}

for name,folder,product_type,product_path,file_type in [
    ('Watchdog','App','application','Watchdog.app','wrapper.application'),
    ('WatchdogTests','Tests/WatchdogTests','bundle.unit-test','WatchdogTests.xctest','wrapper.cfbundle'),
    ('WatchdogUITests','Tests/WatchdogUITests','bundle.ui-testing','WatchdogUITests.xctest','wrapper.cfbundle')]:
    file_refs=[]; source_builds=[]; resource_builds=[]
    for path in sorted((ROOT/folder).rglob('*.swift')):
        rel=path.relative_to(ROOT).as_posix()
        ref=obj('file/'+rel,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(rel)}; sourceTree = SOURCE_ROOT;')
        file_refs.append(ref)
        source_builds.append(obj('build/'+rel,f'isa = PBXBuildFile; fileRef = {ref};'))
    if name=='Watchdog':
        for rel,kind,build in [('App/Info.plist','text.plist.xml',False),('App/PrivacyInfo.xcprivacy','text.xml',True),('App/Assets.xcassets','folder.assetcatalog',True)]:
            ref=obj('file/'+rel,f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(rel)}; sourceTree = SOURCE_ROOT;')
            file_refs.append(ref)
            if build: resource_builds.append(obj('build/'+rel,f'isa = PBXBuildFile; fileRef = {ref};'))
    groups.append(obj('group/'+name, f'isa = PBXGroup; children = {seq(file_refs)}; name = {quote(name)}; sourceTree = "<group>";'))
    product=obj('product/'+name,f'isa = PBXFileReference; explicitFileType = {file_type}; includeInIndex = 0; path = {quote(product_path)}; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    package_products=[]; framework_builds=[]
    if name!='WatchdogUITests':
        dependency=obj('packageProduct/'+name,f'isa = XCSwiftPackageProductDependency; package = {package}; productName = WatchdogCore;')
        package_products.append(dependency)
        framework_builds.append(obj('framework/'+name,f'isa = PBXBuildFile; productRef = {dependency};'))
    phases=[]
    for kind,files in [('Sources',source_builds),('Frameworks',framework_builds),('Resources',resource_builds)]:
        phases.append(obj('phase/'+name+'/'+kind,f'isa = PBX{kind}BuildPhase; buildActionMask = 2147483647; files = {seq(files)}; runOnlyForDeploymentPostprocessing = 0;'))
    dependencies=[]
    if name!='Watchdog':
        proxy=obj('proxy/'+name,f'isa = PBXContainerItemProxy; containerPortal = {project_id}; proxyType = 1; remoteGlobalIDString = {app_id}; remoteInfo = Watchdog;')
        dependencies.append(obj('dependency/'+name,f'isa = PBXTargetDependency; target = {app_id}; targetProxy = {proxy};'))
    settings=common.copy()
    settings.update({'PRODUCT_NAME':'"$(TARGET_NAME)"','PRODUCT_BUNDLE_IDENTIFIER':quote('com.watchdogindex.consumer'+('' if name=='Watchdog' else '.'+name)),
                     'GENERATE_INFOPLIST_FILE':'NO' if name=='Watchdog' else 'YES',
                     'LD_RUNPATH_SEARCH_PATHS':'("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks",)'})
    if name=='Watchdog':
        settings.update({'INFOPLIST_FILE':'App/Info.plist','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon',
                         'MARKETING_VERSION':'1.0','CURRENT_PROJECT_VERSION':'1','PRODUCT_MODULE_NAME':'Watchdog',
                         'ENABLE_PREVIEWS':'YES','SWIFT_EMIT_LOC_STRINGS':'YES'})
    elif name=='WatchdogTests':
        settings.update({'BUNDLE_LOADER':'"$(TEST_HOST)"','TEST_HOST':'"$(BUILT_PRODUCTS_DIR)/Watchdog.app/Watchdog"'})
    else: settings.update({'TEST_TARGET_NAME':'Watchdog'})
    conf=configs('target/'+name,settings,{'ENABLE_TESTABILITY':'YES'})
    targets.append(obj('Target/'+name,f'isa = PBXNativeTarget; buildConfigurationList = {conf}; buildPhases = {seq(phases)}; buildRules = (); dependencies = {seq(dependencies)}; name = {name}; packageProductDependencies = {seq(package_products)}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.{product_type}";'))

products_group=obj('group/products',f'isa = PBXGroup; children = {seq(products)}; name = Products; sourceTree = "<group>";')
core_ref=obj('file/core','isa = PBXFileReference; lastKnownFileType = folder; path = WatchdogCore; sourceTree = SOURCE_ROOT;')
main_group=obj('group/main',f'isa = PBXGroup; children = {seq(groups+[core_ref,products_group])}; sourceTree = "<group>";')
project_config=configs('project',{'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','DEBUG_INFORMATION_FORMAT':'"dwarf-with-dsym"'})
attributes=' '.join(f'{target} = {{ CreatedOnToolsVersion = 16.0; }};' for target in targets)
obj('Project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600; TargetAttributes = {{ {attributes} }}; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = {main_group}; packageReferences = ({package},); productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = {seq(targets)};')
project=ROOT/'Watchdog.xcodeproj'; project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'+'\n'.join(objects)+'\n\t};\n\trootObject = '+project_id+';\n}\n')
workspace=project/'project.xcworkspace'; workspace.mkdir(exist_ok=True)
(workspace/'contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')
schemes=project/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
def buildable(name):
    extension='app' if name=='Watchdog' else 'xctest'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("Target/"+name)}" BuildableName="{name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:Watchdog.xcodeproj"/>'
entries=''.join(f'<BuildActionEntry buildForTesting="YES" buildForRunning="{"YES" if n=="Watchdog" else "NO"}" buildForProfiling="{"YES" if n=="Watchdog" else "NO"}" buildForArchiving="{"YES" if n=="Watchdog" else "NO"}" buildForAnalyzing="YES">{buildable(n)}</BuildActionEntry>' for n in ('Watchdog','WatchdogTests','WatchdogUITests'))
testables=''.join(f'<TestableReference skipped="NO">{buildable(n)}</TestableReference>' for n in ('WatchdogTests','WatchdogUITests'))
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>{entries}</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{testables}</Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('Watchdog')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('Watchdog')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(schemes/'Watchdog.xcscheme').write_text(scheme)
sample=scheme.replace('<LaunchAction buildConfiguration="Debug"','<LaunchAction buildConfiguration="Debug"').replace('</BuildableProductRunnable></LaunchAction>','</BuildableProductRunnable><CommandLineArguments><CommandLineArgument argument="--sample-data" isEnabled="YES"/></CommandLineArguments></LaunchAction>')
(schemes/'Watchdog Sample.xcscheme').write_text(sample)
print(f'Generated Watchdog.xcodeproj with {len(list((ROOT/"App").rglob("*.swift")))} app source files and two test targets.')
