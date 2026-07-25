import ApplicationServices
import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO

/// Isolates all unsupported private cursor API interaction.
///
/// API names and cursor identifiers were researched with Mousecape as a
/// reference. This implementation is original. See THIRD_PARTY_NOTICES.md.
@MainActor
final class CoreGraphicsCursorApplier:
    SystemCursorApplying,
    ImmediateSystemCursorRestoring
{
    private let paths: ApplicationPaths
    private let diagnostics: DiagnosticLogger
    private var api: CursorPrivateAPI?
    private var registeredIdentifiers: Set<String> = []
    private var customFingerprints: [String: UInt64] = [:]
    private var systemBackupIdentifiers: [String: String] = [:]

    init(paths: ApplicationPaths, diagnostics: DiagnosticLogger) {
        self.paths = paths
        self.diagnostics = diagnostics
    }

    func apply(theme: CursorTheme) async throws {
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        ) else {
            throw CursorStudioError.unsupportedOS(
                ProcessInfo.processInfo.operatingSystemVersionString
            )
        }
        guard !theme.entries.isEmpty else {
            throw CursorStudioError.emptyTheme
        }

        let api = try resolvedAPI()
        let connection = api.mainConnection()
        guard connection != 0 else {
            throw CursorStudioError.privateAPIUnavailable("CGSMainConnectionID")
        }

        do {
            try await restoreSystemDefault()
            try createSystemBackups(
                identifiers: Set(
                    theme.entries.flatMap { identifiers(for: $0.role, api: api) }
                ),
                api: api,
                connection: connection
            )
            // Persist the backup map before replacing the first cursor. If the
            // process is interrupted mid-Apply, the next launch can still
            // restore the original WindowServer registrations.
            try persistOverrideLedger()

            for entry in theme.entries {
                try apply(
                    entry: entry,
                    themeID: theme.id,
                    api: api,
                    connection: connection
                )
                try persistOverrideLedger()
            }
            api.setDockCursorOverride(connection, false)
        } catch {
            diagnostics.record(operation: "apply", error: error)
            do {
                try await restoreSystemDefault()
            } catch {
                diagnostics.record(operation: "rollback", error: error)
            }
            if let studioError = error as? CursorStudioError {
                throw studioError
            }
            throw CursorStudioError.applicationFailed(error.localizedDescription)
        }
    }

    func restoreSystemDefault() async throws {
        try restoreSystemDefaultImmediately()
    }

    func restoreSystemDefaultImmediately() throws {
        let api = try resolvedAPI()
        let connection = api.mainConnection()
        guard connection != 0 else {
            throw CursorStudioError.privateAPIUnavailable("CGSMainConnectionID")
        }

        let persistedLedger = loadOverrideLedger()
        var resetIdentifiers = registeredIdentifiers
        if let persistedLedger {
            resetIdentifiers.formUnion(persistedLedger.fingerprints.keys)
        }
        for role in CursorRole.allCases {
            resetIdentifiers.formUnion(identifiers(for: role, api: api))
        }
        let fingerprints = customFingerprints.merging(
            persistedLedger?.fingerprints ?? [:],
            uniquingKeysWith: { current, _ in current }
        )
        let backupIdentifiers = systemBackupIdentifiers.merging(
            persistedLedger?.backupIdentifiers ?? [:],
            uniquingKeysWith: { current, _ in current }
        )

        var finalVerificationError: Error?
        // macOS 26 can publish one named-cursor seed per reset cycle. There
        // are currently nine named aliases, so a bounded 16 passes covers the
        // complete table without a delay or a Dock/Finder restart.
        for _ in 0..<16 {
            let expectedSystemFingerprints = try resetSystemRegistrations(
                identifiers: resetIdentifiers,
                customIdentifiers: Set(fingerprints.keys),
                backupIdentifiers: backupIdentifiers,
                api: api,
                connection: connection
            )
            do {
                try verifyRestoration(
                    identifiers: resetIdentifiers,
                    customFingerprints: fingerprints,
                    expectedSystemFingerprints: expectedSystemFingerprints,
                    api: api,
                    connection: connection
                )
                finalVerificationError = nil
                break
            } catch {
                // A cursor seed can be published one CoreCursorSet behind the
                // registration table. A complete second pass is deterministic
                // and avoids sleeping or restarting Dock/Finder.
                finalVerificationError = error
            }
        }
        if let finalVerificationError {
            throw finalVerificationError
        }
        registeredIdentifiers.removeAll()
        customFingerprints.removeAll()
        removeSystemBackups(
            backupIdentifiers.values,
            api: api,
            connection: connection
        )
        systemBackupIdentifiers.removeAll()
        try? FileManager.default.removeItem(at: paths.cursorOverrideLedgerFile)
    }

    private func apply(
        entry: CursorEntry,
        themeID: UUID,
        api: CursorPrivateAPI,
        connection: Int32
    ) throws {
        guard let assetURL = paths.assetURL(
            themeID: themeID,
            filename: entry.assetFilename
        ), FileManager.default.fileExists(atPath: assetURL.path) else {
            let error = CursorStudioError.missingThemeAsset(entry.assetFilename)
            diagnostics.record(operation: "load-asset", role: entry.role, error: error)
            throw error
        }
        let payload = try registrationPayload(
            entry: entry,
            fallbackAssetURL: assetURL,
            themeID: themeID
        )
        let hotspot = CGPoint(
            x: min(
                CGFloat(entry.hotspot.normalizedX)
                    * max(payload.size.width - 1, 0),
                31.99
            ),
            y: min(
                CGFloat(entry.hotspot.normalizedY)
                    * max(payload.size.height - 1, 0),
                31.99
            )
        )

        let names = identifiers(for: entry.role, api: api)
        var successes = 0
        var lastError: Int32 = 0

        for name in names {
            var seed: Int32 = 0
            let result = withMutableCString(name) { pointer in
                api.registerCursor(
                    connection,
                    pointer,
                    true,
                    true,
                    payload.size,
                    hotspot,
                    payload.frameCount,
                    payload.frameDuration,
                    payload.images as CFArray,
                    &seed
                )
            }
            if result == 0 {
                registeredIdentifiers.insert(name)
                customFingerprints[name] = copyRegisteredPayload(
                    named: name,
                    api: api,
                    connection: connection
                ).map {
                    Self.pixelFingerprint($0.images[0])
                } ?? Self.pixelFingerprint(payload.images[0])
                successes += 1
            } else {
                lastError = result
                diagnostics.record(
                    operation: "register",
                    role: entry.role,
                    error: CursorStudioError.applicationFailed(
                        L10n.text(
                            "The system API returned CGError \(result).",
                            "Системный API вернул CGError \(result)."
                        )
                    )
                )
            }
        }

        guard successes > 0 else {
            throw CursorStudioError.applicationFailed(
                L10n.text(
                    "\(entry.role.displayName) returned CGError \(lastError).",
                    "Роль «\(entry.role.displayName)» вернула CGError \(lastError)."
                )
            )
        }
    }

    private func registrationPayload(
        entry: CursorEntry,
        fallbackAssetURL: URL,
        themeID: UUID
    ) throws -> CursorRegistrationPayload {
        if entry.animationFallbackReason == nil,
           !entry.representations.isEmpty {
            var images: [CGImage] = []
            for representation in entry.representations {
                guard let url = paths.assetURL(
                    themeID: themeID,
                    filename: representation.filename
                ), FileManager.default.fileExists(atPath: url.path),
                   let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw CursorStudioError.missingThemeAsset(
                        representation.filename
                    )
                }
                images.append(image)
            }
            guard !images.isEmpty else {
                throw CursorStudioError.invalidImage
            }
            return CursorRegistrationPayload(
                images: images,
                size: CGSize(
                    width: CGFloat(entry.pointWidth),
                    height: CGFloat(entry.pointHeight)
                ),
                hotspot: .zero,
                frameCount: UInt(min(max(entry.frameCount, 1), 24)),
                frameDuration: entry.frameCount > 1
                    ? max(CGFloat(entry.frameDuration), 1.0 / 240.0)
                    : 1
            )
        }

        guard let source = CGImageSourceCreateWithURL(
            fallbackAssetURL as CFURL,
            nil
        ), let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CursorStudioError.invalidImage
        }
        let image = try Self.cursorImage(from: sourceImage)
        return CursorRegistrationPayload(
            images: [image],
            size: CGSize(
                width: CGFloat(entry.pointWidth),
                height: CGFloat(entry.pointHeight)
            ),
            hotspot: .zero,
            frameCount: 1,
            frameDuration: 1
        )
    }

    private func identifiers(
        for role: CursorRole,
        api: CursorPrivateAPI
    ) -> Set<String> {
        var names = Set(role.systemIdentifiers)
        guard role == .arrow || role == .iBeam else { return names }

        let needle = role == .arrow ? "arrow" : "ibeam"
        for cursorID in 0..<128 {
            guard let rawName = api.cursorName(Int32(cursorID)) else { continue }
            let name = String(cString: rawName)
            if name.localizedCaseInsensitiveContains(needle) {
                names.insert(name)
            }
        }
        return names
    }

    private func resolvedAPI() throws -> CursorPrivateAPI {
        if let api { return api }
        let resolved = try CursorPrivateAPI()
        api = resolved
        return resolved
    }

    private func verifyRestoration(
        identifiers: Set<String>,
        customFingerprints: [String: UInt64],
        expectedSystemFingerprints: [String: UInt64],
        api: CursorPrivateAPI,
        connection: Int32
    ) throws {
        var firstStaleIdentifier: String?
        for identifier in identifiers {
            if let expectedFingerprint = expectedSystemFingerprints[identifier] {
                let restoredFingerprint = copyRegisteredPayload(
                    named: identifier,
                    api: api,
                    connection: connection
                ).map {
                    Self.pixelFingerprint($0.images[0])
                }
                if restoredFingerprint != expectedFingerprint,
                   firstStaleIdentifier == nil {
                    firstStaleIdentifier = identifier
                }
                continue
            }
            guard let customFingerprint = customFingerprints[identifier] else {
                continue
            }
            guard let image = withMutableCString(identifier, {
                api.createCursorImage(connection, $0, nil)?.takeRetainedValue()
            }) else {
                continue
            }
            let restoredFingerprint = Self.pixelFingerprint(image)
            if restoredFingerprint == customFingerprint,
               firstStaleIdentifier == nil {
                firstStaleIdentifier = identifier
            }
        }

        let arrowIsAvailable = self.identifiers(for: .arrow, api: api).contains {
            identifier in
            withMutableCString(identifier) {
                api.createCursorImage(connection, $0, nil)?.takeRetainedValue()
            } != nil
        }
        guard arrowIsAvailable else {
            throw CursorStudioError.restorationFailed(
                L10n.text(
                    "The system Arrow registration is unavailable after reset.",
                    "После сброса недоступна системная регистрация курсора-стрелки."
                )
            )
        }
        if let firstStaleIdentifier {
            throw CursorStudioError.restorationFailed(
                L10n.text(
                    "\(firstStaleIdentifier) is still using the custom image.",
                    "\(firstStaleIdentifier) всё ещё использует пользовательское изображение."
                )
            )
        }
    }

    private func resetSystemRegistrations(
        identifiers: Set<String>,
        customIdentifiers: Set<String>,
        backupIdentifiers: [String: String],
        api: CursorPrivateAPI,
        connection: Int32
    ) throws -> [String: UInt64] {
        api.setDockCursorOverride(connection, false)
        var expectedSystemFingerprints: [String: UInt64] = [:]
        let mainIdentifiers = customIdentifiers
            .union(backupIdentifiers.keys)
            .filter { !$0.hasPrefix("com.apple.cursor.") }
        var identifiersNeedingFallback: [String] = []

        // Read and restore the named-cursor backups before
        // CoreCursorUnregisterAll, which also removes the backup registrations.
        for identifier in mainIdentifiers {
            guard let backupIdentifier = backupIdentifiers[identifier],
                  let payload = copyRegisteredPayload(
                      named: backupIdentifier,
                      api: api,
                      connection: connection
                  ) else {
                identifiersNeedingFallback.append(identifier)
                continue
            }
            removeRegistration(
                named: identifier,
                api: api,
                connection: connection
            )
            try register(
                payload: payload,
                named: identifier,
                api: api,
                connection: connection
            )
            expectedSystemFingerprints[identifier] =
                Self.pixelFingerprint(payload.images[0])
        }

        for name in identifiers where name.hasPrefix("com.apple.cursor.") {
            _ = withMutableCString(name) { pointer in
                api.removeCursor(connection, pointer, false)
            }
        }

        let result = api.unregisterAll(connection)
        guard result == 0 else {
            throw CursorStudioError.restorationFailed(
                L10n.text(
                    "The system API returned CGError \(result).",
                    "Системный API вернул CGError \(result)."
                )
            )
        }

        // CoreCursor only reconstructs com.apple.cursor.* registrations.
        for cursorID in 0..<45 {
            _ = api.setCoreCursor(connection, Int32(cursorID))
        }

        // A legacy ledger from an older Cursor Studio build has no backups.
        // Rebuild only those aliases from macOS's own NSCursor/CoreCursor
        // assets after the CoreCursor table is clean.
        for identifier in identifiersNeedingFallback {
            removeRegistration(
                named: identifier,
                api: api,
                connection: connection
            )
            let payload = try systemFallbackPayload(
                for: identifier,
                api: api,
                connection: connection
            )
            try register(
                payload: payload,
                named: identifier,
                api: api,
                connection: connection
            )
            expectedSystemFingerprints[identifier] =
                Self.pixelFingerprint(payload.images[0])
        }

        let arrowID = (0..<128).first { cursorID in
            guard let rawName = api.cursorName(Int32(cursorID)) else {
                return false
            }
            return String(cString: rawName)
                .localizedCaseInsensitiveContains("arrow")
        } ?? 0
        _ = api.setCoreCursor(connection, Int32(arrowID))
        api.setDockCursorOverride(connection, false)
        return expectedSystemFingerprints
    }

    private func removeRegistration(
        named identifier: String,
        api: CursorPrivateAPI,
        connection: Int32
    ) {
        withMutableCString(identifier) { pointer in
            _ = api.removeCursor(connection, pointer, false)
        }
    }

    private func createSystemBackups(
        identifiers: Set<String>,
        api: CursorPrivateAPI,
        connection: Int32
    ) throws {
        for identifier in identifiers
        where !identifier.hasPrefix("com.apple.cursor.")
            && systemBackupIdentifiers[identifier] == nil {
            guard let payload = copyRegisteredPayload(
                named: identifier,
                api: api,
                connection: connection
            ) else {
                throw CursorStudioError.restorationFailed(
                    L10n.text(
                        "The system cursor \(identifier) could not be backed up.",
                        "Не удалось сохранить системный курсор \(identifier)."
                    )
                )
            }
            let backupIdentifier =
                "com.cursorstudio.system-backup.\(UUID().uuidString)"
            try register(
                payload: payload,
                named: backupIdentifier,
                api: api,
                connection: connection
            )
            systemBackupIdentifiers[identifier] = backupIdentifier
        }
    }

    private func removeSystemBackups<S: Sequence>(
        _ identifiers: S,
        api: CursorPrivateAPI,
        connection: Int32
    ) where S.Element == String {
        for identifier in identifiers {
            withMutableCString(identifier) { pointer in
                _ = api.removeCursor(connection, pointer, false)
            }
        }
    }

    private func copyRegisteredPayload(
        named identifier: String,
        api: CursorPrivateAPI,
        connection: Int32
    ) -> CursorRegistrationPayload? {
        var size = CGSize.zero
        var hotspot = CGPoint.zero
        var frameCount: UInt = 0
        var frameDuration: CGFloat = 0
        var unmanagedImages: Unmanaged<CFArray>?
        let result = withMutableCString(identifier) { pointer in
            api.copyRegisteredCursorImages(
                connection,
                pointer,
                &size,
                &hotspot,
                &frameCount,
                &frameDuration,
                &unmanagedImages
            )
        }
        guard result == 0, let unmanagedImages else { return nil }
        let imageArray = unmanagedImages.takeRetainedValue()
        // The private API contract guarantees an array of CGImage values.
        let images = imageArray as! [CGImage]
        guard !images.isEmpty else { return nil }
        return CursorRegistrationPayload(
            images: images,
            size: size,
            hotspot: hotspot,
            frameCount: max(frameCount, 1),
            frameDuration: frameDuration > 0 ? frameDuration : 1
        )
    }

    private func copyCorePayload(
        cursorID: Int32,
        api: CursorPrivateAPI,
        connection: Int32
    ) -> CursorRegistrationPayload? {
        var size = CGSize.zero
        var hotspot = CGPoint.zero
        var frameCount: UInt = 0
        var frameDuration: CGFloat = 0
        var unmanagedImages: Unmanaged<CFArray>?
        let result = api.copyCoreCursorImages(
            connection,
            cursorID,
            &unmanagedImages,
            &size,
            &hotspot,
            &frameCount,
            &frameDuration
        )
        guard result == 0, let unmanagedImages else { return nil }
        let imageArray = unmanagedImages.takeRetainedValue()
        // The private API contract guarantees an array of CGImage values.
        let images = imageArray as! [CGImage]
        guard !images.isEmpty else { return nil }
        return CursorRegistrationPayload(
            images: images,
            size: size,
            hotspot: hotspot,
            frameCount: max(frameCount, 1),
            frameDuration: frameDuration > 0 ? frameDuration : 1
        )
    }

    private func systemFallbackPayload(
        for identifier: String,
        api: CursorPrivateAPI,
        connection: Int32
    ) throws -> CursorRegistrationPayload {
        let lowercased = identifier.lowercased()
        let resourceName: String?
        if lowercased.contains("ibeam") {
            resourceName = "ibeamvertical"
        } else if lowercased.contains("alias") {
            resourceName = "makealias"
        } else if lowercased.contains("copy") {
            resourceName = "copy"
        } else if lowercased.contains("wait") {
            resourceName = "busybutclickable"
        } else {
            resourceName = nil
        }
        if let resourceName,
           let payload = systemResourcePayload(named: resourceName) {
            return payload
        }

        if identifier.localizedCaseInsensitiveContains("wait"),
           let payload = copyCorePayload(
               cursorID: 4,
               api: api,
               connection: connection
           ) {
            return payload
        }
        if identifier.localizedCaseInsensitiveContains("alias"),
           let payload = copyCorePayload(
               cursorID: 2,
               api: api,
               connection: connection
           ) {
            return payload
        }
        if identifier.localizedCaseInsensitiveContains("copy"),
           let payload = copyCorePayload(
               cursorID: 5,
               api: api,
               connection: connection
           ) {
            return payload
        }

        let cursor: NSCursor?
        if lowercased.contains("arrow") {
            cursor = .arrow
        } else if lowercased.contains("ibeam") {
            cursor = .iBeam
        } else if lowercased.contains("alias") {
            cursor = .dragLink
        } else if lowercased.contains("copy") {
            cursor = .dragCopy
        } else {
            cursor = nil
        }
        guard let cursor,
              let image = cursor.image.cgImage(
                  forProposedRect: nil,
                  context: nil,
                  hints: nil
              ) else {
            throw CursorStudioError.restorationFailed(
                L10n.text(
                    "No system fallback is available for \(identifier).",
                    "Для \(identifier) нет системного варианта восстановления."
                )
            )
        }
        return CursorRegistrationPayload(
            images: [image],
            size: cursor.image.size,
            hotspot: cursor.hotSpot,
            frameCount: 1,
            frameDuration: 1
        )
    }

    /// Reads the pristine vector cursor shipped by HIServices. This is only a
    /// migration fallback for ledgers created before Cursor Studio 1.6, when
    /// no WindowServer backup alias was persisted before Apply.
    private func systemResourcePayload(
        named resourceName: String
    ) -> CursorRegistrationPayload? {
        let roots = [
            "/System/Library/Frameworks/ApplicationServices.framework/"
                + "Frameworks/HIServices.framework/Resources/cursors",
            "/System/Library/Frameworks/ApplicationServices.framework/"
                + "Versions/A/Frameworks/HIServices.framework/Versions/A/"
                + "Resources/cursors",
        ]
        guard let directory = roots
            .map(URL.init(fileURLWithPath:))
            .map({ $0.appendingPathComponent(resourceName, isDirectory: true) })
            .first(where: {
                FileManager.default.fileExists(atPath: $0.path)
            }) else {
            return nil
        }
        let metadataURL = directory.appendingPathComponent("info.plist")
        let imageURL = directory.appendingPathComponent("cursor.pdf")
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ) as? [String: Any],
              let sourceImage = NSImage(contentsOf: imageURL),
              let image = sourceImage.cgImage(
                  forProposedRect: nil,
                  context: nil,
                  hints: nil
              ) else {
            return nil
        }

        let frameCount = max((metadata["frames"] as? NSNumber)?.intValue ?? 1, 1)
        let frameDuration =
            (metadata["delay"] as? NSNumber)?.doubleValue ?? 1
        let width = sourceImage.size.width
        let frameHeight = sourceImage.size.height / CGFloat(frameCount)
        guard width > 0, frameHeight > 0 else { return nil }

        return CursorRegistrationPayload(
            images: [image],
            size: CGSize(width: width, height: frameHeight),
            hotspot: CGPoint(
                x: (metadata["hotx"] as? NSNumber)?.doubleValue ?? 0,
                y: (metadata["hoty"] as? NSNumber)?.doubleValue ?? 0
            ),
            frameCount: UInt(frameCount),
            frameDuration: frameDuration > 0 ? frameDuration : 1
        )
    }

    private func register(
        payload: CursorRegistrationPayload,
        named identifier: String,
        api: CursorPrivateAPI,
        connection: Int32
    ) throws {
        var seed: Int32 = 0
        let result = withMutableCString(identifier) { pointer in
            api.registerCursor(
                connection,
                pointer,
                true,
                true,
                payload.size,
                payload.hotspot,
                payload.frameCount,
                payload.frameDuration,
                payload.images as CFArray,
                &seed
            )
        }
        guard result == 0 else {
            throw CursorStudioError.restorationFailed(
                L10n.text(
                    "The system API returned CGError \(result) for \(identifier).",
                    "Системный API вернул CGError \(result) для \(identifier)."
                )
            )
        }
    }

    private func persistOverrideLedger() throws {
        try paths.createDirectories()
        let ledger = CursorOverrideLedger(
            fingerprints: customFingerprints,
            backupIdentifiers: systemBackupIdentifiers,
            appliedAt: .now
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ledger).write(
            to: paths.cursorOverrideLedgerFile,
            options: .atomic
        )
    }

    private func loadOverrideLedger() -> CursorOverrideLedger? {
        guard let data = try? Data(contentsOf: paths.cursorOverrideLedgerFile) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CursorOverrideLedger.self, from: data)
    }

    private static func cursorImage(from source: CGImage) throws -> CGImage {
        let scale = 64.0 / Double(max(source.width, source.height))
        let targetWidth = max(Int((Double(source.width) * scale).rounded()), 1)
        let targetHeight = max(Int((Double(source.height) * scale).rounded()), 1)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: targetWidth,
                  height: targetHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: targetWidth * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CursorStudioError.invalidImage
        }
        context.interpolationQuality = scale < 1 ? .high : .medium
        context.draw(
            source,
            in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        )
        guard let image = context.makeImage() else {
            throw CursorStudioError.invalidImage
        }
        return image
    }

    private static func pixelFingerprint(_ image: CGImage) -> UInt64 {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return 0 }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return 0
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in pixels {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        hash ^= UInt64(width)
        hash &*= 1_099_511_628_211
        hash ^= UInt64(height)
        return hash
    }
}

private struct CursorOverrideLedger: Codable {
    let fingerprints: [String: UInt64]
    let backupIdentifiers: [String: String]?
    let appliedAt: Date
}

private struct CursorRegistrationPayload {
    let images: [CGImage]
    let size: CGSize
    let hotspot: CGPoint
    let frameCount: UInt
    let frameDuration: CGFloat
}

private typealias ConnectionFunction = @convention(c) () -> Int32
private typealias RegisterCursorFunction = @convention(c) (
    Int32,
    UnsafeMutablePointer<CChar>,
    Bool,
    Bool,
    CGSize,
    CGPoint,
    UInt,
    CGFloat,
    CFArray,
    UnsafeMutablePointer<Int32>
) -> Int32
private typealias RemoveCursorFunction = @convention(c) (
    Int32,
    UnsafeMutablePointer<CChar>,
    Bool
) -> Int32
private typealias UnregisterAllFunction = @convention(c) (Int32) -> Int32
private typealias SetCoreCursorFunction = @convention(c) (Int32, Int32) -> Int32
private typealias CursorNameFunction = @convention(c) (Int32) -> UnsafePointer<CChar>?
private typealias DockCursorOverrideFunction = @convention(c) (Int32, Bool) -> Void
private typealias CreateCursorImageFunction = @convention(c) (
    Int32,
    UnsafeMutablePointer<CChar>,
    UnsafeMutablePointer<CGPoint>?
) -> Unmanaged<CGImage>?
private typealias CopyRegisteredCursorImagesFunction = @convention(c) (
    Int32,
    UnsafeMutablePointer<CChar>,
    UnsafeMutablePointer<CGSize>,
    UnsafeMutablePointer<CGPoint>,
    UnsafeMutablePointer<UInt>,
    UnsafeMutablePointer<CGFloat>,
    UnsafeMutablePointer<Unmanaged<CFArray>?>
) -> Int32
private typealias CopyCoreCursorImagesFunction = @convention(c) (
    Int32,
    Int32,
    UnsafeMutablePointer<Unmanaged<CFArray>?>,
    UnsafeMutablePointer<CGSize>,
    UnsafeMutablePointer<CGPoint>,
    UnsafeMutablePointer<UInt>,
    UnsafeMutablePointer<CGFloat>
) -> Int32

private final class CursorPrivateAPI {
    private var handles: [UnsafeMutableRawPointer] = []

    let mainConnection: ConnectionFunction
    let registerCursor: RegisterCursorFunction
    let removeCursor: RemoveCursorFunction
    let unregisterAll: UnregisterAllFunction
    let setCoreCursor: SetCoreCursorFunction
    let cursorName: CursorNameFunction
    let setDockCursorOverride: DockCursorOverrideFunction
    let createCursorImage: CreateCursorImageFunction
    let copyRegisteredCursorImages: CopyRegisteredCursorImagesFunction
    let copyCoreCursorImages: CopyCoreCursorImagesFunction

    init() throws {
        let frameworkPaths = [
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
        ]
        handles = frameworkPaths.compactMap {
            dlopen($0, RTLD_LAZY | RTLD_LOCAL)
        }
        if let process = dlopen(nil, RTLD_LAZY | RTLD_LOCAL) {
            handles.append(process)
        }

        mainConnection = try Self.load(
            ["CGSMainConnectionID", "SLSMainConnectionID"],
            handles: handles
        )
        registerCursor = try Self.load(
            ["CGSRegisterCursorWithImages", "SLSRegisterCursorWithImages"],
            handles: handles
        )
        removeCursor = try Self.load(
            ["CGSRemoveRegisteredCursor", "SLSRemoveRegisteredCursor"],
            handles: handles
        )
        unregisterAll = try Self.load(["CoreCursorUnregisterAll"], handles: handles)
        setCoreCursor = try Self.load(["CoreCursorSet"], handles: handles)
        cursorName = try Self.load(
            ["CGSCursorNameForSystemCursor", "SLSCursorNameForSystemCursor"],
            handles: handles
        )
        setDockCursorOverride = try Self.load(
            ["CGSSetDockCursorOverride", "SLSSetDockCursorOverride"],
            handles: handles
        )
        createCursorImage = try Self.load(
            ["CGSCreateRegisteredCursorImage", "SLSCreateRegisteredCursorImage"],
            handles: handles
        )
        copyRegisteredCursorImages = try Self.load(
            ["CGSCopyRegisteredCursorImages", "SLSCopyRegisteredCursorImages"],
            handles: handles
        )
        copyCoreCursorImages = try Self.load(
            ["CoreCursorCopyImages"],
            handles: handles
        )
    }

    private static func load<T>(
        _ names: [String],
        handles: [UnsafeMutableRawPointer]
    ) throws -> T {
        for name in names {
            for handle in handles {
                if let symbol = dlsym(handle, name) {
                    return unsafeBitCast(symbol, to: T.self)
                }
            }
        }
        throw CursorStudioError.privateAPIUnavailable(names.joined(separator: " / "))
    }
}

private func withMutableCString<T>(
    _ string: String,
    _ body: (UnsafeMutablePointer<CChar>) throws -> T
) rethrows -> T {
    var bytes = Array(string.utf8CString)
    return try bytes.withUnsafeMutableBufferPointer { buffer in
        try body(buffer.baseAddress!)
    }
}
