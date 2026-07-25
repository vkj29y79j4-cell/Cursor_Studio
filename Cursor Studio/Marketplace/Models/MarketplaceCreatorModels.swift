import Foundation

nonisolated struct MarketplaceAccount: Identifiable, Hashable, Sendable {
    let id: UUID
    let email: String
}

nonisolated struct MarketplaceCreatorProfile: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var handle: String
    var displayName: String
    var bio: String?
    var avatarPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case bio
        case avatarPath = "avatar_path"
    }
}

nonisolated struct MarketplaceCategory: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let slug: String
    let nameEN: String
    let nameRU: String
    let sortOrder: Int

    var displayName: String {
        AppLanguage.runtime == .russian ? nameRU : nameEN
    }

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case nameEN = "name_en"
        case nameRU = "name_ru"
        case sortOrder = "sort_order"
    }
}

nonisolated enum MarketplaceReviewStatus: String, Codable, Sendable {
    case draft
    case pending
    case approved
    case rejected

    var displayName: String {
        switch self {
        case .draft: L10n.reviewDraft
        case .pending: L10n.reviewPending
        case .approved: L10n.reviewApproved
        case .rejected: L10n.reviewRejected
        }
    }
}

nonisolated struct MarketplaceCreatorSubmission: Identifiable, Hashable, Sendable {
    let id: UUID
    let themeID: UUID
    let title: String
    let semanticVersion: String
    let status: MarketplaceReviewStatus
    let submittedAt: Date
}

nonisolated struct MarketplaceModerationItem: Identifiable, Hashable, Sendable {
    var id: UUID { versionID }
    let versionID: UUID
    let themeID: UUID
    let title: String
    let description: String
    let creatorName: String
    let creatorHandle: String
    let semanticVersion: String
    let includedRoles: [String]
    let submittedAt: Date
    let packagePath: String
    let packageSHA256: String
    let previewURL: URL?
}

nonisolated struct MarketplaceModerator: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let handle: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
    }
}

nonisolated struct MarketplacePublishRequest: Hashable, Sendable {
    var titleEN: String
    var titleRU: String
    var descriptionEN: String
    var descriptionRU: String
    var semanticVersion: String
    var categoryID: UUID
}

nonisolated enum MarketplaceSignUpResult: Sendable {
    case signedIn(MarketplaceAccount)
    case emailConfirmationRequired(String)
}

nonisolated enum MarketplaceBackendError: LocalizedError, Equatable, Sendable {
    case configurationMissing
    case authenticationRequired
    case invalidCredentials
    case emailConfirmationRequired
    case invalidInput(String)
    case server(String)
    case invalidResponse
    case offline

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            L10n.marketplaceBackendUnavailable
        case .authenticationRequired:
            L10n.authenticationRequired
        case .invalidCredentials:
            L10n.invalidCredentials
        case .emailConfirmationRequired:
            L10n.emailConfirmationRequired
        case .invalidInput(let message), .server(let message):
            message
        case .invalidResponse:
            L10n.marketplaceInvalidResponse
        case .offline:
            L10n.marketplaceOfflineDetail
        }
    }
}

nonisolated struct PreparedMarketplaceUpload: Sendable {
    let packageURL: URL
    let previewURL: URL
    let cleanupDirectory: URL
    let packageSHA256: String
    let packageBytes: Int64
    let manifest: MarketplacePackageManifest
}
