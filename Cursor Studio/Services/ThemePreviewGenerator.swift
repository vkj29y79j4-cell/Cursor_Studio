import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ThemePreviewGenerator {
    nonisolated static let previewFilename = "theme-preview.png"

    private let fileManager: FileManager

    nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    nonisolated func generatePreview(
        for theme: CursorTheme,
        in assetsDirectory: URL,
        fallbackAssetFilename: String? = nil
    ) throws -> String? {
        let destination = assetsDirectory.appending(
            path: Self.previewFilename,
            directoryHint: .notDirectory
        )
        let preferredEntry = theme.entry(for: .arrow) ?? theme.entries.first
        let sourceFilename = preferredEntry?.assetFilename
            ?? fallbackAssetFilename
        let thumbnail: CGImage
        if let sourceFilename {
            let sourceURL = assetsDirectory.appending(
                path: sourceFilename,
                directoryHint: .notDirectory
            )
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 96,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            if let source = CGImageSourceCreateWithURL(
                sourceURL as CFURL,
                nil
            ), CGImageSourceGetCount(source) > 0,
               let decoded = CGImageSourceCreateThumbnailAtIndex(
                   source,
                   0,
                   options as CFDictionary
               ) {
                thumbnail = decoded
            } else {
                thumbnail = try placeholderImage()
            }
        } else {
            thumbnail = try placeholderImage()
        }

        try fileManager.createDirectory(
            at: assetsDirectory,
            withIntermediateDirectories: true
        )
        let temporary = assetsDirectory.appending(
            path: ".theme-preview-\(UUID().uuidString).png",
            directoryHint: .notDirectory
        )
        guard let imageDestination = CGImageDestinationCreateWithURL(
            temporary as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CursorStudioError.filePermission(temporary.path)
        }
        CGImageDestinationAddImage(imageDestination, thumbnail, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            try? fileManager.removeItem(at: temporary)
            throw CursorStudioError.filePermission(temporary.path)
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
        return Self.previewFilename
    }

    private nonisolated func placeholderImage() throws -> CGImage {
        let size = 64
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: size,
                  height: size,
                  bitsPerComponent: 8,
                  bytesPerRow: size * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CursorStudioError.invalidImage
        }

        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 11, y: 54))
        path.addLine(to: CGPoint(x: 11, y: 10))
        path.addLine(to: CGPoint(x: 23, y: 22))
        path.addLine(to: CGPoint(x: 31, y: 8))
        path.addLine(to: CGPoint(x: 39, y: 13))
        path.addLine(to: CGPoint(x: 31, y: 27))
        path.addLine(to: CGPoint(x: 50, y: 29))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0.96, alpha: 0.92))
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(CGColor(gray: 0.12, alpha: 0.9))
        context.setLineWidth(3)
        context.setLineJoin(.round)
        context.strokePath()

        guard let image = context.makeImage() else {
            throw CursorStudioError.invalidImage
        }
        return image
    }
}
