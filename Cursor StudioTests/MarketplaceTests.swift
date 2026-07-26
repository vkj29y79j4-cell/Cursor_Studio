import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Cursor_Studio

final class MarketplaceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appending(
            path: "CursorStudioMarketplaceTests-\(UUID().uuidString)",
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

    func testMockCatalogSupportsSearchAndVerifiedFilter() async throws {
        let service = MockMarketplaceService()
        let all = try await service.featuredThemes()
        XCTAssertGreaterThanOrEqual(all.count, 5)

        let verified = try await service.searchThemes(
            query: "",
            filters: MarketplaceFilters(verifiedOnly: true)
        )
        XCTAssertFalse(verified.isEmpty)
        XCTAssertTrue(verified.allSatisfy(\.isVerified))

        let named = try await service.searchThemes(
            query: all[0].title,
            filters: MarketplaceFilters()
        )
        XCTAssertEqual(named.first?.id, all[0].id)
    }

    @MainActor
    func testOpeningThemeDetailsLoadsValidatedCursorGallery() async throws {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        let store = ThemeStore(paths: paths)
        try store.load()

        let defaultsSuite = "CursorStudioMarketplaceGalleryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let service = MockMarketplaceService()
        let themes = try await service.featuredThemes()
        let theme = try XCTUnwrap(themes.first)
        let model = MarketplaceViewModel(
            store: store,
            paths: paths,
            preferences: AppPreferences(
                defaults: defaults,
                launchAtLoginOverride: false
            ),
            service: service
        )

        model.openDetails(for: theme)
        for _ in 0..<200 where model.isLoadingCursorPreviews {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.details?.theme.id, theme.id)
        XCTAssertFalse(model.isLoadingCursorPreviews)
        XCTAssertNil(model.cursorPreviewMessage)
        XCTAssertFalse(model.cursorPreviews.isEmpty)
        XCTAssertTrue(
            model.cursorPreviews.allSatisfy {
                FileManager.default.fileExists(atPath: $0.assetURL.path)
            }
        )
    }

    func testSupabaseCatalogDecodesCurrentVersionAsObject() throws {
        let payload = Data(
            """
            [
              {
                "id": "5c74cd92-a874-4707-822e-fd2e00c1014a",
                "title_en": "Luxus3-Obsidian",
                "title_ru": null,
                "description_en": "A great modern theme",
                "description_ru": null,
                "is_verified": false,
                "is_featured": false,
                "published_at": "2026-07-25T19:52:07.555027+00:00",
                "profiles": {"display_name": "ThatD0g"},
                "categories": {
                  "name_en": "Minimal",
                  "name_ru": "Минимализм"
                },
                "theme_versions": {
                  "id": "00e79a86-d364-4ba0-83a0-d242d1e6a74e",
                  "package_path": "owner/theme/1.0.0/theme.cursorstudio-theme",
                  "package_sha256": "cd8cebedf56bea86daec56a1c3f9dbde1a9324aa10c5ad6a687aab039dc1a49a",
                  "semantic_version": "1.0.0",
                  "minimum_macos_major": 15,
                  "maximum_tested_macos_major": null,
                  "compatibility": "compatible",
                  "preview_paths": ["owner/theme/1.0.0/preview.png"],
                  "review_status": "approved"
                }
              }
            ]
            """.utf8
        )

        let themes = try SupabaseMarketplaceService.decodeCatalogPayload(
            payload,
            prefersRussian: false,
            currentMacOSMajor: 15,
            projectURL: URL(string: "https://example.supabase.co")!
        )

        let theme = try XCTUnwrap(themes.first)
        XCTAssertEqual(themes.count, 1)
        XCTAssertEqual(theme.title, "Luxus3-Obsidian")
        XCTAssertEqual(theme.creatorName, "ThatD0g")
        XCTAssertEqual(theme.compatibility, .compatible)
        XCTAssertEqual(
            theme.previewURL?.absoluteString,
            "https://example.supabase.co/storage/v1/object/public/theme-previews/owner/theme/1.0.0/preview.png"
        )
    }

    func testSessionVaultWorksForUnsignedDevelopmentBuilds() throws {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        let vault = MarketplaceSessionVault(
            paths: paths,
            service: "studio.cursor.CursorStudio.tests.\(UUID().uuidString)"
        )
        let expected = MarketplaceStoredSession(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
            userID: UUID(),
            email: "creator@example.com"
        )
        defer { try? vault.clear() }

        try vault.save(expected)
        let restored = try XCTUnwrap(vault.load())

        XCTAssertEqual(restored.accessToken, expected.accessToken)
        XCTAssertEqual(restored.refreshToken, expected.refreshToken)
        XCTAssertEqual(restored.expiresAt, expected.expiresAt)
        XCTAssertEqual(restored.userID, expected.userID)
        XCTAssertEqual(restored.email, expected.email)

        try vault.clear()
        XCTAssertNil(try vault.load())
    }

    func testMarketplaceCursorSizeIsLimitedToSystemScale() {
        let legacy = MarketplaceCursorSizing.normalizedPointSize(
            pixelWidth: 64,
            pixelHeight: 48,
            requestedPointWidth: nil,
            requestedPointHeight: nil
        )
        XCTAssertEqual(legacy.width, 32, accuracy: 0.0001)
        XCTAssertEqual(legacy.height, 24, accuracy: 0.0001)

        let explicit = MarketplaceCursorSizing.normalizedPointSize(
            pixelWidth: 128,
            pixelHeight: 128,
            requestedPointWidth: 24,
            requestedPointHeight: 24
        )
        XCTAssertEqual(explicit.width, 24, accuracy: 0.0001)
        XCTAssertEqual(explicit.height, 24, accuracy: 0.0001)
    }

    @MainActor
    func testMockPackageValidatesAndInstallsTransactionally() async throws {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        let store = ThemeStore(paths: paths)
        try store.load()
        let initialCount = store.themes.count

        let service = MockMarketplaceService()
        let featured = try await service.featuredThemes()
        let theme = try XCTUnwrap(featured.first)
        let packageURL = try await service.downloadTheme(id: theme.id)
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let validator = MarketplacePackageValidator(paths: paths)
        let validated = try await validator.validatePackage(at: packageURL)
        let installed = try MarketplaceInstaller(
            store: store,
            paths: paths
        ).install(validated)

        XCTAssertEqual(store.themes.count, initialCount + 1)
        XCTAssertEqual(installed.importMetadata?.sourceFormat, "Cursor Studio Marketplace")
        let installedArrow = try XCTUnwrap(installed.entry(for: .arrow))
        XCTAssertEqual(
            installedArrow.pointWidth,
            32,
            accuracy: 0.0001
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: paths.themeDirectory(for: installed.id).path
            )
        )
    }

    func testValidatorRejectsSymbolicLinks() async throws {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        try paths.createDirectories()
        let package = temporaryDirectory.appending(
            path: "UnsafePackage",
            directoryHint: .isDirectory
        )
        let assets = package.appending(
            path: "Assets",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: assets,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: assets.appending(path: "arrow.png"),
            withDestinationURL: URL(fileURLWithPath: "/etc/passwd")
        )

        do {
            _ = try await MarketplacePackageValidator(paths: paths)
                .validatePackage(at: package)
            XCTFail("Expected symbolic-link package to fail")
        } catch let error as MarketplaceServiceError {
            guard case .packageInvalid = error else {
                return XCTFail("Unexpected marketplace error: \(error)")
            }
        }
    }

    func testValidatorRejectsPathTraversalZIP() async throws {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        try paths.createDirectories()
        let archive = temporaryDirectory.appending(
            path: "Traversal.cursorstudio-theme"
        )
        let unsafeName = Data("../escape.png".utf8)
        var data = Data()
        data.appendUInt32LE(0x0201_4B50)
        data.appendUInt16LE(0x0314)
        data.appendUInt16LE(20)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt32LE(0)
        data.appendUInt32LE(0)
        data.appendUInt32LE(0)
        data.appendUInt16LE(UInt16(unsafeName.count))
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt32LE(0)
        data.appendUInt32LE(0)
        data.append(unsafeName)
        let centralSize = data.count
        data.appendUInt32LE(0x0605_4B50)
        data.appendUInt16LE(0)
        data.appendUInt16LE(0)
        data.appendUInt16LE(1)
        data.appendUInt16LE(1)
        data.appendUInt32LE(UInt32(centralSize))
        data.appendUInt32LE(0)
        data.appendUInt16LE(0)
        try data.write(to: archive)

        do {
            _ = try await MarketplacePackageValidator(paths: paths)
                .validatePackage(at: archive)
            XCTFail("Expected path-traversal package to fail")
        } catch let error as MarketplaceServiceError {
            guard case .packageInvalid = error else {
                return XCTFail("Unexpected marketplace error: \(error)")
            }
        }
    }

    @MainActor
    func testPublisherCreatesArchiveAcceptedByValidator() async throws {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        let store = ThemeStore(paths: paths)
        try store.load()
        let localTheme = try XCTUnwrap(store.themes.first)
        let remoteThemeID = UUID()

        let prepared = try MarketplacePackageBuilder(paths: paths).prepare(
            theme: localTheme,
            remoteThemeID: remoteThemeID,
            semanticVersion: "1.0.0"
        )
        defer {
            try? FileManager.default.removeItem(
                at: prepared.cleanupDirectory
            )
        }

        XCTAssertGreaterThan(prepared.packageBytes, 0)
        XCTAssertEqual(prepared.packageSHA256.count, 64)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: prepared.previewURL.path
            )
        )

        let validated = try await MarketplacePackageValidator(paths: paths)
            .validatePackage(
                at: prepared.packageURL,
                expectedSHA256: prepared.packageSHA256
            )
        defer {
            if let cleanup = validated.cleanupDirectory {
                try? FileManager.default.removeItem(at: cleanup)
            }
        }
        XCTAssertEqual(validated.manifest.themeID, remoteThemeID)
        XCTAssertEqual(validated.manifest.semanticVersion, "1.0.0")
        XCTAssertFalse(validated.manifest.cursors.isEmpty)
    }

    @MainActor
    func testAnimatedCursorSurvivesMarketplacePublishAndInstall() async throws {
        let paths = ApplicationPaths(rootDirectory: temporaryDirectory)
        try paths.createDirectories()
        let localThemeID = UUID()
        let localAssets = paths.assetsDirectory(for: localThemeID)
        try FileManager.default.createDirectory(
            at: localAssets,
            withIntermediateDirectories: true
        )
        let previewFilename = "animated-preview.png"
        let representationFilename = "animated-strip.png"
        try writePNG(
            width: 16,
            height: 16,
            to: localAssets.appending(path: previewFilename)
        )
        try writePNG(
            width: 16,
            height: 32,
            to: localAssets.appending(path: representationFilename)
        )
        let localTheme = CursorTheme(
            id: localThemeID,
            name: "Animated Marketplace Theme",
            previewAssetFilename: previewFilename,
            entries: [
                CursorEntry(
                    role: .arrow,
                    assetFilename: previewFilename,
                    pixelWidth: 16,
                    pixelHeight: 16,
                    hotspot: CursorHotspot(
                        normalizedX: 0.25,
                        normalizedY: 0.25
                    ),
                    pointWidth: 16,
                    pointHeight: 16,
                    frameCount: 2,
                    frameDuration: 0.08,
                    representations: [
                        CursorRepresentation(
                            filename: representationFilename,
                            scale: 1,
                            pixelWidth: 16,
                            pixelHeight: 32
                        ),
                    ]
                ),
            ]
        )

        let prepared = try MarketplacePackageBuilder(paths: paths).prepare(
            theme: localTheme,
            remoteThemeID: UUID(),
            semanticVersion: "1.0.0"
        )
        defer { try? FileManager.default.removeItem(at: prepared.cleanupDirectory) }
        let publishedCursor = try XCTUnwrap(prepared.manifest.cursors.first)
        XCTAssertEqual(publishedCursor.frameCount, 2)
        XCTAssertEqual(
            try XCTUnwrap(publishedCursor.frameDuration),
            0.08,
            accuracy: 0.0001
        )
        XCTAssertEqual(publishedCursor.representations?.count, 1)

        let validated = try await MarketplacePackageValidator(paths: paths)
            .validatePackage(
                at: prepared.packageURL,
                expectedSHA256: prepared.packageSHA256
            )
        defer {
            if let cleanup = validated.cleanupDirectory {
                try? FileManager.default.removeItem(at: cleanup)
            }
        }
        let packagePreviews = MarketplacePackagePreviewBuilder.previews(
            from: validated
        )
        let arrowPreview = try XCTUnwrap(
            packagePreviews.first(where: { $0.role == .arrow })
        )
        XCTAssertEqual(packagePreviews.count, 1)
        XCTAssertEqual(arrowPreview.frameCount, 2)
        XCTAssertEqual(arrowPreview.pixelWidth, 16)
        XCTAssertEqual(arrowPreview.pixelHeight, 16)
        XCTAssertNotNil(arrowPreview.animationStripURL)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: arrowPreview.assetURL.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(arrowPreview.animationStripURL).path
            )
        )
        let store = ThemeStore(paths: paths)
        try store.load()
        let installed = try MarketplaceInstaller(
            store: store,
            paths: paths
        ).install(validated)
        let installedArrow = try XCTUnwrap(installed.entry(for: .arrow))

        XCTAssertTrue(installedArrow.isAnimated)
        XCTAssertEqual(installedArrow.frameCount, 2)
        XCTAssertEqual(installedArrow.frameDuration, 0.08, accuracy: 0.0001)
        XCTAssertEqual(installedArrow.representations.count, 1)
        let installedRepresentation = try XCTUnwrap(
            installedArrow.representations.first
        )
        let installedStripURL = try XCTUnwrap(
            paths.assetURL(
                themeID: installed.id,
                filename: installedRepresentation.filename
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: installedStripURL.path
            )
        )
        let previewFrames = try XCTUnwrap(
            CursorAnimationFrameLoader.loadImages(
                at: installedStripURL,
                frameCount: installedArrow.frameCount
            )
        )
        XCTAssertEqual(previewFrames.count, 2)
        XCTAssertTrue(
            previewFrames.allSatisfy {
                $0.size == NSSize(width: 16, height: 16)
            }
        )
    }

    private func writePNG(width: Int, height: Int, to url: URL) throws {
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
            CGColor(
                colorSpace: colorSpace,
                components: [0.2, 0.6, 0.95, 1]
            )!
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
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
