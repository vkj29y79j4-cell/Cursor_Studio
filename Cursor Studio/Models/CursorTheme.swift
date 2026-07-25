import Foundation

nonisolated struct CursorTheme: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var previewAssetFilename: String?
    var entries: [CursorEntry]
    var importMetadata: ThemeImportMetadata?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        previewAssetFilename: String? = nil,
        entries: [CursorEntry] = [],
        importMetadata: ThemeImportMetadata? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.previewAssetFilename = previewAssetFilename
        self.entries = entries
        self.importMetadata = importMetadata
    }

    func entry(for role: CursorRole) -> CursorEntry? {
        entries.first { $0.role == role }
    }

    var configuredRoles: Set<CursorRole> {
        Set(entries.map(\.role))
    }

    var missingRoles: Set<CursorRole> {
        Set(CursorRole.allCases).subtracting(configuredRoles)
    }

    mutating func setEntry(_ entry: CursorEntry) {
        if let index = entries.firstIndex(where: { $0.role == entry.role }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        previewAssetFilename = entry.role == .arrow
            ? entry.assetFilename
            : (previewAssetFilename ?? entry.assetFilename)
        modifiedAt = .now
    }

    mutating func removeEntry(for role: CursorRole) {
        entries.removeAll { $0.role == role }
        if previewAssetFilename != nil,
           !entries.contains(where: { $0.assetFilename == previewAssetFilename }) {
            previewAssetFilename = entries.first?.assetFilename
        }
        modifiedAt = .now
    }
}
