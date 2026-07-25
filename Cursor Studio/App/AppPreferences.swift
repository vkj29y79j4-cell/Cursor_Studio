import Combine
import Foundation
import ServiceManagement

nonisolated enum MarketplaceContentLanguage:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case system
    case english
    case russian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: L10n.systemDefault
        case .english: L10n.english
        case .russian: L10n.russian
        }
    }

    var resolvedAppLanguage: AppLanguage {
        switch self {
        case .system: AppLanguage.runtime
        case .english: .english
        case .russian: .russian
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    let launchedLanguage: AppLanguage

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: AppLanguage.defaultsKey)
            Self.configureSystemLanguageOverride(
                language,
                defaults: defaults
            )
        }
    }
    @Published private(set) var launchAtLogin: Bool
    @Published var keepCursorActiveWhenWindowClosed: Bool {
        didSet { defaults.set(keepCursorActiveWhenWindowClosed, forKey: Keys.keepCursorActive) }
    }
    @Published var keepCursorActiveAfterAppQuit: Bool {
        didSet {
            defaults.set(
                keepCursorActiveAfterAppQuit,
                forKey: Keys.keepCursorActiveAfterAppQuit
            )
            if keepCursorActiveAfterAppQuit {
                keepCursorActiveWhenWindowClosed = true
            }
        }
    }
    @Published var confirmBeforeDeletingTheme: Bool {
        didSet { defaults.set(confirmBeforeDeletingTheme, forKey: Keys.confirmDelete) }
    }
    @Published var autoRecoverCursor: Bool {
        didSet { defaults.set(autoRecoverCursor, forKey: Keys.autoRecover) }
    }
    @Published var marketplaceAutoUpdates: Bool {
        didSet { defaults.set(marketplaceAutoUpdates, forKey: Keys.marketplaceAutoUpdates) }
    }
    @Published var marketplaceContentLanguage: MarketplaceContentLanguage {
        didSet {
            defaults.set(
                marketplaceContentLanguage.rawValue,
                forKey: Keys.marketplaceContentLanguage
            )
        }
    }
    @Published var verifiedOnly: Bool {
        didSet { defaults.set(verifiedOnly, forKey: Keys.verifiedOnly) }
    }
    @Published private(set) var onboardingCompleted: Bool

    private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        launchAtLoginOverride: Bool? = nil
    ) {
        self.defaults = defaults
        let storedLanguage = AppLanguage(
            rawValue: defaults.string(forKey: AppLanguage.defaultsKey) ?? ""
        ) ?? .system
        launchedLanguage = storedLanguage
        language = storedLanguage
        launchAtLogin = launchAtLoginOverride
            ?? (SMAppService.mainApp.status == .enabled)
        keepCursorActiveWhenWindowClosed = defaults.object(
            forKey: Keys.keepCursorActive
        ) as? Bool ?? true
        keepCursorActiveAfterAppQuit = defaults.object(
            forKey: Keys.keepCursorActiveAfterAppQuit
        ) as? Bool ?? false
        confirmBeforeDeletingTheme = defaults.object(
            forKey: Keys.confirmDelete
        ) as? Bool ?? true
        autoRecoverCursor = defaults.object(
            forKey: Keys.autoRecover
        ) as? Bool ?? true
        marketplaceAutoUpdates = defaults.object(
            forKey: Keys.marketplaceAutoUpdates
        ) as? Bool ?? false
        marketplaceContentLanguage = MarketplaceContentLanguage(
            rawValue: defaults.string(forKey: Keys.marketplaceContentLanguage) ?? ""
        ) ?? .system
        verifiedOnly = defaults.object(forKey: Keys.verifiedOnly) as? Bool ?? false
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        Self.configureSystemLanguageOverride(
            storedLanguage,
            defaults: defaults
        )
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func markOnboardingCompleted() {
        onboardingCompleted = true
        defaults.set(true, forKey: Keys.onboardingCompleted)
    }

    func requestOnboardingAgain() {
        onboardingCompleted = false
    }

    private enum Keys {
        static let keepCursorActive = "keepCursorActiveWhenWindowClosed"
        static let keepCursorActiveAfterAppQuit =
            "keepCursorActiveAfterAppQuit"
        static let confirmDelete = "confirmBeforeDeletingTheme"
        static let autoRecover = "autoRecoverCursor"
        static let marketplaceAutoUpdates = "marketplaceAutoUpdates"
        static let marketplaceContentLanguage = "marketplaceContentLanguage"
        static let verifiedOnly = "marketplaceVerifiedOnly"
        static let onboardingCompleted = "onboardingCompleted"
    }

    private static func configureSystemLanguageOverride(
        _ language: AppLanguage,
        defaults: UserDefaults
    ) {
        switch language {
        case .system:
            defaults.removeObject(forKey: "AppleLanguages")
        case .english:
            defaults.set(["en"], forKey: "AppleLanguages")
        case .russian:
            defaults.set(["ru"], forKey: "AppleLanguages")
        }
        defaults.synchronize()
    }
}
