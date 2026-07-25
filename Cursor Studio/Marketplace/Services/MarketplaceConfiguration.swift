import Foundation

nonisolated struct MarketplaceConfiguration: Sendable {
    let projectURL: URL
    let publishableKey: String

    static func load(bundle: Bundle = .main) -> MarketplaceConfiguration? {
        guard let url = bundle.url(
            forResource: "MarketplaceConfiguration",
            withExtension: "plist"
        ),
        let data = try? Data(contentsOf: url),
        let object = try? PropertyListSerialization.propertyList(
            from: data,
            format: nil
        ),
        let dictionary = object as? [String: Any],
        let rawURL = dictionary["SUPABASE_URL"] as? String,
        let projectURL = URL(string: rawURL),
        projectURL.scheme == "https",
        let key = dictionary["SUPABASE_PUBLISHABLE_KEY"] as? String,
        !key.isEmpty,
        !key.contains("PROJECT_"),
        !key.lowercased().contains("service_role") else {
            return nil
        }
        return MarketplaceConfiguration(
            projectURL: projectURL,
            publishableKey: key
        )
    }
}

enum MarketplaceServiceFactory {
    static func make() -> any MarketplaceServing & Sendable {
        if let configuration = MarketplaceConfiguration.load() {
            return SupabaseMarketplaceService(configuration: configuration)
        }
        return MockMarketplaceService()
    }
}
