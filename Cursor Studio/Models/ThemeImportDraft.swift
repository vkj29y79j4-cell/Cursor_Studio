import Foundation

nonisolated struct ThemeImportReview: Hashable, Sendable {
    var themeName: String
    var recognizedRoleCount: Int
    var unrecognizedRoleCount: Int
    var warningMessages: [String]
    var missingImageCount: Int
    var animatedRoleCount: Int
    var staticAnimationFallbackCount: Int
}

/// Shared staging model used by Mousecape, Windows, and future theme importers.
/// Importers only parse into this value; ThemeStore owns the transactional move
/// into the user's library.
nonisolated struct ThemeImportDraft: Identifiable, Sendable {
    var id: UUID { theme.id }
    var theme: CursorTheme
    var stagingThemeDirectory: URL
    var review: ThemeImportReview
}

// Source compatibility for the existing Marketplace and .cape test surface.
typealias CapeImportReview = ThemeImportReview
typealias CapeImportDraft = ThemeImportDraft
