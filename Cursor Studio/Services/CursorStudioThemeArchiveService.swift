import Foundation

nonisolated struct ThemeArchiveExportReceipt: Sendable {
    let url: URL
    let byteCount: Int64
    let sha256: String
}

/// Reads and writes Cursor Studio's portable theme archive.
///
/// The archive intentionally reuses the Marketplace package schema and its
/// strict ZIP/PNG validator. Local sharing therefore has the same path
/// traversal, file-count, size, checksum, and decoded-image protections as a
/// downloaded Marketplace theme.
actor CursorStudioThemeArchiveService {
    static let pathExtension = "cursorstudio-theme"

    private let builder: MarketplacePackageBuilder
    private let validator: MarketplacePackageValidator
    private let fileManager: FileManager

    init(
        paths: ApplicationPaths,
        fileManager: FileManager = .default
    ) {
        builder = MarketplacePackageBuilder(
            paths: paths,
            fileManager: fileManager
        )
        // The validator owns its FileManager inside a separate actor. Giving
        // it an independent instance avoids sharing mutable Foundation state
        // across concurrency domains under Swift 6 strict checking.
        validator = MarketplacePackageValidator(paths: paths)
        self.fileManager = fileManager
    }

    nonisolated static func canImport(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare(pathExtension)
            == .orderedSame
    }

    nonisolated static func suggestedFilename(
        for theme: CursorTheme
    ) -> String {
        let invalid = CharacterSet(
            charactersIn: "/:\\?%*|\"<>"
        )
        let components = theme.name.components(
            separatedBy: invalid
        )
        let sanitized = components
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = sanitized.isEmpty ? "Cursor Theme" : sanitized
        return "\(base).\(pathExtension)"
    }

    func export(
        theme: CursorTheme,
        to destinationURL: URL
    ) throws -> ThemeArchiveExportReceipt {
        let prepared = try builder.prepare(
            theme: theme,
            remoteThemeID: theme.id,
            semanticVersion: "1.0.0"
        )
        defer {
            try? fileManager.removeItem(
                at: prepared.cleanupDirectory
            )
        }

        let hasSecurityScope =
            destinationURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }

        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appending(
                path:
                    ".CursorStudioExport-\(UUID().uuidString).tmp",
                directoryHint: .notDirectory
            )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        do {
            try fileManager.copyItem(
                at: prepared.packageURL,
                to: temporaryURL
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: temporaryURL.path
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(
                    destinationURL,
                    withItemAt: temporaryURL
                )
            } else {
                try fileManager.moveItem(
                    at: temporaryURL,
                    to: destinationURL
                )
            }
        } catch {
            throw CursorStudioError.filePermission(
                destinationURL.path
            )
        }

        return ThemeArchiveExportReceipt(
            url: destinationURL,
            byteCount: prepared.packageBytes,
            sha256: prepared.packageSHA256
        )
    }

    func validateImport(
        from sourceURL: URL
    ) async throws -> ValidatedMarketplacePackage {
        let hasSecurityScope =
            sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        return try await validator.validatePackage(at: sourceURL)
    }
}
