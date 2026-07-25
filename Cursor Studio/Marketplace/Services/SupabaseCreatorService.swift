import Foundation

actor SupabaseCreatorService {
    private let configuration: MarketplaceConfiguration
    private let session: URLSession
    private let vault: MarketplaceSessionVault
    private let packageBuilder: MarketplacePackageBuilder
    private let packageValidator: MarketplacePackageValidator
    private let fileManager: FileManager
    private var storedSession: MarketplaceStoredSession?

    init(
        configuration: MarketplaceConfiguration,
        paths: ApplicationPaths,
        vault: MarketplaceSessionVault? = nil,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.vault = vault ?? MarketplaceSessionVault(paths: paths)
        self.fileManager = fileManager
        packageBuilder = MarketplacePackageBuilder(
            paths: paths,
            fileManager: fileManager
        )
        packageValidator = MarketplacePackageValidator(paths: paths)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        session = URLSession(configuration: configuration)
    }

    func restoreSession() async -> MarketplaceAccount? {
        do {
            storedSession = try vault.load()
            guard storedSession != nil else { return nil }
            _ = try await validSession()
            let user: AuthUserResponse = try await request(
                path: "auth/v1/user",
                authenticated: true
            )
            guard var current = storedSession else { return nil }
            current = MarketplaceStoredSession(
                accessToken: current.accessToken,
                refreshToken: current.refreshToken,
                expiresAt: current.expiresAt,
                userID: user.id,
                email: user.email
            )
            storedSession = current
            try vault.save(current)
            return current.account
        } catch {
            storedSession = nil
            try? vault.clear()
            return nil
        }
    }

    func signIn(email: String, password: String) async throws -> MarketplaceAccount {
        let normalizedEmail = email.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalizedEmail.contains("@"), !password.isEmpty else {
            throw MarketplaceBackendError.invalidCredentials
        }
        let response: AuthTokenResponse = try await request(
            path: "auth/v1/token",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "grant_type", value: "password"),
            ],
            body: AuthCredentials(
                email: normalizedEmail,
                password: password
            )
        )
        let session = response.storedSession
        storedSession = session
        try vault.save(session)
        return session.account
    }

    func signUp(
        email: String,
        password: String,
        handle: String,
        displayName: String
    ) async throws -> MarketplaceSignUpResult {
        let normalizedEmail = email.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedHandle = handle.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        let normalizedName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalizedEmail.contains("@"),
              password.count >= 8,
              normalizedHandle.range(
                of: #"^[a-z0-9][a-z0-9_-]{2,31}$"#,
                options: .regularExpression
              ) != nil,
              !normalizedName.isEmpty,
              normalizedName.count <= 80 else {
            throw MarketplaceBackendError.invalidInput(
                L10n.registrationFieldsInvalid
            )
        }

        let data = try await rawRequest(
            path: "auth/v1/signup",
            method: "POST",
            body: SignUpCredentials(
                email: normalizedEmail,
                password: password,
                data: SignUpMetadata(
                    preferredUsername: normalizedHandle,
                    fullName: normalizedName
                )
            )
        )
        if let response = try? Self.makeDecoder().decode(
            AuthTokenResponse.self,
            from: data
        ) {
            let session = response.storedSession
            storedSession = session
            try vault.save(session)
            return .signedIn(session.account)
        }
        if let response = try? Self.makeDecoder().decode(
            SignUpResponse.self,
            from: data
        ),
        let user = response.user ?? response.directUser {
            return .emailConfirmationRequired(user.email)
        }
        throw MarketplaceBackendError.invalidResponse
    }

    func signOut() async {
        if storedSession != nil {
            _ = try? await rawRequest(
                path: "auth/v1/logout",
                method: "POST",
                authenticated: true
            )
        }
        storedSession = nil
        try? vault.clear()
    }

    func loadProfile() async throws -> MarketplaceCreatorProfile {
        let account = try await validSession().account
        let rows: [MarketplaceCreatorProfile] = try await request(
            path: "rest/v1/profiles",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(account.id.uuidString.lowercased())"),
                URLQueryItem(
                    name: "select",
                    value: "id,handle,display_name,bio,avatar_path"
                ),
                URLQueryItem(name: "limit", value: "1"),
            ],
            authenticated: true
        )
        guard let profile = rows.first else {
            throw MarketplaceBackendError.invalidResponse
        }
        return profile
    }

    func updateProfile(
        handle: String,
        displayName: String,
        bio: String
    ) async throws -> MarketplaceCreatorProfile {
        let account = try await validSession().account
        let normalizedHandle = handle.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        let normalizedName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let normalizedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedHandle.range(
            of: #"^[a-z0-9][a-z0-9_-]{2,31}$"#,
            options: .regularExpression
        ) != nil,
        !normalizedName.isEmpty,
        normalizedName.count <= 80,
        normalizedBio.count <= 500 else {
            throw MarketplaceBackendError.invalidInput(
                L10n.profileFieldsInvalid
            )
        }
        let rows: [MarketplaceCreatorProfile] = try await request(
            path: "rest/v1/profiles",
            method: "PATCH",
            queryItems: [
                URLQueryItem(name: "id", value: "eq.\(account.id.uuidString.lowercased())"),
                URLQueryItem(
                    name: "select",
                    value: "id,handle,display_name,bio,avatar_path"
                ),
            ],
            body: ProfileUpdate(
                handle: normalizedHandle,
                displayName: normalizedName,
                bio: normalizedBio.isEmpty ? nil : normalizedBio
            ),
            authenticated: true,
            prefer: "return=representation"
        )
        guard let profile = rows.first else {
            throw MarketplaceBackendError.invalidResponse
        }
        return profile
    }

    func moderatorStatus() async throws -> Bool {
        try await request(
            path: "rest/v1/rpc/is_marketplace_moderator",
            method: "POST",
            body: EmptyBody(),
            authenticated: true
        )
    }

    func categories() async throws -> [MarketplaceCategory] {
        try await request(
            path: "rest/v1/categories",
            queryItems: [
                URLQueryItem(name: "is_active", value: "eq.true"),
                URLQueryItem(
                    name: "select",
                    value: "id,slug,name_en,name_ru,sort_order"
                ),
                URLQueryItem(name: "order", value: "sort_order.asc"),
            ],
            authenticated: true
        )
    }

    func creatorSubmissions() async throws -> [MarketplaceCreatorSubmission] {
        let account = try await validSession().account
        let rows: [CreatorThemeRow] = try await request(
            path: "rest/v1/themes",
            queryItems: [
                URLQueryItem(name: "owner_id", value: "eq.\(account.id.uuidString.lowercased())"),
                URLQueryItem(
                    name: "select",
                    value: "id,title_en,title_ru,theme_versions!theme_versions_theme_id_fkey(id,semantic_version,review_status,created_at)"
                ),
                URLQueryItem(name: "order", value: "updated_at.desc"),
            ],
            authenticated: true
        )
        return rows.flatMap { row in
            row.versions.map { version in
                MarketplaceCreatorSubmission(
                    id: version.id,
                    themeID: row.id,
                    title: AppLanguage.runtime == .russian
                        ? row.titleRU ?? row.titleEN
                        : row.titleEN,
                    semanticVersion: version.semanticVersion,
                    status: version.reviewStatus,
                    submittedAt: version.createdAt
                )
            }
        }
        .sorted { $0.submittedAt > $1.submittedAt }
    }

    func publish(
        theme: CursorTheme,
        request publishRequest: MarketplacePublishRequest
    ) async throws -> MarketplaceCreatorSubmission {
        let account = try await validSession().account
        let titleEN = publishRequest.titleEN.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let titleRU = publishRequest.titleRU.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let descriptionEN = publishRequest.descriptionEN.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let descriptionRU = publishRequest.descriptionRU.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !titleEN.isEmpty,
              titleEN.count <= 100,
              titleRU.count <= 100,
              !descriptionEN.isEmpty,
              descriptionEN.count <= 4_000,
              descriptionRU.count <= 4_000,
              Self.isSemanticVersion(publishRequest.semanticVersion) else {
            throw MarketplaceBackendError.invalidInput(
                L10n.publicationFieldsInvalid
            )
        }

        let themeID = UUID()
        let versionID = UUID()
        let normalizedVersion = publishRequest.semanticVersion
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prepared = try packageBuilder.prepare(
            theme: theme,
            remoteThemeID: themeID,
            semanticVersion: normalizedVersion
        )
        let validated = try await packageValidator.validatePackage(
            at: prepared.packageURL,
            expectedSHA256: prepared.packageSHA256
        )
        defer {
            try? fileManager.removeItem(at: prepared.cleanupDirectory)
            if let cleanup = validated.cleanupDirectory,
               cleanup != prepared.cleanupDirectory {
                try? fileManager.removeItem(at: cleanup)
            }
        }

        let basePath = [
            account.id.uuidString.lowercased(),
            themeID.uuidString.lowercased(),
            normalizedVersion,
        ].joined(separator: "/")
        let previewPath = "\(basePath)/preview.png"
        let packagePath = "\(basePath)/theme.cursorstudio-theme"
        var themeCreated = false
        var previewUploaded = false
        var packageUploaded = false

        do {
            _ = try await rawRequest(
                path: "rest/v1/themes",
                method: "POST",
                body: NewThemeRow(
                    id: themeID,
                    ownerID: account.id,
                    slug: Self.slug(title: titleEN, id: themeID),
                    titleEN: titleEN,
                    titleRU: titleRU.isEmpty ? nil : titleRU,
                    descriptionEN: descriptionEN,
                    descriptionRU: descriptionRU.isEmpty ? nil : descriptionRU,
                    categoryID: publishRequest.categoryID
                ),
                authenticated: true,
                prefer: "return=minimal"
            )
            themeCreated = true

            try await upload(
                fileURL: prepared.previewURL,
                bucket: "theme-previews",
                path: previewPath,
                contentType: "image/png"
            )
            previewUploaded = true

            try await upload(
                fileURL: prepared.packageURL,
                bucket: "theme-packages",
                path: packagePath,
                contentType: "application/zip"
            )
            packageUploaded = true

            _ = try await rawRequest(
                path: "rest/v1/theme_versions",
                method: "POST",
                body: NewVersionRow(
                    id: versionID,
                    themeID: themeID,
                    semanticVersion: normalizedVersion,
                    packagePath: packagePath,
                    packageSHA256: prepared.packageSHA256,
                    previewPaths: [previewPath],
                    packageBytes: prepared.packageBytes,
                    manifest: prepared.manifest,
                    minimumMacOSMajor: 15
                ),
                authenticated: true,
                prefer: "return=minimal"
            )

            _ = try await rawRequest(
                path: "rest/v1/rpc/submit_theme_version",
                method: "POST",
                body: VersionIDBody(requestedVersionID: versionID),
                authenticated: true
            )

            return MarketplaceCreatorSubmission(
                id: versionID,
                themeID: themeID,
                title: AppLanguage.runtime == .russian
                    ? (titleRU.isEmpty ? titleEN : titleRU)
                    : titleEN,
                semanticVersion: normalizedVersion,
                status: .pending,
                submittedAt: .now
            )
        } catch {
            if packageUploaded {
                try? await deleteObject(
                    bucket: "theme-packages",
                    path: packagePath
                )
            }
            if previewUploaded {
                try? await deleteObject(
                    bucket: "theme-previews",
                    path: previewPath
                )
            }
            if themeCreated {
                _ = try? await rawRequest(
                    path: "rest/v1/themes",
                    method: "DELETE",
                    queryItems: [
                        URLQueryItem(name: "id", value: "eq.\(themeID.uuidString.lowercased())"),
                    ],
                    authenticated: true
                )
            }
            throw error
        }
    }

    func moderationQueue() async throws -> [MarketplaceModerationItem] {
        let rows: [ModerationVersionRow] = try await request(
            path: "rest/v1/theme_versions",
            queryItems: [
                URLQueryItem(name: "review_status", value: "eq.pending"),
                URLQueryItem(
                    name: "select",
                    value: "id,theme_id,semantic_version,package_path,package_sha256,preview_paths,manifest,created_at,themes!theme_versions_theme_id_fkey!inner(title_en,title_ru,description_en,description_ru,profiles!themes_owner_id_fkey(display_name,handle))"
                ),
                URLQueryItem(name: "order", value: "created_at.asc"),
            ],
            authenticated: true
        )
        return rows.map { row in
            let russian = AppLanguage.runtime == .russian
            return MarketplaceModerationItem(
                versionID: row.id,
                themeID: row.themeID,
                title: russian
                    ? row.theme.titleRU ?? row.theme.titleEN
                    : row.theme.titleEN,
                description: russian
                    ? row.theme.descriptionRU ?? row.theme.descriptionEN
                    : row.theme.descriptionEN,
                creatorName: row.theme.profile.displayName,
                creatorHandle: row.theme.profile.handle,
                semanticVersion: row.semanticVersion,
                includedRoles: row.manifest.cursors.map(\.role),
                submittedAt: row.createdAt,
                packagePath: row.packagePath,
                packageSHA256: row.packageSHA256,
                previewURL: row.previewPaths.first.flatMap {
                    publicPreviewURL(path: $0)
                }
            )
        }
    }

    func prepareModerationTest(
        item: MarketplaceModerationItem
    ) async throws -> ValidatedMarketplacePackage {
        let packageURL = try await downloadPrivatePackage(
            path: item.packagePath
        )
        defer {
            try? fileManager.removeItem(at: packageURL)
        }
        let validated = try await packageValidator.validatePackage(
            at: packageURL,
            expectedSHA256: item.packageSHA256
        )
        guard validated.manifest.themeID == item.themeID,
              validated.manifest.semanticVersion == item.semanticVersion else {
            if let cleanup = validated.cleanupDirectory {
                try? fileManager.removeItem(at: cleanup)
            }
            throw MarketplaceBackendError.invalidInput(
                L10n.moderationPackageMismatch
            )
        }
        return validated
    }

    func moderate(
        item: MarketplaceModerationItem,
        approve: Bool,
        compatibility: MarketplaceCompatibility,
        note: String
    ) async throws {
        if approve {
            let validated = try await prepareModerationTest(item: item)
            if let cleanup = validated.cleanupDirectory {
                try? fileManager.removeItem(at: cleanup)
            }
        }
        _ = try await rawRequest(
            path: "rest/v1/rpc/moderate_theme_version",
            method: "POST",
            body: ModerationBody(
                requestedVersionID: item.versionID,
                decision: approve ? "approved" : "rejected",
                compatibility: compatibility.rawValue,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            authenticated: true
        )
    }

    func moderators() async throws -> [MarketplaceModerator] {
        try await request(
            path: "rest/v1/rpc/list_marketplace_moderators",
            method: "POST",
            body: EmptyBody(),
            authenticated: true
        )
    }

    func setModerator(handle: String, enabled: Bool) async throws {
        let normalized = handle.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        guard !normalized.isEmpty else {
            throw MarketplaceBackendError.invalidInput(
                L10n.moderatorHandleRequired
            )
        }
        _ = try await rawRequest(
            path: "rest/v1/rpc/set_marketplace_moderator",
            method: "POST",
            body: ModeratorUpdateBody(
                requestedHandle: normalized,
                enabled: enabled
            ),
            authenticated: true
        )
    }

    private func validSession() async throws -> MarketplaceStoredSession {
        guard var current = storedSession else {
            throw MarketplaceBackendError.authenticationRequired
        }
        if current.expiresAt.timeIntervalSinceNow <= 60 {
            let response: AuthTokenResponse = try await request(
                path: "auth/v1/token",
                method: "POST",
                queryItems: [
                    URLQueryItem(name: "grant_type", value: "refresh_token"),
                ],
                body: RefreshCredentials(refreshToken: current.refreshToken)
            )
            current = response.storedSession
            storedSession = current
            try vault.save(current)
        }
        return current
    }

    private func upload(
        fileURL: URL,
        bucket: String,
        path: String,
        contentType: String
    ) async throws {
        let current = try await validSession()
        var request = URLRequest(url: storageURL(bucket: bucket, path: path))
        request.httpMethod = "POST"
        addPublicHeaders(to: &request)
        request.setValue(
            "Bearer \(current.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        do {
            let (_, response) = try await session.upload(
                for: request,
                fromFile: fileURL
            )
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                throw MarketplaceBackendError.server(
                    L10n.storageUploadFailed
                )
            }
        } catch let error as MarketplaceBackendError {
            throw error
        } catch {
            throw MarketplaceBackendError.offline
        }
    }

    private func deleteObject(bucket: String, path: String) async throws {
        let current = try await validSession()
        var request = URLRequest(url: storageURL(bucket: bucket, path: path))
        request.httpMethod = "DELETE"
        addPublicHeaders(to: &request)
        request.setValue(
            "Bearer \(current.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else {
            throw MarketplaceBackendError.server(L10n.storageCleanupFailed)
        }
    }

    private func downloadPrivatePackage(path: String) async throws -> URL {
        let current = try await validSession()
        var request = URLRequest(
            url: storageURL(bucket: "theme-packages", path: path)
        )
        addPublicHeaders(to: &request)
        request.setValue(
            "Bearer \(current.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        do {
            let (temporaryURL, response) = try await session.download(
                for: request
            )
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                throw MarketplaceBackendError.server(
                    L10n.moderationPackageUnavailable
                )
            }
            let destination = fileManager.temporaryDirectory.appending(
                path: "\(UUID().uuidString).cursorstudio-theme"
            )
            try fileManager.moveItem(
                at: temporaryURL,
                to: destination
            )
            return destination
        } catch let error as MarketplaceBackendError {
            throw error
        } catch {
            throw MarketplaceBackendError.offline
        }
    }

    private func storageURL(bucket: String, path: String) -> URL {
        var url = configuration.projectURL
            .appending(path: "storage")
            .appending(path: "v1")
            .appending(path: "object")
            .appending(path: bucket)
        for component in path.split(separator: "/") {
            url.append(path: String(component))
        }
        return url
    }

    private func publicPreviewURL(path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        var url = configuration.projectURL
            .appending(path: "storage")
            .appending(path: "v1")
            .appending(path: "object")
            .appending(path: "public")
            .appending(path: "theme-previews")
        for component in path.split(separator: "/") {
            url.append(path: String(component))
        }
        return url
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        authenticated: Bool = false,
        prefer: String? = nil
    ) async throws -> T {
        let data = try await rawRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            authenticated: authenticated,
            prefer: prefer
        )
        do {
            return try Self.makeDecoder().decode(T.self, from: data)
        } catch {
            throw MarketplaceBackendError.invalidResponse
        }
    }

    private func request<T: Decodable, Body: Encodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Body,
        authenticated: Bool = false,
        prefer: String? = nil
    ) async throws -> T {
        let data = try await rawRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body,
            authenticated: authenticated,
            prefer: prefer
        )
        do {
            return try Self.makeDecoder().decode(T.self, from: data)
        } catch {
            throw MarketplaceBackendError.invalidResponse
        }
    }

    private func rawRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        authenticated: Bool = false,
        prefer: String? = nil
    ) async throws -> Data {
        try await perform(
            path: path,
            method: method,
            queryItems: queryItems,
            body: nil,
            authenticated: authenticated,
            prefer: prefer
        )
    }

    private func rawRequest<Body: Encodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Body,
        authenticated: Bool = false,
        prefer: String? = nil
    ) async throws -> Data {
        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(body)
        } catch {
            throw MarketplaceBackendError.invalidInput(
                L10n.marketplaceInvalidRequest
            )
        }
        return try await perform(
            path: path,
            method: method,
            queryItems: queryItems,
            body: bodyData,
            authenticated: authenticated,
            prefer: prefer
        )
    }

    private func perform(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Data?,
        authenticated: Bool,
        prefer: String?
    ) async throws -> Data {
        var components = URLComponents(
            url: configuration.projectURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw MarketplaceBackendError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        addPublicHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
        }
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        if authenticated {
            let current = try await validSession()
            request.setValue(
                "Bearer \(current.accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MarketplaceBackendError.invalidResponse
            }
            guard 200..<300 ~= http.statusCode else {
                if http.statusCode == 400 || http.statusCode == 401,
                   path.contains("auth/v1/token") {
                    throw MarketplaceBackendError.invalidCredentials
                }
                throw MarketplaceBackendError.server(
                    Self.serverMessage(from: data)
                        ?? L10n.marketplaceRequestFailed(http.statusCode)
                )
            }
            return data
        } catch let error as MarketplaceBackendError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MarketplaceBackendError.offline
        }
    }

    private func addPublicHeaders(to request: inout URLRequest) {
        request.setValue(
            configuration.publishableKey,
            forHTTPHeaderField: "apikey"
        )
    }

    private static func serverMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        for key in ["message", "msg", "error_description", "error", "hint"] {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func slug(title: String, id: UUID) -> String {
        let allowed = CharacterSet.alphanumerics
        var slug = title.lowercased().unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) && scalar.isASCII ? String(scalar) : "-"
        }.joined()
        while slug.contains("--") {
            slug = slug.replacingOccurrences(of: "--", with: "-")
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.count < 3 {
            slug = "theme"
        }
        let suffix = id.uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
            .lowercased()
        return "\(slug.prefix(60))-\(suffix)"
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).range(
            of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][0-9A-Za-z.-]+)?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds,
            ]
            let standard = ISO8601DateFormatter()
            if let date = fractional.date(from: value)
                ?? standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date."
            )
        }
        return decoder
    }
}

nonisolated private struct EmptyBody: Encodable {}

nonisolated private struct AuthCredentials: Encodable {
    let email: String
    let password: String
}

nonisolated private struct RefreshCredentials: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

nonisolated private struct SignUpCredentials: Encodable {
    let email: String
    let password: String
    let data: SignUpMetadata
}

nonisolated private struct SignUpMetadata: Encodable {
    let preferredUsername: String
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case preferredUsername = "preferred_username"
        case fullName = "full_name"
    }
}

nonisolated private struct AuthUserResponse: Codable {
    let id: UUID
    let email: String
}

nonisolated private struct AuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let expiresAt: TimeInterval?
    let user: AuthUserResponse

    var storedSession: MarketplaceStoredSession {
        MarketplaceStoredSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt.map(Date.init(timeIntervalSince1970:))
                ?? Date().addingTimeInterval(expiresIn),
            userID: user.id,
            email: user.email
        )
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

nonisolated private struct SignUpResponse: Decodable {
    let user: AuthUserResponse?
    let id: UUID?
    let email: String?

    var directUser: AuthUserResponse? {
        guard let id, let email else { return nil }
        return AuthUserResponse(id: id, email: email)
    }
}

nonisolated private struct ProfileUpdate: Encodable {
    let handle: String
    let displayName: String
    let bio: String?

    enum CodingKeys: String, CodingKey {
        case handle
        case displayName = "display_name"
        case bio
    }
}

nonisolated private struct NewThemeRow: Encodable {
    let id: UUID
    let ownerID: UUID
    let slug: String
    let titleEN: String
    let titleRU: String?
    let descriptionEN: String
    let descriptionRU: String?
    let categoryID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case slug
        case titleEN = "title_en"
        case titleRU = "title_ru"
        case descriptionEN = "description_en"
        case descriptionRU = "description_ru"
        case categoryID = "category_id"
    }
}

nonisolated private struct NewVersionRow: Encodable {
    let id: UUID
    let themeID: UUID
    let semanticVersion: String
    let packagePath: String
    let packageSHA256: String
    let previewPaths: [String]
    let packageBytes: Int64
    let manifest: MarketplacePackageManifest
    let minimumMacOSMajor: Int

    enum CodingKeys: String, CodingKey {
        case id
        case themeID = "theme_id"
        case semanticVersion = "semantic_version"
        case packagePath = "package_path"
        case packageSHA256 = "package_sha256"
        case previewPaths = "preview_paths"
        case packageBytes = "package_bytes"
        case manifest
        case minimumMacOSMajor = "minimum_macos_major"
    }
}

nonisolated private struct VersionIDBody: Encodable {
    let requestedVersionID: UUID

    enum CodingKeys: String, CodingKey {
        case requestedVersionID = "requested_version_id"
    }
}

nonisolated private struct ModerationBody: Encodable {
    let requestedVersionID: UUID
    let decision: String
    let compatibility: String
    let note: String

    enum CodingKeys: String, CodingKey {
        case requestedVersionID = "requested_version_id"
        case decision
        case compatibility = "compatibility_result"
        case note
    }
}

nonisolated private struct ModeratorUpdateBody: Encodable {
    let requestedHandle: String
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case requestedHandle = "requested_handle"
        case enabled
    }
}

nonisolated private struct CreatorThemeRow: Decodable {
    let id: UUID
    let titleEN: String
    let titleRU: String?
    let versions: [CreatorVersionRow]

    enum CodingKeys: String, CodingKey {
        case id
        case titleEN = "title_en"
        case titleRU = "title_ru"
        case versions = "theme_versions"
    }
}

nonisolated private struct CreatorVersionRow: Decodable {
    let id: UUID
    let semanticVersion: String
    let reviewStatus: MarketplaceReviewStatus
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case semanticVersion = "semantic_version"
        case reviewStatus = "review_status"
        case createdAt = "created_at"
    }
}

nonisolated private struct ModerationVersionRow: Decodable {
    let id: UUID
    let themeID: UUID
    let semanticVersion: String
    let packagePath: String
    let packageSHA256: String
    let previewPaths: [String]
    let manifest: MarketplacePackageManifest
    let createdAt: Date
    let theme: ModerationThemeRow

    enum CodingKeys: String, CodingKey {
        case id
        case themeID = "theme_id"
        case semanticVersion = "semantic_version"
        case packagePath = "package_path"
        case packageSHA256 = "package_sha256"
        case previewPaths = "preview_paths"
        case manifest
        case createdAt = "created_at"
        case theme = "themes"
    }
}

nonisolated private struct ModerationThemeRow: Decodable {
    let titleEN: String
    let titleRU: String?
    let descriptionEN: String
    let descriptionRU: String?
    let profile: ModerationProfileRow

    enum CodingKeys: String, CodingKey {
        case titleEN = "title_en"
        case titleRU = "title_ru"
        case descriptionEN = "description_en"
        case descriptionRU = "description_ru"
        case profile = "profiles"
    }
}

nonisolated private struct ModerationProfileRow: Decodable {
    let displayName: String
    let handle: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case handle
    }
}
