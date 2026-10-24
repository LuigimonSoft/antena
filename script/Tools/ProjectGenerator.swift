import Foundation
import CryptoKit

func generateProject() throws {
    let root = projectRoot
    var objects: [String] = []
    var children: [String: [String]] = [:]
    func uid(_ key: String) -> String {
        Insecure.SHA1.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02X", $0) }.joined()
    }
    func quote(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes])
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
    @discardableResult func object(_ key: String, _ body: String) -> String {
        let id = uid(key)
        objects.append("\(id) = { \(body) };")
        return id
    }
    func parent(_ path: String) -> String {
        let parts = path.split(separator: "/").dropLast()
        return parts.joined(separator: "/")
    }
    func reference(_ url: URL, _ type: String) -> String {
        let path = relativePath(url)
        let id = object(path, "isa = PBXFileReference; lastKnownFileType = \(type); path = \(quote(url.lastPathComponent)); sourceTree = \"<group>\";")
        children[parent(path), default: []].append(id)
        return id
    }
    let appFiles = files(in: root.appendingPathComponent("Antena"))
    let sourceFiles = appFiles.filter { $0.pathExtension == "swift" } + appFiles.filter { $0.pathExtension == "c" && relativePath($0).hasPrefix("Antena/Bridge/") }
    var builds: [String] = []
    for file in sourceFiles {
        let ref = reference(file, file.pathExtension == "swift" ? "sourcecode.swift" : "sourcecode.c.c")
        builds.append(object("build:" + relativePath(file), "isa = PBXBuildFile; fileRef = \(ref);"))
    }
    for file in appFiles where file.pathExtension == "h" && relativePath(file).hasPrefix("Antena/Bridge/") {
        _ = reference(file, "sourcecode.c.h")
    }
    let asset = object("assets", "isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\";")
    children["Antena/Resources", default: []].append(asset)
    let assetBuild = object("assets-build", "isa = PBXBuildFile; fileRef = \(asset);")
    let translations = ["en", "es", "fr"].map { language in
        object("strings:" + language, "isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = \(language); path = \"\(language).lproj/Localizable.strings\"; sourceTree = \"<group>\";")
    }
    let localized = object("localized-strings", "isa = PBXVariantGroup; children = (\(translations.joined(separator: ","))); name = Localizable.strings; sourceTree = \"<group>\";")
    children["Antena/Resources", default: []].append(localized)
    let localizedBuild = object("localized-strings-build", "isa = PBXBuildFile; fileRef = \(localized);")
    let resources = object("resources", "isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (\(assetBuild),\(localizedBuild)); runOnlyForDeploymentPostprocessing = 0;")
    let types = ["yml": "text.yaml", "yaml": "text.yaml", "swift": "sourcecode.swift", "c": "sourcecode.c.c", "h": "sourcecode.c.h", "sh": "text.script.sh", "md": "net.daringfireball.markdown", "json": "text.json"]
    let folders = [".github", "Sources", "Tests", "script", "docs", "firmware"]
    for folder in folders {
        for file in files(in: root.appendingPathComponent(folder)) where file.lastPathComponent != "RECOVERY.md" {
            if let type = types[file.pathExtension] { _ = reference(file, type) }
        }
    }
    let rootFiles = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    for file in rootFiles.filter({ $0.lastPathComponent.hasPrefix("README") && $0.pathExtension == "md" }).sorted(by: { $0.path < $1.path }) {
        _ = reference(file, "net.daringfireball.markdown")
    }
    _ = reference(root.appendingPathComponent("LICENSE"), "text")
    _ = reference(root.appendingPathComponent("Makefile"), "sourcecode.make")
    _ = reference(root.appendingPathComponent("VERSION"), "text")
    func group(_ directory: String) -> String {
        let prefix = directory + "/"
        let subdirectories = Set(children.keys.filter { $0.hasPrefix(prefix) }.compactMap { $0.dropFirst(prefix.count).split(separator: "/").first.map(String.init) }).sorted()
        let members = subdirectories.map { group(directory + "/" + $0) } + (children[directory] ?? [])
        let name = directory.split(separator: "/").last.map(String.init) ?? directory
        return object("group:" + directory, "isa = PBXGroup; children = (\(members.joined(separator: ","))); path = \(quote(name)); sourceTree = \"<group>\";")
    }
    let roots = (["Antena"] + folders).map(group)
    let product = object("product", "isa = PBXFileReference; explicitFileType = wrapper.application; path = Antena.app; sourceTree = BUILT_PRODUCTS_DIR;")
    let products = object("products", "isa = PBXGroup; children = (\(product)); name = Products; sourceTree = \"<group>\";")
    let members = roots + (children[""] ?? []) + [products]
    let main = object("main", "isa = PBXGroup; children = (\(members.joined(separator: ","))); sourceTree = \"<group>\";")
    let sources = object("sources", "isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\(builds.joined(separator: ","))); runOnlyForDeploymentPostprocessing = 0;")
    let shell = object("runtime", "isa = PBXShellScriptBuildPhase; alwaysOutOfDate = 1; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/bash; name = \"Embed tuner and VideoLAN runtime\"; shellScript = \(quote("\"$SRCROOT/script/embed_runtime.sh\""));")
    let settings = [
        "VLC_ROOT": "$(SRCROOT)/Vendor/VLC", "SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "27.0", "ARCHS": "arm64",
        "SWIFT_VERSION": "5.0", "SWIFT_STRICT_CONCURRENCY": "minimal", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "PRODUCT_NAME": "Antena", "PRODUCT_BUNDLE_IDENTIFIER": "local.antena.television", "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_CFBundleDevelopmentRegion": "en", "INFOPLIST_KEY_CFBundleDisplayName": "Antena",
        "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.entertainment", "INFOPLIST_KEY_NSHighResolutionCapable": "YES",
        "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "-", "ENABLE_HARDENED_RUNTIME": "NO", "ENABLE_APP_SANDBOX": "NO",
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO", "COMBINE_HIDPI_IMAGES": "YES", "SWIFT_OBJC_BRIDGING_HEADER": "Antena/Bridge/Antena-Bridging-Header.h",
        "HEADER_SEARCH_PATHS": "$(inherited) \"$(VLC_ROOT)/include\" \"$(SRCROOT)/Antena/Bridge\"", "LIBRARY_SEARCH_PATHS": "$(inherited) \"$(VLC_ROOT)/lib\"",
        "OTHER_LDFLAGS": "$(inherited) -lvlc", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Resources/VLC/lib @loader_path/../Resources/VLC/lib",
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": (try String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines)
    ]
    var configs: [String] = []
    for name in ["Debug", "Release"] {
        var config = settings
        config["SWIFT_OPTIMIZATION_LEVEL"] = name == "Debug" ? "-Onone" : "-O"
        config["DEBUG_INFORMATION_FORMAT"] = name == "Debug" ? "dwarf" : "dwarf-with-dsym"
        if name == "Debug" { config["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG" }
        let body = config.keys.sorted().map { "\($0) = \(quote(config[$0]!));" }.joined()
        configs.append(object("target-config:" + name, "isa = XCBuildConfiguration; name = \(name); buildSettings = {\(body)};"))
    }
    let targetConfigs = object("target-configs", "isa = XCConfigurationList; buildConfigurations = (\(configs.joined(separator: ","))); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    let projectConfigs = ["Debug", "Release"].map { object("project-config:" + $0, "isa = XCBuildConfiguration; name = \($0); buildSettings = {};") }
    let pc = object("project-configs", "isa = XCConfigurationList; buildConfigurations = (\(projectConfigs.joined(separator: ","))); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    let target = object("target", "isa = PBXNativeTarget; buildConfigurationList = \(targetConfigs); buildPhases = (\(sources),\(resources),\(shell)); buildRules = (); dependencies = (); name = Antena; productName = Antena; productReference = \(product); productType = \"com.apple.product-type.application\";")
    let project = object("project", "isa = PBXProject; attributes = { BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; }; buildConfigurationList = \(pc); compatibilityVersion = \"Xcode 14.0\"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,es,fr,Base); mainGroup = \(main); productRefGroup = \(products); projectDirPath = \"\"; projectRoot = \"\"; targets = (\(target));")
    try write("// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n" + objects.joined(separator: "\n") + "\n}; rootObject = \(project); }\n", to: root.appendingPathComponent("Antena.xcodeproj/project.pbxproj"))
    let scheme = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme LastUpgradeVersion="2700" version="1.3">
     <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="\(target)" BuildableName="Antena.app" BlueprintName="Antena" ReferencedContainer="container:Antena.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
     <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="\(target)" BuildableName="Antena.app" BlueprintName="Antena" ReferencedContainer="container:Antena.xcodeproj"/></BuildableProductRunnable></LaunchAction>
     <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
     <AnalyzeAction buildConfiguration="Debug"/>
     <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
    </Scheme>
    """
    try write(scheme + "\n", to: root.appendingPathComponent("Antena.xcodeproj/xcshareddata/xcschemes/Antena.xcscheme"))
    print("Generated Antena.xcodeproj (\(sourceFiles.count) app sources)")
}
