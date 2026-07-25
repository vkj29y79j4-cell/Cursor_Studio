import Foundation

/// Maps Windows cursor scheme names and common file names onto Cursor Studio's
/// platform-neutral cursor roles. Unknown Windows roles are preserved as
/// unassigned entries instead of being discarded.
nonisolated enum WindowsCursorRoleMapper {
    static func role(
        for sourceName: String,
        schemeRole: String? = nil
    ) -> CursorRole? {
        if let schemeRole, let exact = role(forWindowsSchemeRole: schemeRole) {
            return exact
        }

        let key = normalized(sourceName)
        let compact = key.replacingOccurrences(of: " ", with: "")

        if containsAny(compact, ["handwriting", "nwpen", "pen"])
            || containsAny(key, ["alternate select", "up arrow"]) {
            return nil
        }
        if containsAny(
            compact,
            ["sizenwse", "nwseresize", "diagonal1", "diagonalresize1", "dgn1"]
        ) {
            return .resizeDiagonalNWSE
        }
        if containsAny(
            compact,
            ["sizenesw", "neswresize", "diagonal2", "diagonalresize2", "dgn2"]
        ) {
            return .resizeDiagonalNESW
        }
        if containsAny(compact, ["sizewe", "resizeew", "resizeleftright", "horizontal"]) {
            return .resizeLeftRight
        }
        if containsAny(compact, ["sizens", "resizens", "resizeupdown", "vertical"]) {
            return .resizeUpDown
        }
        if containsAny(key, ["working in background", "app starting"])
            || containsAny(compact, ["appstarting", "working", "background"]) {
            return .progress
        }
        if containsAny(compact, ["wait", "busy"]) {
            return .busy
        }
        if containsAny(compact, ["dragcopy", "copydrag"]) {
            return .dragCopy
        }
        if containsAny(compact, ["draglink", "alias"]) {
            return .dragLink
        }
        if containsAny(key, ["link select", "pointing hand"])
            || containsAny(compact, ["linkselect", "pointinghand", "pointer", "hand", "link"]) {
            return .pointingHand
        }
        if containsAny(key, ["text select"])
            || containsAny(compact, ["ibeam", "textselect", "text"]) {
            return .iBeam
        }
        if containsAny(key, ["precision select"])
            || containsAny(compact, ["crosshair", "precision", "cross"]) {
            return .crosshair
        }
        if containsAny(key, ["normal select"])
            || containsAny(compact, ["arrow", "normalselect", "normal"]) {
            return .arrow
        }
        if containsAny(
            compact,
            ["unavailable", "notavailable", "notallowed", "forbidden"]
        )
            || compact == "no" {
            return .operationNotAllowed
        }
        if containsAny(compact, ["help", "question"]) {
            return .help
        }
        if containsAny(compact, ["sizeall", "move", "openhand"]) {
            return .openHand
        }
        if containsAny(compact, ["closedhand", "grabbing"]) {
            return .closedHand
        }
        if containsAny(compact, ["contextmenu", "contextualmenu"]) {
            return .contextualMenu
        }
        return nil
    }

    static func role(forWindowsSchemeRole rawValue: String) -> CursorRole? {
        switch normalized(rawValue).replacingOccurrences(of: " ", with: "") {
        case "arrow", "normalselect":
            .arrow
        case "hand", "linkselect":
            .pointingHand
        case "ibeam", "textselect":
            .iBeam
        case "crosshair", "precisionselect":
            .crosshair
        case "sizens":
            .resizeUpDown
        case "sizewe":
            .resizeLeftRight
        case "sizenwse":
            .resizeDiagonalNWSE
        case "sizenesw":
            .resizeDiagonalNESW
        case "sizeall":
            .openHand
        case "no", "unavailable":
            .operationNotAllowed
        case "help", "helpselect":
            .help
        case "appstarting", "workinginbackground":
            .progress
        case "wait", "busy":
            .busy
        default:
            nil
        }
    }

    private static func normalized(_ value: String) -> String {
        URL(fileURLWithPath: value)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
            .replacingOccurrences(
                of: #"[_\-.]+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAny(
        _ value: String,
        _ needles: [String]
    ) -> Bool {
        needles.contains { value.contains($0) }
    }
}
