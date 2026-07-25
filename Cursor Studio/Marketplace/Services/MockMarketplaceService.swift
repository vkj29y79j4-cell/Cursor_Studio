import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor MockMarketplaceService: MarketplaceServing {
    private let fileManager = FileManager.default

    func featuredThemes() async throws -> [MarketplaceTheme] {
        catalog
    }

    func searchThemes(
        query: String,
        filters: MarketplaceFilters
    ) async throws -> [MarketplaceTheme] {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var results = catalog.filter { theme in
            let matchesQuery = normalizedQuery.isEmpty
                || theme.title.localizedCaseInsensitiveContains(normalizedQuery)
                || theme.summary.localizedCaseInsensitiveContains(normalizedQuery)
                || theme.creatorName.localizedCaseInsensitiveContains(normalizedQuery)
            let matchesCategory = filters.category == nil
                || theme.category == filters.category
            let matchesVerification = !filters.verifiedOnly || theme.isVerified
            return matchesQuery && matchesCategory && matchesVerification
        }

        switch filters.sort {
        case .featured:
            results.sort {
                if $0.isVerified != $1.isVerified {
                    return $0.isVerified && !$1.isVerified
                }
                return $0.downloadCount > $1.downloadCount
            }
        case .recent:
            results.sort { $0.publishedAt > $1.publishedAt }
        case .popular:
            results.sort { $0.downloadCount > $1.downloadCount }
        }
        return results
    }

    func themeDetails(id: UUID) async throws -> MarketplaceThemeDetails {
        guard let theme = catalog.first(where: { $0.id == id }) else {
            throw MarketplaceServiceError.themeUnavailable
        }
        return MarketplaceThemeDetails(
            theme: theme,
            description: L10n.text(
                "A safe preview theme from the built-in offline catalog. It includes an Arrow cursor and can be installed without a network connection.",
                "Безопасная демонстрационная тема из встроенного офлайн-каталога. Она содержит курсор-стрелку и устанавливается без подключения к сети."
            ),
            semanticVersion: "1.0.0",
            includedRoles: [CursorRole.arrow.displayName],
            screenshotURLs: [],
            packageSHA256: nil
        )
    }

    func downloadTheme(id: UUID) async throws -> URL {
        guard let theme = catalog.first(where: { $0.id == id }) else {
            throw MarketplaceServiceError.themeUnavailable
        }
        let root = fileManager.temporaryDirectory.appending(
            path: "CursorStudioMarketplace-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let assets = root.appending(path: "Assets", directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: assets,
            withIntermediateDirectories: true
        )

        do {
            let imageURL = assets.appending(path: "arrow.png")
            try Self.writeCursorPNG(to: imageURL, colorSeed: theme.id.uuidString)
            let manifest = MarketplacePackageManifest(
                schemaVersion: 1,
                themeID: theme.id,
                name: theme.title,
                semanticVersion: "1.0.0",
                cursors: [
                    MarketplacePackageCursor(
                        role: CursorRole.arrow.rawValue,
                        asset: "Assets/arrow.png",
                        pixelWidth: 64,
                        pixelHeight: 64,
                        pointWidth: 32,
                        pointHeight: 32,
                        hotspotX: 4.0 / 63.0,
                        hotspotY: 4.0 / 63.0
                    ),
                ]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(
                to: root.appending(path: "manifest.json"),
                options: .atomic
            )
            return root
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    private var catalog: [MarketplaceTheme] {
        let now = Date.now
        return [
            theme(
                id: "6A7A6C20-DB44-4CF7-BF78-9911B0278F01",
                title: L10n.text("Graphite Precision", "Графитовая точность"),
                summary: L10n.text(
                    "Crisp monochrome cursors for focused work.",
                    "Чёткие монохромные курсоры для сосредоточенной работы."
                ),
                creator: "Northstar",
                category: L10n.text("Professional", "Профессиональные"),
                verified: true,
                compatibility: .compatible,
                downloads: 12_840,
                date: now.addingTimeInterval(-86_400 * 4)
            ),
            theme(
                id: "6A7A6C20-DB44-4CF7-BF78-9911B0278F02",
                title: L10n.text("Pixel Orchard", "Пиксельный сад"),
                summary: L10n.text(
                    "Friendly pixel-art pointers with high contrast.",
                    "Дружелюбные пиксельные указатели с высокой контрастностью."
                ),
                creator: "Mira",
                category: L10n.text("Pixel Art", "Пиксель-арт"),
                verified: true,
                compatibility: .compatible,
                downloads: 9_320,
                date: now.addingTimeInterval(-86_400 * 10)
            ),
            theme(
                id: "6A7A6C20-DB44-4CF7-BF78-9911B0278F03",
                title: L10n.text("Nordic Ice", "Северный лёд"),
                summary: L10n.text(
                    "Cool translucent shapes for light and dark desktops.",
                    "Холодные полупрозрачные формы для светлого и тёмного оформления."
                ),
                creator: "Lumen Lab",
                category: L10n.text("Minimal", "Минимализм"),
                verified: false,
                compatibility: .limited,
                downloads: 5_170,
                date: now.addingTimeInterval(-86_400 * 2)
            ),
            theme(
                id: "6A7A6C20-DB44-4CF7-BF78-9911B0278F04",
                title: L10n.text("Large & Clear", "Крупно и ясно"),
                summary: L10n.text(
                    "Extra-visible shapes designed for accessibility.",
                    "Особенно заметные формы для универсального доступа."
                ),
                creator: "Open Access",
                category: L10n.text("Accessibility", "Универсальный доступ"),
                verified: true,
                compatibility: .compatible,
                downloads: 17_490,
                date: now.addingTimeInterval(-86_400 * 18)
            ),
            theme(
                id: "6A7A6C20-DB44-4CF7-BF78-9911B0278F05",
                title: L10n.text("Candy Glass", "Леденцовое стекло"),
                summary: L10n.text(
                    "Bright playful pointers with a glossy finish.",
                    "Яркие игровые указатели с глянцевым эффектом."
                ),
                creator: "Pico Studio",
                category: L10n.text("Colorful", "Яркие"),
                verified: false,
                compatibility: .unknown,
                downloads: 2_440,
                date: now.addingTimeInterval(-86_400)
            ),
            theme(
                id: "6A7A6C20-DB44-4CF7-BF78-9911B0278F06",
                title: L10n.text("Orbit Motion", "Движение по орбите"),
                summary: L10n.text(
                    "Restrained animated progress and busy cursors.",
                    "Сдержанные анимированные курсоры выполнения и ожидания."
                ),
                creator: "Kepler Works",
                category: L10n.text("Animated", "Анимированные"),
                verified: true,
                compatibility: .limited,
                downloads: 7_060,
                date: now.addingTimeInterval(-86_400 * 6)
            ),
        ]
    }

    private func theme(
        id: String,
        title: String,
        summary: String,
        creator: String,
        category: String,
        verified: Bool,
        compatibility: MarketplaceCompatibility,
        downloads: Int,
        date: Date
    ) -> MarketplaceTheme {
        MarketplaceTheme(
            id: UUID(uuidString: id)!,
            title: title,
            summary: summary,
            creatorName: creator,
            category: category,
            previewURL: nil,
            isVerified: verified,
            compatibility: compatibility,
            downloadCount: downloads,
            publishedAt: date
        )
    }

    nonisolated private static func writeCursorPNG(
        to url: URL,
        colorSeed: String
    ) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: 64,
                height: 64,
                bitsPerComponent: 8,
                bytesPerRow: 256,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw MarketplaceServiceError.packageInvalid("Image context")
        }

        let hue = CGFloat(abs(colorSeed.hashValue % 255)) / 255
        let color = CGColor(
            red: 0.25 + hue * 0.45,
            green: 0.55,
            blue: 0.95 - hue * 0.35,
            alpha: 1
        )
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 5, y: 59))
        path.addLine(to: CGPoint(x: 5, y: 9))
        path.addLine(to: CGPoint(x: 43, y: 42))
        path.addLine(to: CGPoint(x: 25, y: 44))
        path.addLine(to: CGPoint(x: 35, y: 61))
        path.addLine(to: CGPoint(x: 26, y: 63))
        path.addLine(to: CGPoint(x: 17, y: 47))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(CGColor(gray: 0.08, alpha: 1))
        context.setLineWidth(3)
        context.setLineJoin(.round)
        context.strokePath()

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else {
            throw MarketplaceServiceError.packageInvalid("Image destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MarketplaceServiceError.packageInvalid("Image encoding")
        }
    }
}
