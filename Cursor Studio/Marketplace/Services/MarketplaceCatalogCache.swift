import CryptoKit
import Foundation

actor MarketplaceCatalogCache {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(paths: ApplicationPaths, fileManager: FileManager = .default) {
        directory = paths.marketplaceCacheDirectory.appending(
            path: "Catalog",
            directoryHint: .isDirectory
        )
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(key: String) -> [MarketplaceTheme]? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let record = try? decoder.decode(CacheRecord.self, from: data)
        else {
            return nil
        }
        return record.themes
    }

    func save(_ themes: [MarketplaceTheme], key: String) {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(
                CacheRecord(savedAt: .now, themes: themes)
            )
            try data.write(to: fileURL(for: key), options: .atomic)
            prune()
        } catch {
            // Cache failures never affect the local library or Marketplace UI.
        }
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appending(path: "\(digest).json")
    }

    private func prune() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ),
        files.count > 24 else {
            return
        }
        let sorted = files.sorted {
            let left = try? $0.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            let right = try? $1.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            return (left ?? .distantPast) < (right ?? .distantPast)
        }
        for file in sorted.prefix(files.count - 24) {
            try? fileManager.removeItem(at: file)
        }
    }
}

nonisolated private struct CacheRecord: Codable, Sendable {
    var savedAt: Date
    var themes: [MarketplaceTheme]
}
