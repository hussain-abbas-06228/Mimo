// Generates the LiveTranslate app icon: parrot mascot on an indigo→violet
// gradient squircle with two "subtitle" bars. Writes a full .iconset folder.
// Usage: swift scripts/make-icon.swift assets/AppIcon.iconset
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let f = CGFloat(px) / 1024.0

    // Squircle background
    let inset = 90.0 * f
    let rect = NSRect(x: inset, y: inset,
                      width: CGFloat(px) - inset * 2, height: CGFloat(px) - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: 190 * f, yRadius: 190 * f)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.32, green: 0.45, blue: 0.97, alpha: 1.0),  // blue (top)
        NSColor(calibratedRed: 0.47, green: 0.28, blue: 0.93, alpha: 1.0),  // violet (bottom)
    ])!
    gradient.draw(in: squircle, angle: 270)

    // Soft top highlight for depth
    squircle.addClip()
    let gloss = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.20),
        NSColor.white.withAlphaComponent(0.0),
    ])!
    gloss.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2),
               angle: 270)

    // Parrot mascot
    let emoji = "🦜"
    let font = NSFont.systemFont(ofSize: 470 * f)
    let attr = NSAttributedString(string: emoji, attributes: [.font: font])
    let size = attr.size()
    attr.draw(at: NSPoint(x: (CGFloat(px) - size.width) / 2,
                          y: CGFloat(px) * 0.345))

    // Subtitle bars
    func bar(width: CGFloat, centerY: CGFloat, alpha: CGFloat) {
        let h = 58 * f
        let r = NSRect(x: (CGFloat(px) - width) / 2, y: centerY - h / 2, width: width, height: h)
        NSColor.white.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2).fill()
    }
    bar(width: 400 * f, centerY: 268 * f, alpha: 0.95)
    bar(width: 250 * f, centerY: 180 * f, alpha: 0.55)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(px: Int, name: String) {
    let rep = render(px: px)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

for (base, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                      (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = base * scale
    let name = scale == 1 ? "icon_\(base)x\(base)" : "icon_\(base)x\(base)@2x"
    write(px: px, name: name)
}
print("Icon set written to \(outDir)")
