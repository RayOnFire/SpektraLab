// Reproducible original artwork; no upstream names, logo or third-party art.
import AppKit
let size = NSSize(width: 1024, height: 1024)
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.075, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let amber = NSColor(calibratedRed: 0.92, green: 0.66, blue: 0.38, alpha: 1)
amber.setFill()
NSBezierPath(roundedRect: NSRect(x: 170, y: 178, width: 684, height: 668), xRadius: 70, yRadius: 70).fill()
NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 260, y: 260, width: 504, height: 504), xRadius: 24, yRadius: 24).fill()
amber.setStroke()
let arc = NSBezierPath(ovalIn: NSRect(x: 358, y: 358, width: 308, height: 308)); arc.lineWidth = 26; arc.stroke()
for x in [202, 790] { for y in [280, 400, 520, 640, 760] {
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 32, height: 52), xRadius: 8, yRadius: 8).fill()
} }
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: url)
