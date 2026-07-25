import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Cursor_Studio

final class CapeImportTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var paths: ApplicationPaths!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appending(
            path: "CursorStudioCapeTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        paths = ApplicationPaths(
            rootDirectory: temporaryDirectory.appending(
                path: "Application Support",
                directoryHint: .isDirectory
            )
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    @MainActor
    func testCapeFileDetectionIsCaseInsensitive() {
        XCTAssertTrue(
            CapeImportService.canImport(
                URL(fileURLWithPath: "/tmp/theme.cape")
            )
        )
        XCTAssertTrue(
            CapeImportService.canImport(
                URL(fileURLWithPath: "/tmp/theme.CAPE")
            )
        )
        XCTAssertFalse(
            CapeImportService.canImport(
                URL(fileURLWithPath: "/tmp/theme.plist")
            )
        )
    }

    @MainActor
    func testValidCapeImportsScaleHotspotAnimationAndUnknownRole() async throws {
        let source = temporaryDirectory.appending(path: "valid.cape")
        try writeCape(
            named: "Synthetic Cape",
            cursors: [
                "com.apple.coregraphics.Arrow": cursorDictionary(
                    pointWidth: 16,
                    pointHeight: 16,
                    hotspotX: 4,
                    hotspotY: 6,
                    frameCount: 2,
                    frameDuration: 0.08,
                    representations: [
                        try makeStripPNG(
                            pointWidth: 16,
                            pointHeight: 16,
                            scale: 2,
                            frameCount: 2
                        ),
                    ]
                ),
                "com.example.FutureCursor": cursorDictionary(
                    representations: [
                        try makeStripPNG(
                            pointWidth: 16,
                            pointHeight: 16,
                            scale: 1,
                            frameCount: 1
                        ),
                    ]
                ),
            ],
            to: source
        )

        let draft = try await CapeImportService(paths: paths)
            .prepareImport(from: source)
        let arrow = try XCTUnwrap(draft.theme.entry(for: .arrow))
        let representation = try XCTUnwrap(arrow.representations.first)

        XCTAssertEqual(draft.theme.name, "Synthetic Cape")
        XCTAssertEqual(draft.theme.importMetadata?.author, "Cursor Studio Tests")
        XCTAssertEqual(draft.review.recognizedRoleCount, 1)
        XCTAssertEqual(draft.review.unrecognizedRoleCount, 1)
        XCTAssertEqual(draft.review.animatedRoleCount, 1)
        XCTAssertEqual(arrow.frameCount, 2)
        XCTAssertEqual(arrow.frameDuration, 0.08, accuracy: 0.0001)
        XCTAssertEqual(arrow.hotspot.normalizedX, 4.0 / 15.0, accuracy: 0.0001)
        XCTAssertEqual(arrow.hotspot.normalizedY, 6.0 / 15.0, accuracy: 0.0001)
        XCTAssertEqual(representation.scale, 2, accuracy: 0.0001)
        XCTAssertEqual(representation.pixelWidth, 32)
        XCTAssertEqual(representation.pixelHeight, 64)
        XCTAssertEqual(arrow.pixelWidth, 32)
        XCTAssertEqual(arrow.pixelHeight, 32)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: draft.stagingThemeDirectory.appending(
                    path: "Assets/\(arrow.assetFilename)"
                ).path
            )
        )
        XCTAssertNotNil(draft.theme.previewAssetFilename)

        await CapeImportService(paths: paths).discard(draft)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: draft.stagingThemeDirectory.path
            )
        )
    }

    @MainActor
    func testHotspotIsClampedWithNonblockingWarning() async throws {
        let source = temporaryDirectory.appending(path: "hotspot.cape")
        try writeCape(
            named: "Clamped",
            cursors: [
                "Arrow": cursorDictionary(
                    hotspotX: 100,
                    hotspotY: -5,
                    representations: [
                        try makeStripPNG(
                            pointWidth: 16,
                            pointHeight: 16,
                            scale: 1,
                            frameCount: 1
                        ),
                    ]
                ),
            ],
            to: source
        )

        let draft = try await CapeImportService(paths: paths)
            .prepareImport(from: source)
        let arrow = try XCTUnwrap(draft.theme.entry(for: .arrow))

        XCTAssertEqual(arrow.hotspot.normalizedX, 1)
        XCTAssertEqual(arrow.hotspot.normalizedY, 0)
        XCTAssertTrue(
            draft.review.warningMessages.contains {
                $0.localizedCaseInsensitiveContains("clamped")
                    || $0.localizedCaseInsensitiveContains("перемещена")
            }
        )
    }

    @MainActor
    func testInvalidCapeAndCorruptedImageLeaveNoStagingTheme() async throws {
        let invalid = temporaryDirectory.appending(path: "invalid.cape")
        try Data("not a property list".utf8).write(to: invalid)
        let importer = CapeImportService(paths: paths)

        do {
            _ = try await importer.prepareImport(from: invalid)
            XCTFail("Expected invalid cape to fail")
        } catch {
            XCTAssertEqual(
                error as? CursorStudioError,
                .invalidCape("The property list could not be decoded.")
            )
        }

        let corrupt = temporaryDirectory.appending(path: "corrupt.cape")
        try writeCape(
            named: "Corrupt",
            cursors: [
                "Arrow": cursorDictionary(
                    representations: [Data([0, 1, 2, 3])]
                ),
            ],
            to: corrupt
        )
        do {
            _ = try await importer.prepareImport(from: corrupt)
            XCTFail("Expected corrupted image to fail")
        } catch {
            XCTAssertEqual(
                error as? CursorStudioError,
                .capeMissingCursorEntries
            )
        }

        let stagingContents = (
            try? FileManager.default.contentsOfDirectory(
                at: paths.importStagingDirectory,
                includingPropertiesForKeys: nil
            )
        ) ?? []
        XCTAssertTrue(stagingContents.isEmpty)
    }

    @MainActor
    func testCommitIsTransactionalAndDuplicateNamesAreMadeUnique() async throws {
        let firstSource = temporaryDirectory.appending(path: "first.cape")
        let secondSource = temporaryDirectory.appending(path: "second.cape")
        let cursors = [
            "Arrow": cursorDictionary(
                representations: [
                    try makeStripPNG(
                        pointWidth: 16,
                        pointHeight: 16,
                        scale: 1,
                        frameCount: 1
                    ),
                ]
            ),
        ]
        try writeCape(named: "Duplicate", cursors: cursors, to: firstSource)
        try writeCape(named: "Duplicate", cursors: cursors, to: secondSource)

        let importer = CapeImportService(paths: paths)
        let firstDraft = try await importer.prepareImport(from: firstSource)
        let secondDraft = try await importer.prepareImport(from: secondSource)
        let store = ThemeStore(paths: paths)
        try store.load()

        let first = try store.commitCapeImport(firstDraft)
        let second = try store.commitCapeImport(secondDraft)

        XCTAssertEqual(first.name, "Duplicate")
        XCTAssertEqual(second.name, "Duplicate 2")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: paths.themeDirectory(for: first.id).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: paths.assetURL(
                    themeID: first.id,
                    filename: ThemePreviewGenerator.previewFilename
                )!.path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: firstDraft.stagingThemeDirectory.path
            )
        )

        let reloaded = ThemeStore(paths: paths)
        try reloaded.load()
        XCTAssertNotNil(reloaded.theme(withID: first.id)?.importMetadata)
        XCTAssertNotNil(reloaded.theme(withID: second.id)?.entry(for: .arrow))
    }

    @MainActor
    func testMoreThanTwentyFourFramesUsesStaticFallback() async throws {
        let source = temporaryDirectory.appending(path: "fallback.cape")
        try writeCape(
            named: "Fallback",
            cursors: [
                "Wait": cursorDictionary(
                    frameCount: 25,
                    frameDuration: 0.04,
                    representations: [
                        try makeStripPNG(
                            pointWidth: 2,
                            pointHeight: 2,
                            scale: 1,
                            frameCount: 25
                        ),
                    ]
                ),
            ],
            to: source
        )

        let draft = try await CapeImportService(paths: paths)
            .prepareImport(from: source)
        let entry = try XCTUnwrap(draft.theme.entry(for: .progress))

        XCTAssertTrue(entry.usesStaticAnimationFallback)
        XCTAssertEqual(draft.review.staticAnimationFallbackCount, 1)
        XCTAssertEqual(entry.pixelHeight, 2)
    }

    @MainActor
    func testImportAndDeleteTwentyThemesLeavesNoThemeAssets() async throws {
        let png = try makeStripPNG(
            pointWidth: 8,
            pointHeight: 8,
            scale: 1,
            frameCount: 1
        )
        let importer = CapeImportService(paths: paths)
        let store = ThemeStore(paths: paths)
        try store.load()
        var importedIDs: [UUID] = []

        for index in 0..<20 {
            let source = temporaryDirectory.appending(
                path: "stress-\(index).cape"
            )
            try writeCape(
                named: "Stress \(index)",
                cursors: [
                    "Arrow": cursorDictionary(representations: [png]),
                ],
                to: source
            )
            let draft = try await importer.prepareImport(from: source)
            importedIDs.append(try store.commitCapeImport(draft).id)
        }

        for id in importedIDs {
            try store.deleteTheme(id: id)
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: paths.themeDirectory(for: id).path
                )
            )
        }
        XCTAssertTrue(
            store.themes.allSatisfy { !importedIDs.contains($0.id) }
        )
        let staging = try FileManager.default.contentsOfDirectory(
            at: paths.importStagingDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(staging.isEmpty)
    }

    private func cursorDictionary(
        pointWidth: Int = 16,
        pointHeight: Int = 16,
        hotspotX: Double = 0,
        hotspotY: Double = 0,
        frameCount: Int = 1,
        frameDuration: Double = 0,
        representations: [Data]
    ) -> [String: Any] {
        [
            "PointsWide": pointWidth,
            "PointsHigh": pointHeight,
            "HotSpotX": hotspotX,
            "HotSpotY": hotspotY,
            "FrameCount": frameCount,
            "FrameDuration": frameDuration,
            "Representations": representations,
        ]
    }

    private func writeCape(
        named name: String,
        cursors: [String: Any],
        to url: URL
    ) throws {
        let root: [String: Any] = [
            "CapeName": name,
            "Author": "Cursor Studio Tests",
            "Identifier": "com.cursorstudio.synthetic",
            "CapeVersion": 1,
            "Cursors": cursors,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }

    private func makeStripPNG(
        pointWidth: Int,
        pointHeight: Int,
        scale: Int,
        frameCount: Int
    ) throws -> Data {
        let width = pointWidth * scale
        let frameHeight = pointHeight * scale
        let height = frameHeight * frameCount
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
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        for frame in 0..<frameCount {
            context.setFillColor(
                CGColor(
                    red: CGFloat(frame + 1) / CGFloat(frameCount + 1),
                    green: 0.4,
                    blue: 0.8,
                    alpha: 1
                )
            )
            context.fill(
                CGRect(
                    x: 0,
                    y: frame * frameHeight,
                    width: width,
                    height: frameHeight
                )
            )
        }

        let image = try XCTUnwrap(context.makeImage())
        let mutableData = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                mutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return mutableData as Data
    }
}
