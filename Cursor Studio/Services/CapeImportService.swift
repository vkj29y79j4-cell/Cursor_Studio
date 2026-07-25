import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor CapeImportService {
    private static let maximumCapeBytes = 128 * 1_024 * 1_024
    private static let maximumRepresentationBytes = 32 * 1_024 * 1_024
    private static let maximumCursorCount = 256
    private static let maximumRepresentationCount = 8
    private static let maximumDecodedPixels = 32_000_000

    private let paths: ApplicationPaths
    private let fileManager: FileManager
    private let previewGenerator: ThemePreviewGenerator

    init(paths: ApplicationPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        previewGenerator = ThemePreviewGenerator(fileManager: fileManager)
    }

    nonisolated static func canImport(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("cape") == .orderedSame
    }

    func prepareImport(from sourceURL: URL) throws -> CapeImportDraft {
        guard Self.canImport(sourceURL) else {
            throw CursorStudioError.invalidCape("The file extension must be .cape.")
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try paths.createDirectories(fileManager: fileManager)
        removeStaleStagingDirectories()

        if let fileSize = try? sourceURL.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize, fileSize > Self.maximumCapeBytes {
            throw CursorStudioError.invalidCape("The file is too large.")
        }

        let sourceData: Data
        do {
            sourceData = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        } catch {
            throw CursorStudioError.filePermission(sourceURL.lastPathComponent)
        }
        guard !sourceData.isEmpty, sourceData.count <= Self.maximumCapeBytes else {
            throw CursorStudioError.invalidCape("The property list is empty or too large.")
        }

        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(
                from: sourceData,
                options: [],
                format: nil
            )
        } catch {
            throw CursorStudioError.invalidCape("The property list could not be decoded.")
        }
        guard let root = propertyList as? [String: Any] else {
            throw CursorStudioError.unsupportedCapeStructure
        }
        if root["$archiver"] != nil || root["$objects"] != nil {
            throw CursorStudioError.unsupportedCapeStructure
        }
        guard let cursorDictionaries = root["Cursors"] as? [String: Any],
              !cursorDictionaries.isEmpty else {
            throw CursorStudioError.capeMissingCursorEntries
        }
        guard cursorDictionaries.count <= Self.maximumCursorCount else {
            throw CursorStudioError.invalidCape("It contains too many cursor entries.")
        }

        let themeID = UUID()
        let stagingThemeDirectory = paths.importStagingDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let assetsDirectory = stagingThemeDirectory.appending(
            path: "Assets",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: assetsDirectory,
            withIntermediateDirectories: true
        )

        var keepStagingDirectory = false
        defer {
            if !keepStagingDirectory {
                try? fileManager.removeItem(at: stagingThemeDirectory)
            }
        }

        let requestedName = string(root["CapeName"])
            ?? sourceURL.deletingPathExtension().lastPathComponent
        let themeName = requestedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var theme = CursorTheme(
            id: themeID,
            name: themeName.isEmpty ? "Imported Cape" : themeName
        )
        var warnings: [String] = []
        var unassigned: [UnassignedCursorEntry] = []
        var missingImageCount = 0
        var animatedRoleCount = 0
        var staticAnimationFallbackCount = 0
        var validImageCount = 0
        var assignedRoles: Set<CursorRole> = []

        if let minimumVersion = number(root["MinimumVersion"]),
           minimumVersion > 2.0 {
            warnings.append(
                L10n.text(
                    "This cape targets Mousecape format \(format(minimumVersion)); only known fields were imported.",
                    "Тема рассчитана на формат Mousecape \(format(minimumVersion)); импортированы только известные поля."
                )
            )
        }

        for sourceIdentifier in cursorDictionaries.keys.sorted() {
            guard let cursor = cursorDictionaries[sourceIdentifier]
                as? [String: Any] else {
                warnings.append(
                    L10n.text(
                        "\(sourceIdentifier): cursor metadata is not a dictionary.",
                        "\(sourceIdentifier): метаданные курсора не являются словарём."
                    )
                )
                continue
            }

            let parsed = try parseCursor(
                sourceIdentifier: sourceIdentifier,
                dictionary: cursor,
                assetsDirectory: assetsDirectory,
                warnings: &warnings
            )
            missingImageCount += parsed.missingImageCount
            guard let parsedCursor = parsed.cursor else {
                continue
            }
            validImageCount += 1

            if parsedCursor.frameCount > 1 {
                animatedRoleCount += 1
            }
            if parsedCursor.animationFallbackReason != nil {
                staticAnimationFallbackCount += 1
            }

            guard let role = CapeCursorRoleMapper.role(for: sourceIdentifier) else {
                unassigned.append(
                    parsedCursor.unassigned(
                        reason: L10n.text(
                            "No Cursor Studio role mapping exists yet.",
                            "В Cursor Studio пока нет соответствующей роли."
                        )
                    )
                )
                continue
            }
            guard assignedRoles.insert(role).inserted else {
                let reason = L10n.text(
                    "Another cursor in this cape already maps to \(role.displayName).",
                    "Другой курсор этой темы уже сопоставлен с ролью «\(role.displayName)»."
                )
                warnings.append("\(sourceIdentifier): \(reason)")
                unassigned.append(parsedCursor.unassigned(reason: reason))
                continue
            }

            theme.setEntry(parsedCursor.entry(for: role))
        }

        guard validImageCount > 0 else {
            throw CursorStudioError.capeMissingCursorEntries
        }

        theme.importMetadata = ThemeImportMetadata(
            sourceFormat: "Mousecape .cape",
            sourceIdentifier: string(root["Identifier"]),
            author: string(root["Author"]),
            sourceVersion: number(root["CapeVersion"]).map(format),
            importedAt: .now,
            warnings: warnings,
            unassignedEntries: unassigned
        )
        theme.previewAssetFilename = try previewGenerator.generatePreview(
            for: theme,
            in: assetsDirectory,
            fallbackAssetFilename: unassigned.first?.previewAssetFilename
        )

        let review = CapeImportReview(
            themeName: theme.name,
            recognizedRoleCount: theme.entries.count,
            unrecognizedRoleCount: unassigned.count,
            warningMessages: warnings,
            missingImageCount: missingImageCount,
            animatedRoleCount: animatedRoleCount,
            staticAnimationFallbackCount: staticAnimationFallbackCount
        )
        keepStagingDirectory = true
        return CapeImportDraft(
            theme: theme,
            stagingThemeDirectory: stagingThemeDirectory,
            review: review
        )
    }

    func discard(_ draft: CapeImportDraft) {
        try? fileManager.removeItem(at: draft.stagingThemeDirectory)
    }

    private func parseCursor(
        sourceIdentifier: String,
        dictionary: [String: Any],
        assetsDirectory: URL,
        warnings: inout [String]
    ) throws -> ParsedCapeCursorResult {
        let pointWidth = number(dictionary["PointsWide"]) ?? 0
        let pointHeight = number(dictionary["PointsHigh"]) ?? 0
        guard pointWidth.isFinite, pointHeight.isFinite,
              pointWidth > 0, pointHeight > 0,
              pointWidth <= 2_048, pointHeight <= 2_048 else {
            warnings.append(
                L10n.text(
                    "\(sourceIdentifier): invalid point dimensions.",
                    "\(sourceIdentifier): некорректные размеры в пунктах."
                )
            )
            return ParsedCapeCursorResult(cursor: nil, missingImageCount: 1)
        }

        let rawFrameCount = number(dictionary["FrameCount"]) ?? 1
        guard rawFrameCount.isFinite, rawFrameCount >= 1,
              rawFrameCount <= 512 else {
            warnings.append(
                L10n.text(
                    "\(sourceIdentifier): invalid frame count.",
                    "\(sourceIdentifier): некорректное количество кадров."
                )
            )
            return ParsedCapeCursorResult(cursor: nil, missingImageCount: 1)
        }
        let frameCount = max(Int(rawFrameCount.rounded()), 1)
        let rawFrameDuration = number(dictionary["FrameDuration"]) ?? 0
        let frameDuration = rawFrameDuration.isFinite ? max(rawFrameDuration, 0) : 0

        let rawHotspotX = number(dictionary["HotSpotX"]) ?? 0
        let rawHotspotY = number(dictionary["HotSpotY"]) ?? 0
        guard rawHotspotX.isFinite, rawHotspotY.isFinite else {
            warnings.append(
                L10n.text(
                    "\(sourceIdentifier): invalid hotspot coordinates.",
                    "\(sourceIdentifier): некорректные координаты активной точки."
                )
            )
            return ParsedCapeCursorResult(cursor: nil, missingImageCount: 1)
        }
        let maximumHotspotX = max(pointWidth - 1, 0)
        let maximumHotspotY = max(pointHeight - 1, 0)
        let hotspotX = min(max(rawHotspotX, 0), maximumHotspotX)
        let hotspotY = min(max(rawHotspotY, 0), maximumHotspotY)
        if hotspotX != rawHotspotX || hotspotY != rawHotspotY {
            warnings.append(
                L10n.text(
                    "\(sourceIdentifier): hotspot was outside the cursor and has been clamped.",
                    "\(sourceIdentifier): активная точка была за пределами курсора и перемещена внутрь."
                )
            )
        }
        let hotspot = CursorHotspot(
            normalizedX: maximumHotspotX > 0 ? hotspotX / maximumHotspotX : 0,
            normalizedY: maximumHotspotY > 0 ? hotspotY / maximumHotspotY : 0
        )

        guard let representationData = dictionary["Representations"] as? [Any],
              !representationData.isEmpty else {
            warnings.append(
                L10n.text(
                    "\(sourceIdentifier): no image representations.",
                    "\(sourceIdentifier): нет вариантов изображения."
                )
            )
            return ParsedCapeCursorResult(cursor: nil, missingImageCount: 1)
        }
        if representationData.count > Self.maximumRepresentationCount {
            warnings.append(
                L10n.text(
                    "\(sourceIdentifier): only the first \(Self.maximumRepresentationCount) representations were considered.",
                    "\(sourceIdentifier): рассмотрены только первые \(Self.maximumRepresentationCount) вариантов изображения."
                )
            )
        }

        var decoded: [DecodedCapeRepresentation] = []
        for (index, object) in representationData
            .prefix(Self.maximumRepresentationCount)
            .enumerated() {
            guard let data = object as? Data,
                  !data.isEmpty,
                  data.count <= Self.maximumRepresentationBytes,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0 else {
                warnings.append(
                    L10n.text(
                        "\(sourceIdentifier): representation \(index + 1) is missing or corrupted.",
                        "\(sourceIdentifier): вариант изображения \(index + 1) отсутствует или повреждён."
                    )
                )
                continue
            }

            guard let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any],
                let pixelWidth = properties[kCGImagePropertyPixelWidth]
                    as? NSNumber,
                let pixelHeight = properties[kCGImagePropertyPixelHeight]
                    as? NSNumber else {
                warnings.append(
                    L10n.text(
                        "\(sourceIdentifier): representation \(index + 1) has no pixel dimensions.",
                        "\(sourceIdentifier): для варианта \(index + 1) не указаны размеры в пикселях."
                    )
                )
                continue
            }
            let encodedWidth = pixelWidth.intValue
            let encodedHeight = pixelHeight.intValue
            guard encodedWidth > 0, encodedHeight > 0,
                  encodedHeight <= Self.maximumDecodedPixels,
                  encodedWidth <= Self.maximumDecodedPixels / encodedHeight,
                  encodedHeight.isMultiple(of: frameCount) else {
                warnings.append(
                    L10n.text(
                        "\(sourceIdentifier): representation \(index + 1) has invalid frame dimensions.",
                        "\(sourceIdentifier): у варианта \(index + 1) некорректные размеры кадров."
                    )
                )
                continue
            }
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary),
                image.width == encodedWidth,
                image.height == encodedHeight else {
                warnings.append(
                    L10n.text(
                        "\(sourceIdentifier): representation \(index + 1) could not be decoded safely.",
                        "\(sourceIdentifier): вариант \(index + 1) не удалось безопасно декодировать."
                    )
                )
                continue
            }

            let framePixelHeight = image.height / frameCount
            let horizontalScale = Double(image.width) / pointWidth
            let verticalScale = Double(framePixelHeight) / pointHeight
            let tolerance = max(horizontalScale, verticalScale) * 0.06
            guard horizontalScale.isFinite, verticalScale.isFinite,
                  horizontalScale > 0, verticalScale > 0,
                  abs(horizontalScale - verticalScale) <= tolerance else {
                warnings.append(
                    L10n.text(
                        "\(sourceIdentifier): representation \(index + 1) has inconsistent Retina scaling.",
                        "\(sourceIdentifier): у варианта \(index + 1) несогласованный масштаб Retina."
                    )
                )
                continue
            }

            let filename = "cape-\(UUID().uuidString)-rep-\(index + 1).png"
            let destination = assetsDirectory.appending(path: filename)
            try writePNG(image, to: destination)
            decoded.append(
                DecodedCapeRepresentation(
                    image: image,
                    metadata: CursorRepresentation(
                        filename: filename,
                        scale: (horizontalScale + verticalScale) / 2,
                        pixelWidth: image.width,
                        pixelHeight: image.height
                    ),
                    framePixelHeight: framePixelHeight
                )
            )
        }

        guard !decoded.isEmpty else {
            warnings.append(
                L10n.text(
                    "\(sourceIdentifier): no usable image representations.",
                    "\(sourceIdentifier): нет пригодных вариантов изображения."
                )
            )
            return ParsedCapeCursorResult(cursor: nil, missingImageCount: 1)
        }

        let preferred = decoded.min {
            let leftDistance = abs($0.metadata.scale - 2)
            let rightDistance = abs($1.metadata.scale - 2)
            if leftDistance == rightDistance {
                return $0.metadata.scale > $1.metadata.scale
            }
            return leftDistance < rightDistance
        }!
        guard let firstFrame = preferred.image.cropping(
            to: CGRect(
                x: 0,
                y: 0,
                width: preferred.image.width,
                height: preferred.framePixelHeight
            )
        ) else {
            warnings.append(
                L10n.text(
                    "\(sourceIdentifier): the first animation frame could not be extracted.",
                    "\(sourceIdentifier): не удалось извлечь первый кадр анимации."
                )
            )
            return ParsedCapeCursorResult(cursor: nil, missingImageCount: 1)
        }
        let previewFilename = "cape-\(UUID().uuidString)-first-frame.png"
        try writePNG(
            firstFrame,
            to: assetsDirectory.appending(path: previewFilename)
        )

        let fallbackReason: String?
        if frameCount > 24 {
            let reason = L10n.text(
                "The source has \(frameCount) frames; this build applies its first frame because the private API supports at most 24.",
                "В источнике \(frameCount) кадров; эта сборка применяет первый кадр, поскольку закрытый API поддерживает не более 24."
            )
            fallbackReason = reason
            warnings.append("\(sourceIdentifier): \(reason)")
        } else {
            fallbackReason = nil
        }

        return ParsedCapeCursorResult(
            cursor: ParsedCapeCursor(
                sourceIdentifier: sourceIdentifier,
                previewAssetFilename: previewFilename,
                pixelWidth: preferred.image.width,
                pixelHeight: preferred.framePixelHeight,
                pointWidth: pointWidth,
                pointHeight: pointHeight,
                hotspot: hotspot,
                frameCount: frameCount,
                frameDuration: frameDuration,
                representations: decoded.map(\.metadata),
                animationFallbackReason: fallbackReason
            ),
            missingImageCount: 0
        )
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CursorStudioError.filePermission(url.lastPathComponent)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CursorStudioError.filePermission(url.lastPathComponent)
        }
    }

    private func removeStaleStagingDirectories() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: paths.importStagingDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let cutoff = Date.now.addingTimeInterval(-24 * 60 * 60)
        for url in contents {
            let modified = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            if modified == nil || modified! < cutoff {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private func string(_ value: Any?) -> String? {
        value as? String
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }
}

nonisolated private struct ParsedCapeCursorResult {
    var cursor: ParsedCapeCursor?
    var missingImageCount: Int
}

nonisolated private struct DecodedCapeRepresentation {
    var image: CGImage
    var metadata: CursorRepresentation
    var framePixelHeight: Int
}

nonisolated private struct ParsedCapeCursor {
    var sourceIdentifier: String
    var previewAssetFilename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var pointWidth: Double
    var pointHeight: Double
    var hotspot: CursorHotspot
    var frameCount: Int
    var frameDuration: Double
    var representations: [CursorRepresentation]
    var animationFallbackReason: String?

    func entry(for role: CursorRole) -> CursorEntry {
        CursorEntry(
            role: role,
            assetFilename: previewAssetFilename,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            hotspot: hotspot,
            pointWidth: pointWidth,
            pointHeight: pointHeight,
            frameCount: frameCount,
            frameDuration: frameDuration,
            representations: representations,
            sourceIdentifier: sourceIdentifier,
            animationFallbackReason: animationFallbackReason
        )
    }

    func unassigned(reason: String) -> UnassignedCursorEntry {
        UnassignedCursorEntry(
            sourceIdentifier: sourceIdentifier,
            previewAssetFilename: previewAssetFilename,
            pointWidth: pointWidth,
            pointHeight: pointHeight,
            hotspot: hotspot,
            frameCount: frameCount,
            frameDuration: frameDuration,
            representations: representations,
            reason: reason
        )
    }
}
