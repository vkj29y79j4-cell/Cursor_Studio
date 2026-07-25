import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImportedCursorAsset: Sendable {
    let filename: String
    let pixelWidth: Int
    let pixelHeight: Int
}

final class ImageImportService {
    private let paths: ApplicationPaths
    private let fileManager: FileManager

    init(paths: ApplicationPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func importImage(from sourceURL: URL, for themeID: UUID) throws -> ImportedCursorAsset {
        if sourceURL.pathExtension.lowercased() == "svg" {
            throw CursorStudioError.unsupportedSVG
        }
        guard sourceURL.pathExtension.lowercased() == "png" else {
            throw CursorStudioError.invalidImage
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source),
              UTType(type as String)?.conforms(to: .png) == true,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0,
              image.height > 0,
              image.width <= 4_096,
              image.height <= 4_096 else {
            throw CursorStudioError.invalidImage
        }

        let assetsDirectory = paths.assetsDirectory(for: themeID)
        do {
            try fileManager.createDirectory(
                at: assetsDirectory,
                withIntermediateDirectories: true
            )
            let filename = UUID().uuidString + ".png"
            let destinationURL = assetsDirectory.appending(
                path: filename,
                directoryHint: .notDirectory
            )
            guard let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                throw CursorStudioError.filePermission(destinationURL.path)
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw CursorStudioError.filePermission(destinationURL.path)
            }
            return ImportedCursorAsset(
                filename: filename,
                pixelWidth: image.width,
                pixelHeight: image.height
            )
        } catch let error as CursorStudioError {
            throw error
        } catch {
            throw CursorStudioError.filePermission(assetsDirectory.path)
        }
    }
}
