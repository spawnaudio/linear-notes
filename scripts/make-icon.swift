import AppKit

// Draw the app's original vector artwork at each macOS icon size.
let target = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let size = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024); transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 1), ending: NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1))!.draw(in: background, angle: -90)
    NSColor(white: 1, alpha: 0.10).setStroke(); background.lineWidth = 3; background.stroke()
    let page = NSBezierPath(roundedRect: NSRect(x: 273, y: 226, width: 478, height: 578), xRadius: 37, yRadius: 37)
    NSGradient(starting: NSColor(red: 0.92, green: 0.92, blue: 0.98, alpha: 1), ending: NSColor(red: 0.72, green: 0.72, blue: 0.85, alpha: 1))!.draw(in: page, angle: -90)
    NSColor(red: 0.37, green: 0.35, blue: 0.61, alpha: 0.9).setFill()
    for (y, width, height) in [(649, 253, 34), (536, 314, 19), (474, 314, 19), (412, 221, 19)] {
        NSBezierPath(roundedRect: NSRect(x: 355, y: CGFloat(y), width: CGFloat(width), height: CGFloat(height)), xRadius: 9, yRadius: 9).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: target.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
