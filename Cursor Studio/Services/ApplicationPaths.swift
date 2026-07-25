import Foundation

nonisolated struct ApplicationPaths: Sendable {
    let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    static func live(fileManager: FileManager = .default) throws -> ApplicationPaths {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return ApplicationPaths(
            rootDirectory: applicationSupport.appending(
                path: ProductInfo.name,
                directoryHint: .isDirectory
            )
        )
    }

    var libraryFile: URL {
        rootDirectory.appending(path: "library.json", directoryHint: .notDirectory)
    }

    var themesDirectory: URL {
        rootDirectory.appending(path: "Themes", directoryHint: .isDirectory)
    }

    var logsDirectory: URL {
        rootDirectory.appending(path: "Logs", directoryHint: .isDirectory)
    }

    var importStagingDirectory: URL {
        rootDirectory.appending(path: "ImportStaging", directoryHint: .isDirectory)
    }

    var marketplaceCacheDirectory: URL {
        rootDirectory.appending(path: "MarketplaceCache", directoryHint: .isDirectory)
    }

    var diagnosticLog: URL {
        logsDirectory.appending(path: "diagnostics.log", directoryHint: .notDirectory)
    }

    var cursorOverrideLedgerFile: URL {
        rootDirectory.appending(
            path: "cursor-overrides.json",
            directoryHint: .notDirectory
        )
    }

    func themeDirectory(for themeID: UUID) -> URL {
        themesDirectory.appending(path: themeID.uuidString, directoryHint: .isDirectory)
    }

    func assetsDirectory(for themeID: UUID) -> URL {
        themeDirectory(for: themeID)
            .appending(path: "Assets", directoryHint: .isDirectory)
    }

    func assetURL(themeID: UUID, filename: String) -> URL? {
        guard !filename.isEmpty,
              filename == URL(fileURLWithPath: filename).lastPathComponent,
              !filename.contains("/") else {
            return nil
        }
        return assetsDirectory(for: themeID)
            .appending(path: filename, directoryHint: .notDirectory)
    }

    func createDirectories(fileManager: FileManager = .default) throws {
        for directory in [
            rootDirectory,
            themesDirectory,
            logsDirectory,
            importStagingDirectory,
            marketplaceCacheDirectory,
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }
}
