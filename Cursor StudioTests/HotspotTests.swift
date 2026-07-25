import CoreGraphics
import XCTest
@testable import Cursor_Studio

final class HotspotTests: XCTestCase {
    @MainActor
    func testHotspotClampsAndConvertsToPixels() {
        let hotspot = CursorHotspot(normalizedX: 1.5, normalizedY: -0.5)
        XCTAssertEqual(hotspot.normalizedX, 1)
        XCTAssertEqual(hotspot.normalizedY, 0)
        XCTAssertEqual(hotspot.pixelPoint(width: 64, height: 32), CGPoint(x: 63, y: 0))
    }

    @MainActor
    func testPixelRoundTripUsesPixelIndependentNormalization() {
        let original = CGPoint(x: 15, y: 7)
        let hotspot = CursorHotspot.fromPixelPoint(original, width: 31, height: 15)
        let converted = hotspot.pixelPoint(width: 61, height: 29)

        XCTAssertEqual(converted.x, 30, accuracy: 0.0001)
        XCTAssertEqual(converted.y, 14, accuracy: 0.0001)
    }

    @MainActor
    func testZeroSizeNeverProducesInvalidCoordinates() {
        XCTAssertEqual(
            CursorHotspot.center.pixelPoint(width: 0, height: 0),
            .zero
        )
    }
}
