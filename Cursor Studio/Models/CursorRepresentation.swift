import Foundation

nonisolated struct CursorRepresentation: Codable, Hashable, Sendable {
    var filename: String
    var scale: Double
    var pixelWidth: Int
    var pixelHeight: Int

    init(
        filename: String,
        scale: Double,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.filename = filename
        self.scale = max(scale, 0.01)
        self.pixelWidth = max(pixelWidth, 1)
        self.pixelHeight = max(pixelHeight, 1)
    }
}
