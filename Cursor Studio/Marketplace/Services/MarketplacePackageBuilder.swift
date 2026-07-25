import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct MarketplacePackageBuilder: @unchecked Sendable {
    private let paths: ApplicationPaths
    private let fileManager: FileManager

    init(
        paths: ApplicationPaths,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func prepare(
        theme: CursorTheme,
        remoteThemeID: UUID,
        semanticVersion: String
    ) throws -> PreparedMarketplaceUpload {
        guard !theme.entries.isEmpty else {
            throw MarketplaceBackendError.invalidInput(
                L10n.publishThemeNeedsCursor
            )
        }

        let cleanupDirectory = fileManager.temporaryDirectory.appending(
            path: "CursorStudioPublish-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let packageRoot = cleanupDirectory.appending(
            path: "Package",
            directoryHint: .isDirectory
        )
        let assetsDirectory = packageRoot.appending(
            path: "Assets",
            directoryHint: .isDirectory
        )
        let packageURL = cleanupDirectory.appending(
            path: "\(remoteThemeID.uuidString.lowercased()).cursorstudio-theme",
            directoryHint: .notDirectory
        )
        let previewURL = cleanupDirectory.appending(
            path: "preview.png",
            directoryHint: .notDirectory
        )

        do {
            try fileManager.createDirectory(
                at: assetsDirectory,
                withIntermediateDirectories: true
            )

            var manifestCursors: [MarketplacePackageCursor] = []
            for entry in theme.entries.sorted(by: {
                $0.role.rawValue < $1.role.rawValue
            }) {
                guard let sourceURL = paths.assetURL(
                    themeID: theme.id,
                    filename: entry.assetFilename
                ),
                fileManager.fileExists(atPath: sourceURL.path) else {
                    throw MarketplaceBackendError.invalidInput(
                        L10n.publishMissingAsset(entry.assetFilename)
                    )
                }
                try validatePNG(at: sourceURL)
                let filename = "\(entry.role.rawValue).png"
                let destinationURL = assetsDirectory.appending(path: filename)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o644],
                    ofItemAtPath: destinationURL.path
                )
                manifestCursors.append(
                    MarketplacePackageCursor(
                        role: entry.role.rawValue,
                        asset: "Assets/\(filename)",
                        pixelWidth: entry.pixelWidth,
                        pixelHeight: entry.pixelHeight,
                        pointWidth: entry.pointWidth,
                        pointHeight: entry.pointHeight,
                        hotspotX: entry.hotspot.normalizedX,
                        hotspotY: entry.hotspot.normalizedY
                    )
                )
            }

            let manifest = MarketplacePackageManifest(
                schemaVersion: 1,
                themeID: remoteThemeID,
                name: theme.name,
                semanticVersion: semanticVersion,
                cursors: manifestCursors
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let manifestURL = packageRoot.appending(path: "manifest.json")
            try encoder.encode(manifest).write(
                to: manifestURL,
                options: .atomic
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: manifestURL.path
            )

            guard let sourcePreview = previewSource(for: theme) else {
                throw MarketplaceBackendError.invalidInput(
                    L10n.publishThemeNeedsPreview
                )
            }
            try validatePNG(at: sourcePreview)
            try fileManager.copyItem(at: sourcePreview, to: previewURL)
            try createZIP(from: packageRoot, at: packageURL)

            let packageData = try Data(
                contentsOf: packageURL,
                options: .mappedIfSafe
            )
            let digest = SHA256.hash(data: packageData)
                .map { String(format: "%02x", $0) }
                .joined()
            return PreparedMarketplaceUpload(
                packageURL: packageURL,
                previewURL: previewURL,
                cleanupDirectory: cleanupDirectory,
                packageSHA256: digest,
                packageBytes: Int64(packageData.count),
                manifest: manifest
            )
        } catch {
            try? fileManager.removeItem(at: cleanupDirectory)
            throw error
        }
    }

    private func previewSource(for theme: CursorTheme) -> URL? {
        if let filename = theme.previewAssetFilename,
           let url = paths.assetURL(themeID: theme.id, filename: filename),
           fileManager.fileExists(atPath: url.path) {
            return url
        }
        guard let entry = theme.entry(for: .arrow) ?? theme.entries.first else {
            return nil
        }
        return paths.assetURL(
            themeID: theme.id,
            filename: entry.assetFilename
        )
    }

    private func validatePNG(at url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1 else {
            throw MarketplaceBackendError.invalidInput(
                L10n.publishOnlyPNG
            )
        }
    }

    private func createZIP(from directory: URL, at destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--norsrc",
            directory.path,
            destination.path,
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              fileManager.fileExists(atPath: destination.path) else {
            throw MarketplaceBackendError.server(
                L10n.publishPackageCreationFailed
            )
        }
    }
}
