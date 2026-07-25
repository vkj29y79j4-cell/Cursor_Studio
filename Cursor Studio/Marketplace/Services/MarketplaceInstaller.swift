import Foundation

@MainActor
final class MarketplaceInstaller {
    private let store: ThemeStore
    private let paths: ApplicationPaths
    private let fileManager: FileManager
    private let previewGenerator: ThemePreviewGenerator

    init(
        store: ThemeStore,
        paths: ApplicationPaths,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.paths = paths
        self.fileManager = fileManager
        previewGenerator = ThemePreviewGenerator(fileManager: fileManager)
    }

    func install(_ package: ValidatedMarketplacePackage) throws -> CursorTheme {
        let themeID = UUID()
        let stagingThemeDirectory = paths.importStagingDirectory.appending(
            path: "Install-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let stagingAssets = stagingThemeDirectory.appending(
            path: "Assets",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: stagingAssets,
            withIntermediateDirectories: true
        )

        var committed = false
        defer {
            if !committed {
                try? fileManager.removeItem(at: stagingThemeDirectory)
            }
        }

        var theme = CursorTheme(
            id: themeID,
            name: package.manifest.name
        )
        for cursor in package.manifest.cursors {
            guard let role = CursorRole(rawValue: cursor.role) else {
                throw MarketplaceServiceError.packageInvalid(
                    L10n.text("Unknown cursor role.", "Неизвестная роль курсора.")
                )
            }
            let source = package.rootDirectory.appending(path: cursor.asset)
            let filename = "\(role.rawValue)-\(UUID().uuidString).png"
            try fileManager.copyItem(
                at: source,
                to: stagingAssets.appending(path: filename)
            )
            let pointSize = MarketplaceCursorSizing.normalizedPointSize(
                pixelWidth: cursor.pixelWidth,
                pixelHeight: cursor.pixelHeight,
                requestedPointWidth: cursor.pointWidth,
                requestedPointHeight: cursor.pointHeight
            )
            theme.setEntry(
                CursorEntry(
                    role: role,
                    assetFilename: filename,
                    pixelWidth: cursor.pixelWidth,
                    pixelHeight: cursor.pixelHeight,
                    hotspot: CursorHotspot(
                        normalizedX: cursor.hotspotX,
                        normalizedY: cursor.hotspotY
                    ),
                    pointWidth: pointSize.width,
                    pointHeight: pointSize.height,
                    sourceIdentifier: cursor.role
                )
            )
        }
        theme.importMetadata = ThemeImportMetadata(
            sourceFormat: "Cursor Studio Marketplace",
            sourceIdentifier: package.manifest.themeID.uuidString,
            sourceVersion: package.manifest.semanticVersion,
            importedAt: .now,
            warnings: [],
            unassignedEntries: []
        )
        theme.previewAssetFilename = try previewGenerator.generatePreview(
            for: theme,
            in: stagingAssets
        )
        let draft = CapeImportDraft(
            theme: theme,
            stagingThemeDirectory: stagingThemeDirectory,
            review: CapeImportReview(
                themeName: theme.name,
                recognizedRoleCount: theme.entries.count,
                unrecognizedRoleCount: 0,
                warningMessages: [],
                missingImageCount: 0,
                animatedRoleCount: 0,
                staticAnimationFallbackCount: 0
            )
        )
        let installed = try store.commitCapeImport(draft)
        committed = true
        return installed
    }
}
