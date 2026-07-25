import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Cursor_Studio

final class WindowsCursorImportTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var paths: ApplicationPaths!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appending(
            path: "CursorStudioWindowsTests-\(UUID().uuidString)",
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
    func testFormatDetectionIsAutomatic() {
        XCTAssertTrue(
            WindowsCursorImportService.canImport(
                URL(fileURLWithPath: "/tmp/theme.CUR")
            )
        )
        XCTAssertTrue(
            WindowsCursorImportService.canImport(
                URL(fileURLWithPath: "/tmp/theme.ANI")
            )
        )
        XCTAssertTrue(
            WindowsCursorImportService.canImport(
                URL(fileURLWithPath: "/tmp/theme.zip")
            )
        )
        XCTAssertFalse(
            WindowsCursorImportService.canImport(
                URL(fileURLWithPath: "/tmp/theme.cape")
            )
        )
    }

    @MainActor
    func testCommonWindowsFilenamesMapWithoutManualSelection() {
        XCTAssertEqual(
            WindowsCursorRoleMapper.role(for: "diagonal_resize_1.cur"),
            .resizeDiagonalNWSE
        )
        XCTAssertEqual(
            WindowsCursorRoleMapper.role(for: "diagonal_resize_2.cur"),
            .resizeDiagonalNESW
        )
        XCTAssertEqual(
            WindowsCursorRoleMapper.role(for: "not_available.cur"),
            .operationNotAllowed
        )
        XCTAssertNil(
            WindowsCursorRoleMapper.role(for: "handwriting.cur")
        )
    }

    @MainActor
    func testCURImportsHotspotAndRetinaPointSize() async throws {
        let source = temporaryDirectory.appending(path: "aero_arrow.cur")
        try makeCUR(
            images: [
                (try makePNG(width: 32, height: 32, red: 0.2), 5, 7),
                (try makePNG(width: 64, height: 64, red: 0.7), 10, 14),
            ]
        ).write(to: source)

        let importer = WindowsCursorImportService(paths: paths)
        let draft = try await importer.prepareImport(from: source)
        let arrow = try XCTUnwrap(draft.theme.entry(for: .arrow))

        XCTAssertEqual(draft.theme.name, "aero_arrow")
        XCTAssertEqual(
            draft.theme.importMetadata?.sourceFormat,
            "Windows cursor (.cur)"
        )
        XCTAssertEqual(arrow.sourceIdentifier, "aero_arrow.cur")
        XCTAssertEqual(arrow.pointWidth, 32, accuracy: 0.001)
        XCTAssertEqual(arrow.pointHeight, 32, accuracy: 0.001)
        XCTAssertEqual(arrow.hotspot.normalizedX, 5.0 / 31.0, accuracy: 0.001)
        XCTAssertEqual(arrow.hotspot.normalizedY, 7.0 / 31.0, accuracy: 0.001)
        XCTAssertEqual(arrow.representations.count, 2)
        XCTAssertEqual(
            Set(arrow.representations.map(\.pixelWidth)),
            Set([32, 64])
        )
        XCTAssertNotNil(draft.theme.previewAssetFilename)
        XCTAssertTrue(
            draft.review.warningMessages.contains {
                $0.localizedCaseInsensitiveContains("does not provide")
                    || $0.localizedCaseInsensitiveContains("отсутств")
            }
        )

        let store = ThemeStore(paths: paths)
        try store.load()
        let committed = try store.commitImportedTheme(draft)
        let reloaded = ThemeStore(paths: paths)
        try reloaded.load()
        XCTAssertEqual(
            reloaded.theme(withID: committed.id)?.entry(for: .arrow)?.hotspot,
            arrow.hotspot
        )
    }

    @MainActor
    func testClassicDIBBackedCURIsDecoded() async throws {
        let source = temporaryDirectory.appending(path: "precision.cur")
        try makeDIBCUR(
            width: 16,
            height: 16,
            hotspotX: 8,
            hotspotY: 8
        ).write(to: source)

        let draft = try await WindowsCursorImportService(paths: paths)
            .prepareImport(from: source)
        let crosshair = try XCTUnwrap(draft.theme.entry(for: .crosshair))

        XCTAssertEqual(crosshair.pixelWidth, 16)
        XCTAssertEqual(crosshair.pixelHeight, 16)
        XCTAssertEqual(crosshair.hotspot.normalizedX, 8.0 / 15.0, accuracy: 0.001)
        XCTAssertEqual(crosshair.hotspot.normalizedY, 8.0 / 15.0, accuracy: 0.001)
    }

    @MainActor
    func testFolderUsesINFRoleHintsAndSkipsBrokenCursor() async throws {
        let folder = temporaryDirectory.appending(
            path: "Blue Windows",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        try makeCUR(
            images: [(try makePNG(width: 32, height: 32, red: 0.3), 4, 12)]
        ).write(to: folder.appending(path: "blue-beam.cur"))
        try makeCUR(
            images: [(try makePNG(width: 32, height: 32, red: 0.6), 1, 1)]
        ).write(to: folder.appending(path: "normal.cur"))
        try Data([0, 1, 2]).write(to: folder.appending(path: "broken.cur"))
        try """
        [Scheme.Reg]
        HKCU,"Control Panel\\Cursors",IBeam,0x00020000,"%10%\\blue-beam.cur"
        HKCU,"Control Panel\\Cursors",Arrow,0x00020000,"%10%\\normal.cur"
        """.write(
            to: folder.appending(path: "install.inf"),
            atomically: true,
            encoding: .utf8
        )

        let draft = try await WindowsCursorImportService(paths: paths)
            .prepareImport(from: folder)

        XCTAssertEqual(draft.theme.name, "Blue Windows")
        XCTAssertNotNil(draft.theme.entry(for: .iBeam))
        XCTAssertNotNil(draft.theme.entry(for: .arrow))
        XCTAssertEqual(draft.review.missingImageCount, 1)
        XCTAssertTrue(
            draft.review.warningMessages.contains {
                $0.localizedCaseInsensitiveContains("broken.cur")
            }
        )
    }

    @MainActor
    func testANIImportsAnimatedVerticalStrip() async throws {
        let first = try makeCUR(
            images: [(makePNG(width: 32, height: 32, red: 0.2), 2, 3)]
        )
        let second = try makeCUR(
            images: [(makePNG(width: 32, height: 32, red: 0.8), 2, 3)]
        )
        let source = temporaryDirectory.appending(path: "aero_busy.ani")
        try makeANI(frames: [first, second], jiffies: 6).write(to: source)

        let draft = try await WindowsCursorImportService(paths: paths)
            .prepareImport(from: source)
        let busy = try XCTUnwrap(draft.theme.entry(for: .busy))
        let representation = try XCTUnwrap(busy.representations.first)

        XCTAssertEqual(busy.frameCount, 2)
        XCTAssertEqual(busy.frameDuration, 0.1, accuracy: 0.0001)
        XCTAssertFalse(busy.usesStaticAnimationFallback)
        XCTAssertEqual(draft.review.animatedRoleCount, 1)
        XCTAssertEqual(representation.pixelWidth, 32)
        XCTAssertEqual(representation.pixelHeight, 64)
    }

    @MainActor
    func testZIPThemeImportsWithoutManualFormatChoice() async throws {
        let folder = temporaryDirectory.appending(
            path: "Archive Theme",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        try makeCUR(
            images: [(try makePNG(width: 32, height: 32, red: 0.5), 0, 0)]
        ).write(to: folder.appending(path: "arrow.cur"))
        let archive = temporaryDirectory.appending(path: "Archive Theme.zip")
        try createZIP(from: folder, at: archive)

        let draft = try await WindowsCursorImportService(paths: paths)
            .prepareImport(from: archive)

        XCTAssertEqual(draft.theme.name, "Archive Theme")
        XCTAssertNotNil(draft.theme.entry(for: .arrow))
        XCTAssertEqual(
            draft.theme.importMetadata?.sourceFormat,
            "Windows cursor theme (ZIP)"
        )
    }

    private func makeCUR(
        images: [(png: Data, hotspotX: UInt16, hotspotY: UInt16)]
    ) throws -> Data {
        var result = Data()
        result.appendUInt16LE(0)
        result.appendUInt16LE(2)
        result.appendUInt16LE(UInt16(images.count))

        var payloadOffset = 6 + images.count * 16
        for item in images {
            let dimensions = try pngDimensions(item.png)
            result.append(dimensions.width == 256 ? 0 : UInt8(dimensions.width))
            result.append(dimensions.height == 256 ? 0 : UInt8(dimensions.height))
            result.append(0)
            result.append(0)
            result.appendUInt16LE(item.hotspotX)
            result.appendUInt16LE(item.hotspotY)
            result.appendUInt32LE(UInt32(item.png.count))
            result.appendUInt32LE(UInt32(payloadOffset))
            payloadOffset += item.png.count
        }
        for item in images {
            result.append(item.png)
        }
        return result
    }

    private func makeANI(frames: [Data], jiffies: UInt32) -> Data {
        var animationHeader = Data()
        animationHeader.appendUInt32LE(36)
        animationHeader.appendUInt32LE(UInt32(frames.count))
        animationHeader.appendUInt32LE(UInt32(frames.count))
        animationHeader.appendUInt32LE(32)
        animationHeader.appendUInt32LE(32)
        animationHeader.appendUInt32LE(32)
        animationHeader.appendUInt32LE(1)
        animationHeader.appendUInt32LE(jiffies)
        animationHeader.appendUInt32LE(1)

        var frameList = Data("fram".utf8)
        for frame in frames {
            frameList.append(chunk("icon", payload: frame))
        }

        var acon = Data("ACON".utf8)
        acon.append(chunk("anih", payload: animationHeader))
        acon.append(chunk("LIST", payload: frameList))

        var riff = Data("RIFF".utf8)
        riff.appendUInt32LE(UInt32(acon.count))
        riff.append(acon)
        return riff
    }

    private func makeDIBCUR(
        width: Int,
        height: Int,
        hotspotX: UInt16,
        hotspotY: UInt16
    ) -> Data {
        var dib = Data()
        dib.appendUInt32LE(40)
        dib.appendUInt32LE(UInt32(width))
        dib.appendUInt32LE(UInt32(height * 2))
        dib.appendUInt16LE(1)
        dib.appendUInt16LE(32)
        dib.appendUInt32LE(0)
        dib.appendUInt32LE(UInt32(width * height * 4))
        dib.appendUInt32LE(0)
        dib.appendUInt32LE(0)
        dib.appendUInt32LE(0)
        dib.appendUInt32LE(0)
        for y in 0..<height {
            for x in 0..<width {
                dib.append(UInt8((x * 255) / max(width - 1, 1)))
                dib.append(UInt8((y * 255) / max(height - 1, 1)))
                dib.append(180)
                dib.append(255)
            }
        }
        let maskBytesPerRow = ((width + 31) / 32) * 4
        dib.append(
            Data(repeating: 0, count: maskBytesPerRow * height)
        )

        var cursor = Data()
        cursor.appendUInt16LE(0)
        cursor.appendUInt16LE(2)
        cursor.appendUInt16LE(1)
        cursor.append(UInt8(width))
        cursor.append(UInt8(height))
        cursor.append(0)
        cursor.append(0)
        cursor.appendUInt16LE(hotspotX)
        cursor.appendUInt16LE(hotspotY)
        cursor.appendUInt32LE(UInt32(dib.count))
        cursor.appendUInt32LE(22)
        cursor.append(dib)
        return cursor
    }

    private func chunk(_ identifier: String, payload: Data) -> Data {
        var result = Data(identifier.utf8)
        result.appendUInt32LE(UInt32(payload.count))
        result.append(payload)
        if !payload.count.isMultiple(of: 2) {
            result.append(0)
        }
        return result
    }

    private func makePNG(
        width: Int,
        height: Int,
        red: CGFloat
    ) throws -> Data {
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
        context.setFillColor(
            CGColor(red: red, green: 0.3, blue: 0.7, alpha: 1)
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pngDimensions(_ data: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(data as CFData, nil)
        )
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        )
        return (
            try XCTUnwrap(
                (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
            ),
            try XCTUnwrap(
                (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            )
        )
    }

    private func createZIP(from directory: URL, at destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--norsrc",
            directory.path,
            destination.path,
        ]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

private extension Data {
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
