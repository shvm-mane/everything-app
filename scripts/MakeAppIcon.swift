// Builds Resources/AppIcon.icns from a square photo, shaped like a macOS
// app icon: an 824 pt continuous rounded square on the 1024 grid, with the
// system's soft drop shadow.
//   swift scripts/MakeAppIcon.swift <photo> <output.icns>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: MakeAppIcon <photo> <output.icns>"); exit(1)
}

func render(_ pixels: Int) -> Data? {
    let scale = CGFloat(pixels) / 1024
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    // Continuous corners approximated with a superellipse-ish radius.
    let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    // Center-crop the photo to the body.
    let side = CGFloat(min(cg.width, cg.height))
    let crop = CGRect(x: (CGFloat(cg.width) - side) / 2, y: (CGFloat(cg.height) - side) / 2, width: side, height: side)
    if let square = cg.cropping(to: crop) { ctx.draw(square, in: body) }
    // A faint top sheen and inner edge, as system icons have.
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                           colors: [CGColor(gray: 1, alpha: 0.16), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    // The "sum" symbol, white, centred, with a soft shadow to lift it off the photo.
    let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "sum", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let fit = 440 / max(symbol.size.width, symbol.size.height)
        let size = CGSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
        let rect = CGRect(x: 512 - size.width / 2, y: 512 - size.height / 2, width: size.width, height: size.height)
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        symbol.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.18)); ctx.setLineWidth(2); ctx.strokePath()
    guard let image = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try? render(base * factor)?.write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", args[2]]
try task.run(); task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "wrote \(args[2])" : "iconutil failed")
