import Foundation
import Security

nonisolated struct MarketplaceStoredSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: UUID
    let email: String

    var account: MarketplaceAccount {
        MarketplaceAccount(id: userID, email: email)
    }
}

nonisolated final class MarketplaceSessionVault: @unchecked Sendable {
    private let service: String
    private let account = "supabase-session"
    private let fallbackDirectory: URL
    private let fallbackFile: URL
    private let fileManager: FileManager

    init(
        paths: ApplicationPaths,
        service: String = "studio.cursor.CursorStudio.marketplace",
        fileManager: FileManager = .default
    ) {
        self.service = service
        self.fileManager = fileManager
        fallbackDirectory = paths.rootDirectory.appending(
            path: "MarketplaceSession",
            directoryHint: .isDirectory
        )
        fallbackFile = fallbackDirectory.appending(
            path: "session.json",
            directoryHint: .notDirectory
        )
    }

    func load() throws -> MarketplaceStoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            guard let fallback = try loadFallback() else { return nil }
            let data = try JSONEncoder().encode(fallback)
            if try saveToKeychain(data) {
                try? removeFallback()
            }
            return fallback
        }
        if status == errSecMissingEntitlement {
            return try loadFallback()
        }
        guard status == errSecSuccess,
              let data = result as? Data else {
            throw MarketplaceBackendError.server(L10n.keychainUnavailable)
        }
        do {
            return try JSONDecoder().decode(
                MarketplaceStoredSession.self,
                from: data
            )
        } catch {
            try? clear()
            return nil
        }
    }

    func save(_ session: MarketplaceStoredSession) throws {
        let data = try JSONEncoder().encode(session)
        if try saveToKeychain(data) {
            try? removeFallback()
        } else {
            try saveFallback(data)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess
                || status == errSecItemNotFound
                || status == errSecMissingEntitlement else {
            throw MarketplaceBackendError.server(L10n.keychainUnavailable)
        }
        try removeFallback()
    }

    private func saveToKeychain(_ data: Data) throws -> Bool {
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            update as CFDictionary
        )
        if status == errSecItemNotFound {
            var insert = baseQuery
            update.forEach { insert[$0.key] = $0.value }
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            if insertStatus == errSecMissingEntitlement {
                return false
            }
            guard insertStatus == errSecSuccess else {
                throw MarketplaceBackendError.server(L10n.keychainUnavailable)
            }
        } else if status == errSecMissingEntitlement {
            return false
        } else if status != errSecSuccess {
            throw MarketplaceBackendError.server(L10n.keychainUnavailable)
        }
        return true
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // The legacy file-based macOS Keychain can show an ACL prompt after
            // the app is rebuilt or re-signed. The data-protection Keychain uses
            // the app's signing access group and does not present that dialog.
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func loadFallback() throws -> MarketplaceStoredSession? {
        guard fileManager.fileExists(atPath: fallbackFile.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fallbackFile)
            return try JSONDecoder().decode(
                MarketplaceStoredSession.self,
                from: data
            )
        } catch {
            try? removeFallback()
            return nil
        }
    }

    private func saveFallback(_ data: Data) throws {
        try fileManager.createDirectory(
            at: fallbackDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fallbackDirectory.path
        )
        try data.write(to: fallbackFile, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fallbackFile.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = fallbackDirectory
        try? directory.setResourceValues(values)
    }

    private func removeFallback() throws {
        guard fileManager.fileExists(atPath: fallbackDirectory.path) else {
            return
        }
        try fileManager.removeItem(at: fallbackDirectory)
    }
}
