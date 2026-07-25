import Foundation

nonisolated enum MarketplaceSort: String, CaseIterable, Codable, Sendable {
    case featured
    case recent
    case popular

    var displayName: String {
        switch self {
        case .featured: L10n.featured
        case .recent: L10n.recent
        case .popular: L10n.popular
        }
    }
}

nonisolated enum MarketplaceCompatibility: String, Codable, Sendable {
    case compatible
    case limited
    case incompatible
    case unknown

    var displayName: String {
        switch self {
        case .compatible: L10n.compatible
        case .limited: L10n.text("Limited compatibility", "Ограниченная совместимость")
        case .incompatible: L10n.incompatible
        case .unknown: L10n.compatibilityUnknown
        }
    }
}

nonisolated struct MarketplaceFilters: Hashable, Codable, Sendable {
    var category: String?
    var sort: MarketplaceSort
    var verifiedOnly: Bool
    var contentLanguage: MarketplaceContentLanguage

    init(
        category: String? = nil,
        sort: MarketplaceSort = .featured,
        verifiedOnly: Bool = false,
        contentLanguage: MarketplaceContentLanguage = .system
    ) {
        self.category = category
        self.sort = sort
        self.verifiedOnly = verifiedOnly
        self.contentLanguage = contentLanguage
    }
}

nonisolated struct MarketplaceTheme: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var title: String
    var summary: String
    var creatorName: String
    var category: String
    var previewURL: URL?
    var isVerified: Bool
    var compatibility: MarketplaceCompatibility
    var downloadCount: Int
    var publishedAt: Date
}

nonisolated struct MarketplaceThemeDetails: Identifiable, Hashable, Codable, Sendable {
    var id: UUID { theme.id }
    var theme: MarketplaceTheme
    var description: String
    var semanticVersion: String
    var includedRoles: [String]
    var screenshotURLs: [URL]
    var packageSHA256: String?
}

nonisolated enum MarketplaceServiceError: LocalizedError, Equatable, Sendable {
    case configurationMissing
    case invalidResponse
    case offline
    case themeUnavailable
    case packageInvalid(String)

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            L10n.text(
                "Supabase is not configured. The preview catalog is available instead.",
                "Supabase не настроен. Вместо него доступен демонстрационный каталог."
            )
        case .invalidResponse:
            L10n.text(
                "Marketplace returned an invalid response.",
                "Маркетплейс вернул некорректный ответ."
            )
        case .offline:
            L10n.marketplaceOfflineDetail
        case .themeUnavailable:
            L10n.text(
                "This theme is no longer available.",
                "Эта тема больше недоступна."
            )
        case .packageInvalid(let reason):
            "\(L10n.packageValidationFailed) \(reason)"
        }
    }
}

nonisolated struct MarketplacePackageManifest: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var themeID: UUID
    var name: String
    var semanticVersion: String
    var cursors: [MarketplacePackageCursor]
}

nonisolated struct MarketplacePackageCursor: Codable, Hashable, Sendable {
    var role: String
    var asset: String
    var pixelWidth: Int
    var pixelHeight: Int
    var pointWidth: Double?
    var pointHeight: Double?
    var hotspotX: Double
    var hotspotY: Double
}

nonisolated enum MarketplaceCursorSizing {
    static let maximumPointDimension = 32.0

    static func normalizedPointSize(
        pixelWidth: Int,
        pixelHeight: Int,
        requestedPointWidth: Double?,
        requestedPointHeight: Double?
    ) -> (width: Double, height: Double) {
        let width = requestedPointWidth.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        } ?? Double(max(pixelWidth, 1))
        let height = requestedPointHeight.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        } ?? Double(max(pixelHeight, 1))
        let scale = min(
            1,
            maximumPointDimension / max(width, height)
        )
        return (
            width: max(width * scale, 1),
            height: max(height * scale, 1)
        )
    }
}

nonisolated struct ValidatedMarketplacePackage: Sendable {
    var rootDirectory: URL
    var cleanupDirectory: URL?
    var manifest: MarketplacePackageManifest
    var sha256: String?
}
