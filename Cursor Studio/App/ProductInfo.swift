import Foundation

nonisolated enum ProductInfo {
    static let name = "Cursor Studio"
    static let bundleIdentifier = "studio.cursor.CursorStudio"
    static let schemaVersion = 3
    static let diagnosticLogLimit = 512 * 1_024

    static var privacySummary: String { L10n.privacySummary }
    static var compatibilityNotice: String { L10n.compatibilityNotice }
}
