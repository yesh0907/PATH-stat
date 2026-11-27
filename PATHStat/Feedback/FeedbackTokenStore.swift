import Foundation
import Security

/// Where the GitHub token for feedback lives. Never log or display the full token.
@MainActor
protocol FeedbackTokenStore: AnyObject {
    func token() -> String?
    func save(_ token: String) throws
    func delete() throws
}

enum FeedbackTokenError: LocalizedError {
    case empty
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .empty: "Paste a token first."
        case .keychain(let status): "Couldn't save to the Keychain (\(status))."
        }
    }
}

extension FeedbackTokenStore {
    /// "github_pat_…1a2b": enough to recognise the token, never the whole thing.
    static func masked(_ token: String) -> String {
        let last4 = String(token.suffix(4))
        return token.hasPrefix("github_pat_") ? "github_pat_…\(last4)" : "…\(last4)"
    }
}

/// The device Keychain: a generic password only this app on this device can read
/// (no access group, no iCloud sync, available after first unlock for background retries).
@MainActor
final class KeychainTokenStore: FeedbackTokenStore {
    static let service = "com.yesh0907.PATHStat.feedback"
    static let account = "github-token"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func token() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    func save(_ token: String) throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw FeedbackTokenError.empty }
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw FeedbackTokenError.keychain(status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw FeedbackTokenError.keychain(status) }
    }
}

/// Scenario mode: never touches the Keychain.
@MainActor
final class InMemoryTokenStore: FeedbackTokenStore {
    private var value: String?

    init(token: String? = nil) {
        value = token
    }

    func token() -> String? { value }

    func save(_ token: String) throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw FeedbackTokenError.empty }
        value = token
    }

    func delete() throws {
        value = nil
    }
}
