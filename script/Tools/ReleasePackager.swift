import Foundation

private func isMachO(_ url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 4) else { return false }
    return [[0xcf, 0xfa, 0xed, 0xfe], [0xfe, 0xed, 0xfa, 0xcf], [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca]].contains(Array(data))
}
func packageDMG(source: URL) throws {
    try require(isAntena(source), "Expected the Antena application bundle")
    let infoData = try Data(contentsOf: source.appendingPathComponent("Contents/Info.plist"))
    let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as! [String: Any]
    guard let version = info["CFBundleShortVersionString"] as? String,
          version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else { throw ToolError("Expected a numeric major.minor.patch application version") }
    try require(info["CFBundleExecutable"] as? String == "Antena", "Unexpected application executable")
    let staging = URL(fileURLWithPath: "/private/tmp/Antena-release-" + UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: staging) }
    let imageRoot = staging.appendingPathComponent("image")
    let app = imageRoot.appendingPathComponent("Antena.app")
    try copyCleanTree(source: source, destination: app)
    let executable = app.appendingPathComponent("Contents/MacOS/Antena")
    let architectures = try run("/usr/bin/xcrun", ["lipo", "-archs", executable.path]).text.split(whereSeparator: \.isWhitespace).map(String.init)
    try require(architectures == ["arm64"], "This package requires an arm64-only Antena executable")
    for path in ["Contents/MacOS/kworld-tv", "Contents/Resources/VLC/lib/libvlc.dylib", "Contents/Resources/firmware/xc3028-v27.fw", "Contents/Resources/LICENSE-GPL-2.0.txt"] {
        try require(fileManager.fileExists(atPath: app.appendingPathComponent(path).path), "Missing runtime resource: " + path)
    }
    _ = try validateFirmware(Data(contentsOf: app.appendingPathComponent("Contents/Resources/firmware/xc3028-v27.fw")))
    let identity = ProcessInfo.processInfo.environment["SIGNING_IDENTITY"] ?? "-"
    let signing = ["--force", "--sign", identity] + (identity == "-" ? ["--timestamp=none"] : ["--timestamp", "--options", "runtime"])
    // Sign each real Mach-O file before signing the enclosing app. Following
    // library symlinks a second time is unnecessary and can break verification.
    for file in files(in: app).sorted(by: { $0.path.count > $1.path.count }) {
        let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { continue }
        let executableCode = isMachO(file)
        try fileManager.setAttributes([.posixPermissions: executableCode ? 0o755 : 0o644], ofItemAtPath: file.path)
        if executableCode {
            try run("/usr/bin/codesign", signing + [file.path])
        }
    }
    try run("/usr/bin/codesign", signing + [app.path])
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    try fileManager.createSymbolicLink(atPath: imageRoot.appendingPathComponent("Applications").path, withDestinationPath: "/Applications")
    try write("""
    Antena \(version) · Apple Silicon · macOS 27+
    Created by Luigimonsoft — https://github.com/luigimonsoft

    English: Drag Antena.app to Applications, then eject this disk image.
    Español: Arrastra Antena.app a Aplicaciones y expulsa esta imagen de disco.
    Français : Glissez Antena.app dans Applications, puis éjectez cette image disque.

    \(identity == "-" ? "Development package: ad hoc signed, not notarized by Apple." : "Developer ID signed. Notarization is a separate distribution step.")
    Firmware provenance and code license are included inside Antena.app/Contents/Resources.
    VideoLAN and station logos retain their respective terms and credits.
    """ + "\n", to: imageRoot.appendingPathComponent("INSTALL.txt"))
    let name = "Antena-\(version)-arm64.dmg"
    let image = staging.appendingPathComponent(name)
    try run("/usr/bin/hdiutil", ["create", "-volname", "Antena", "-fs", "HFS+", "-format", "UDZO", "-srcfolder", imageRoot.path, image.path])
    if identity != "-" { try run("/usr/bin/codesign", ["--force", "--sign", identity, "--timestamp", image.path]) }
    try run("/usr/bin/hdiutil", ["verify", image.path])
    let mount = staging.appendingPathComponent("mounted")
    try fileManager.createDirectory(at: mount, withIntermediateDirectories: true)
    try run("/usr/bin/hdiutil", ["attach", image.path, "-readonly", "-nobrowse", "-mountpoint", mount.path])
    do {
        let mountedApp = mount.appendingPathComponent("Antena.app")
        try require(isAntena(mountedApp), "The mounted disk image is missing Antena")
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", mountedApp.path])
        try require(try fileManager.destinationOfSymbolicLink(atPath: mount.appendingPathComponent("Applications").path) == "/Applications", "Missing Applications installation shortcut")
    } catch {
        _ = try? run("/usr/bin/hdiutil", ["detach", mount.path])
        throw error
    }
    try run("/usr/bin/hdiutil", ["detach", mount.path])
    let destination = projectRoot.appendingPathComponent("dist/" + name)
    try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contentsOf: image, options: .mappedIfSafe).write(to: destination, options: .atomic)
    print(destination.path)
}
