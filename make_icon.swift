import AppKit

// Generates the WO app icon — composites video_5154901.png onto dark rounded background.
// Usage: swift make_icon.swift <output-dir>

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let canvas: CGFloat = 1024
let inset: CGFloat = 100
let cornerRadius: CGFloat = 185

guard let sourceImage = NSImage(contentsOfFile: "resources/icon-source.png") else {
    FileHandle.standardError.write(Data("failed to load video_5154901.png\n".utf8))
    exit(1)
}

func renderIcon(pixelSize px: Int) -> NSBitmapImageRep? {
    let scale = CGFloat(px) / canvas

    guard let ctx = CGContext(data: nil, width: px, height: px,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    let aw = (canvas - inset * 2) * scale
    let artRect = CGRect(x: inset * scale, y: inset * scale, width: aw, height: aw)
    let bgPath = CGPath(roundedRect: artRect,
                        cornerWidth: cornerRadius * scale, cornerHeight: cornerRadius * scale,
                        transform: nil)

    // Dark charcoal gradient background
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let top = CGColor(srgbRed: 0.22, green: 0.22, blue: 0.23, alpha: 1)
    let mid = CGColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    let bottom = CGColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)
    let bgGrad = CGGradient(colorsSpace: cs, colors: [top, mid, bottom] as CFArray,
                            locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(bgGrad,
                           start: CGPoint(x: artRect.midX, y: artRect.maxY),
                           end: CGPoint(x: artRect.midX, y: artRect.minY),
                           options: [])
    ctx.restoreGState()

    // Draw source image centered, scaled to 50% of art area
    let drawW = artRect.width * 0.65
    let drawH = artRect.height * 0.65
    let drawRect = CGRect(
        x: artRect.midX - drawW / 2,
        y: artRect.midY - drawH / 2,
        width: drawW, height: drawH)
    if let cgSource = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.draw(cgSource, in: drawRect)
    }

    guard let cg = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: cg)
}

// MARK: - Export full iconset

let fm = FileManager.default
let iconsetURL = URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconsetURL)
try! fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, px) in sizes {
    guard let rep = renderIcon(pixelSize: px),
          let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
        continue
    }
    try! data.write(to: iconsetURL.appendingPathComponent(name))
    print("wrote \(name)")
}
print("done: \(iconsetURL.path)")
