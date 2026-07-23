import Foundation

/// One account-visible Codex model from `GET /backend-api/codex/models`.
struct ChatGPTAccountModel: Sendable, Equatable, Identifiable {
    let slug: String
    let displayName: String?
    let isDefault: Bool
    let showInPicker: Bool

    var id: String { slug }

    /// Prefer the slug for picker tags so requests match the wire value.
    var pickerLabel: String { slug }
}

enum ChatGPTAccountModelCatalogError: LocalizedError, Equatable, Sendable {
    case notSignedIn
    case requestFailed(String)
    case emptyCatalog
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return L10n.text("Connect ChatGPT before loading account models.")
        case .requestFailed(let message):
            return L10n.format("Could not load account models: %@", message)
        case .emptyCatalog:
            return L10n.text(
                "Account model list was empty. Showing built-in presets until the catalog is available."
            )
        case .invalidResponse:
            return L10n.text(
                "Account model list response was invalid. Showing built-in presets."
            )
        }
    }
}

struct ChatGPTAccountModelCatalogSnapshot: Sendable, Equatable {
    let models: [ChatGPTAccountModel]
    let fetchedAt: Date
    let usedFallbackPresets: Bool
    let message: String?

    var pickerSlugs: [String] {
        models.map(\.slug)
    }

    var defaultSlug: String? {
        models.first(where: \.isDefault)?.slug ?? models.first?.slug
    }
}

/// Loads and caches account-scoped Codex models for the ChatGPT Auth polish route.
///
/// Network access is restricted to `ManagedEndpointPolicy.modelsURL` and uses the
/// managed ChatGPT session token only — never a user-owned API key.
actor ChatGPTAccountModelCatalog {
    static let shared = ChatGPTAccountModelCatalog()

    /// How long a successful live catalog stays warm without re-fetch.
    static let cacheTTL: TimeInterval = 15 * 60

    /// Codex filters `/codex/models` by `client_version` / `minimal_client_version`.
    /// VibeWhisper's product version (e.g. `0.1.0`) is too low and yields an empty
    /// catalog, so we advertise a Codex-compatible capability version for this
    /// endpoint only. Keep this independent of `ProductIdentity.runtimeVersion`.
    static let codexModelsClientVersion = "1.0.0"

    private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let now: @Sendable () -> Date
    private let clientVersionProvider: @Sendable () -> String

    private var cached: ChatGPTAccountModelCatalogSnapshot?
    private var inFlight: Task<ChatGPTAccountModelCatalogSnapshot, Error>?

    init(
        dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
            = { try await SecureHTTPClient.data(for: $0) },
        now: @escaping @Sendable () -> Date = Date.init,
        clientVersionProvider: @escaping @Sendable () -> String = {
            ChatGPTAccountModelCatalog.codexModelsClientVersion
        }
    ) {
        self.dataLoader = dataLoader
        self.now = now
        self.clientVersionProvider = clientVersionProvider
    }

    /// Cached picker models if still fresh; otherwise nil.
    func cachedSnapshotIfFresh() -> ChatGPTAccountModelCatalogSnapshot? {
        guard let cached else { return nil }
        guard now().timeIntervalSince(cached.fetchedAt) < Self.cacheTTL else {
            return nil
        }
        return cached
    }

    func invalidate() {
        cached = nil
        inFlight?.cancel()
        inFlight = nil
    }

    /// Resolve picker models for the Account polish source.
    ///
    /// On success returns the live catalog (picker-visible first). On failure returns
    /// built-in presets with an explanatory message — never silently invents "account" models.
    func resolveForPicker(
        accessToken: String?,
        forceRefresh: Bool = false
    ) async -> ChatGPTAccountModelCatalogSnapshot {
        if !forceRefresh, let fresh = cachedSnapshotIfFresh(), !fresh.usedFallbackPresets {
            return fresh
        }

        guard
            let accessToken,
            !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return fallbackSnapshot(
                reason: ChatGPTAccountModelCatalogError.notSignedIn.localizedDescription
            )
        }

        do {
            let live = try await fetchLive(accessToken: accessToken)
            cached = live
            return live
        } catch {
            return fallbackSnapshot(reason: error.localizedDescription)
        }
    }

    func fetchLive(accessToken: String) async throws -> ChatGPTAccountModelCatalogSnapshot {
        if let inFlight {
            return try await inFlight.value
        }

        let task = Task { () throws -> ChatGPTAccountModelCatalogSnapshot in
            try await self.performFetch(accessToken: accessToken)
        }
        inFlight = task
        defer { inFlight = nil }

        let snapshot = try await task.value
        cached = snapshot
        return snapshot
    }

    private func performFetch(
        accessToken: String
    ) async throws -> ChatGPTAccountModelCatalogSnapshot {
        let clientVersion = clientVersionProvider()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = try ManagedEndpointPolicy.modelsListURL(
            clientVersion: clientVersion.isEmpty
                ? Self.codexModelsClientVersion
                : clientVersion
        )
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(ProductIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Workspace accounts often need ChatGPT-Account-ID on backend-api routes.
        if let accountID = Self.chatgptAccountID(fromAccessToken: accessToken) {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await dataLoader(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ChatGPTAccountModelCatalogError.requestFailed(
                L10n.text("Network request failed.")
            )
        }

        guard let http = response as? HTTPURLResponse else {
            throw ChatGPTAccountModelCatalogError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyPrefix = String(data: data.prefix(240), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail: String
            if let parsed = Self.extractErrorMessage(from: data), !parsed.isEmpty {
                detail = parsed
            } else if !bodyPrefix.isEmpty {
                detail = bodyPrefix
            } else {
                detail = L10n.format("HTTP %ld", http.statusCode)
            }
            throw ChatGPTAccountModelCatalogError.requestFailed(detail)
        }

        let models = Self.parseModels(from: data)
        guard !models.isEmpty else {
            throw ChatGPTAccountModelCatalogError.emptyCatalog
        }

        return ChatGPTAccountModelCatalogSnapshot(
            models: models,
            fetchedAt: now(),
            usedFallbackPresets: false,
            message: nil
        )
    }

    /// Extract `chatgpt_account_id` from a ChatGPT access JWT when present.
    static func chatgptAccountID(fromAccessToken token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let remainder = payload.count % 4
        if remainder > 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }
        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        if let direct = object["chatgpt_account_id"] as? String,
           !direct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return direct.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let auth = object["https://api.openai.com/auth"] as? [String: Any],
           let accountID = auth["chatgpt_account_id"] as? String
        {
            let trimmed = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func fallbackSnapshot(reason: String) -> ChatGPTAccountModelCatalogSnapshot {
        let presets = ProductModelCatalog.rewritePresets.map { slug in
            ChatGPTAccountModel(
                slug: slug,
                displayName: nil,
                isDefault: slug == ProductModelCatalog.rewritePresets.first,
                showInPicker: true
            )
        }
        let snapshot = ChatGPTAccountModelCatalogSnapshot(
            models: presets,
            fetchedAt: now(),
            usedFallbackPresets: true,
            message: reason
        )
        // Do not treat fallback as a warm cache for live success.
        return snapshot
    }

    // MARK: - Parsing

    /// Accepts Codex `{ "models": [ { "slug": … } ] }` and OpenAI-style `{ "data": [ { "id": … } ] }`.
    static func parseModels(from data: Data) -> [ChatGPTAccountModel] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }

        let rawList: [[String: Any]]
        if let models = object["models"] as? [[String: Any]] {
            rawList = models
        } else if let dataList = object["data"] as? [[String: Any]] {
            rawList = dataList
        } else {
            return []
        }

        var seen = Set<String>()
        var picker: [ChatGPTAccountModel] = []
        var hidden: [ChatGPTAccountModel] = []

        for item in rawList {
            guard let slug = extractSlug(from: item) else { continue }
            guard seen.insert(slug).inserted else { continue }

            let showInPicker = visibilityShowsInPicker(item)
            let isDefault =
                (item["is_default"] as? Bool)
                ?? (item["isDefault"] as? Bool)
                ?? false
            let displayName =
                (item["display_name"] as? String)
                ?? (item["displayName"] as? String)
                ?? (item["title"] as? String)

            let model = ChatGPTAccountModel(
                slug: slug,
                displayName: displayName,
                isDefault: isDefault,
                showInPicker: showInPicker
            )
            if showInPicker {
                picker.append(model)
            } else {
                hidden.append(model)
            }
        }

        // Prefer picker-visible models; if the catalog only marks everything hidden,
        // still surface the full list so the account is not reduced to empty presets.
        let ordered = picker.isEmpty ? hidden : picker
        return ordered
    }

    static func extractSlug(from item: [String: Any]) -> String? {
        let candidates = [
            item["slug"] as? String,
            item["id"] as? String,
            item["model"] as? String,
            item["name"] as? String,
        ]
        for candidate in candidates {
            guard let value = candidate?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty
            else {
                continue
            }
            return value
        }
        return nil
    }

    static func visibilityShowsInPicker(_ item: [String: Any]) -> Bool {
        if let show = item["show_in_picker"] as? Bool {
            return show
        }
        if let show = item["showInPicker"] as? Bool {
            return show
        }
        if let visibility = (item["visibility"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
            // Codex: "list" = picker, "hidden" / "api" may be excluded.
            if visibility == "list" || visibility == "visible" || visibility == "default" {
                return true
            }
            if visibility == "hidden" {
                return false
            }
        }
        // Unknown shape: keep the model so we don't over-filter real account access.
        return true
    }

    static func extractErrorMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        if let detail = object["detail"] as? String, !detail.isEmpty {
            return detail
        }
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = object["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            if let code = error["code"] as? String, !code.isEmpty {
                return code
            }
        }
        if let error = object["error"] as? String, !error.isEmpty {
            return error
        }
        return nil
    }

    /// Merge preferred order with extra account models without dropping real IDs.
    static func mergePreservingOrder(
        preferred: [String],
        extra: [String]
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in preferred + extra {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}
