import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconSlot {
    let filename: String
    let pixels: Int
}

let slots = [
    IconSlot(filename: "app-icon-16.png", pixels: 16),
    IconSlot(filename: "app-icon-16@2x.png", pixels: 32),
    IconSlot(filename: "app-icon-32.png", pixels: 32),
    IconSlot(filename: "app-icon-32@2x.png", pixels: 64),
    IconSlot(filename: "app-icon-128.png", pixels: 128),
    IconSlot(filename: "app-icon-128@2x.png", pixels: 256),
    IconSlot(filename: "app-icon-256.png", pixels: 256),
    IconSlot(filename: "app-icon-256@2x.png", pixels: 512),
    IconSlot(filename: "app-icon-512.png", pixels: 512),
    IconSlot(filename: "app-icon-512@2x.png", pixels: 1_024),
]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("Usage: generate_app_icons.swift <AppIcon.appiconset>\n".utf8)
    )
    exit(2)
}

let outputDirectory = URL(
    fileURLWithPath: CommandLine.arguments[1],
    isDirectory: true
)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

for slot in slots {
    let size = CGFloat(slot.pixels)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: slot.pixels,
              height: slot.pixels,
              bitsPerComponent: 8,
              bytesPerRow: slot.pixels * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        throw NSError(domain: "CursorStudioIcon", code: 1)
    }

    context.interpolationQuality = .high
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)

    let unit = size / 1_024
    let tile = CGRect(x: 72 * unit, y: 72 * unit, width: 880 * unit, height: 880 * unit)
    let tilePath = CGPath(
        roundedRect: tile,
        cornerWidth: 212 * unit,
        cornerHeight: 212 * unit,
        transform: nil
    )

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: 28 * unit),
        blur: 44 * unit,
        color: CGColor(red: 0.08, green: 0.04, blue: 0.18, alpha: 0.45)
    )
    context.addPath(tilePath)
    context.setFillColor(CGColor(red: 0.30, green: 0.19, blue: 0.78, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.45, green: 0.30, blue: 0.96, alpha: 1),
            CGColor(red: 0.25, green: 0.13, blue: 0.66, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: size / 2, y: 92 * unit),
        end: CGPoint(x: size / 2, y: 940 * unit),
        options: []
    )

    context.setStrokeColor(CGColor(red: 0.72, green: 0.62, blue: 1, alpha: 0.5))
    context.setLineWidth(10 * unit)
    context.addPath(
        CGPath(
            roundedRect: tile.insetBy(dx: 8 * unit, dy: 8 * unit),
            cornerWidth: 204 * unit,
            cornerHeight: 204 * unit,
            transform: nil
        )
    )
    context.strokePath()
    context.restoreGState()

    let cursor = CGMutablePath()
    cursor.move(to: CGPoint(x: 292 * unit, y: 222 * unit))
    cursor.addLine(to: CGPoint(x: 292 * unit, y: 718 * unit))
    cursor.addLine(to: CGPoint(x: 430 * unit, y: 590 * unit))
    cursor.addLine(to: CGPoint(x: 565 * unit, y: 827 * unit))
    cursor.addLine(to: CGPoint(x: 690 * unit, y: 755 * unit))
    cursor.addLine(to: CGPoint(x: 558 * unit, y: 536 * unit))
    cursor.addLine(to: CGPoint(x: 748 * unit, y: 536 * unit))
    cursor.closeSubpath()

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 16 * unit, height: 24 * unit),
        blur: 24 * unit,
        color: CGColor(gray: 0.05, alpha: 0.55)
    )
    context.addPath(cursor)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.addPath(cursor)
    context.setStrokeColor(CGColor(red: 0.09, green: 0.07, blue: 0.15, alpha: 1))
    context.setLineJoin(.round)
    context.setLineWidth(max(26 * unit, 1))
    context.strokePath()

    let hotspot = CGRect(
        x: 254 * unit,
        y: 184 * unit,
        width: 76 * unit,
        height: 76 * unit
    )
    context.setFillColor(CGColor(red: 0.30, green: 0.94, blue: 0.88, alpha: 1))
    context.fillEllipse(in: hotspot)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
    context.setLineWidth(max(12 * unit, 1))
    context.strokeEllipse(in: hotspot)

    guard let image = context.makeImage() else {
        throw NSError(domain: "CursorStudioIcon", code: 2)
    }
    let destinationURL = outputDirectory.appendingPathComponent(slot.filename)
    guard let destination = CGImageDestinationCreateWithURL(
        destinationURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "CursorStudioIcon", code: 3)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "CursorStudioIcon", code: 4)
    }
}

print("Generated \(slots.count) Cursor Studio app icon files.")
