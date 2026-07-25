import Foundation

nonisolated protocol MarketplaceServing {
    func featuredThemes() async throws -> [MarketplaceTheme]
    func searchThemes(
        query: String,
        filters: MarketplaceFilters
    ) async throws -> [MarketplaceTheme]
    func themeDetails(id: UUID) async throws -> MarketplaceThemeDetails
    func downloadTheme(id: UUID) async throws -> URL
}
