import Foundation
import CryptoKit

let expectedFirmwareSHA256 = "0d4cfd7974a19a94f4d42eb2d160d5a3e71cca1cfa61bd2cc063cf3f36ffd32e"
func validateFirmware(_ data: Data) throws -> (count: Int, digest: String) {
    let bytes = Array(data)
    try require(bytes.count >= 36, "Incomplete firmware header")
    func little(_ offset: Int, _ size: Int) -> UInt32 {
        (0..<size).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }
    let name = String(decoding: bytes.prefix(32).prefix { $0 != 0 }, as: UTF8.self)
    let count = Int(little(34, 2))
    try require(name == "xc2028 firmware" && little(32, 2) == 0x0207 && count == 80, "Unexpected XC3028 v2.7 container")
    var offset = 36
    for image in 0..<count {
        try require(offset + 12 <= bytes.count, "Incomplete header in image \(image)")
        let kind = little(offset, 4)
        offset += 12
        if kind & (1 << 30) != 0 {
            try require(offset + 2 <= bytes.count, "Incomplete IF frequency in image \(image)")
            offset += 2
        }
        try require(offset + 4 <= bytes.count, "Incomplete length in image \(image)")
        let size = Int(little(offset, 4))
        offset += 4
        try require(size > 0 && size <= bytes.count - offset, "Incomplete data in image \(image)")
        offset += size
    }
    try require(offset == bytes.count, "Extra data after the 80 images")
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    try require(digest == expectedFirmwareSHA256, "SHA-256 differs from the expected firmware: \(digest)")
    return (count, digest)
}
func verifyFirmware(at url: URL) throws {
    let data = try Data(contentsOf: url)
    let result = try validateFirmware(data)
    print("Valid XC3028 v2.7 firmware: \(data.count) bytes, \(result.count) images")
    print("SHA-256: \(result.digest)")
}
