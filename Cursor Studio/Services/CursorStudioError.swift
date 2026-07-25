import Foundation

nonisolated enum CursorStudioError: LocalizedError, Equatable {
    case unsupportedOS(String)
    case privateAPIUnavailable(String)
    case invalidImage
    case unsupportedSVG
    case impossibleHotspot
    case missingThemeAsset(String)
    case applicationFailed(String)
    case restorationFailed(String)
    case corruptedDatabase
    case filePermission(String)
    case themeNotFound
    case emptyTheme
    case invalidCape(String)
    case unsupportedCapeStructure
    case capeMissingCursorEntries
    case corruptedCapeImage(String)
    case invalidCapeHotspot(String)
    case unsupportedCapeAnimation(String)
    case invalidWindowsCursor(String)
    case invalidWindowsArchive(String)
    case windowsThemeMissingCursors

    var errorDescription: String? {
        L10n.errorDescription(self)
    }
}
