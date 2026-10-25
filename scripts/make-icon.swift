import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
let symbolName = NSImage(systemSymbolName: "sailboat", accessibilityDescription: nil) == nil ? "ferry" : "sailboat"
for (name, pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor(red: 0.055, green: 0.063, blue: 0.071, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: size * 0.06, y: size * 0.06, width: size * 0.88, height: size * 0.88), xRadius: size * 0.2, yRadius: size * 0.2).fill()
    if let configured = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size * 0.52, weight: .medium)) {
        let tinted = NSImage(size: configured.size)
        tinted.lockFocus()
        configured.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor(red: 0.81, green: 0.98, blue: 0.36, alpha: 1).set()
        NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let scale = min(size * 0.62 / configured.size.width, size * 0.62 / configured.size.height)
        let width = configured.size.width * scale
        let height = configured.size.height * scale
        tinted.draw(in: NSRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height))
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
}
