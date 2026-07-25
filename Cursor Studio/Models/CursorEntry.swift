import Foundation

nonisolated struct CursorEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var role: CursorRole
    var assetFilename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var hotspot: CursorHotspot
    var modifiedAt: Date
    var pointWidth: Double
    var pointHeight: Double
    var frameCount: Int
    var frameDuration: Double
    var representations: [CursorRepresentation]
    var sourceIdentifier: String?
    var animationFallbackReason: String?

    init(
        id: UUID = UUID(),
        role: CursorRole,
        assetFilename: String,
        pixelWidth: Int,
        pixelHeight: Int,
        hotspot: CursorHotspot = .topLeft,
        modifiedAt: Date = .now,
        pointWidth: Double? = nil,
        pointHeight: Double? = nil,
        frameCount: Int = 1,
        frameDuration: Double = 0,
        representations: [CursorRepresentation] = [],
        sourceIdentifier: String? = nil,
        animationFallbackReason: String? = nil
    ) {
        self.id = id
        self.role = role
        self.assetFilename = assetFilename
        self.pixelWidth = max(pixelWidth, 1)
        self.pixelHeight = max(pixelHeight, 1)
        self.hotspot = hotspot
        self.modifiedAt = modifiedAt
        self.pointWidth = max(pointWidth ?? Double(pixelWidth), 1)
        self.pointHeight = max(pointHeight ?? Double(pixelHeight), 1)
        self.frameCount = max(frameCount, 1)
        self.frameDuration = max(frameDuration, 0)
        self.representations = representations
        self.sourceIdentifier = sourceIdentifier
        self.animationFallbackReason = animationFallbackReason
    }

    var isAnimated: Bool {
        frameCount > 1
    }

    var usesStaticAnimationFallback: Bool {
        animationFallbackReason != nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case assetFilename
        case pixelWidth
        case pixelHeight
        case hotspot
        case modifiedAt
        case pointWidth
        case pointHeight
        case frameCount
        case frameDuration
        case representations
        case sourceIdentifier
        case animationFallbackReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(CursorRole.self, forKey: .role)
        assetFilename = try container.decode(String.self, forKey: .assetFilename)
        pixelWidth = max(
            try container.decodeIfPresent(Int.self, forKey: .pixelWidth) ?? 1,
            1
        )
        pixelHeight = max(
            try container.decodeIfPresent(Int.self, forKey: .pixelHeight) ?? 1,
            1
        )
        hotspot = try container.decodeIfPresent(
            CursorHotspot.self,
            forKey: .hotspot
        ) ?? .topLeft
        modifiedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .modifiedAt
        ) ?? .now
        pointWidth = max(
            try container.decodeIfPresent(Double.self, forKey: .pointWidth)
                ?? Double(pixelWidth),
            1
        )
        pointHeight = max(
            try container.decodeIfPresent(Double.self, forKey: .pointHeight)
                ?? Double(pixelHeight),
            1
        )
        frameCount = max(
            try container.decodeIfPresent(Int.self, forKey: .frameCount) ?? 1,
            1
        )
        frameDuration = max(
            try container.decodeIfPresent(Double.self, forKey: .frameDuration)
                ?? 0,
            0
        )
        representations = try container.decodeIfPresent(
            [CursorRepresentation].self,
            forKey: .representations
        ) ?? []
        sourceIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .sourceIdentifier
        )
        animationFallbackReason = try container.decodeIfPresent(
            String.self,
            forKey: .animationFallbackReason
        )
    }
}
