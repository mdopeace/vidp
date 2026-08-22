import AppKit
import CoreText

// Generates the OTV app icon (Apple TV style: dark rounded square, "otv" wordmark
// with subtle rainbow tint). Usage: swift make_icon.swift <output-dir>

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let canvas: CGFloat = 1024
let inset: CGFloat = 100          // artwork 824x824 on the macOS icon grid
let cornerRadius: CGFloat = 185

// MARK: - Font

func brandFont(_ size: CGFloat) -> CTFont {
    let pro = CTFontCreateWithName("SFPro-Medium" as CFString, size, nil)
    if CTFontCopyPostScriptName(pro) as String == "SFPro-Medium" { return pro }
    let sys = NSFont.systemFont(ofSize: size, weight: .medium)
    return CTFontCreateWithName(sys.fontName as CFString, size, nil)
}

func makeLine(_ text: String, _ font: CTFont) -> CTLine {
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTKernAttributeName: Float(CTFontGetSize(font) * 0.03),
    ]
    let astr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
    return CTLineCreateWithAttributedString(astr)
}

// MARK: - Ink bounding box scan (top-origin pixel coords)

func inkBounds(_ ctx: CGContext) -> CGRect {
    let w = ctx.width, h = ctx.height
    guard let data = ctx.data else { return .null }
    let buf = data.assumingMemoryBound(to: UInt8.self)
    let bpr = ctx.bytesPerRow
    let stepY = max(1, h / 400), stepX = max(1, w / 400)
    var minX = w, maxX = -1, minY = h, maxY = -1
    for y in stride(from: 0, to: h, by: stepY) {
        for x in stride(from: 0, to: w, by: stepX) {
            if buf[y * bpr + x] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX >= minX else { return .null }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

// MARK: - Glyph mask (alpha-only bitmap of the wordmark)

func glyphMask(line: CTLine, font: CTFont, width w: Int, height h: Int,
               baselineY: CGFloat, originX: CGFloat) -> (CGImage?, CGRect) {
    guard let ctx = CGContext(data: nil, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.linearGray)!,
                              bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return (nil, .null) }
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.textPosition = CGPoint(x: originX, y: baselineY)
    CTLineDraw(line, ctx)
    return (ctx.makeImage(), inkBounds(ctx))
}

// MARK: - Icon renderer

func renderIcon(pixelSize px: Int) -> NSBitmapImageRep? {
    let scale = CGFloat(px) / canvas

    guard let ctx = CGContext(data: nil, width: px, height: px,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    // Dark charcoal gradient background on the icon grid.
    let artRect = CGRect(x: inset * scale, y: inset * scale,
                         width: (canvas - inset * 2) * scale, height: (canvas - inset * 2) * scale)
    let path = CGPath(roundedRect: artRect,
                      cornerWidth: cornerRadius * scale, cornerHeight: cornerRadius * scale,
                      transform: nil)

    // Clip and draw gradient.
    ctx.saveGState()
    ctx.addPath(path)
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

    // Wordmark: fit "otv" to ~72% of artwork width, centered by actual INK bounds
    // (typographic boxes are optically misleading).
    var font = brandFont(420 * scale)
    var line = makeLine("otv", font)
    var lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    let maxW = artRect.width * 0.72
    if lineWidth > maxW {
        let fit = maxW / lineWidth
        font = brandFont(420 * scale * fit)
        line = makeLine("otv", font)
        lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)

    let pad: CGFloat = 4 * scale
    let maskW = Int(ceil(lineWidth + pad * 2))
    let maskH = Int(ceil(ascent + descent + pad * 2))
    let (maskOpt, ink) = glyphMask(line: line, font: font,
                                   width: maskW, height: maskH,
                                   baselineY: descent + pad, originX: pad)
    guard let mask = maskOpt, !ink.isNull else { return nil }

    // Ink center in bottom-origin coords (scan is top-origin).
    let inkCx = (ink.minX + ink.maxX) / 2
    let inkCy = (CGFloat(maskH) - 1) - (ink.minY + ink.maxY) / 2

    // Optically lift lowercase wordmarks ~3px (ink-centered baseline).
    let targetCx = artRect.midX
    let targetCy = artRect.midY + artRect.height * 0.004

    let markW = CGFloat(maskW), markH = CGFloat(maskH)
    let markRect = CGRect(x: targetCx - inkCx,
                          y: targetCy - inkCy,
                          width: markW, height: markH)

    ctx.saveGState()
    ctx.clip(to: markRect, mask: mask)

    // White base…
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(markRect)
    // …with subtle rainbow fringe (purple/pink left, blues right).
    let tintStops: [(CGFloat, CGColor)] = [
        (0.00, CGColor(srgbRed: 0.78, green: 0.49, blue: 1.00, alpha: 0.50)),
        (0.20, CGColor(srgbRed: 1.00, green: 0.54, blue: 0.87, alpha: 0.40)),
        (0.42, CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)),
        (0.60, CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)),
        (0.80, CGColor(srgbRed: 0.49, green: 0.63, blue: 1.00, alpha: 0.42)),
        (1.00, CGColor(srgbRed: 0.37, green: 0.43, blue: 1.00, alpha: 0.50)),
    ]
    let tintGrad = CGGradient(colorsSpace: cs,
                              colors: tintStops.map { $0.1 } as CFArray,
                              locations: tintStops.map { $0.0 })!
    ctx.drawLinearGradient(tintGrad,
                           start: CGPoint(x: markRect.minX, y: markRect.midY),
                           end: CGPoint(x: markRect.maxX, y: markRect.midY),
                           options: [.drawsBeforeStartLocation])
    ctx.restoreGState()

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
