import Combine
import Foundation

@MainActor
final class MarketplaceViewModel: ObservableObject {
    @Published var query = ""
    @Published var filters: MarketplaceFilters
    @Published private(set) var themes: [MarketplaceTheme] = []
    @Published var selectedTheme: MarketplaceTheme?
    @Published private(set) var details: MarketplaceThemeDetails?
    @Published private(set) var isLoading = false
    @Published private(set) var isOffline = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var installProgress: Double?
    @Published private(set) var installingThemeID: UUID?
    @Published private(set) var installedThemeID: UUID?
    @Published private(set) var cursorPreviews: [MarketplaceCursorPreview] = []
    @Published private(set) var isLoadingCursorPreviews = false
    @Published private(set) var cursorPreviewMessage: String?

    let usesMockService: Bool

    private let service: any MarketplaceServing & Sendable
    private let cache: MarketplaceCatalogCache
    private let validator: MarketplacePackageValidator
    private let installer: MarketplaceInstaller
    private var searchTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var detailsTask: Task<Void, Never>?
    private var lastInstallTheme: MarketplaceTheme?
    private var previewLease: MarketplacePackagePreviewLease?
    private var previewThemeID: UUID?
    private var detailsRequestID = UUID()

    init(
        store: ThemeStore,
        paths: ApplicationPaths,
        preferences: AppPreferences,
        service: (any MarketplaceServing & Sendable)? = nil
    ) {
        let resolvedService = service ?? MarketplaceServiceFactory.make()
        self.service = resolvedService
        usesMockService = resolvedService is MockMarketplaceService
        cache = MarketplaceCatalogCache(paths: paths)
        validator = MarketplacePackageValidator(paths: paths)
        installer = MarketplaceInstaller(store: store, paths: paths)
        filters = MarketplaceFilters(
            verifiedOnly: preferences.verifiedOnly,
            contentLanguage: preferences.marketplaceContentLanguage
        )
    }

    func load() {
        guard themes.isEmpty, !isLoading else { return }
        search(immediately: true)
    }

    func search(immediately: Bool = false) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: .milliseconds(280))
            }
            guard !Task.isCancelled, let self else { return }
            await self.performSearch()
        }
    }

    func selectCategory(_ category: String?) {
        filters.category = category
        search(immediately: true)
    }

    func selectSort(_ sort: MarketplaceSort) {
        filters.sort = sort
        search(immediately: true)
    }

    func openDetails(for theme: MarketplaceTheme) {
        selectedTheme = theme
        if previewThemeID == theme.id,
           details?.theme.id == theme.id,
           !cursorPreviews.isEmpty {
            return
        }
        details = nil
        detailsTask?.cancel()
        let requestID = UUID()
        detailsRequestID = requestID
        previewLease = nil
        previewThemeID = nil
        cursorPreviews = []
        cursorPreviewMessage = nil
        isLoadingCursorPreviews = true
        detailsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let details = try await self.service.themeDetails(id: theme.id)
                try Task.checkCancellation()
                guard self.detailsRequestID == requestID else { return }
                self.details = details
                await self.loadCursorPreviews(
                    for: theme,
                    expectedSHA256: details.packageSHA256,
                    requestID: requestID
                )
            } catch is CancellationError {
                if self.detailsRequestID == requestID {
                    self.isLoadingCursorPreviews = false
                }
                return
            } catch {
                if self.detailsRequestID == requestID {
                    self.isLoadingCursorPreviews = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func install(_ theme: MarketplaceTheme) {
        installTask?.cancel()
        lastInstallTheme = theme
        installingThemeID = theme.id
        installProgress = 0.08
        errorMessage = nil
        installedThemeID = nil

        installTask = Task { [weak self] in
            guard let self else { return }
            var downloadedURL: URL?
            var extractedCleanupURL: URL?
            defer {
                if let downloadedURL {
                    try? FileManager.default.removeItem(at: downloadedURL)
                }
                if let extractedCleanupURL,
                   extractedCleanupURL != downloadedURL {
                    try? FileManager.default.removeItem(at: extractedCleanupURL)
                }
            }
            do {
                let details = try await self.service.themeDetails(id: theme.id)
                try Task.checkCancellation()
                self.installProgress = 0.18

                let packageURL = try await self.service.downloadTheme(id: theme.id)
                downloadedURL = packageURL
                try Task.checkCancellation()
                self.installProgress = 0.55

                let validated = try await self.validator.validatePackage(
                    at: packageURL,
                    expectedSHA256: details.packageSHA256
                )
                extractedCleanupURL = validated.cleanupDirectory
                try Task.checkCancellation()
                self.installProgress = 0.82

                let installed = try self.installer.install(validated)
                self.installProgress = 1
                self.installedThemeID = installed.id
                try? await Task.sleep(for: .milliseconds(450))
                self.installProgress = nil
                self.installingThemeID = nil
            } catch is CancellationError {
                self.installProgress = nil
                self.installingThemeID = nil
            } catch {
                self.installProgress = nil
                self.installingThemeID = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
        installProgress = nil
        installingThemeID = nil
    }

    func retryInstall() {
        if let lastInstallTheme {
            install(lastInstallTheme)
        }
    }

    func clearInstalledThemeID() {
        installedThemeID = nil
    }

    func updatePreferences(_ preferences: AppPreferences) {
        let changed = filters.verifiedOnly != preferences.verifiedOnly
            || filters.contentLanguage != preferences.marketplaceContentLanguage
        filters.verifiedOnly = preferences.verifiedOnly
        filters.contentLanguage = preferences.marketplaceContentLanguage
        if changed {
            search(immediately: true)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func loadCursorPreviews(
        for theme: MarketplaceTheme,
        expectedSHA256: String?,
        requestID: UUID
    ) async {
        var downloadedURL: URL?
        var cleanupURL: URL?
        do {
            let packageURL = try await service.downloadTheme(id: theme.id)
            downloadedURL = packageURL
            try Task.checkCancellation()

            let validated = try await validator.validatePackage(
                at: packageURL,
                expectedSHA256: expectedSHA256
            )
            cleanupURL = validated.cleanupDirectory
            try Task.checkCancellation()
            guard detailsRequestID == requestID else {
                throw CancellationError()
            }

            let previews = MarketplacePackagePreviewBuilder.previews(
                from: validated
            )
            guard !previews.isEmpty else {
                throw MarketplaceServiceError.packageInvalid(
                    L10n.text(
                        "The package has no cursor previews.",
                        "В пакете нет курсоров для предпросмотра."
                    )
                )
            }

            let lease = MarketplacePackagePreviewLease(
                previews: previews,
                cleanupURL: cleanupURL
            )
            cleanupURL = nil
            if let downloadedURL,
               downloadedURL.standardizedFileURL
                != validated.rootDirectory.standardizedFileURL {
                try? FileManager.default.removeItem(at: downloadedURL)
            }
            self.previewLease = lease
            self.previewThemeID = theme.id
            self.cursorPreviews = previews
            self.cursorPreviewMessage = nil
            self.isLoadingCursorPreviews = false
        } catch is CancellationError {
            if let cleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            } else if let downloadedURL {
                try? FileManager.default.removeItem(at: downloadedURL)
            }
            if detailsRequestID == requestID {
                isLoadingCursorPreviews = false
            }
        } catch {
            if let cleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            } else if let downloadedURL {
                try? FileManager.default.removeItem(at: downloadedURL)
            }
            if detailsRequestID == requestID {
                cursorPreviewMessage = L10n.text(
                    "Cursor previews are unavailable: \(error.localizedDescription)",
                    "Предпросмотр курсоров недоступен: \(error.localizedDescription)"
                )
                isLoadingCursorPreviews = false
            }
        }
    }

    private func performSearch() async {
        isLoading = themes.isEmpty
        errorMessage = nil
        let key = cacheKey
        do {
            let results = try await service.searchThemes(
                query: query,
                filters: filters
            )
            guard !Task.isCancelled else { return }
            themes = results
            isOffline = false
            isLoading = false
            await cache.save(results, key: key)
        } catch is CancellationError {
            isLoading = false
        } catch {
            if let cached = await cache.load(key: key) {
                themes = cached
                isOffline = true
            } else {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private var cacheKey: String {
        [
            query.lowercased(),
            filters.category ?? "*",
            filters.sort.rawValue,
            filters.verifiedOnly.description,
            filters.contentLanguage.resolvedAppLanguage.rawValue,
        ].joined(separator: "|")
    }
}

@MainActor
private final class MarketplacePackagePreviewLease {
    let previews: [MarketplaceCursorPreview]
    private let cleanupURL: URL?

    init(
        previews: [MarketplaceCursorPreview],
        cleanupURL: URL?
    ) {
        self.previews = previews
        self.cleanupURL = cleanupURL
    }

    deinit {
        if let cleanupURL {
            try? FileManager.default.removeItem(at: cleanupURL)
        }
    }
}
