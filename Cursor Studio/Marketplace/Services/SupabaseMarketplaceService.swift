import Foundation

actor SupabaseMarketplaceService: MarketplaceServing {
    private let configuration: MarketplaceConfiguration
    private let session: URLSession
    private var packagePaths: [UUID: String] = [:]
    private var prefersRussian = AppLanguage.runtime == .russian

    init(configuration: MarketplaceConfiguration) {
        self.configuration = configuration
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.urlCache = URLCache(
            memoryCapacity: 32 * 1_024 * 1_024,
            diskCapacity: 128 * 1_024 * 1_024
        )
        sessionConfiguration.requestCachePolicy = .reloadRevalidatingCacheData
        session = URLSession(configuration: sessionConfiguration)
    }

    func featuredThemes() async throws -> [MarketplaceTheme] {
        try await searchThemes(
            query: "",
            filters: MarketplaceFilters(sort: .featured)
        )
    }

    func searchThemes(
        query: String,
        filters: MarketplaceFilters
    ) async throws -> [MarketplaceTheme] {
        prefersRussian = filters.contentLanguage.resolvedAppLanguage == .russian
        var items = [
            URLQueryItem(
                name: "select",
                value: """
                id,title_en,title_ru,description_en,description_ru,is_verified,\
                is_featured,published_at,\
                profiles!themes_owner_id_fkey(display_name),\
                categories(name_en,name_ru),\
                theme_versions!themes_current_version_fk(\
                id,semantic_version,package_path,package_sha256,\
                minimum_macos_major,maximum_tested_macos_major,compatibility,\
                preview_paths,review_status)
                """
            ),
            URLQueryItem(name: "publication_status", value: "eq.published"),
            URLQueryItem(name: "limit", value: "60"),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let escaped = trimmed.replacingOccurrences(of: ",", with: " ")
            items.append(
                URLQueryItem(
                    name: "or",
                    value: "(title_en.ilike.*\(escaped)*,title_ru.ilike.*\(escaped)*,description_en.ilike.*\(escaped)*)"
                )
            )
        }
        switch filters.sort {
        case .featured:
            items.append(
                URLQueryItem(
                    name: "order",
                    value: "is_featured.desc,published_at.desc"
                )
            )
        case .recent:
            items.append(URLQueryItem(name: "order", value: "published_at.desc"))
        case .popular:
            items.append(
                URLQueryItem(
                    name: "order",
                    value: "is_featured.desc,published_at.desc"
                )
            )
        }
        if filters.verifiedOnly {
            items.append(URLQueryItem(name: "is_verified", value: "eq.true"))
        }

        let data = try await requestData(
            path: "/rest/v1/themes",
            queryItems: items
        )
        let currentMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        var themes = try Self.decodeCatalogPayload(
            data,
            prefersRussian: prefersRussian,
            currentMacOSMajor: currentMajor,
            projectURL: configuration.projectURL
        )
        if let category = filters.category {
            themes = themes.filter { $0.category == category }
        }
        if filters.sort == .popular {
            themes.sort { $0.downloadCount > $1.downloadCount }
        }
        return themes
    }

    func themeDetails(id: UUID) async throws -> MarketplaceThemeDetails {
        let rows: [ThemeRow] = try await request(
            path: "/rest/v1/themes",
            queryItems: [
                URLQueryItem(
                    name: "select",
                    value: """
                    id,title_en,title_ru,description_en,description_ru,is_verified,\
                    is_featured,published_at,\
                    profiles!themes_owner_id_fkey(display_name),\
                    categories(name_en,name_ru),\
                    theme_versions!themes_current_version_fk(\
                    id,semantic_version,package_path,package_sha256,\
                    minimum_macos_major,maximum_tested_macos_major,compatibility,\
                    preview_paths,manifest,review_status)
                    """
                ),
                URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
                URLQueryItem(name: "publication_status", value: "eq.published"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        guard let row = rows.first,
              let theme = row.marketplaceTheme(
                prefersRussian: AppLanguage.selected.resolved == .russian,
                currentMacOSMajor: ProcessInfo.processInfo
                    .operatingSystemVersion.majorVersion,
                projectURL: configuration.projectURL
              ),
              let version = row.currentVersion else {
            throw MarketplaceServiceError.themeUnavailable
        }
        packagePaths[id] = version.packagePath
        let russian = prefersRussian
        return MarketplaceThemeDetails(
            theme: theme,
            description: russian
                ? row.descriptionRU ?? row.descriptionEN
                : row.descriptionEN,
            semanticVersion: version.semanticVersion,
            includedRoles: version.manifest?.cursors?.map(\.role) ?? [],
            screenshotURLs: version.previewPaths.compactMap {
                Self.publicPreviewURL(
                    projectURL: configuration.projectURL,
                    path: $0
                )
            },
            packageSHA256: version.packageSHA256
        )
    }

    func downloadTheme(id: UUID) async throws -> URL {
        if packagePaths[id] == nil {
            _ = try await themeDetails(id: id)
        }
        guard let packagePath = packagePaths[id] else {
            throw MarketplaceServiceError.themeUnavailable
        }
        let encodedPath = packagePath
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "" }
            .joined(separator: "/")
        let url = configuration.projectURL
            .appending(path: "storage/v1/object/theme-packages")
            .appending(path: encodedPath)
        var request = URLRequest(url: url)
        addPublicHeaders(to: &request)

        do {
            let (temporaryURL, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                throw MarketplaceServiceError.themeUnavailable
            }
            let destination = FileManager.default.temporaryDirectory.appending(
                path: "\(UUID().uuidString).cursorstudio-theme"
            )
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            return destination
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MarketplaceServiceError {
            throw error
        } catch {
            throw MarketplaceServiceError.offline
        }
    }

    private func request<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> T {
        let data = try await requestData(path: path, queryItems: queryItems)
        do {
            return try Self.decoder().decode(T.self, from: data)
        } catch {
            throw MarketplaceServiceError.invalidResponse
        }
    }

    private func requestData(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Data {
        var components = URLComponents(
            url: configuration.projectURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw MarketplaceServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        addPublicHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                throw MarketplaceServiceError.invalidResponse
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MarketplaceServiceError {
            throw error
        } catch {
            throw MarketplaceServiceError.offline
        }
    }

    nonisolated static func decodeCatalogPayload(
        _ data: Data,
        prefersRussian: Bool,
        currentMacOSMajor: Int,
        projectURL: URL
    ) throws -> [MarketplaceTheme] {
        let rows = try decoder().decode([ThemeRow].self, from: data)
        return rows.compactMap {
            $0.marketplaceTheme(
                prefersRussian: prefersRussian,
                currentMacOSMajor: currentMacOSMajor,
                projectURL: projectURL
            )
        }
    }

    nonisolated private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func addPublicHeaders(to request: inout URLRequest) {
        request.setValue(
            configuration.publishableKey,
            forHTTPHeaderField: "apikey"
        )
        if configuration.publishableKey.split(separator: ".").count == 3 {
            request.setValue(
                "Bearer \(configuration.publishableKey)",
                forHTTPHeaderField: "Authorization"
            )
        }
    }

    nonisolated fileprivate static func publicPreviewURL(
        projectURL: URL,
        path: String
    ) -> URL? {
        let encoded = path
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "" }
            .joined(separator: "/")
        return projectURL
            .appending(path: "storage/v1/object/public/theme-previews")
            .appending(path: encoded)
    }
}

nonisolated private struct ThemeRow: Decodable, Sendable {
    let id: UUID
    let titleEN: String
    let titleRU: String?
    let descriptionEN: String
    let descriptionRU: String?
    let isVerified: Bool
    let isFeatured: Bool
    let publishedAt: Date
    let profiles: ProfileRow?
    let categories: CategoryRow?
    let currentVersion: VersionRow?

    enum CodingKeys: String, CodingKey {
        case id
        case titleEN = "title_en"
        case titleRU = "title_ru"
        case descriptionEN = "description_en"
        case descriptionRU = "description_ru"
        case isVerified = "is_verified"
        case isFeatured = "is_featured"
        case publishedAt = "published_at"
        case profiles
        case categories
        case currentVersion = "theme_versions"
    }

    func marketplaceTheme(
        prefersRussian: Bool,
        currentMacOSMajor: Int,
        projectURL: URL
    ) -> MarketplaceTheme? {
        guard let version = currentVersion,
              version.reviewStatus == "approved" else {
            return nil
        }
        let title = prefersRussian ? titleRU ?? titleEN : titleEN
        let description = prefersRussian
            ? descriptionRU ?? descriptionEN
            : descriptionEN
        let category = prefersRussian
            ? categories?.nameRU ?? categories?.nameEN
            : categories?.nameEN
        let compatibility: MarketplaceCompatibility
        if currentMacOSMajor < version.minimumMacOSMajor {
            compatibility = .incompatible
        } else if let maximum = version.maximumTestedMacOSMajor,
                  currentMacOSMajor > maximum {
            compatibility = .unknown
        } else {
            compatibility = MarketplaceCompatibility(
                rawValue: version.compatibility
            ) ?? .unknown
        }
        return MarketplaceTheme(
            id: id,
            title: title,
            summary: description,
            creatorName: profiles?.displayName ?? "—",
            category: category ?? "—",
            previewURL: version.previewPaths.first.flatMap {
                SupabaseMarketplaceService.publicPreviewURL(
                    projectURL: projectURL,
                    path: $0
                )
            },
            isVerified: isVerified,
            compatibility: compatibility,
            downloadCount: 0,
            publishedAt: publishedAt
        )
    }
}

nonisolated private struct ProfileRow: Decodable, Sendable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

nonisolated private struct CategoryRow: Decodable, Sendable {
    let nameEN: String
    let nameRU: String

    enum CodingKeys: String, CodingKey {
        case nameEN = "name_en"
        case nameRU = "name_ru"
    }
}

nonisolated private struct VersionRow: Decodable, Sendable {
    let id: UUID
    let semanticVersion: String
    let packagePath: String
    let packageSHA256: String
    let minimumMacOSMajor: Int
    let maximumTestedMacOSMajor: Int?
    let compatibility: String
    let previewPaths: [String]
    let reviewStatus: String
    let manifest: ManifestRow?

    enum CodingKeys: String, CodingKey {
        case id
        case semanticVersion = "semantic_version"
        case packagePath = "package_path"
        case packageSHA256 = "package_sha256"
        case minimumMacOSMajor = "minimum_macos_major"
        case maximumTestedMacOSMajor = "maximum_tested_macos_major"
        case compatibility
        case previewPaths = "preview_paths"
        case reviewStatus = "review_status"
        case manifest
    }
}

nonisolated private struct ManifestRow: Decodable, Sendable {
    let cursors: [ManifestCursorRow]?
}

nonisolated private struct ManifestCursorRow: Decodable, Sendable {
    let role: String
}
