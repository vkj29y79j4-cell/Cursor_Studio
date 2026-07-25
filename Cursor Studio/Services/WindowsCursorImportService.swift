import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor WindowsCursorImportService {
    private static let maximumArchiveBytes = 128 * 1_024 * 1_024
    private static let maximumExpandedBytes = 256 * 1_024 * 1_024
    private static let maximumCursorBytes = 32 * 1_024 * 1_024
    private static let maximumFileCount = 1_024

    private let paths: ApplicationPaths
    private let fileManager: FileManager
    private let previewGenerator: ThemePreviewGenerator

    init(paths: ApplicationPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        previewGenerator = ThemePreviewGenerator(fileManager: fileManager)
    }

    nonisolated static func canImport(_ url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return true
        }
        return ["cur", "ani", "zip"].contains(url.pathExtension.lowercased())
    }

    func prepareImport(from sourceURL: URL) throws -> ThemeImportDraft {
        guard Self.canImport(sourceURL) else {
            throw CursorStudioError.invalidWindowsCursor(
                "Choose a .cur, .ani, Windows cursor folder, or ZIP archive."
            )
        }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try paths.createDirectories(fileManager: fileManager)
        let sourceValues = try sourceURL.resourceValues(
            forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        )
        let isZIP = sourceValues.isRegularFile == true
            && sourceURL.pathExtension.caseInsensitiveCompare("zip") == .orderedSame

        var extractionDirectory: URL?
        defer {
            if let extractionDirectory {
                try? fileManager.removeItem(at: extractionDirectory)
            }
        }

        let searchRoot: URL
        if isZIP {
            guard (sourceValues.fileSize ?? Self.maximumArchiveBytes + 1)
                <= Self.maximumArchiveBytes else {
                throw CursorStudioError.invalidWindowsArchive(
                    "The ZIP archive is too large."
                )
            }
            let destination = paths.importStagingDirectory.appending(
                path: "WindowsZIP-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
            extractionDirectory = destination
            do {
                try SafeWindowsZIPExtractor(
                    maximumExpandedBytes: Self.maximumExpandedBytes,
                    maximumFileCount: Self.maximumFileCount
                ).extract(sourceURL, to: destination)
            } catch let error as CursorStudioError {
                throw error
            } catch {
                throw CursorStudioError.invalidWindowsArchive(
                    error.localizedDescription
                )
            }
            searchRoot = destination
        } else {
            searchRoot = sourceURL
        }

        let files = try discoverFiles(
            at: searchRoot,
            sourceIsDirectory: sourceValues.isDirectory == true || isZIP
        )
        let cursorFiles = files.filter {
            ["cur", "ani"].contains($0.pathExtension.lowercased())
        }
        guard !cursorFiles.isEmpty else {
            throw CursorStudioError.windowsThemeMissingCursors
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

        var theme = CursorTheme(
            id: themeID,
            name: importedThemeName(
                sourceURL: sourceURL,
                searchRoot: searchRoot,
                cursorFiles: cursorFiles
            )
        )
        let schemeRoles = readSchemeRoleHints(from: files)
        var warnings: [String] = []
        var unassigned: [UnassignedCursorEntry] = []
        var assignedRoles: Set<CursorRole> = []
        var validCursorCount = 0
        var animatedRoleCount = 0
        var staticFallbackCount = 0

        for cursorURL in cursorFiles.sorted(by: {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }) {
            let sourceIdentifier = cursorURL.lastPathComponent
            do {
                let data = try Data(
                    contentsOf: cursorURL,
                    options: .mappedIfSafe
                )
                guard !data.isEmpty, data.count <= Self.maximumCursorBytes else {
                    throw CursorStudioError.invalidWindowsCursor(
                        "\(sourceIdentifier) is empty or too large."
                    )
                }

                let parsed = try WindowsCursorFileParser.parse(
                    data,
                    fileExtension: cursorURL.pathExtension
                )
                warnings.append(contentsOf: parsed.warnings.map {
                    "\(sourceIdentifier): \($0)"
                })
                let stored = try store(
                    parsed,
                    sourceIdentifier: sourceIdentifier,
                    in: assetsDirectory
                )
                validCursorCount += 1
                if stored.frameCount > 1 {
                    animatedRoleCount += 1
                }
                if stored.animationFallbackReason != nil {
                    staticFallbackCount += 1
                }

                let schemeRole = schemeRoles[
                    sourceIdentifier.precomposedStringWithCanonicalMapping
                        .lowercased()
                ]
                guard let role = WindowsCursorRoleMapper.role(
                    for: sourceIdentifier,
                    schemeRole: schemeRole
                ) else {
                    unassigned.append(
                        stored.unassigned(
                            reason: L10n.text(
                                "No Cursor Studio role mapping exists for this Windows cursor.",
                                "Для этого курсора Windows пока нет соответствующей роли Cursor Studio."
                            )
                        )
                    )
                    continue
                }
                guard assignedRoles.insert(role).inserted else {
                    let reason = L10n.text(
                        "Another imported cursor already maps to \(role.displayName).",
                        "Другой импортированный курсор уже сопоставлен с ролью «\(role.displayName)»."
                    )
                    warnings.append("\(sourceIdentifier): \(reason)")
                    unassigned.append(stored.unassigned(reason: reason))
                    continue
                }
                theme.setEntry(stored.entry(for: role))
            } catch {
                warnings.append(
                    L10n.text(
                        "\(sourceIdentifier) was skipped: \(error.localizedDescription)",
                        "\(sourceIdentifier) пропущен: \(error.localizedDescription)"
                    )
                )
            }
        }

        guard validCursorCount > 0 else {
            throw CursorStudioError.windowsThemeMissingCursors
        }

        let missingRoles = CursorRole.allCases.filter {
            !assignedRoles.contains($0)
        }
        if !missingRoles.isEmpty {
            warnings.append(
                L10n.text(
                    "The Windows theme does not provide \(missingRoles.count) macOS cursor roles; the available cursors were imported.",
                    "В теме Windows отсутствуют \(missingRoles.count) ролей курсоров macOS; доступные курсоры импортированы."
                )
            )
        }

        let sourceFormat: String
        if isZIP {
            sourceFormat = "Windows cursor theme (ZIP)"
        } else if sourceValues.isDirectory == true {
            sourceFormat = "Windows cursor theme folder"
        } else if sourceURL.pathExtension.caseInsensitiveCompare("ani") == .orderedSame {
            sourceFormat = "Windows animated cursor (.ani)"
        } else {
            sourceFormat = "Windows cursor (.cur)"
        }
        theme.importMetadata = ThemeImportMetadata(
            sourceFormat: sourceFormat,
            sourceIdentifier: sourceURL.lastPathComponent,
            author: nil,
            sourceVersion: nil,
            importedAt: .now,
            warnings: warnings,
            unassignedEntries: unassigned
        )
        theme.previewAssetFilename = try previewGenerator.generatePreview(
            for: theme,
            in: assetsDirectory,
            fallbackAssetFilename: unassigned.first?.previewAssetFilename
        )

        keepStagingDirectory = true
        return ThemeImportDraft(
            theme: theme,
            stagingThemeDirectory: stagingThemeDirectory,
            review: ThemeImportReview(
                themeName: theme.name,
                recognizedRoleCount: theme.entries.count,
                unrecognizedRoleCount: unassigned.count,
                warningMessages: warnings,
                missingImageCount: cursorFiles.count - validCursorCount,
                animatedRoleCount: animatedRoleCount,
                staticAnimationFallbackCount: staticFallbackCount
            )
        )
    }

    func discard(_ draft: ThemeImportDraft) {
        try? fileManager.removeItem(at: draft.stagingThemeDirectory)
    }

    private func discoverFiles(
        at source: URL,
        sourceIsDirectory: Bool
    ) throws -> [URL] {
        guard sourceIsDirectory else { return [source] }
        let root = source.standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in false }
        ) else {
            throw CursorStudioError.filePermission(source.path)
        }

        var result: [URL] = []
        var totalBytes = 0
        var itemCount = 0
        while let url = enumerator.nextObject() as? URL {
            itemCount += 1
            guard itemCount <= Self.maximumFileCount else {
                throw CursorStudioError.invalidWindowsArchive(
                    "The theme contains too many files."
                )
            }
            let values = try url.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ]
            )
            guard values.isSymbolicLink != true else {
                throw CursorStudioError.invalidWindowsArchive(
                    "Symbolic links are not allowed."
                )
            }
            guard values.isRegularFile == true else { continue }
            totalBytes += values.fileSize ?? 0
            guard totalBytes <= Self.maximumExpandedBytes else {
                throw CursorStudioError.invalidWindowsArchive(
                    "The expanded theme is too large."
                )
            }
            if ["cur", "ani", "inf"].contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result
    }

    private func readSchemeRoleHints(from files: [URL]) -> [String: String] {
        var result: [String: String] = [:]
        let knownRoles = [
            "Arrow", "Help", "AppStarting", "Wait", "Crosshair", "IBeam",
            "NWPen", "No", "SizeNS", "SizeWE", "SizeNWSE", "SizeNESW",
            "SizeAll", "UpArrow", "Hand",
        ]

        for url in files where url.pathExtension.caseInsensitiveCompare("inf") == .orderedSame {
            guard let data = try? Data(contentsOf: url),
                  data.count <= 2 * 1_024 * 1_024,
                  let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .windowsCP1252)
                    ?? String(data: data, encoding: .utf16) else {
                continue
            }
            for line in text.components(separatedBy: .newlines) {
                let lowerLine = line.lowercased()
                guard lowerLine.contains(".cur") || lowerLine.contains(".ani") else {
                    continue
                }
                guard let role = knownRoles.first(where: {
                    lowerLine.range(
                        of: #"\b\#($0.lowercased())\b"#,
                        options: .regularExpression
                    ) != nil
                }) else {
                    continue
                }
                for filename in extractWindowsCursorFilenames(from: line) {
                    result[
                        filename.precomposedStringWithCanonicalMapping.lowercased()
                    ] = role
                }
            }
        }
        return result
    }

    private func extractWindowsCursorFilenames(from line: String) -> [String] {
        line.split(whereSeparator: { "\"'=,; \t".contains($0) })
            .map(String.init)
            .filter {
                ["cur", "ani"].contains(
                    URL(fileURLWithPath: $0.replacingOccurrences(of: "\\", with: "/"))
                        .pathExtension.lowercased()
                )
            }
            .map {
                URL(fileURLWithPath: $0.replacingOccurrences(of: "\\", with: "/"))
                    .lastPathComponent
            }
    }

    private func importedThemeName(
        sourceURL: URL,
        searchRoot: URL,
        cursorFiles: [URL]
    ) -> String {
        if cursorFiles.count == 1,
           sourceURL.pathExtension.lowercased() != "zip",
           (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                != true {
            return sourceURL.deletingPathExtension().lastPathComponent
        }

        if sourceURL.pathExtension.lowercased() == "zip" {
            return sourceURL.deletingPathExtension().lastPathComponent
        }
        let name = searchRoot.lastPathComponent
        return name.isEmpty ? L10n.importedWindowsTheme : name
    }

    private func store(
        _ parsed: ParsedWindowsCursor,
        sourceIdentifier: String,
        in assetsDirectory: URL
    ) throws -> StoredWindowsCursor {
        var representations: [CursorRepresentation] = []
        for (index, image) in parsed.representations.enumerated() {
            let filename = "windows-\(UUID().uuidString)-rep-\(index + 1).png"
            try writePNG(
                image,
                to: assetsDirectory.appending(path: filename)
            )
            representations.append(
                CursorRepresentation(
                    filename: filename,
                    scale: Double(image.width) / parsed.pointWidth,
                    pixelWidth: image.width,
                    pixelHeight: image.height
                )
            )
        }

        let previewFilename = "windows-\(UUID().uuidString)-preview.png"
        try writePNG(
            parsed.previewImage,
            to: assetsDirectory.appending(path: previewFilename)
        )
        return StoredWindowsCursor(
            sourceIdentifier: sourceIdentifier,
            previewAssetFilename: previewFilename,
            pixelWidth: parsed.previewImage.width,
            pixelHeight: parsed.previewImage.height,
            pointWidth: parsed.pointWidth,
            pointHeight: parsed.pointHeight,
            hotspot: parsed.hotspot,
            frameCount: parsed.frameCount,
            frameDuration: parsed.frameDuration,
            representations: representations,
            animationFallbackReason: parsed.animationFallbackReason
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
}

nonisolated private struct StoredWindowsCursor {
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

nonisolated private struct ParsedWindowsCursor {
    var previewImage: CGImage
    /// Static cursors store one image per resolution. Animated cursors store a
    /// vertical frame strip, matching Cursor Studio's existing .cape pipeline.
    var representations: [CGImage]
    var pointWidth: Double
    var pointHeight: Double
    var hotspot: CursorHotspot
    var frameCount: Int
    var frameDuration: Double
    var animationFallbackReason: String?
    var warnings: [String]
}

nonisolated private struct DecodedWindowsCursorImage {
    var image: CGImage
    var hotspotX: Int
    var hotspotY: Int
}

/// Binary parser for Windows CUR and RIFF ACON/ANI files.
///
/// CUR uses the ICO directory layout, but replaces planes/bit depth with the
/// hotspot coordinates. Each payload is wrapped in a one-image ICO container
/// so ImageIO can decode both PNG-backed and classic DIB-backed cursors.
nonisolated private enum WindowsCursorFileParser {
    private static let maximumImageCount = 64
    private static let maximumFrameCount = 256
    private static let maximumDecodedPixels = 32_000_000

    static func parse(
        _ data: Data,
        fileExtension: String
    ) throws -> ParsedWindowsCursor {
        switch fileExtension.lowercased() {
        case "cur":
            return try parseStaticCursor(data)
        case "ani":
            return try parseAnimatedCursor(data)
        default:
            throw CursorStudioError.invalidWindowsCursor(
                "The cursor format is not supported."
            )
        }
    }

    private static func parseStaticCursor(
        _ data: Data
    ) throws -> ParsedWindowsCursor {
        let images = try decodeIconContainer(data, requireCursorType: true)
        let preferred = preferredImage(in: images)
        let pointSize = pointSize(for: preferred.image)
        let hotspot = normalizedHotspot(
            x: preferred.hotspotX,
            y: preferred.hotspotY,
            image: preferred.image
        )

        let uniqueRepresentations = Dictionary(
            grouping: images,
            by: { "\($0.image.width)x\($0.image.height)" }
        )
        .values
        .compactMap(\.first)
        .sorted { $0.image.width < $1.image.width }
        .map(\.image)

        return ParsedWindowsCursor(
            previewImage: preferred.image,
            representations: uniqueRepresentations,
            pointWidth: pointSize.width,
            pointHeight: pointSize.height,
            hotspot: hotspot,
            frameCount: 1,
            frameDuration: 0,
            animationFallbackReason: nil,
            warnings: hotspotWarnings(images)
        )
    }

    private static func parseAnimatedCursor(
        _ data: Data
    ) throws -> ParsedWindowsCursor {
        guard data.count >= 12,
              data.ascii(at: 0, length: 4) == "RIFF",
              data.ascii(at: 8, length: 4) == "ACON" else {
            throw CursorStudioError.invalidWindowsCursor(
                "The .ani RIFF header is invalid."
            )
        }
        let declaredSize = Int(data.uint32LE(at: 4)) + 8
        guard declaredSize <= data.count else {
            throw CursorStudioError.invalidWindowsCursor(
                "The .ani file is truncated."
            )
        }

        var iconChunks: [Data] = []
        var rates: [UInt32] = []
        var sequence: [UInt32] = []
        var headerFrameCount: Int?
        var headerStepCount: Int?
        var defaultRate: UInt32 = 6
        var warnings: [String] = []

        try walkRIFFChunks(
            data,
            range: 12..<declaredSize
        ) { identifier, payload, listType in
            switch identifier {
            case "anih":
                guard payload.count >= 36 else {
                    throw CursorStudioError.invalidWindowsCursor(
                        "The .ani header is truncated."
                    )
                }
                headerFrameCount = Int(payload.uint32LE(at: 4))
                headerStepCount = Int(payload.uint32LE(at: 8))
                defaultRate = max(payload.uint32LE(at: 28), 1)
            case "rate":
                rates = payload.uint32Values()
            case "seq ":
                sequence = payload.uint32Values()
            case "icon":
                iconChunks.append(payload)
            case "LIST" where listType == "fram":
                try walkRIFFChunks(
                    payload,
                    range: 4..<payload.count
                ) { nestedIdentifier, nestedPayload, _ in
                    if nestedIdentifier == "icon" {
                        iconChunks.append(nestedPayload)
                    }
                }
            default:
                break
            }
        }

        guard !iconChunks.isEmpty,
              iconChunks.count <= maximumFrameCount else {
            throw CursorStudioError.invalidWindowsCursor(
                "The .ani file contains no usable frames or too many frames."
            )
        }
        if let headerFrameCount, headerFrameCount != iconChunks.count {
            warnings.append(
                "The ANI frame count did not match the embedded frames; embedded frames were used."
            )
        }

        let decodedFrames = try iconChunks.map {
            try decodeIconContainer($0, requireCursorType: false)
        }
        let firstPreferred = preferredImage(in: decodedFrames[0])
        let targetWidth = firstPreferred.image.width
        let targetHeight = firstPreferred.image.height

        let requestedSequence: [Int]
        if sequence.isEmpty {
            let steps = headerStepCount.map {
                min(max($0, 1), iconChunks.count)
            } ?? iconChunks.count
            requestedSequence = Array(0..<steps)
        } else {
            requestedSequence = sequence.prefix(maximumFrameCount).map(Int.init)
        }
        let orderedIndices = requestedSequence.filter {
            decodedFrames.indices.contains($0)
        }
        guard !orderedIndices.isEmpty else {
            throw CursorStudioError.invalidWindowsCursor(
                "The .ani frame sequence is invalid."
            )
        }
        if orderedIndices.count != requestedSequence.count {
            warnings.append(
                "Invalid ANI sequence entries were ignored."
            )
        }

        let orderedImages = orderedIndices.map { index in
            closestImage(
                in: decodedFrames[index],
                width: targetWidth,
                height: targetHeight
            )
        }
        let strip = try verticalStrip(
            orderedImages.map(\.image),
            width: targetWidth,
            height: targetHeight
        )

        let stepRates: [UInt32]
        if rates.isEmpty {
            stepRates = Array(
                repeating: defaultRate,
                count: orderedImages.count
            )
        } else {
            stepRates = (0..<orderedImages.count).map {
                $0 < rates.count ? max(rates[$0], 1) : defaultRate
            }
            if Set(stepRates).count > 1 {
                warnings.append(
                    "Variable ANI frame timing was converted to one average duration."
                )
            }
        }
        let averageJiffies = Double(
            stepRates.reduce(UInt64(0)) { $0 + UInt64($1) }
        )
            / Double(stepRates.count)
        let frameDuration = max(averageJiffies / 60.0, 1.0 / 240.0)
        let pointSize = pointSize(for: firstPreferred.image)
        let hotspot = normalizedHotspot(
            x: firstPreferred.hotspotX,
            y: firstPreferred.hotspotY,
            image: firstPreferred.image
        )

        let fallbackReason: String?
        if orderedImages.count > 24 {
            fallbackReason = L10n.text(
                "The source has \(orderedImages.count) frames; it will use its first frame because macOS accepts at most 24.",
                "В источнике \(orderedImages.count) кадров; будет использован первый кадр, поскольку macOS принимает не более 24."
            )
            warnings.append(fallbackReason!)
        } else {
            fallbackReason = nil
        }

        return ParsedWindowsCursor(
            previewImage: orderedImages[0].image,
            representations: [strip],
            pointWidth: pointSize.width,
            pointHeight: pointSize.height,
            hotspot: hotspot,
            frameCount: orderedImages.count,
            frameDuration: frameDuration,
            animationFallbackReason: fallbackReason,
            warnings: warnings + hotspotWarnings(orderedImages)
        )
    }

    private static func decodeIconContainer(
        _ data: Data,
        requireCursorType: Bool
    ) throws -> [DecodedWindowsCursorImage] {
        guard data.count >= 6,
              data.uint16LE(at: 0) == 0 else {
            throw CursorStudioError.invalidWindowsCursor(
                "The CUR/ICO directory header is invalid."
            )
        }
        let containerType = data.uint16LE(at: 2)
        guard containerType == 2 || (!requireCursorType && containerType == 1) else {
            throw CursorStudioError.invalidWindowsCursor(
                "The file is not a Windows cursor resource."
            )
        }
        let count = Int(data.uint16LE(at: 4))
        guard count > 0, count <= maximumImageCount,
              6 + count * 16 <= data.count else {
            throw CursorStudioError.invalidWindowsCursor(
                "The cursor image directory is invalid."
            )
        }

        var decoded: [DecodedWindowsCursorImage] = []
        for index in 0..<count {
            let offset = 6 + index * 16
            let width = data[offset] == 0 ? 256 : Int(data[offset])
            let height = data[offset + 1] == 0 ? 256 : Int(data[offset + 1])
            let firstWord = data.uint16LE(at: offset + 4)
            let secondWord = data.uint16LE(at: offset + 6)
            let payloadSize = Int(data.uint32LE(at: offset + 8))
            let payloadOffset = Int(data.uint32LE(at: offset + 12))
            guard width > 0, height > 0,
                  payloadSize > 0,
                  payloadOffset >= 0,
                  payloadOffset <= data.count,
                  payloadSize <= data.count - payloadOffset else {
                continue
            }

            let payload = data.subdata(
                in: payloadOffset..<(payloadOffset + payloadSize)
            )
            let iconData = synthesizedICO(
                payload: payload,
                widthByte: data[offset],
                heightByte: data[offset + 1],
                colorCount: data[offset + 2],
                planes: containerType == 1 ? max(firstWord, 1) : 1,
                bitCount: containerType == 1
                    ? max(secondWord, 1)
                    : bitDepth(in: payload)
            )
            guard let source = CGImageSourceCreateWithData(
                iconData as CFData,
                nil
            ), CGImageSourceGetCount(source) > 0,
               let image = CGImageSourceCreateImageAtIndex(
                   source,
                   0,
                   [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
               ),
               image.width > 0, image.height > 0,
               image.height <= maximumDecodedPixels,
               image.width <= maximumDecodedPixels / image.height else {
                continue
            }
            decoded.append(
                DecodedWindowsCursorImage(
                    image: image,
                    hotspotX: containerType == 2 ? Int(firstWord) : 0,
                    hotspotY: containerType == 2 ? Int(secondWord) : 0
                )
            )
        }
        guard !decoded.isEmpty else {
            throw CursorStudioError.invalidWindowsCursor(
                "No cursor image could be decoded."
            )
        }
        return decoded
    }

    private static func synthesizedICO(
        payload: Data,
        widthByte: UInt8,
        heightByte: UInt8,
        colorCount: UInt8,
        planes: UInt16,
        bitCount: UInt16
    ) -> Data {
        var result = Data()
        result.appendUInt16LE(0)
        result.appendUInt16LE(1)
        result.appendUInt16LE(1)
        result.append(widthByte)
        result.append(heightByte)
        result.append(colorCount)
        result.append(0)
        result.appendUInt16LE(planes)
        result.appendUInt16LE(bitCount)
        result.appendUInt32LE(UInt32(payload.count))
        result.appendUInt32LE(22)
        result.append(payload)
        return result
    }

    private static func bitDepth(in payload: Data) -> UInt16 {
        let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])
        if payload.starts(with: pngSignature) {
            return 32
        }
        guard payload.count >= 16,
              payload.uint32LE(at: 0) >= 16 else {
            return 32
        }
        return max(payload.uint16LE(at: 14), 1)
    }

    private static func walkRIFFChunks(
        _ data: Data,
        range: Range<Int>,
        body: (
            _ identifier: String,
            _ payload: Data,
            _ listType: String?
        ) throws -> Void
    ) throws {
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound {
            let identifier = data.ascii(at: offset, length: 4)
            let size = Int(data.uint32LE(at: offset + 4))
            let payloadStart = offset + 8
            guard size >= 0,
                  payloadStart <= range.upperBound,
                  size <= range.upperBound - payloadStart else {
                throw CursorStudioError.invalidWindowsCursor(
                    "A RIFF chunk is truncated."
                )
            }
            let payload = data.subdata(in: payloadStart..<(payloadStart + size))
            let listType = identifier == "LIST" && payload.count >= 4
                ? payload.ascii(at: 0, length: 4)
                : nil
            try body(identifier, payload, listType)
            offset = payloadStart + size + (size.isMultiple(of: 2) ? 0 : 1)
        }
    }

    private static func preferredImage(
        in images: [DecodedWindowsCursorImage]
    ) -> DecodedWindowsCursorImage {
        images.min {
            let leftDistance = abs(max($0.image.width, $0.image.height) - 32)
            let rightDistance = abs(max($1.image.width, $1.image.height) - 32)
            if leftDistance == rightDistance {
                return $0.image.width > $1.image.width
            }
            return leftDistance < rightDistance
        }!
    }

    private static func closestImage(
        in images: [DecodedWindowsCursorImage],
        width: Int,
        height: Int
    ) -> DecodedWindowsCursorImage {
        images.min {
            abs($0.image.width - width) + abs($0.image.height - height)
                < abs($1.image.width - width) + abs($1.image.height - height)
        }!
    }

    private static func pointSize(
        for image: CGImage
    ) -> (width: Double, height: Double) {
        let longestEdge = Double(max(image.width, image.height))
        let scale = min(1, 32 / longestEdge)
        return (
            max(Double(image.width) * scale, 1),
            max(Double(image.height) * scale, 1)
        )
    }

    private static func normalizedHotspot(
        x: Int,
        y: Int,
        image: CGImage
    ) -> CursorHotspot {
        CursorHotspot.fromPixelPoint(
            CGPoint(
                x: min(max(x, 0), max(image.width - 1, 0)),
                y: min(max(y, 0), max(image.height - 1, 0))
            ),
            width: image.width,
            height: image.height
        )
    }

    private static func hotspotWarnings(
        _ images: [DecodedWindowsCursorImage]
    ) -> [String] {
        guard images.contains(where: {
            $0.hotspotX < 0 || $0.hotspotY < 0
                || $0.hotspotX >= $0.image.width
                || $0.hotspotY >= $0.image.height
        }) else {
            return []
        }
        return [
            L10n.text(
                "A hotspot outside its image was clamped to the cursor bounds.",
                "Активная точка за пределами изображения была перемещена внутрь курсора."
            ),
        ]
    }

    private static func verticalStrip(
        _ images: [CGImage],
        width: Int,
        height: Int
    ) throws -> CGImage {
        guard !images.isEmpty,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height * images.count,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CursorStudioError.invalidImage
        }
        context.interpolationQuality = .high
        context.clear(
            CGRect(x: 0, y: 0, width: width, height: height * images.count)
        )
        for (index, image) in images.enumerated() {
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: index * height,
                    width: width,
                    height: height
                )
            )
        }
        guard let strip = context.makeImage() else {
            throw CursorStudioError.invalidImage
        }
        return strip
    }
}

/// Performs bounded ZIP extraction before the import scanner sees any file.
/// Central-directory validation prevents traversal, links, devices, encrypted
/// entries, and decompression bombs while still accepting ordinary Windows ZIPs.
nonisolated private struct SafeWindowsZIPExtractor {
    let maximumExpandedBytes: Int
    let maximumFileCount: Int

    func extract(_ sourceURL: URL, to destination: URL) throws {
        let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        try inspectCentralDirectory(data)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-x",
            "-k",
            "--noqtn",
            sourceURL.path,
            destination.path,
        ]
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CursorStudioError.invalidWindowsArchive(
                "The ZIP archive could not be extracted."
            )
        }
        try inspectExtractedTree(destination)
    }

    private func inspectCentralDirectory(_ data: Data) throws {
        guard let eocd = endOfCentralDirectoryOffset(in: data),
              data.uint32LE(at: eocd) == 0x0605_4B50 else {
            throw CursorStudioError.invalidWindowsArchive(
                "The ZIP directory is missing."
            )
        }
        let entryCount = Int(data.uint16LE(at: eocd + 10))
        let centralSize = Int(data.uint32LE(at: eocd + 12))
        let centralOffset = Int(data.uint32LE(at: eocd + 16))
        guard entryCount > 0,
              entryCount <= maximumFileCount,
              centralOffset >= 0,
              centralSize >= 0,
              centralOffset + centralSize <= data.count else {
            throw CursorStudioError.invalidWindowsArchive(
                "The ZIP directory is outside the allowed limits."
            )
        }

        var offset = centralOffset
        var expandedBytes: UInt64 = 0
        var normalizedPaths: Set<String> = []
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count,
                  data.uint32LE(at: offset) == 0x0201_4B50 else {
                throw CursorStudioError.invalidWindowsArchive(
                    "A ZIP entry is malformed."
                )
            }
            let flags = data.uint16LE(at: offset + 8)
            let method = data.uint16LE(at: offset + 10)
            let creatorSystem = data[offset + 5]
            let uncompressedSize = UInt64(data.uint32LE(at: offset + 24))
            let nameLength = Int(data.uint16LE(at: offset + 28))
            let extraLength = Int(data.uint16LE(at: offset + 30))
            let commentLength = Int(data.uint16LE(at: offset + 32))
            let externalAttributes = data.uint32LE(at: offset + 38)
            let end = offset + 46 + nameLength + extraLength + commentLength
            guard nameLength > 0, end <= data.count else {
                throw CursorStudioError.invalidWindowsArchive(
                    "A ZIP entry name is malformed."
                )
            }
            guard flags & 0x1 == 0 else {
                throw CursorStudioError.invalidWindowsArchive(
                    "Encrypted ZIP entries are not supported."
                )
            }
            guard method == 0 || method == 8 else {
                throw CursorStudioError.invalidWindowsArchive(
                    "Only Store and Deflate ZIP compression are supported."
                )
            }

            let nameData = data.subdata(
                in: (offset + 46)..<(offset + 46 + nameLength)
            )
            guard let rawName = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .windowsCP1252)
                ?? String(data: nameData, encoding: .isoLatin1) else {
                throw CursorStudioError.invalidWindowsArchive(
                    "A ZIP path could not be decoded."
                )
            }
            let portableName = rawName.replacingOccurrences(of: "\\", with: "/")
            let isDirectory = portableName.hasSuffix("/")
            let checkedName = isDirectory
                ? String(portableName.dropLast())
                : portableName
            try validateRelativePath(checkedName)

            let unixMode = UInt16((externalAttributes >> 16) & 0xffff)
            let fileType = unixMode & 0o170000
            if creatorSystem == 3 || creatorSystem == 19 {
                guard fileType != 0o120000,
                      fileType != 0o060000,
                      fileType != 0o020000,
                      fileType != 0o010000 else {
                    throw CursorStudioError.invalidWindowsArchive(
                        "Links and device files are not allowed."
                    )
                }
            }

            let folded = checkedName
                .precomposedStringWithCanonicalMapping
                .lowercased()
            guard normalizedPaths.insert(folded).inserted else {
                throw CursorStudioError.invalidWindowsArchive(
                    "The ZIP contains duplicate paths."
                )
            }
            expandedBytes += uncompressedSize
            guard expandedBytes <= UInt64(maximumExpandedBytes) else {
                throw CursorStudioError.invalidWindowsArchive(
                    "The expanded ZIP is too large."
                )
            }
            offset = end
        }
        guard offset <= centralOffset + centralSize else {
            throw CursorStudioError.invalidWindowsArchive(
                "The ZIP directory size is inconsistent."
            )
        }
    }

    private func inspectExtractedTree(_ root: URL) throws {
        let standardizedRoot = root.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw CursorStudioError.invalidWindowsArchive(
                "The extracted ZIP cannot be read."
            )
        }

        var itemCount = 0
        var expandedBytes = 0
        while let url = enumerator.nextObject() as? URL {
            itemCount += 1
            guard itemCount <= maximumFileCount else {
                throw CursorStudioError.invalidWindowsArchive(
                    "The ZIP contains too many files."
                )
            }
            let values = try url.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ]
            )
            guard values.isSymbolicLink != true else {
                throw CursorStudioError.invalidWindowsArchive(
                    "Symbolic links are not allowed."
                )
            }
            let standardizedURL = url.standardizedFileURL
            guard standardizedURL.path == standardizedRoot.path
                    || standardizedURL.path.hasPrefix(standardizedRoot.path + "/") else {
                throw CursorStudioError.invalidWindowsArchive(
                    "A ZIP entry escaped the extraction folder."
                )
            }
            if values.isRegularFile == true {
                expandedBytes += values.fileSize ?? 0
                guard expandedBytes <= maximumExpandedBytes else {
                    throw CursorStudioError.invalidWindowsArchive(
                        "The expanded ZIP is too large."
                    )
                }
            }
        }
    }

    private func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw CursorStudioError.invalidWindowsArchive(
                "The ZIP contains an unsafe path."
            )
        }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !components.isEmpty,
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }),
              !(components.first?.contains(":") ?? false) else {
            throw CursorStudioError.invalidWindowsArchive(
                "The ZIP contains an unsafe path."
            )
        }
    }

    private func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let lowerBound = max(0, data.count - 65_557)
        for offset in stride(from: data.count - 22, through: lowerBound, by: -1)
            where data.uint32LE(at: offset) == 0x0605_4B50 {
            return offset
        }
        return nil
    }
}

nonisolated private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[offset])
            | UInt16(self[offset + 1]) << 8
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }

    func uint32Values() -> [UInt32] {
        stride(from: 0, to: count - count % 4, by: 4).map {
            uint32LE(at: $0)
        }
    }

    func ascii(at offset: Int, length: Int) -> String {
        guard offset >= 0, length >= 0, offset + length <= count else {
            return ""
        }
        return String(
            data: subdata(in: offset..<(offset + length)),
            encoding: .ascii
        ) ?? ""
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
