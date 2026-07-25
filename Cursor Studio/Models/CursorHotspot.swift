import CoreGraphics
import Foundation

nonisolated struct CursorHotspot: Codable, Hashable, Sendable {
    private(set) var normalizedX: Double
    private(set) var normalizedY: Double

    init(normalizedX: Double, normalizedY: Double) {
        self.normalizedX = min(max(normalizedX, 0), 1)
        self.normalizedY = min(max(normalizedY, 0), 1)
    }

    static let topLeft = CursorHotspot(normalizedX: 0, normalizedY: 0)
    static let center = CursorHotspot(normalizedX: 0.5, normalizedY: 0.5)

    mutating func set(normalizedX: Double, normalizedY: Double) {
        self.normalizedX = min(max(normalizedX, 0), 1)
        self.normalizedY = min(max(normalizedY, 0), 1)
    }

    func pixelPoint(width: Int, height: Int) -> CGPoint {
        guard width > 0, height > 0 else { return .zero }
        return CGPoint(
            x: normalizedX * Double(max(width - 1, 0)),
            y: normalizedY * Double(max(height - 1, 0))
        )
    }

    static func fromPixelPoint(
        _ point: CGPoint,
        width: Int,
        height: Int
    ) -> CursorHotspot {
        guard width > 1, height > 1 else { return .topLeft }
        return CursorHotspot(
            normalizedX: point.x / Double(width - 1),
            normalizedY: point.y / Double(height - 1)
        )
    }
}
