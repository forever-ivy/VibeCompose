import Foundation
import Security

protocol OpenAICompatibleCredentialPersisting: Sendable {
    func loadAPIKey() throws -> String?
    func hasAPIKey() throws -> Bool
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
}

enum OpenAICompatibleCredentialStoreError: Error, Equatable, LocalizedError {
    case emptyAPIKey
    case apiKeyTooLong
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return L10n.text("Enter an API key before saving.")
        case .apiKeyTooLong:
            return L10n.text("The API key is too long to store.")
        case .unexpectedData:
            return L10n.text(
                "The OpenAI-Compatible API key stored in Keychain could not be read."
            )
        case .unhandledStatus(let status):
            return L10n.format(
                "OpenWhisper could not access the OpenAI-Compatible API key in Keychain (OSStatus %d).",
                status
            )
        }
    }
}

struct KeychainOpenAICompatibleCredentialStore:
    OpenAICompatibleCredentialPersisting
{
    let service: String
    let account: String

    init(
        service: String = ProductIdentity.recoveryAPIKeychainService,
        account: String = "default"
    ) {
        self.service = service
        self.account = account
    }

    func loadAPIKey() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard
                let data = item as? Data,
                let value = String(data: data, encoding: .utf8)
            else {
                throw OpenAICompatibleCredentialStoreError.unexpectedData
            }
            return try Self.validatedAPIKey(value)
        case errSecItemNotFound:
            return nil
        default:
            throw OpenAICompatibleCredentialStoreError.unhandledStatus(status)
        }
    }

    func hasAPIKey() throws -> Bool {
        try loadAPIKey() != nil
    }

    func saveAPIKey(_ apiKey: String) throws {
        let validated = try Self.validatedAPIKey(apiKey)
        let data = Data(validated.utf8)
        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateStatus = SecItemUpdate(
                baseQuery() as CFDictionary,
                [
                    kSecValueData as String: data,
                    kSecAttrAccessible as String:
                        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                ] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw OpenAICompatibleCredentialStoreError.unhandledStatus(
                    updateStatus
                )
            }
        default:
            throw OpenAICompatibleCredentialStoreError.unhandledStatus(
                addStatus
            )
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAICompatibleCredentialStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func validatedAPIKey(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAICompatibleCredentialStoreError.emptyAPIKey
        }
        guard trimmed.utf8.count <= 8 * 1024 else {
            throw OpenAICompatibleCredentialStoreError.apiKeyTooLong
        }
        return trimmed
    }
}

final class InMemoryOpenAICompatibleCredentialStore:
    OpenAICompatibleCredentialPersisting,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    func loadAPIKey() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let apiKey else {
            return nil
        }
        return try validated(apiKey)
    }

    func hasAPIKey() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let apiKey else {
            return false
        }
        _ = try validated(apiKey)
        return true
    }

    func saveAPIKey(_ apiKey: String) throws {
        let validated = try validated(apiKey)
        lock.lock()
        self.apiKey = validated
        lock.unlock()
    }

    func deleteAPIKey() throws {
        lock.lock()
        apiKey = nil
        lock.unlock()
    }

    private func validated(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAICompatibleCredentialStoreError.emptyAPIKey
        }
        guard trimmed.utf8.count <= 8 * 1024 else {
            throw OpenAICompatibleCredentialStoreError.apiKeyTooLong
        }
        return trimmed
    }
}
