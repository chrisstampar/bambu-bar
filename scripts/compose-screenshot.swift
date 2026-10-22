// Composes one Mac App Store screenshot: a caption over a dark tile with the icon's green bloom, and window
// captures side by side (each later one overlapping the previous a little), all with soft shadows.
// Usage: swift scripts/compose-screenshot.swift <out.png> <title> <subtitle> <image>[@scale[@corner radius]] …
//   GAP=28 swift scripts/compose-screenshot.swift …   space between captures (default -90: overlapping)
// The canvas is 1440×900, one of the sizes App Store Connect accepts for Mac apps (16:10).
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: compose-screenshot.swift <out.png> <title> <subtitle> <image>[@scale] …\n".data(using: .utf8)!)
    exit(2)
}
let (out, title, subtitle) = (args[0], args[1], args[2])
let width = 1440, height = 900
let size = NSSize(width: width, height: height)

struct Layer {
    var image: NSImage
    var scale: CGFloat
    var radius: CGFloat
    var drawn: NSSize { NSSize(width: image.size.width * scale, height: image.size.height * scale) }
}

let layers: [Layer] = args.dropFirst(3).map { spec in
    let parts = spec.split(separator: "@").map(String.init)
    guard let rep = NSImageRep(contentsOfFile: parts[0]) else {
        FileHandle.standardError.write("can't read \(parts[0])\n".data(using: .utf8)!)
        exit(1)
    }
    // Captures are 1x: size the image by its pixels.
    let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
    image.addRepresentation(rep)
    func number(_ index: Int, _ fallback: Double) -> CGFloat { CGFloat(index < parts.count ? Double(parts[index]) ?? fallback : fallback) }
    return Layer(image: image, scale: number(1, 1), radius: number(2, 14))
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
context.imageInterpolation = .high

// Backdrop: the icon's dark tile and the green glow rising from below.
let bounds = NSRect(origin: .zero, size: size)
NSGradient(colors: [color(0.13, 0.15, 0.16), color(0.05, 0.06, 0.07)])!.draw(in: bounds, angle: -90)
NSGradient(colors: [color(0.10, 0.85, 0.42, 0.30), color(0.10, 0.85, 0.42, 0)])!
    .draw(fromCenter: NSPoint(x: size.width / 2, y: -140), radius: 0,
          toCenter: NSPoint(x: size.width / 2, y: -140), radius: 820, options: [])

// Caption.
let centered = NSMutableParagraphStyle()
centered.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 46, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: centered,
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 21, weight: .regular), .foregroundColor: color(0.72, 0.76, 0.78),
    .paragraphStyle: centered,
]
(title as NSString).draw(in: NSRect(x: 60, y: size.height - 112, width: size.width - 120, height: 60), withAttributes: titleAttributes)
(subtitle as NSString).draw(in: NSRect(x: 120, y: size.height - 152, width: size.width - 240, height: 32), withAttributes: subtitleAttributes)

// Captures, centred in the space under the caption; by default each one overlaps the previous by 90 points.
let overlap = -CGFloat(Double(ProcessInfo.processInfo.environment["GAP"] ?? "") ?? -90)
let top = size.height - 190, bottom: CGFloat = 36
let total = layers.enumerated().reduce(CGFloat(0)) { $0 + $1.element.drawn.width - ($1.offset > 0 ? overlap : 0) }
var x = (size.width - total) / 2
for (index, layer) in layers.enumerated() {
    if index > 0 { x -= overlap }
    let drawn = layer.drawn
    let y = bottom + (top - bottom - drawn.height) / 2
    let frame = NSRect(x: x.rounded(), y: y.rounded(), width: drawn.width, height: drawn.height)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    // Window captures have their own rounded corners; crops don't, so round them.
    let clip = NSBezierPath(roundedRect: frame, xRadius: layer.radius * layer.scale, yRadius: layer.radius * layer.scale)
    color(0, 0, 0, 0.01).setFill()
    clip.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    layer.image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    x += drawn.width
}

NSGraphicsContext.restoreGraphicsState()
// App Store Connect rejects screenshots with an alpha channel; flatten onto an opaque RGB bitmap.
let flat = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                     space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
flat.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
let png = NSBitmapImageRep(cgImage: flat.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
