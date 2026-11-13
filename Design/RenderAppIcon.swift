import AppKit

// A plate with tally marks represents logging any food or drink, without a beverage-specific symbol.
// Run from the repository root: swift Design/RenderAppIcon.swift
// An explicit pixel canvas makes output independent of the Mac's display scale and keeps the icon opaque.
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(srgbRed: 0, green: 0.42, blue: 0.42, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setStrokeColor(CGColor(srgbRed: 0.91, green: 0.98, blue: 0.96, alpha: 1))
context.setLineWidth(34)
context.strokeEllipse(in: CGRect(x: 180, y: 180, width: 664, height: 664))
context.setLineWidth(39)
context.setLineCap(.round)
for x in [366, 463, 560, 657] {
    context.move(to: CGPoint(x: x, y: 394))
    context.addLine(to: CGPoint(x: x, y: 630))
}
context.move(to: CGPoint(x: 332, y: 428))
context.addLine(to: CGPoint(x: 687, y: 599))
context.strokePath()
let canvas = NSBitmapImageRep(cgImage: context.makeImage()!)
let output = URL(fileURLWithPath: "Tally/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try canvas.representation(using: .png, properties: [:])!.write(to: output)
