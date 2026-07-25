import XCTest
@testable import Cursor_Studio

final class ModelPersistenceTests: XCTestCase {
    @MainActor
    func testThemeEncodingRoundTrip() throws {
        let entry = CursorEntry(
            role: .arrow,
            assetFilename: "arrow.png",
            pixelWidth: 64,
            pixelHeight: 64,
            hotspot: CursorHotspot(normalizedX: 0.125, normalizedY: 0.25)
        )
        let theme = CursorTheme(name: "Test Theme", entries: [entry])
        let document = ThemeLibraryDocument(
            themes: [theme],
            activeThemeID: theme.id
        )

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(
            ThemeLibraryDocument.self,
            from: data
        )

        XCTAssertEqual(decoded.themes, [theme])
        XCTAssertEqual(decoded.activeThemeID, theme.id)
    }

    @MainActor
    func testCursorRolePersistenceValuesAreStable() throws {
        let expected = [
            "arrow", "pointingHand", "iBeam", "crosshair", "openHand",
            "closedHand", "resizeLeftRight", "resizeUpDown",
            "resizeDiagonalNWSE", "resizeDiagonalNESW",
            "operationNotAllowed", "help", "contextualMenu",
            "dragCopy", "dragLink", "progress", "busy",
        ]
        XCTAssertEqual(CursorRole.allCases.map(\.rawValue), expected)

        for role in CursorRole.allCases {
            let data = try JSONEncoder().encode(role)
            XCTAssertEqual(try JSONDecoder().decode(CursorRole.self, from: data), role)
        }
    }

    @MainActor
    func testPartialThemeKeepsUnconfiguredRolesMissing() {
        let entry = CursorEntry(
            role: .arrow,
            assetFilename: "arrow.png",
            pixelWidth: 32,
            pixelHeight: 32
        )
        let theme = CursorTheme(name: "Partial", entries: [entry])

        XCTAssertEqual(theme.configuredRoles, [.arrow])
        XCTAssertFalse(theme.missingRoles.contains(.arrow))
        XCTAssertTrue(theme.missingRoles.contains(.iBeam))
        XCTAssertEqual(
            theme.missingRoles.count,
            CursorRole.allCases.count - 1
        )
    }

    @MainActor
    func testVersionOneDocumentDecodesWithCapeDefaults() throws {
        let themeID = UUID()
        let entryID = UUID()
        let oldJSON: [String: Any] = [
            "themes": [[
                "id": themeID.uuidString,
                "name": "Existing MVP Theme",
                "createdAt": "2025-01-01T00:00:00Z",
                "modifiedAt": "2025-01-01T00:00:00Z",
                "entries": [[
                    "id": entryID.uuidString,
                    "role": "arrow",
                    "assetFilename": "arrow.png",
                    "pixelWidth": 64,
                    "pixelHeight": 64,
                    "hotspot": [
                        "normalizedX": 0.1,
                        "normalizedY": 0.2,
                    ],
                    "modifiedAt": "2025-01-01T00:00:00Z",
                ]],
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: oldJSON)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let document = try decoder.decode(
            ThemeLibraryDocument.self,
            from: data
        )
        let entry = try XCTUnwrap(document.themes.first?.entries.first)

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertNil(document.themes.first?.importMetadata)
        XCTAssertEqual(entry.pointWidth, 64)
        XCTAssertEqual(entry.pointHeight, 64)
        XCTAssertEqual(entry.frameCount, 1)
        XCTAssertTrue(entry.representations.isEmpty)
    }
}
