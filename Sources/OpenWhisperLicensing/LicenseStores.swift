import Foundation
import Security

public protocol LicenseReceiptPersisting: Sendable {
    func loadReceiptData() throws -> Data?
    func saveReceiptData(_ data: Data) throws
    func deleteReceiptData() throws
}

public protocol LicenseDeviceIdentifying: Sendable {
    func loadOrCreateDeviceIdentifier() throws -> String
    func deleteDeviceIdentifier() throws
}

public enum LicenseStorageError:
    Error,
    Equatable,
    Sendable
{
    case unexpectedData
    case unhandledStatus(OSStatus)
}

extension LicenseStorageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "The license information stored in Keychain could not be read."
        case .unhandledStatus(let status):
            return "OpenWhisper could not access license information in Keychain (OSStatus \(status))."
        }
    }
}

public struct KeychainLicenseReceiptStore:
    LicenseReceiptPersisting,
    Sendable
{
    public let service: String
    public let account: String

    public init(service: String, account: String = "receipt") {
        self.service = service
        self.account = account
    }

    public func loadReceiptData() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw LicenseStorageError.unexpectedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw LicenseStorageError.unhandledStatus(status)
        }
    }

    public func saveReceiptData(_ data: Data) throws {
        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        switch status {
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
                throw LicenseStorageError.unhandledStatus(updateStatus)
            }
        default:
            throw LicenseStorageError.unhandledStatus(status)
        }
    }

    public func deleteReceiptData() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseStorageError.unhandledStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public struct KeychainLicenseDeviceIdentifierStore:
    LicenseDeviceIdentifying,
    Sendable
{
    public let service: String
    public let account: String

    public init(service: String, account: String = "device") {
        self.service = service
        self.account = account
    }

    public func loadOrCreateDeviceIdentifier() throws -> String {
        if let existing = try load() {
            return existing
        }

        let identifier = UUID().uuidString.lowercased()
        let data = Data(identifier.utf8)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return identifier
        case errSecDuplicateItem:
            guard let existing = try load() else {
                throw LicenseStorageError.unexpectedData
            }
            return existing
        default:
            throw LicenseStorageError.unhandledStatus(status)
        }
    }

    public func deleteDeviceIdentifier() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseStorageError.unhandledStatus(status)
        }
    }

    private func load() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard
                let data = item as? Data,
                let identifier = String(data: data, encoding: .utf8),
                UUID(uuidString: identifier) != nil
            else {
                throw LicenseStorageError.unexpectedData
            }
            return identifier.lowercased()
        case errSecItemNotFound:
            return nil
        default:
            throw LicenseStorageError.unhandledStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public final class InMemoryLicenseReceiptStore:
    LicenseReceiptPersisting,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var data: Data?

    public init(data: Data? = nil) {
        self.data = data
    }

    public func loadReceiptData() throws -> Data? {
        lock.withLock { data }
    }

    public func saveReceiptData(_ data: Data) throws {
        lock.withLock {
            self.data = data
        }
    }

    public func deleteReceiptData() throws {
        lock.withLock {
            data = nil
        }
    }
}

public final class InMemoryLicenseDeviceIdentifierStore:
    LicenseDeviceIdentifying,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var identifier: String?

    public init(identifier: String? = nil) {
        self.identifier = identifier
    }

    public func loadOrCreateDeviceIdentifier() throws -> String {
        lock.withLock {
            if let identifier {
                return identifier
            }
            let created = UUID().uuidString.lowercased()
            identifier = created
            return created
        }
    }

    public func deleteDeviceIdentifier() throws {
        lock.withLock {
            identifier = nil
        }
    }
}
