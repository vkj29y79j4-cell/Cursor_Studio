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

nonisolated struct MarketplaceCursorPreview:
    Identifiable,
    Hashable,
    Sendable
{
    var id: CursorRole { role }
    var role: CursorRole
    var assetURL: URL
    var animationStripURL: URL?
    var pixelWidth: Int
    var pixelHeight: Int
    var frameCount: Int
    var frameDuration: Double
    var usesStaticAnimationFallback: Bool
}

nonisolated enum MarketplacePackagePreviewBuilder {
    static func previews(
        from package: ValidatedMarketplacePackage
    ) -> [MarketplaceCursorPreview] {
        package.manifest.cursors.compactMap { cursor in
            guard let role = CursorRole(rawValue: cursor.role) else {
                return nil
            }
            let frameCount = max(cursor.frameCount ?? 1, 1)
            let usesStaticFallback =
                cursor.usesStaticAnimationFallback == true || frameCount > 24
            let preferredRepresentation = (cursor.representations ?? []).min {
                let leftDistance = abs($0.scale - 2)
                let rightDistance = abs($1.scale - 2)
                if leftDistance == rightDistance {
                    return $0.scale > $1.scale
                }
                return leftDistance < rightDistance
            }
            let animationStripURL =
                frameCount > 1 && !usesStaticFallback
                ? preferredRepresentation.map {
                    package.rootDirectory.appending(path: $0.asset)
                }
                : nil

            return MarketplaceCursorPreview(
                role: role,
                assetURL: package.rootDirectory.appending(
                    path: cursor.asset
                ),
                animationStripURL: animationStripURL,
                pixelWidth: cursor.pixelWidth,
                pixelHeight: cursor.pixelHeight,
                frameCount: frameCount,
                frameDuration: max(cursor.frameDuration ?? 0, 1.0 / 60.0),
                usesStaticAnimationFallback: usesStaticFallback
            )
        }
        .sorted {
            let left = CursorRole.allCases.firstIndex(of: $0.role) ?? 0
            let right = CursorRole.allCases.firstIndex(of: $1.role) ?? 0
            return left < right
        }
    }
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
    // Optional so schema-v1 packages created before animation support continue
    // to decode as static cursors.
    var frameCount: Int? = nil
    var frameDuration: Double? = nil
    var representations: [MarketplacePackageRepresentation]? = nil
    var usesStaticAnimationFallback: Bool? = nil
}

nonisolated struct MarketplacePackageRepresentation:
    Codable,
    Hashable,
    Sendable
{
    var asset: String
    var scale: Double
    var pixelWidth: Int
    var pixelHeight: Int
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
