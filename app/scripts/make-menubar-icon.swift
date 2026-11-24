#!/usr/bin/env swift
// Draws Budget Guard's menu bar glyph (original: eight-branch spark inside a thin gauge arc)
// as a black-on-transparent vector PDF, to be used as a template image.
// Usage: swift scripts/make-menubar-icon.swift [output.pdf]   (default: Resources/MenuBarIcon.pdf)
import CoreGraphics
import Foundation

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/MenuBarIcon.pdf"
// Optional 2nd arg: preview scale (default 1; the shipped icon is 16 pt).
let scale: CGFloat = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2]) ?? 1) : 1
let size: CGFloat = 16
var box = CGRect(x: 0, y: 0, width: size * scale, height: size * scale)
guard let ctx = CGContext(URL(fileURLWithPath: out) as CFURL, mediaBox: &box, nil) else {
    FileHandle.standardError.write(Data("cannot create \(out)\n".utf8)); exit(1)
}
ctx.beginPDFPage(nil)
ctx.scaleBy(x: scale, y: scale)
ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
ctx.setLineCap(.round)
let c = CGPoint(x: size / 2, y: size / 2)

// Gauge: 270-degree arc, opening at the bottom.
ctx.setLineWidth(1.1)
ctx.addArc(center: c, radius: 7.2, startAngle: -.pi / 4, endAngle: .pi * 5 / 4, clockwise: false)
ctx.strokePath()

// Spark: eight branches, alternating long and short.
ctx.setLineWidth(1.2)
for i in 0..<8 {
    let a = CGFloat(i) * .pi / 4
    let inner: CGFloat = 1.4
    let outer: CGFloat = i % 2 == 0 ? 5.2 : 3.6
    ctx.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
    ctx.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
}
ctx.strokePath()
ctx.endPDFPage()
ctx.closePDF()
print("wrote \(out)")
