import Foundation

func isAntena(_ url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
    return plist["CFBundleIdentifier"] as? String == "local.antena.television"
}
func copyCleanTree(source: URL, destination: URL) throws {
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    let entries = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    for entry in entries {
        let name = entry.lastPathComponent
        if name.hasPrefix("._") || name == ".DS_Store" { continue }
        let target = destination.appendingPathComponent(name)
        let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            try fileManager.createSymbolicLink(atPath: target.path, withDestinationPath: fileManager.destinationOfSymbolicLink(atPath: entry.path))
        } else if values.isDirectory == true {
            try copyCleanTree(source: entry, destination: target)
        } else {
            // Copy bytes rather than metadata so generated bundles are signable.
            try Data(contentsOf: entry).write(to: target)
            let attributes = try fileManager.attributesOfItem(atPath: entry.path)
            try fileManager.setAttributes([.posixPermissions: attributes[.posixPermissions] ?? 0o644], ofItemAtPath: target.path)
        }
    }
}
func stageApp(source: URL) throws {
    let target = URL(fileURLWithPath: "/private/tmp/Antena-Local/Antena.app")
    try require(source.resolvingSymlinksInPath() != target.resolvingSymlinksInPath(), "Source and staging destination must differ")
    try require(isAntena(source), "Unexpected application bundle")
    if fileManager.fileExists(atPath: target.path) {
        try require(isAntena(target), "Refusing to replace another application")
        try fileManager.removeItem(at: target)
    }
    try copyCleanTree(source: source, destination: target)
    let binaries = try fileManager.contentsOfDirectory(at: target.appendingPathComponent("Contents/MacOS"), includingPropertiesForKeys: [.isRegularFileKey])
    for binary in binaries where (try binary.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        if binary.pathExtension == "dylib" || binary.lastPathComponent == "kworld-tv" {
            let result = try run("/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", binary.path])
            FileHandle.standardError.write(result.output)
        }
    }
    try run("/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", target.path])
    try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", target.path])
    print(target.path)
}
