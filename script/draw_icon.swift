import AppKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var entries: [[String: Any]] = []
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let t = AffineTransform(scale: CGFloat(pixels) / 1024)
        (t as NSAffineTransform).concat()
        let shape = NSBezierPath(roundedRect: NSRect(x: 65,y: 65,width: 894,height: 894), xRadius: 205,yRadius: 205)
        NSGradient(starting: NSColor(red: 0.12, green: 0.22, blue: 0.40, alpha: 1), ending: NSColor(red: 0.025, green: 0.04, blue: 0.08, alpha: 1))!.draw(in: shape, angle: -75)
        let attrs: [NSAttributedString.Key:Any] = [.font: NSFont.systemFont(ofSize: 670, weight: .heavy), .foregroundColor: NSColor.white]
        ("a" as NSString).draw(at: NSPoint(x: 220, y: 130), withAttributes: attrs)
        NSColor(red: 0.42, green: 0.88, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 709,y: 271,width: 102,height: 102)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let file = "icon-\(size)-\(scale)x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(file))
        entries.append(["idiom":"mac", "size":"\(size)x\(size)", "scale":"\(scale)x", "filename":file])
    }
}
let data = try JSONSerialization.data(withJSONObject: ["images":entries,"info":["author":"xcode","version":1]], options: [.prettyPrinted,.sortedKeys])
try data.write(to: directory.appendingPathComponent("Contents.json"))
