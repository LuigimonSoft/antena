import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let help = """
Usage: ./script/antena_tools.sh COMMAND [ARGUMENTS]
  verify-firmware [FILE]    Validate the exact XC3028 v2.7 container
  inspect-ts FILE          Inspect MPEG-TS PAT/PMT/VCT and section CRCs
  generate-project         Regenerate Antena.xcodeproj deterministically
  stage-app APP            Copy and sign Antena on APFS
  package-dmg APP          Create and verify an installable disk image
  prepare-github [--check]  Validate or export public sources
  self-test                Run tooling regression tests (no USB required)
"""
do {
    switch arguments.first {
    case "verify-firmware":
        try require(arguments.count <= 2, help)
        try verifyFirmware(at: URL(fileURLWithPath: arguments.count == 2 ? arguments[1] : "firmware/xc3028-v27.fw"))
    case "inspect-ts":
        try require(arguments.count == 2, help)
        let report = try inspectTransport(at: URL(fileURLWithPath: arguments[1]))
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        print(String(decoding: data, as: UTF8.self))
        let programs = report["programs"] as? [[String: Any]] ?? []
        try require(programs.contains { !($0["streams"] as? [[String: Any]] ?? []).isEmpty }, "No complete PAT/PMT verified")
    case "generate-project":
        try require(arguments.count == 1, help)
        try generateProject()
    case "stage-app":
        try require(arguments.count == 2, help)
        try stageApp(source: URL(fileURLWithPath: arguments[1]))
    case "package-dmg":
        try require(arguments.count == 2, help)
        try packageDMG(source: URL(fileURLWithPath: arguments[1]))
    case "prepare-github":
        try require(arguments.count == 1 || arguments == ["prepare-github", "--check"], help)
        try prepareGitHub(checkOnly: arguments.count == 2)
    case "self-test":
        try require(arguments.count == 1, help)
        try toolingSelfTest()
    case "--help", "help", nil:
        print(help)
    default: throw ToolError(help)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
