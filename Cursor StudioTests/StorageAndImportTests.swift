import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Cursor_Studio

final class StorageAndImportTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "CursorStudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testApplicationPathsAreContainedUnderRoot() {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        let themeID = UUID()

        XCTAssertEqual(paths.libraryFile.deletingLastPathComponent(), temporaryDirectory)
        XCTAssertTrue(paths.assetsDirectory(for: themeID).path.hasPrefix(temporaryDirectory.path))
        XCTAssertNil(paths.assetURL(themeID: themeID, filename: "../escape.png"))
    }

    @MainActor
    func testDuplicateSourceFilenamesDoNotCollide() throws {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        let importer = ImageImportService(paths: paths)
        let source = temporaryDirectory.appending(path: "cursor.png")
        try writePNG(to: source)
        let themeID = UUID()

        let first = try importer.importImage(from: source, for: themeID)
        let second = try importer.importImage(from: source, for: themeID)

        XCTAssertNotEqual(first.filename, second.filename)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: paths.assetURL(themeID: themeID, filename: first.filename)!.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: paths.assetURL(themeID: themeID, filename: second.filename)!.path
            )
        )
    }

    @MainActor
    func testActiveThemeWithMissingAssetIsDeactivated() throws {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        let store = ThemeStore(paths: paths)
        try store.load()
        let theme = try store.createTheme(named: "Missing Asset")
        try store.setEntry(
            CursorEntry(
                role: .arrow,
                assetFilename: "does-not-exist.png",
                pixelWidth: 32,
                pixelHeight: 32
            ),
            in: theme.id
        )
        try store.setActiveThemeID(theme.id)

        let reloaded = ThemeStore(paths: paths)
        XCTAssertThrowsError(try reloaded.load()) { error in
            XCTAssertEqual(
                error as? CursorStudioError,
                .missingThemeAsset("does-not-exist.png")
            )
        }
        XCTAssertNil(reloaded.activeThemeID)
    }

    @MainActor
    func testImportedThemeSurvivesReload() throws {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        let store = ThemeStore(paths: paths)
        try store.load()
        let theme = try store.createTheme(named: "Persistent")
        let source = temporaryDirectory.appending(path: "cursor.png")
        try writePNG(to: source)
        let imported = try ImageImportService(paths: paths)
            .importImage(from: source, for: theme.id)
        try store.setEntry(
            CursorEntry(
                role: .arrow,
                assetFilename: imported.filename,
                pixelWidth: imported.pixelWidth,
                pixelHeight: imported.pixelHeight
            ),
            in: theme.id
        )

        let reloaded = ThemeStore(paths: paths)
        try reloaded.load()
        XCTAssertEqual(
            reloaded.theme(withID: theme.id)?.entry(for: .arrow)?.assetFilename,
            imported.filename
        )
    }

    private func writePNG(to url: URL) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: 16,
                  height: 16,
                  bitsPerComponent: 8,
                  bytesPerRow: 64,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              ) else {
            XCTFail("Could not create test PNG")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
