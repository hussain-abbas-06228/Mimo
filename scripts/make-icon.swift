// Generates the Mimo app icon: two overlapping orbs (coral = German,
// blue = English) sharing one pair of eyes, on a dark squircle.
// Writes a full .iconset folder.
// Usage: swift scripts/make-icon.swift assets/AppIcon.iconset
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let f = CGFloat(px) / 1024.0
    let c = CGFloat(px) / 2

    // Dark squircle background
    let inset = 90.0 * f
    let rect = NSRect(x: inset, y: inset,
                      width: CGFloat(px) - inset * 2, height: CGFloat(px) - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: 190 * f, yRadius: 190 * f)
    NSGradient(colors: [rgb(38, 38, 46), rgb(18, 18, 23)])!.draw(in: squircle, angle: 270)

    // Mascot, in design units (orbs 200 wide, centres 130 apart) scaled to the tile
    let u = 2.1 * f
    func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: c + (cx - w / 2) * u, y: c + (cy - h / 2) * u,
                                    width: w * u, height: h * u)).fill()
    }
    oval(-65, 0, 200, 200, rgb(255, 112, 90))        // German orb
    oval(65, 0, 200, 200, rgb(70, 140, 255, 0.85))   // English orb
    oval(-38, 22, 42, 52, rgb(24, 22, 40))           // eyes
    oval(38, 22, 42, 52, rgb(24, 22, 40))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(px: Int, name: String) {
    let data = render(px: px).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

for (base, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                      (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = base * scale
    let name = scale == 1 ? "icon_\(base)x\(base)" : "icon_\(base)x\(base)@2x"
    write(px: px, name: name)
}
print("Icon set written to \(outDir)")
