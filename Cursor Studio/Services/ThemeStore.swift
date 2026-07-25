import Combine
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var themes: [CursorTheme] = []
    @Published private(set) var activeThemeID: UUID?

    let paths: ApplicationPaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let previewGenerator: ThemePreviewGenerator

    init(paths: ApplicationPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        previewGenerator = ThemePreviewGenerator(fileManager: fileManager)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws {
        try paths.createDirectories(fileManager: fileManager)

        guard fileManager.fileExists(atPath: paths.libraryFile.path) else {
            try createInitialLibrary()
            return
        }

        do {
            let data = try Data(contentsOf: paths.libraryFile)
            let document = try decoder.decode(ThemeLibraryDocument.self, from: data)
            guard document.schemaVersion <= ProductInfo.schemaVersion else {
                throw CursorStudioError.corruptedDatabase
            }
            let needsMigration = document.schemaVersion < ProductInfo.schemaVersion
            if needsMigration {
                try backupLibrary(
                    data: data,
                    schemaVersion: document.schemaVersion
                )
            }
            themes = document.themes
                .map {
                    Self.normalizedTheme(
                        $0,
                        fromSchemaVersion: document.schemaVersion
                    )
                }
                .sorted { $0.modifiedAt > $1.modifiedAt }
            activeThemeID = document.activeThemeID.flatMap { id in
                themes.contains(where: { $0.id == id }) ? id : nil
            }

            if let activeTheme = activeTheme,
               let missing = activeTheme.entries.first(where: {
                   guard let url = paths.assetURL(
                       themeID: activeTheme.id,
                       filename: $0.assetFilename
                   ) else { return true }
                   return !fileManager.fileExists(atPath: url.path)
               }) {
                activeThemeID = nil
                try persist()
                throw CursorStudioError.missingThemeAsset(missing.assetFilename)
            }

            var previewChanged = false
            for index in themes.indices {
                let expectedURL = paths.assetsDirectory(for: themes[index].id)
                    .appending(path: ThemePreviewGenerator.previewFilename)
                if themes[index].previewAssetFilename
                    != ThemePreviewGenerator.previewFilename
                    || !fileManager.fileExists(atPath: expectedURL.path) {
                    let generated = try previewGenerator.generatePreview(
                        for: themes[index],
                        in: paths.assetsDirectory(for: themes[index].id)
                    )
                    if themes[index].previewAssetFilename != generated {
                        themes[index].previewAssetFilename = generated
                        previewChanged = true
                    }
                }
            }
            if needsMigration || previewChanged {
                try persist()
            }
        } catch let error as CursorStudioError {
            if error == .corruptedDatabase {
                try recoverCorruptedLibrary()
            }
            throw error
        } catch {
            try recoverCorruptedLibrary()
            throw CursorStudioError.corruptedDatabase
        }
    }

    var activeTheme: CursorTheme? {
        activeThemeID.flatMap(theme(withID:))
    }

    func theme(withID id: UUID) -> CursorTheme? {
        themes.first { $0.id == id }
    }

    @discardableResult
    func createTheme(named requestedName: String = L10n.untitledTheme) throws -> CursorTheme {
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        var theme = CursorTheme(name: trimmed.isEmpty ? L10n.untitledTheme : trimmed)
        let assetsDirectory = paths.assetsDirectory(for: theme.id)
        try fileManager.createDirectory(
            at: assetsDirectory,
            withIntermediateDirectories: true
        )
        theme.previewAssetFilename = try previewGenerator.generatePreview(
            for: theme,
            in: assetsDirectory
        )
        themes.insert(theme, at: 0)
        try persist()
        return theme
    }

    func renameTheme(id: UUID, to requestedName: String) throws {
        guard let index = themes.firstIndex(where: { $0.id == id }) else {
            throw CursorStudioError.themeNotFound
        }
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        themes[index].name = trimmed
        themes[index].modifiedAt = .now
        try persist()
    }

    func setEntry(_ entry: CursorEntry, in themeID: UUID) throws {
        guard let index = themes.firstIndex(where: { $0.id == themeID }) else {
            throw CursorStudioError.themeNotFound
        }
        let replaced = themes[index].entry(for: entry.role)
        themes[index].setEntry(entry)
        themes[index].previewAssetFilename = try previewGenerator.generatePreview(
            for: themes[index],
            in: paths.assetsDirectory(for: themeID)
        )
        try persist()

        if let replaced {
            let retained = Set(themes[index].entries.flatMap(Self.assetFilenames))
            for filename in Self.assetFilenames(replaced)
                where !retained.contains(filename) {
                if let oldURL = paths.assetURL(
                    themeID: themeID,
                    filename: filename
                ) {
                    try? fileManager.removeItem(at: oldURL)
                }
            }
        }
    }

    func setHotspot(
        _ hotspot: CursorHotspot,
        role: CursorRole,
        themeID: UUID
    ) throws {
        guard let themeIndex = themes.firstIndex(where: { $0.id == themeID }),
              let entryIndex = themes[themeIndex].entries.firstIndex(where: {
                  $0.role == role
              }) else {
            throw CursorStudioError.themeNotFound
        }
        themes[themeIndex].entries[entryIndex].hotspot = hotspot
        themes[themeIndex].entries[entryIndex].modifiedAt = .now
        themes[themeIndex].modifiedAt = .now
        try persist()
    }

    func removeEntry(role: CursorRole, from themeID: UUID) throws {
        guard let index = themes.firstIndex(where: { $0.id == themeID }) else {
            throw CursorStudioError.themeNotFound
        }
        let removed = themes[index].entry(for: role)
        themes[index].removeEntry(for: role)
        themes[index].previewAssetFilename = try previewGenerator.generatePreview(
            for: themes[index],
            in: paths.assetsDirectory(for: themeID)
        )
        try persist()
        if let removed {
            let retained = Set(themes[index].entries.flatMap(Self.assetFilenames))
            for filename in Self.assetFilenames(removed)
                where !retained.contains(filename) {
                if let url = paths.assetURL(themeID: themeID, filename: filename) {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }

    @discardableResult
    func duplicateTheme(id: UUID) throws -> CursorTheme {
        guard var duplicate = theme(withID: id) else {
            throw CursorStudioError.themeNotFound
        }
        let sourceID = duplicate.id
        duplicate.id = UUID()
        duplicate.name = uniqueCopyName(for: duplicate.name)
        duplicate.createdAt = .now
        duplicate.modifiedAt = .now
        duplicate.entries = duplicate.entries.map {
            var entry = $0
            entry.id = UUID()
            entry.modifiedAt = .now
            return entry
        }

        let sourceDirectory = paths.themeDirectory(for: sourceID)
        let destinationDirectory = paths.themeDirectory(for: duplicate.id)
        guard fileManager.fileExists(atPath: sourceDirectory.path) else {
            throw CursorStudioError.missingThemeAsset(duplicate.name)
        }
        try fileManager.copyItem(at: sourceDirectory, to: destinationDirectory)

        themes.insert(duplicate, at: 0)
        try persist()
        return duplicate
    }

    @discardableResult
    func commitCapeImport(_ draft: CapeImportDraft) throws -> CursorTheme {
        try commitImportedTheme(draft)
    }

    @discardableResult
    func commitImportedTheme(_ draft: ThemeImportDraft) throws -> CursorTheme {
        var theme = draft.theme
        theme.name = uniqueImportedName(for: theme.name)
        theme.modifiedAt = .now

        let destination = paths.themeDirectory(for: theme.id)
        guard !fileManager.fileExists(atPath: destination.path),
              fileManager.fileExists(atPath: draft.stagingThemeDirectory.path) else {
            throw CursorStudioError.filePermission(destination.path)
        }

        do {
            try fileManager.moveItem(
                at: draft.stagingThemeDirectory,
                to: destination
            )
            themes.insert(theme, at: 0)
            do {
                try persist()
            } catch {
                themes.removeAll { $0.id == theme.id }
                try? fileManager.moveItem(
                    at: destination,
                    to: draft.stagingThemeDirectory
                )
                throw error
            }
            return theme
        } catch let error as CursorStudioError {
            throw error
        } catch {
            throw CursorStudioError.filePermission(destination.path)
        }
    }

    func deleteTheme(id: UUID) throws {
        guard themes.contains(where: { $0.id == id }) else {
            throw CursorStudioError.themeNotFound
        }
        themes.removeAll { $0.id == id }
        if activeThemeID == id {
            activeThemeID = nil
        }
        try persist()
        let directory = paths.themeDirectory(for: id)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    func setActiveThemeID(_ id: UUID?) throws {
        if let id, !themes.contains(where: { $0.id == id }) {
            throw CursorStudioError.themeNotFound
        }
        activeThemeID = id
        try persist()
    }

    func assetURL(for entry: CursorEntry, themeID: UUID) -> URL? {
        paths.assetURL(themeID: themeID, filename: entry.assetFilename)
    }

    func previewURL(for theme: CursorTheme) -> URL? {
        guard let filename = theme.previewAssetFilename else { return nil }
        return paths.assetURL(themeID: theme.id, filename: filename)
    }

    func persist() throws {
        let document = ThemeLibraryDocument(
            themes: themes,
            activeThemeID: activeThemeID
        )
        do {
            try paths.createDirectories(fileManager: fileManager)
            let data = try encoder.encode(document)
            try data.write(to: paths.libraryFile, options: .atomic)
        } catch {
            throw CursorStudioError.filePermission(paths.libraryFile.path)
        }
    }

    private func createInitialLibrary() throws {
        let theme = CursorTheme(name: L10n.demoTheme)
        let assetsDirectory = paths.assetsDirectory(for: theme.id)
        try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)

        let filename = "demo-arrow.png"
        let assetURL = assetsDirectory.appending(path: filename)
        try Self.writeDemoArrow(to: assetURL)

        var configured = theme
        configured.setEntry(
            CursorEntry(
                role: .arrow,
                assetFilename: filename,
                pixelWidth: 64,
                pixelHeight: 64,
                hotspot: CursorHotspot(
                    normalizedX: 4.0 / 63.0,
                    normalizedY: 4.0 / 63.0
                )
            )
        )
        configured.previewAssetFilename = try previewGenerator.generatePreview(
            for: configured,
            in: assetsDirectory
        )
        themes = [configured]
        activeThemeID = nil
        try persist()
    }

    private func recoverCorruptedLibrary() throws {
        if fileManager.fileExists(atPath: paths.libraryFile.path) {
            let backup = paths.rootDirectory.appending(
                path: "library.corrupt-\(Int(Date.now.timeIntervalSince1970)).json"
            )
            try? fileManager.moveItem(at: paths.libraryFile, to: backup)
        }
        themes = []
        activeThemeID = nil
        try createInitialLibrary()
    }

    private func uniqueCopyName(for name: String) -> String {
        let base = "\(name) \(L10n.copySuffix)"
        if !themes.contains(where: { $0.name == base }) {
            return base
        }
        var index = 2
        while themes.contains(where: { $0.name == "\(base) \(index)" }) {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func uniqueImportedName(for name: String) -> String {
        guard themes.contains(where: { $0.name == name }) else {
            return name
        }
        var index = 2
        while themes.contains(where: { $0.name == "\(name) \(index)" }) {
            index += 1
        }
        return "\(name) \(index)"
    }

    private func backupLibrary(data: Data, schemaVersion: Int) throws {
        let backup = paths.rootDirectory.appending(
            path: "library.backup-v\(schemaVersion)-\(Int(Date.now.timeIntervalSince1970)).json"
        )
        do {
            try data.write(to: backup, options: .withoutOverwriting)
        } catch let error as CocoaError
            where error.code == .fileWriteFileExists {
            return
        } catch {
            throw CursorStudioError.filePermission(backup.path)
        }
    }

    private static func normalizedTheme(
        _ theme: CursorTheme,
        fromSchemaVersion schemaVersion: Int
    ) -> CursorTheme {
        var normalized = theme
        var seen: Set<CursorRole> = []
        normalized.entries = theme.entries.filter { seen.insert($0.role).inserted }
        if schemaVersion < 3,
           theme.importMetadata?.sourceFormat == "Cursor Studio Marketplace" {
            normalized.entries = normalized.entries.map { entry in
                var resized = entry
                let size = MarketplaceCursorSizing.normalizedPointSize(
                    pixelWidth: entry.pixelWidth,
                    pixelHeight: entry.pixelHeight,
                    requestedPointWidth: entry.pointWidth,
                    requestedPointHeight: entry.pointHeight
                )
                resized.pointWidth = size.width
                resized.pointHeight = size.height
                return resized
            }
        }
        return normalized
    }

    private static func assetFilenames(_ entry: CursorEntry) -> [String] {
        [entry.assetFilename] + entry.representations.map(\.filename)
    }

    private static func writeDemoArrow(to url: URL) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: 64,
                  height: 64,
                  bitsPerComponent: 8,
                  bytesPerRow: 64 * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CursorStudioError.invalidImage
        }
        context.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.translateBy(x: 0, y: 64)
        context.scaleBy(x: 1, y: -1)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4, y: 3))
        path.addLine(to: CGPoint(x: 4, y: 51))
        path.addLine(to: CGPoint(x: 17, y: 39))
        path.addLine(to: CGPoint(x: 28, y: 60))
        path.addLine(to: CGPoint(x: 38, y: 55))
        path.addLine(to: CGPoint(x: 28, y: 35))
        path.addLine(to: CGPoint(x: 48, y: 33))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0.98, alpha: 1))
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(CGColor(gray: 0.08, alpha: 1))
        context.setLineWidth(4)
        context.setLineJoin(.round)
        context.strokePath()

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              ) else {
            throw CursorStudioError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CursorStudioError.filePermission(url.path)
        }
    }
}
