import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Cursor_Studio

final class ThemeArchiveTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appending(
            path: "CursorStudioThemeArchiveTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
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
    func testArchiveRoundTripPreservesCursorMetadata() async throws {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        let store = ThemeStore(paths: paths)
        try store.load()

        let themeID = UUID()
        let assets = paths.assetsDirectory(for: themeID)
        try FileManager.default.createDirectory(
            at: assets,
            withIntermediateDirectories: true
        )
        let previewFilename = "arrow.png"
        let retinaFilename = "arrow-animation@2x.png"
        try writePNG(
            width: 20,
            height: 24,
            to: assets.appending(path: previewFilename)
        )
        try writePNG(
            width: 40,
            height: 96,
            to: assets.appending(path: retinaFilename)
        )

        let theme = CursorTheme(
            id: themeID,
            name: "Portable Motion",
            previewAssetFilename: previewFilename,
            entries: [
                CursorEntry(
                    role: .arrow,
                    assetFilename: previewFilename,
                    pixelWidth: 20,
                    pixelHeight: 24,
                    hotspot: CursorHotspot(
                        normalizedX: 0.25,
                        normalizedY: 0.375
                    ),
                    pointWidth: 10,
                    pointHeight: 12,
                    frameCount: 2,
                    frameDuration: 0.075,
                    representations: [
                        CursorRepresentation(
                            filename: retinaFilename,
                            scale: 2,
                            pixelWidth: 40,
                            pixelHeight: 96
                        ),
                    ]
                ),
            ],
            importMetadata: ThemeImportMetadata(
                sourceFormat: "Windows ANI",
                sourceIdentifier: "portable-motion",
                author: "Cursor Artist",
                sourceVersion: "2.0",
                importedAt: .now,
                warnings: [],
                unassignedEntries: []
            )
        )
        let archiveURL = temporaryDirectory.appending(
            path: "Portable Motion.cursorstudio-theme"
        )
        let service = CursorStudioThemeArchiveService(paths: paths)

        let receipt = try await service.export(
            theme: theme,
            to: archiveURL
        )
        XCTAssertEqual(receipt.url, archiveURL)
        XCTAssertGreaterThan(receipt.byteCount, 0)
        XCTAssertEqual(receipt.sha256.count, 64)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: archiveURL.path)
        )

        let package = try await service.validateImport(from: archiveURL)
        defer {
            if let cleanup = package.cleanupDirectory {
                try? FileManager.default.removeItem(at: cleanup)
            }
        }
        XCTAssertEqual(package.manifest.themeID, themeID)
        XCTAssertEqual(package.manifest.name, theme.name)
        XCTAssertEqual(package.manifest.author, "Cursor Artist")
        XCTAssertNotNil(package.manifest.exportedAt)

        let installer = MarketplaceInstaller(
            store: store,
            paths: paths
        )
        let draft = try installer.prepareImport(
            package,
            sourceFormat: "Cursor Studio Theme Package"
        )
        XCTAssertEqual(draft.review.recognizedRoleCount, 1)
        XCTAssertEqual(draft.review.animatedRoleCount, 1)
        XCTAssertEqual(draft.review.staticAnimationFallbackCount, 0)

        let imported = try store.commitImportedTheme(draft)
        let arrow = try XCTUnwrap(imported.entry(for: .arrow))
        XCTAssertNotEqual(imported.id, theme.id)
        XCTAssertEqual(imported.name, theme.name)
        XCTAssertEqual(arrow.pixelWidth, 20)
        XCTAssertEqual(arrow.pixelHeight, 24)
        XCTAssertEqual(arrow.pointWidth, 10, accuracy: 0.0001)
        XCTAssertEqual(arrow.pointHeight, 12, accuracy: 0.0001)
        XCTAssertEqual(
            arrow.hotspot.normalizedX,
            0.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            arrow.hotspot.normalizedY,
            0.375,
            accuracy: 0.0001
        )
        XCTAssertEqual(arrow.frameCount, 2)
        XCTAssertEqual(arrow.frameDuration, 0.075, accuracy: 0.0001)
        XCTAssertEqual(arrow.representations.first?.scale, 2)
        XCTAssertEqual(
            imported.importMetadata?.sourceFormat,
            "Cursor Studio Theme Package"
        )
        XCTAssertEqual(
            imported.importMetadata?.author,
            "Cursor Artist"
        )
    }

    func testArchiveDetectionAndSafeFilename() {
        XCTAssertTrue(
            CursorStudioThemeArchiveService.canImport(
                URL(fileURLWithPath: "/tmp/theme.CURSORSTUDIO-THEME")
            )
        )
        XCTAssertFalse(
            CursorStudioThemeArchiveService.canImport(
                URL(fileURLWithPath: "/tmp/theme.zip")
            )
        )
        XCTAssertEqual(
            CursorStudioThemeArchiveService.suggestedFilename(
                for: CursorTheme(name: "Night/Day: Pro?")
            ),
            "Night-Day- Pro-.cursorstudio-theme"
        )
    }

    private func writePNG(
        width: Int,
        height: Int,
        to url: URL
    ) throws {
        let colorSpace = try XCTUnwrap(
            CGColorSpace(name: CGColorSpace.sRGB)
        )
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo:
                    CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(
            CGColor(
                colorSpace: colorSpace,
                components: [0.3, 0.5, 0.95, 1]
            )!
        )
        context.fill(
            CGRect(x: 0, y: 0, width: width, height: height)
        )
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
