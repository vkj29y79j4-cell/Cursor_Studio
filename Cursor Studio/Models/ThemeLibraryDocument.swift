import Foundation

nonisolated struct ThemeLibraryDocument: Codable, Sendable {
    var schemaVersion: Int
    var themes: [CursorTheme]
    var activeThemeID: UUID?

    init(
        schemaVersion: Int = ProductInfo.schemaVersion,
        themes: [CursorTheme] = [],
        activeThemeID: UUID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.themes = themes
        self.activeThemeID = activeThemeID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case themes
        case activeThemeID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 1
        themes = try container.decodeIfPresent(
            [CursorTheme].self,
            forKey: .themes
        ) ?? []
        activeThemeID = try container.decodeIfPresent(
            UUID.self,
            forKey: .activeThemeID
        )
    }
}
