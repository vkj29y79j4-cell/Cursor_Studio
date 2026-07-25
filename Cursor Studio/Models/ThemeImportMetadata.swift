import Foundation

nonisolated struct ThemeImportMetadata: Codable, Hashable, Sendable {
    var sourceFormat: String
    var sourceIdentifier: String?
    var author: String?
    var sourceVersion: String?
    var importedAt: Date
    var warnings: [String]
    var unassignedEntries: [UnassignedCursorEntry]
}

nonisolated struct UnassignedCursorEntry: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var sourceIdentifier: String
    var previewAssetFilename: String?
    var pointWidth: Double?
    var pointHeight: Double?
    var hotspot: CursorHotspot?
    var frameCount: Int
    var frameDuration: Double
    var representations: [CursorRepresentation]
    var reason: String

    init(
        id: UUID = UUID(),
        sourceIdentifier: String,
        previewAssetFilename: String? = nil,
        pointWidth: Double? = nil,
        pointHeight: Double? = nil,
        hotspot: CursorHotspot? = nil,
        frameCount: Int = 1,
        frameDuration: Double = 0,
        representations: [CursorRepresentation] = [],
        reason: String
    ) {
        self.id = id
        self.sourceIdentifier = sourceIdentifier
        self.previewAssetFilename = previewAssetFilename
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.hotspot = hotspot
        self.frameCount = max(frameCount, 1)
        self.frameDuration = max(frameDuration, 0)
        self.representations = representations
        self.reason = reason
    }
}
