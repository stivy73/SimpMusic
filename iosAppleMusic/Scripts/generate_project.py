from pathlib import Path
import hashlib,plistlib
root=Path(__file__).resolve().parents[2];base=root/'iosAppleMusic';objects=[]
def ident(s):return hashlib.sha1(('apple-music-'+s).encode()).hexdigest()[:24].upper()
def obj(name,s):objects.append(f'{ident(name)} = {{ {s} }};');return ident(name)
files=['Sources/MusicAccessRecovery.swift','Sources/SongWebMeaning.swift','Sources/MeaningHTTP.swift','Sources/SongMeaningSourcesView.swift','Sources/MusicWatchBridge.swift','../iosPrototype/Sources/Core/WatchCompanion.swift','../iosPrototype/WatchApp/WatchSessionLink.swift','Sources/MusicIntents.swift','Sources/MusicCarPlay.swift','Sources/LicensedLyrics.swift','Sources/MusicLibraryModel.swift','Sources/NarrationModel.swift','Sources/NoteNarrateMusicApp.swift','../iosPrototype/Sources/Core/Interpretation.swift','../iosPrototype/Sources/Core/GeminiService.swift','../iosPrototype/Sources/Core/SpeechStream.swift','../iosPrototype/Sources/Core/PCMStreamPlayer.swift']
refs=[];builds=[]
for f in files:
 refs.append(obj(f,'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "'+f+'"; sourceTree = "<group>";'))
 builds.append(obj(f+'build','isa = PBXBuildFile; fileRef = '+ident(f)+';'))
res=[]
for f,t in [('../iosPrototype/Assets.xcassets','folder.assetcatalog'),('../iosPrototype/PrivacyInfo.xcprivacy','text.xml')]:
 refs.append(obj(f,f'isa = PBXFileReference; lastKnownFileType = {t}; path = "{f}"; sourceTree = "<group>";'))
 res.append(obj(f+'build','isa = PBXBuildFile; fileRef = '+ident(f)+';'))
product=obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; path = NoteNarrateMusic.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('main','isa = PBXGroup; children = ('+','.join(refs+[product])+'); sourceTree = "<group>";')
obj('sources','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(builds)+'); runOnlyForDeploymentPostprocessing = 0;')
obj('resources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(res)+'); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
for kind in ['Debug','Release']:
 settings='SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES;'
 obj('project'+kind,f'isa = XCBuildConfiguration; name = {kind}; buildSettings = {{ {settings} }};')
 settings='PRODUCT_BUNDLE_IDENTIFIER = com.stivy.notenarrate.applemusic; PRODUCT_NAME = NoteNarrateMusic; INFOPLIST_FILE = Info.plist; GENERATE_INFOPLIST_FILE = NO; TARGETED_DEVICE_FAMILY = "1,2"; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = 63W2ZKR3Z7; MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 2; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks"; SWIFT_OPTIMIZATION_LEVEL = "'+('-Onone' if kind=='Debug' else '-O')+'";'
 obj('app'+kind,f'isa = XCBuildConfiguration; name = {kind}; buildSettings = {{ {settings} }};')
for scope in ['app','project']:obj(scope+'configs','isa = XCConfigurationList; buildConfigurations = ('+ident(scope+'Debug')+','+ident(scope+'Release')+'); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target','isa = PBXNativeTarget; name = NoteNarrateMusic; productName = NoteNarrateMusic; productType = "com.apple.product-type.application"; productReference = '+product+'; buildConfigurationList = '+ident('appconfigs')+'; buildPhases = ('+','.join(ident(x) for x in ['sources','frameworks','resources'])+'); dependencies = (); buildRules = ();')

watchFiles=['../iosPrototype/WatchApp/NoteNarrateWatchApp.swift','../iosPrototype/WatchApp/WatchSessionLink.swift','../iosPrototype/Sources/Core/WatchCompanion.swift']
watchRefs=[];watchBuilds=[]
for f in watchFiles:
 if f not in files: refs.append(obj(f,'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "'+f+'"; sourceTree = "<group>";'))
 watchBuilds.append(obj(f+'watchbuild','isa = PBXBuildFile; fileRef = '+ident(f)+';'))
f='../iosPrototype/WatchApp/Assets.xcassets'
refs.append(obj(f,'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "'+f+'"; sourceTree = "<group>";'))
watchResource=obj(f+'watchbuild','isa = PBXBuildFile; fileRef = '+ident(f)+';')
watchProduct=obj('watchproduct','isa = PBXFileReference; explicitFileType = wrapper.application; path = NoteNarrateMusicWatch.app; sourceTree = BUILT_PRODUCTS_DIR;')
for kind in ['Debug','Release']:
 obj('watch'+kind,'isa = XCBuildConfiguration; name = '+kind+'; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.stivy.notenarrate.applemusic.watchapp; PRODUCT_NAME = NoteNarrateMusicWatch; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = NoteNarrate; INFOPLIST_KEY_WKApplication = YES; INFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.stivy.notenarrate.applemusic; INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = NO; SDKROOT = watchos; SUPPORTED_PLATFORMS = "watchos watchsimulator"; WATCHOS_DEPLOYMENT_TARGET = 10.0; TARGETED_DEVICE_FAMILY = 4; SWIFT_VERSION = 6.0; SWIFT_ACTIVE_COMPILATION_CONDITIONS = APPLE_MUSIC; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = 63W2ZKR3Z7; SKIP_INSTALL = YES; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 2;};')
obj('watchconfigs','isa = XCConfigurationList; buildConfigurations = ('+ident('watchDebug')+','+ident('watchRelease')+'); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('watchsources','isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+','.join(watchBuilds)+'); runOnlyForDeploymentPostprocessing = 0;')
obj('watchresources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ('+watchResource+'); runOnlyForDeploymentPostprocessing = 0;')
obj('watchframeworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('watchtarget','isa = PBXNativeTarget; name = NoteNarrateMusicWatch; productName = NoteNarrateMusicWatch; productType = "com.apple.product-type.application"; productReference = '+watchProduct+'; buildConfigurationList = '+ident('watchconfigs')+'; buildPhases = ('+','.join(ident(x) for x in ['watchsources','watchframeworks','watchresources'])+'); dependencies = (); buildRules = ();')
obj('watchproxy','isa = PBXContainerItemProxy; containerPortal = '+ident('project')+'; proxyType = 1; remoteGlobalIDString = '+ident('watchtarget')+'; remoteInfo = NoteNarrateMusicWatch;')
obj('watchdependency','isa = PBXTargetDependency; target = '+ident('watchtarget')+'; targetProxy = '+ident('watchproxy')+';')
obj('watchembedfile','isa = PBXBuildFile; fileRef = '+watchProduct+'; settings = {ATTRIBUTES = (RemoveHeadersOnCopy,);};')
obj('watchembedphase','isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"; dstSubfolderSpec = 16; files = ('+ident('watchembedfile')+'); name = "Embed Watch Content"; runOnlyForDeploymentPostprocessing = 0;')
objects[:]=[entry.replace('dependencies = (); buildRules = ();','dependencies = ('+ident('watchdependency')+'); buildRules = ();').replace(ident('resources')+');',ident('resources')+','+ident('watchembedphase')+');') if entry.startswith(ident('target')+' =') else entry for entry in objects]
objects[:]=[entry for entry in objects if not entry.startswith(ident('main')+' =')]
obj('main','isa = PBXGroup; children = ('+','.join(refs+[product,watchProduct])+'); sourceTree = "<group>";')

obj('project','isa = PBXProject; attributes = {LastUpgradeCheck = 2720; TargetAttributes = {'+ident('target')+' = {SystemCapabilities = { com.apple.BackgroundModes = {enabled = 1;};};};};}; buildConfigurationList = '+ident('projectconfigs')+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = it; knownRegions = (it,en,Base); mainGroup = '+ident('main')+'; projectDirPath = ""; projectRoot = ""; targets = ('+ident('target')+','+ident('watchtarget')+');')
(base/'NoteNarrateMusic.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+ident('project')+'; }')
ref=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target")}" BuildableName="NoteNarrateMusic.app" BlueprintName="NoteNarrateMusic" ReferencedContainer="container:NoteNarrateMusic.xcodeproj"/>'
(base/'NoteNarrateMusic.xcodeproj/xcshareddata/xcschemes/NoteNarrateMusic.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme version="1.3"><BuildAction><BuildActionEntries><BuildActionEntry buildForRunning="YES" buildForTesting="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
info={'CFBundleDevelopmentRegion':'it','CFBundleLocalizations':['it','en'],'CFBundleDisplayName':'NoteNarrate','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)','LSRequiresIPhoneOS':True,'NSAppleMusicUsageDescription':'NoteNarrate accede a brani, album e playlist per riprodurre la tua musica con Apple Music.','LicensedLyricsEndpoint':'$(LICENSED_LYRICS_ENDPOINT)','ITSAppUsesNonExemptEncryption':False,'UILaunchScreen':{},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{'CPTemplateApplicationSceneSessionRoleApplication':[{'UISceneConfigurationName':'CarPlay','UISceneClassName':'CPTemplateApplicationScene','UISceneDelegateClassName':'$(PRODUCT_MODULE_NAME).MusicCarPlayScene'}]}},'UIBackgroundModes':['audio'],'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight']}
(base/'Info.plist').write_bytes(plistlib.dumps(info,sort_keys=False))
