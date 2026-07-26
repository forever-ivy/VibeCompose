import Foundation
import Security

struct ChatGPTStoredCookie: Codable, Sendable, Equatable {
    var domain: String
    var path: String
    var name: String
    var value: String
    var secure: Bool
    var expiresAt: Date?

    init(cookie: HTTPCookie) {
        domain = cookie.domain
        path = cookie.path
        name = cookie.name
        value = cookie.value
        secure = cookie.isSecure
        expiresAt = cookie.expiresDate
    }

    init(
        domain: String,
        path: String,
        name: String,
        value: String,
        secure: Bool,
        expiresAt: Date?
    ) {
        self.domain = domain
        self.path = path
        self.name = name
        self.value = value
        self.secure = secure
        self.expiresAt = expiresAt
    }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: path,
            .name: name,
            .value: value,
            .secure: secure ? "TRUE" : "FALSE",
        ]
        if let expiresAt {
            properties[.expires] = expiresAt
        }
        return HTTPCookie(properties: properties)
    }
}

struct ChatGPTSession: Codable, Sendable, Equatable {
    var accessToken: String
    var accessTokenExpiresAt: Date?
    var refreshToken: String?
    var idToken: String?
    var cookies: [ChatGPTStoredCookie]
    var userEmail: String?
    var updatedAt: Date

    init(
        accessToken: String,
        accessTokenExpiresAt: Date?,
        refreshToken: String? = nil,
        idToken: String? = nil,
        cookies: [ChatGPTStoredCookie],
        userEmail: String?,
        updatedAt: Date
    ) {
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.cookies = cookies
        self.userEmail = userEmail
        self.updatedAt = updatedAt
    }

    func tokenIsUsable(now: Date) -> Bool {
        let trimmed = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        guard let accessTokenExpiresAt else {
            return true
        }

        return accessTokenExpiresAt > now
    }
}

protocol ChatGPTSessionPersisting: Sendable {
    func load() throws -> ChatGPTSession?
    func save(_ session: ChatGPTSession) throws
    func delete() throws
}

enum ChatGPTSessionStoreError: LocalizedError {
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "VibeCompose 保存的 ChatGPT 会话无法解析。"
        case .unhandledStatus(let status):
            return "VibeCompose 无法访问本地 ChatGPT 会话存储（OSStatus \(status)）。"
        }
    }
}

struct KeychainChatGPTSessionStore: ChatGPTSessionPersisting {
    let service: String
    let account: String
    let legacyService: String?
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(
        service: String = ProductIdentity.keychainService,
        account: String = "default",
        legacyService: String? = nil,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.service = service
        self.account = account
        self.legacyService = legacyService
            ?? LegacyProductIdentity.keychainService(
                forCurrentService: service
            )
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() throws -> ChatGPTSession? {
        if let session = try load(service: service) {
            return session
        }
        guard let legacyService else {
            return nil
        }
        do {
            guard let session = try load(service: legacyService) else {
                return nil
            }
            try save(session)
            return session
        } catch ChatGPTSessionStoreError.unhandledStatus(let status)
            where LegacyProductIdentity.isUnavailableLegacyKeychainStatus(
                status
            )
        {
            // A renamed bundle may not be allowed to read the former bundle's
            // Keychain row. Treat that as signed out, not as a launch failure.
            return nil
        }
    }

    private func load(service: String) throws -> ChatGPTSession? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw ChatGPTSessionStoreError.unexpectedData
            }
            return try decoder.decode(ChatGPTSession.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw ChatGPTSessionStoreError.unhandledStatus(status)
        }
    }

    func save(_ session: ChatGPTSession) throws {
        let data = try encoder.encode(session)
        var addQuery = baseQuery(service: service)
        addQuery[kSecValueData as String] = data

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updateQuery = baseQuery(service: service)
            let updateStatus = SecItemUpdate(
                updateQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw ChatGPTSessionStoreError.unhandledStatus(updateStatus)
            }
        default:
            throw ChatGPTSessionStoreError.unhandledStatus(addStatus)
        }
    }

    func delete() throws {
        try delete(service: service, toleratingLegacyAccessFailure: false)
        if let legacyService {
            try delete(
                service: legacyService,
                toleratingLegacyAccessFailure: true
            )
        }
    }

    private func delete(
        service: String,
        toleratingLegacyAccessFailure: Bool
    ) throws {
        let status = SecItemDelete(
            baseQuery(service: service) as CFDictionary
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            if toleratingLegacyAccessFailure,
               LegacyProductIdentity.isUnavailableLegacyKeychainStatus(status)
            {
                return
            }
            throw ChatGPTSessionStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

final class InMemoryChatGPTSessionStore: ChatGPTSessionPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var session: ChatGPTSession?

    init(session: ChatGPTSession? = nil) {
        self.session = session
    }

    func load() throws -> ChatGPTSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    func save(_ session: ChatGPTSession) throws {
        lock.lock()
        self.session = session
        lock.unlock()
    }

    func delete() throws {
        lock.lock()
        session = nil
        lock.unlock()
    }
}
