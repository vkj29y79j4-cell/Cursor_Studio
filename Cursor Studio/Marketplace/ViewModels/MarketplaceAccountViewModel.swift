import Combine
import Foundation

@MainActor
final class MarketplaceAccountViewModel: ObservableObject {
    @Published private(set) var account: MarketplaceAccount?
    @Published private(set) var profile: MarketplaceCreatorProfile?
    @Published private(set) var isModerator = false
    @Published private(set) var categories: [MarketplaceCategory] = []
    @Published private(set) var submissions: [MarketplaceCreatorSubmission] = []
    @Published private(set) var moderationQueue: [MarketplaceModerationItem] = []
    @Published private(set) var moderators: [MarketplaceModerator] = []
    @Published private(set) var testedVersionIDs: Set<UUID> = []
    @Published private(set) var isRestoringSession = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    let backendConfigured: Bool

    private let service: SupabaseCreatorService?
    private var hasRestoredSession = false

    init(paths: ApplicationPaths) {
        if let configuration = MarketplaceConfiguration.load() {
            service = SupabaseCreatorService(
                configuration: configuration,
                paths: paths
            )
            backendConfigured = true
        } else {
            service = nil
            backendConfigured = false
        }
    }

    var isSignedIn: Bool {
        account != nil
    }

    func restoreSessionIfNeeded() async {
        guard !hasRestoredSession else { return }
        hasRestoredSession = true
        guard let service else { return }
        isRestoringSession = true
        account = await service.restoreSession()
        isRestoringSession = false
        if account != nil {
            await reloadCreatorData()
        }
    }

    func signIn(email: String, password: String) async -> Bool {
        guard let service else {
            errorMessage = L10n.marketplaceBackendUnavailable
            return false
        }
        return await work {
            self.account = try await service.signIn(
                email: email,
                password: password
            )
            self.noticeMessage = L10n.signedInSuccessfully
            await self.reloadCreatorData()
        }
    }

    func signUp(
        email: String,
        password: String,
        handle: String,
        displayName: String
    ) async -> Bool {
        guard let service else {
            errorMessage = L10n.marketplaceBackendUnavailable
            return false
        }
        return await work {
            let result = try await service.signUp(
                email: email,
                password: password,
                handle: handle,
                displayName: displayName
            )
            switch result {
            case .signedIn(let account):
                self.account = account
                self.noticeMessage = L10n.accountCreated
                await self.reloadCreatorData()
            case .emailConfirmationRequired(let email):
                self.noticeMessage = L10n.confirmEmail(email)
            }
        }
    }

    func signOut() async {
        guard let service else { return }
        isWorking = true
        await service.signOut()
        account = nil
        profile = nil
        isModerator = false
        submissions = []
        moderationQueue = []
        moderators = []
        testedVersionIDs = []
        categories = []
        noticeMessage = L10n.signedOutSuccessfully
        isWorking = false
    }

    func saveProfile(
        handle: String,
        displayName: String,
        bio: String
    ) async -> Bool {
        guard let service else { return false }
        return await work {
            self.profile = try await service.updateProfile(
                handle: handle,
                displayName: displayName,
                bio: bio
            )
            self.noticeMessage = L10n.profileSaved
        }
    }

    func publish(
        theme: CursorTheme,
        request: MarketplacePublishRequest
    ) async -> Bool {
        guard let service else { return false }
        return await work {
            let submission = try await service.publish(
                theme: theme,
                request: request
            )
            self.submissions.insert(submission, at: 0)
            self.noticeMessage = L10n.themeSubmittedForReview
        }
    }

    func reloadCreatorData() async {
        guard let service, account != nil else { return }
        do {
            async let loadedProfile = service.loadProfile()
            async let loadedModeratorStatus = service.moderatorStatus()
            async let loadedCategories = service.categories()
            async let loadedSubmissions = service.creatorSubmissions()
            let (
                profile,
                moderatorStatus,
                categories,
                submissions
            ) = try await (
                loadedProfile,
                loadedModeratorStatus,
                loadedCategories,
                loadedSubmissions
            )
            self.profile = profile
            isModerator = moderatorStatus
            self.categories = categories
            self.submissions = submissions
            if moderatorStatus {
                async let queue = service.moderationQueue()
                async let loadedModerators = service.moderators()
                let (queueResult, moderatorResult) = try await (
                    queue,
                    loadedModerators
                )
                moderationQueue = queueResult
                moderators = moderatorResult
            } else {
                moderationQueue = []
                moderators = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moderate(
        item: MarketplaceModerationItem,
        approve: Bool,
        compatibility: MarketplaceCompatibility,
        note: String
    ) async -> Bool {
        guard let service else { return false }
        return await work {
            try await service.moderate(
                item: item,
                approve: approve,
                compatibility: compatibility,
                note: note
            )
            self.moderationQueue.removeAll { $0.id == item.id }
            self.testedVersionIDs.remove(item.id)
            self.noticeMessage = approve
                ? L10n.themeApproved
                : L10n.themeRejected
        }
    }

    func prepareModerationTest(
        item: MarketplaceModerationItem
    ) async -> ValidatedMarketplacePackage? {
        guard let service, !isWorking else { return nil }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            return try await service.prepareModerationTest(item: item)
        } catch is CancellationError {
            return nil
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func markModerationTested(_ item: MarketplaceModerationItem) {
        testedVersionIDs.insert(item.id)
    }

    func setModerator(handle: String, enabled: Bool) async -> Bool {
        guard let service else { return false }
        return await work {
            try await service.setModerator(handle: handle, enabled: enabled)
            self.moderators = try await service.moderators()
            self.noticeMessage = enabled
                ? L10n.moderatorAdded
                : L10n.moderatorRemoved
        }
    }

    func dismissMessages() {
        errorMessage = nil
        noticeMessage = nil
    }

    private func work(
        _ operation: () async throws -> Void
    ) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await operation()
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
