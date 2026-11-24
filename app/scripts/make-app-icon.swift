#!/usr/bin/env swift
// Draws Budget Guard's app icon (original: spark inside a gauge arc, on a warm background)
// and writes an .icns. Usage: swift scripts/make-app-icon.swift [output.icns]  (default Resources/AppIcon.icns)
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px)
    // Rounded square with the macOS margin (~10 %).
    let r = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = CGPath(roundedRect: r, cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(srgbRed: 0.98, green: 0.78, blue: 0.55, alpha: 1), CGColor(srgbRed: 0.90, green: 0.45, blue: 0.30, alpha: 1)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: s / 2, y: s * 0.9), end: CGPoint(x: s / 2, y: s * 0.1), options: [])
    ctx.restoreGState()

    let c = CGPoint(x: s / 2, y: s / 2)
    let u = s / 100
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
    ctx.setLineCap(.round)
    ctx.setLineWidth(4.2 * u)
    ctx.addArc(center: c, radius: 28 * u, startAngle: -.pi / 4, endAngle: .pi * 5 / 4, clockwise: false)
    ctx.strokePath()
    ctx.setLineWidth(4.6 * u)
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4
        let outer: CGFloat = (i % 2 == 0 ? 20 : 13.5) * u
        ctx.move(to: CGPoint(x: c.x + cos(a) * 5.5 * u, y: c.y + sin(a) * 5.5 * u))
        ctx.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
    }
    ctx.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
print(p.terminationStatus == 0 ? "wrote \(out)" : "iconutil failed")
exit(p.terminationStatus)
