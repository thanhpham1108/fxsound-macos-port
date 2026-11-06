// Original multicolour waveform icon for the unofficial macOS port.
// Run with: swift generate_icon.swift output.png
import AppKit
import CoreGraphics

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift generate_icon.swift output.png\n", stderr)
    exit(2)
}

let size = 1024
let space = CGColorSpaceCreateDeviceRGB()
func color(_ rgb: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((rgb >> 16) & 255) / 255,
        CGFloat((rgb >> 8) & 255) / 255,
        CGFloat(rgb & 255) / 255,
        alpha
    ])!
}

guard let context = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Could not create icon bitmap")
}
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let tile = CGPath(roundedRect: CGRect(x: 72, y: 72, width: 880, height: 880),
                  cornerWidth: 210, cornerHeight: 210, transform: nil)
context.saveGState()
context.addPath(tile)
context.clip()
let background = CGGradient(colorsSpace: space,
                            colors: [color(0x172640), color(0x101424)] as CFArray,
                            locations: [0, 1])!
context.drawLinearGradient(background,
                           start: CGPoint(x: 70, y: 950),
                           end: CGPoint(x: 950, y: 70), options: [])

let wave = CGMutablePath()
wave.move(to: CGPoint(x: 166, y: 500))
wave.addLine(to: CGPoint(x: 310, y: 500))
wave.addCurve(to: CGPoint(x: 430, y: 725),
              control1: CGPoint(x: 355, y: 500), control2: CGPoint(x: 355, y: 725))
wave.addCurve(to: CGPoint(x: 582, y: 300),
              control1: CGPoint(x: 540, y: 725), control2: CGPoint(x: 470, y: 300))
wave.addCurve(to: CGPoint(x: 720, y: 500),
              control1: CGPoint(x: 690, y: 300), control2: CGPoint(x: 670, y: 500))
wave.addLine(to: CGPoint(x: 858, y: 500))

context.saveGState()
context.setShadow(offset: .zero, blur: 80, color: color(0x8b5cf6, alpha: 0.7))
context.addPath(wave)
context.setStrokeColor(color(0x8b5cf6, alpha: 0.5))
context.setLineWidth(100)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()
context.restoreGState()

context.saveGState()
context.addPath(wave)
context.setLineWidth(84)
context.setLineCap(.round)
context.setLineJoin(.round)
context.replacePathWithStrokedPath()
context.clip()
let spectrum = CGGradient(colorsSpace: space,
                          colors: [color(0x36d8e7), color(0x9a76ff), color(0xff5e90)] as CFArray,
                          locations: [0, 0.52, 1])!
context.drawLinearGradient(spectrum,
                           start: CGPoint(x: 166, y: 0),
                           end: CGPoint(x: 858, y: 0), options: [])
context.restoreGState()
context.restoreGState()

guard let image = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
