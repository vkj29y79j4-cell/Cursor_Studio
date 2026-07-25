import Foundation

nonisolated enum CursorRole: String, CaseIterable, Codable, Identifiable, Sendable {
    case arrow
    case pointingHand
    case iBeam
    case crosshair
    case openHand
    case closedHand
    case resizeLeftRight
    case resizeUpDown
    case resizeDiagonalNWSE
    case resizeDiagonalNESW
    case operationNotAllowed
    case help
    case contextualMenu
    case dragCopy
    case dragLink
    case progress
    case busy

    var id: String { rawValue }

    var displayName: String {
        L10n.roleName(self)
    }

    var symbolName: String {
        switch self {
        case .arrow: "arrow.up.left"
        case .pointingHand: "hand.point.up.left"
        case .iBeam: "character.cursor.ibeam"
        case .crosshair: "scope"
        case .openHand: "hand.raised"
        case .closedHand: "hand.raised.fingers.spread"
        case .resizeLeftRight: "arrow.left.and.right"
        case .resizeUpDown: "arrow.up.and.down"
        case .resizeDiagonalNWSE: "arrow.up.left.and.arrow.down.right"
        case .resizeDiagonalNESW: "arrow.up.right.and.arrow.down.left"
        case .operationNotAllowed: "nosign"
        case .help: "questionmark.circle"
        case .contextualMenu: "contextualmenu.and.cursorarrow"
        case .dragCopy: "plus.square.on.square"
        case .dragLink: "link"
        case .progress: "progress.indicator"
        case .busy: "hourglass"
        }
    }

    /// Known WindowServer identifiers. Arrow and I-Beam synonyms are also
    /// discovered at runtime on newer macOS versions.
    var systemIdentifiers: [String] {
        switch self {
        case .arrow:
            ["com.apple.coregraphics.Arrow", "com.apple.coregraphics.ArrowCtx"]
        case .pointingHand:
            ["com.apple.cursor.13"]
        case .iBeam:
            ["com.apple.coregraphics.IBeam", "com.apple.coregraphics.IBeamXOR"]
        case .crosshair:
            ["com.apple.cursor.7", "com.apple.cursor.8"]
        case .openHand:
            ["com.apple.cursor.12"]
        case .closedHand:
            ["com.apple.cursor.11"]
        case .resizeLeftRight:
            [
                "com.apple.cursor.17", "com.apple.cursor.18",
                "com.apple.cursor.19", "com.apple.cursor.28",
            ]
        case .resizeUpDown:
            [
                "com.apple.cursor.21", "com.apple.cursor.22",
                "com.apple.cursor.23", "com.apple.cursor.31",
                "com.apple.cursor.32", "com.apple.cursor.36",
            ]
        case .resizeDiagonalNWSE:
            [
                "com.apple.cursor.33", "com.apple.cursor.34",
                "com.apple.cursor.35",
            ]
        case .resizeDiagonalNESW:
            [
                "com.apple.cursor.29", "com.apple.cursor.30",
                "com.apple.cursor.37",
            ]
        case .operationNotAllowed:
            ["com.apple.cursor.3"]
        case .help:
            ["com.apple.cursor.40"]
        case .contextualMenu:
            ["com.apple.cursor.24"]
        case .dragCopy:
            ["com.apple.coregraphics.Copy", "com.apple.cursor.5"]
        case .dragLink:
            ["com.apple.coregraphics.Alias", "com.apple.cursor.2"]
        case .progress:
            ["com.apple.coregraphics.Wait"]
        case .busy:
            ["com.apple.cursor.4"]
        }
    }
}
