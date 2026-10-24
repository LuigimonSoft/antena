import Foundation

let sourceDirectories: Set<String> = [".github", "Antena", "Antena.xcodeproj", "Sources", "Tests", "script", "docs", "firmware", "Reference"]
let rootFiles: Set<String> = ["README.md", "README.es.md", "README.fr.md", "LICENSE", "Makefile", "VERSION", ".gitignore", ".gitattributes"]
let textExtensions: Set<String> = ["yml", "yaml", "swift", "c", "h", "sh", "md", "txt", "json", "strings", "pbxproj", "xcscheme", "plist", "pl"]
func publicSourceFiles() throws -> [String] {
    try withTemporaryDirectory { temporary in
        let repository = temporary.appendingPathComponent("repository")
        try run("/usr/bin/git", ["init", "--quiet", repository.path])
        let arguments = ["-c", "core.excludesFile=/dev/null", "--git-dir=" + repository.appendingPathComponent(".git").path, "--work-tree=" + projectRoot.path]
        let result = try run("/usr/bin/git", arguments + ["ls-files", "--others", "--exclude-standard", "-z"])
        let files = result.output.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }.sorted()
        let examples = [".codex/environments/environment.toml", ".agents/notes.md", "AGENTS.md", "docs/RECOVERY.md", "build/test", "dist/test.zip", "firmware/test.fw", "Vendor/VLC/lib/test.dylib", "recordings/test.ts", "Antena/._test.swift", "Antena.xcodeproj/xcuserdata/test.xcuserdatad/state"]
        let check = try run("/usr/bin/git", arguments + ["check-ignore", "--no-index", "--stdin"], input: Data((examples.joined(separator: "\n") + "\n").utf8), allowFailure: true)
        try require(Set(check.text.split(separator: "\n").map(String.init)) == Set(examples), "Ignore rules do not exclude all local-only examples")
        return files
    }
}
func validatePublicSources(_ files: [String]) throws {
    let available = Set(files)
    let required = rootFiles.union(["Antena.xcodeproj/project.pbxproj", "Antena.xcodeproj/xcshareddata/xcschemes/Antena.xcscheme", "firmware/PROVENANCE.md", "script/build_and_run.sh", "script/antena_tools.sh"])
    try require(required.isSubset(of: available), "Missing required public files: " + required.subtracting(available).sorted().joined(separator: ", "))
    let pattern = "/" + #"(?:Users|Volumes)/[A-Za-z0-9][^/\s"']*"#
    let personalPath = try NSRegularExpression(pattern: pattern)
    for file in files {
        let components = file.split(separator: "/").map(String.init)
        try require(rootFiles.contains(file) || sourceDirectories.contains(components.first ?? ""), "Unexpected public file: " + file)
        let url = projectRoot.appendingPathComponent(file)
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        try require(values.isSymbolicLink != true && values.isRegularFile == true, "Source exports require regular files: " + file)
        try require(!["py", "pyc", "pyo"].contains(url.pathExtension), "Unsupported source language: " + file)
        if textExtensions.contains(url.pathExtension) || rootFiles.contains(file) {
            let text = try String(contentsOf: url, encoding: .utf8)
            try require(personalPath.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil, "Workstation-specific path in: " + file)
        }
    }
    let repository = try run("/usr/bin/git", ["-C", projectRoot.path, "rev-parse", "--show-toplevel"], allowFailure: true)
    if repository.status == 0 && URL(fileURLWithPath: repository.text.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath() == projectRoot.resolvingSymlinksInPath() {
        let tracked = try run("/usr/bin/git", ["-C", projectRoot.path, "ls-files", "-z"])
        let unexpected = Set(tracked.output.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }).subtracting(available)
        try require(unexpected.isEmpty, "Tracked files outside public source rules: " + unexpected.sorted().joined(separator: ", "))
    }
}
func prepareGitHub(checkOnly: Bool) throws {
    let files = try publicSourceFiles()
    try validatePublicSources(files)
    print("PASS: \(files.count) public source files; ignore rules and workstation paths checked")
    guard !checkOnly else { return }
    let destination = projectRoot.appendingPathComponent("dist")
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    let archive = destination.appendingPathComponent("Antena-source.zip")
    try withTemporaryDirectory { temporary in
        let clean = temporary.appendingPathComponent("Antena-source")
        for file in files {
            let target = clean.appendingPathComponent(file)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: projectRoot.appendingPathComponent(file)).write(to: target)
            let executable = file.hasPrefix("script/") && target.pathExtension == "sh"
            try fileManager.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: target.path)
        }
        // macOS ships ditto; no package manager or archive library is required.
        let pending = temporary.appendingPathComponent("Antena-source.zip")
        try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", clean.path, pending.path])
        try run("/usr/bin/unzip", ["-t", pending.path])
        try Data(contentsOf: pending).write(to: archive, options: .atomic)
    }
    let manifest = destination.appendingPathComponent("github-manifest.txt")
    try write(files.joined(separator: "\n") + "\n", to: manifest)
    print(archive.path)
    print(manifest.path)
}
