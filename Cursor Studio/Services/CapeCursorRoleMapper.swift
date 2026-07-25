import Foundation

nonisolated enum CapeCursorRoleMapper {
    private static let identifierMap: [String: CursorRole] = {
        var result: [String: CursorRole] = [:]
        for role in CursorRole.allCases {
            for identifier in role.systemIdentifiers {
                result[identifier.lowercased()] = role
            }
        }

        result["com.apple.coregraphics.ibeamxor"] = .iBeam
        result["com.apple.cursor.7"] = .crosshair
        result["com.apple.cursor.8"] = .crosshair
        result["arrow"] = .arrow
        result["pointing"] = .pointingHand
        result["pointing hand"] = .pointingHand
        result["ibeam"] = .iBeam
        result["i-beam"] = .iBeam
        result["crosshair"] = .crosshair
        result["open"] = .openHand
        result["open hand"] = .openHand
        result["closed"] = .closedHand
        result["closed hand"] = .closedHand
        result["forbidden"] = .operationNotAllowed
        result["help"] = .help
        result["ctx menu"] = .contextualMenu
        result["contextual menu"] = .contextualMenu
        result["copy drag"] = .dragCopy
        result["drag copy"] = .dragCopy
        result["link"] = .dragLink
        result["drag link"] = .dragLink
        result["wait"] = .progress
        result["busy"] = .busy
        return result
    }()

    static func role(for sourceIdentifier: String) -> CursorRole? {
        let key = sourceIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let exact = identifierMap[key] {
            return exact
        }
        if key.contains("arrow"), key.contains("coregraphics") {
            return .arrow
        }
        if key.contains("ibeam") {
            return .iBeam
        }
        return nil
    }
}
