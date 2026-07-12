import CryptoKit
import Foundation

enum ProviderCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case managedTranscription
    case chatGPTTextPolish

    var title: String {
        switch self {
        case .managedTranscription:
            return L10n.text("Managed ChatGPT transcription")
        case .chatGPTTextPolish:
            return L10n.text("ChatGPT AI Polish")
        }
    }
}

struct ProviderCapabilityPolicyConfiguration: Equatable, Sendable {
    enum ValidationError: Error, Equatable, LocalizedError {
        case incomplete
        case invalidURL
        case invalidPublicKey

        var errorDescription: String? {
            switch self {
            case .incomplete:
                return L10n.text(
                    "Provider safety policy is unavailable because this build has incomplete configuration."
                )
            case .invalidURL:
                return L10n.text(
                    "Provider safety policy is unavailable because this build has an invalid policy URL."
                )
            case .invalidPublicKey:
                return L10n.text(
                    "Provider safety policy is unavailable because this build has an invalid signing key."
                )
            }
        }
    }

    let policyURL: URL
    let publicKeyData: Data

    init(infoDictionary: [String: Any]) throws {
        let rawURL = (infoDictionary["OWCapabilityPolicyURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawPublicKey = (infoDictionary["OWCapabilityPublicEDKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !rawURL.isEmpty, !rawPublicKey.isEmpty else {
            throw ValidationError.incomplete
        }
        guard
            let policyURL = URL(string: rawURL),
            policyURL.scheme?.lowercased() == "https",
            policyURL.host != nil,
            policyURL.user == nil,
            policyURL.password == nil,
            policyURL.query == nil,
            policyURL.fragment == nil
        else {
            throw ValidationError.invalidURL
        }
        guard
            let publicKeyData = Data(base64Encoded: rawPublicKey),
            publicKeyData.count == 32
        else {
            throw ValidationError.invalidPublicKey
        }

        self.policyURL = policyURL
        self.publicKeyData = publicKeyData
    }

    static func load(bundle: Bundle = .main) -> Result<Self, ValidationError> {
        do {
            return .success(try Self(infoDictionary: bundle.infoDictionary ?? [:]))
        } catch let error as ValidationError {
            return .failure(error)
        } catch {
            return .failure(.incomplete)
        }
    }
}

struct ProviderCapabilityPolicyPayload: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let revision: Int
    let incidentID: String
    let issuedAt: String
    let expiresAt: String
    let minimumBuild: Int?
    let maximumBuild: Int?
    let disabledCapabilities: [ProviderCapability]
}

private struct ProviderCapabilityPolicyEnvelope: Codable, Sendable {
    let payload: String
    let signature: String
}

struct ProviderCapabilityPolicySnapshot: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case unconfigured
        case ready
        case disabled
        case refreshFailed
    }

    let state: State
    let isConfigured: Bool
    let disabledCapabilities: [ProviderCapability]
    let incidentID: String?
    let expiresAt: Date?
    let lastCheckedAt: Date?
    let detail: String

    static var loading: ProviderCapabilityPolicySnapshot {
        ProviderCapabilityPolicySnapshot(
            state: .unconfigured,
            isConfigured: false,
            disabledCapabilities: [],
            incidentID: nil,
            expiresAt: nil,
            lastCheckedAt: nil,
            detail: L10n.text("Checking the signed provider safety policy…")
        )
    }
}

enum ProviderCapabilityPolicyError: Error, Equatable, LocalizedError {
    case disabled(
        capability: ProviderCapability,
        incidentID: String,
        expiresAt: Date
    )
    case invalidResponse
    case responseTooLarge
    case invalidEnvelope
    case invalidSignature
    case invalidPayload
    case expired
    case replayedRevision
    case revisionConflict

    var errorDescription: String? {
        switch self {
        case .disabled(let capability, let incidentID, _):
            return L10n.format(
                "%@ is temporarily disabled by a signed OpenWhisper safety policy (incident %@). No audio or transcript was sent. Use the OpenAI-Compatible Recovery route or try again later.",
                capability.title,
                incidentID
            )
        case .invalidResponse:
            return L10n.text("The provider safety policy server returned an invalid response.")
        case .responseTooLarge:
            return L10n.text("The provider safety policy response exceeded the allowed size.")
        case .invalidEnvelope:
            return L10n.text("The provider safety policy envelope is invalid.")
        case .invalidSignature:
            return L10n.text("The provider safety policy signature is invalid.")
        case .invalidPayload:
            return L10n.text("The provider safety policy payload is invalid.")
        case .expired:
            return L10n.text("The provider safety policy has expired.")
        case .replayedRevision:
            return L10n.text("An older provider safety policy revision was rejected.")
        case .revisionConflict:
            return L10n.text("A conflicting provider safety policy revision was rejected.")
        }
    }
}

protocol ProviderCapabilityChecking: Sendable {
    func require(_ capability: ProviderCapability) async throws
    func refresh(force: Bool) async -> ProviderCapabilityPolicySnapshot
    func snapshot() async -> ProviderCapabilityPolicySnapshot
}

actor ProviderCapabilityPolicyController: ProviderCapabilityChecking {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let shared = ProviderCapabilityPolicyController()

    private struct VerifiedPolicy: Sendable {
        let payload: ProviderCapabilityPolicyPayload
        let payloadData: Data
        let envelopeData: Data
        let issuedAt: Date
        let expiresAt: Date
    }

    private static let maximumResponseBytes = 64 * 1024
    private static let maximumPolicyLifetime: TimeInterval = 31 * 24 * 60 * 60
    private static let allowedClockSkew: TimeInterval = 5 * 60
    private static let defaultRefreshInterval: TimeInterval = 15 * 60

    private let configuration: Result<
        ProviderCapabilityPolicyConfiguration,
        ProviderCapabilityPolicyConfiguration.ValidationError
    >
    private let cacheURL: URL
    private let currentBuild: Int
    private let refreshInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let dataLoader: DataLoader

    private var didLoadCache = false
    private var currentPolicy: VerifiedPolicy?
    private var highestAcceptedRevision = 0
    private var lastRefreshAttempt: Date?
    private var lastSuccessfulRefresh: Date?
    private var lastRefreshError: String?
    private var refreshTask: Task<
        Result<VerifiedPolicy, ProviderCapabilityPolicyError>,
        Never
    >?

    init(
        configuration: Result<
            ProviderCapabilityPolicyConfiguration,
            ProviderCapabilityPolicyConfiguration.ValidationError
        > = ProviderCapabilityPolicyConfiguration.load(),
        cacheURL: URL = ConfigStore().directoryURL
            .appendingPathComponent("provider-capability-policy.json"),
        currentBuild: Int = Int(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        ) ?? 1,
        refreshInterval: TimeInterval = defaultRefreshInterval,
        now: @escaping @Sendable () -> Date = Date.init,
        dataLoader: @escaping DataLoader = { request in
            try await SecureHTTPClient.data(for: request)
        }
    ) {
        self.configuration = configuration
        self.cacheURL = cacheURL
        self.currentBuild = max(1, currentBuild)
        self.refreshInterval = max(0, refreshInterval)
        self.now = now
        self.dataLoader = dataLoader
    }

    func require(_ capability: ProviderCapability) async throws {
        loadCachedPolicyIfNeeded()
        _ = await refresh(force: false)

        guard
            let policy = effectivePolicy(at: now()),
            policy.payload.disabledCapabilities.contains(capability)
        else {
            return
        }

        throw ProviderCapabilityPolicyError.disabled(
            capability: capability,
            incidentID: policy.payload.incidentID,
            expiresAt: policy.expiresAt
        )
    }

    func refresh(force: Bool = false) async -> ProviderCapabilityPolicySnapshot {
        loadCachedPolicyIfNeeded()

        guard case .success(let configuration) = configuration else {
            return makeSnapshot(at: now())
        }

        let refreshDate = now()
        if
            !force,
            refreshTask == nil,
            let lastRefreshAttempt,
            refreshDate.timeIntervalSince(lastRefreshAttempt) < refreshInterval
        {
            return makeSnapshot(at: refreshDate)
        }

        if let refreshTask {
            let result = await refreshTask.value
            applyRefreshResult(result, checkedAt: now())
            return makeSnapshot(at: now())
        }

        lastRefreshAttempt = refreshDate
        let publicKeyData = configuration.publicKeyData
        let policyURL = configuration.policyURL
        let dataLoader = dataLoader
        let validationDate = refreshDate
        let task: Task<
            Result<VerifiedPolicy, ProviderCapabilityPolicyError>,
            Never
        > = Task {
            do {
                return Result.success(
                    try await Self.fetchPolicy(
                        policyURL: policyURL,
                        publicKeyData: publicKeyData,
                        validationDate: validationDate,
                        dataLoader: dataLoader
                    )
                )
            } catch let error as ProviderCapabilityPolicyError {
                return Result.failure(error)
            } catch {
                return Result.failure(.invalidResponse)
            }
        }
        refreshTask = task

        let result = await task.value
        refreshTask = nil
        applyRefreshResult(result, checkedAt: now())
        return makeSnapshot(at: now())
    }

    func snapshot() async -> ProviderCapabilityPolicySnapshot {
        loadCachedPolicyIfNeeded()
        return makeSnapshot(at: now())
    }

    private func applyRefreshResult(
        _ result: Result<VerifiedPolicy, ProviderCapabilityPolicyError>,
        checkedAt: Date
    ) {
        switch result {
        case .success(let policy):
            do {
                try accept(policy)
                lastSuccessfulRefresh = checkedAt
                lastRefreshError = nil
            } catch let error as ProviderCapabilityPolicyError {
                lastRefreshError = error.localizedDescription
            } catch {
                lastRefreshError = ProviderCapabilityPolicyError.invalidPayload
                    .localizedDescription
            }
        case .failure(let error):
            lastRefreshError = error.localizedDescription
        }
    }

    private func accept(_ policy: VerifiedPolicy) throws {
        guard policy.payload.revision >= highestAcceptedRevision else {
            throw ProviderCapabilityPolicyError.replayedRevision
        }
        if
            policy.payload.revision == highestAcceptedRevision,
            let currentPolicy,
            currentPolicy.payloadData != policy.payloadData
        {
            throw ProviderCapabilityPolicyError.revisionConflict
        }

        highestAcceptedRevision = policy.payload.revision
        currentPolicy = policy
        try persist(policy.envelopeData)
    }

    private func effectivePolicy(at date: Date) -> VerifiedPolicy? {
        guard
            let currentPolicy,
            currentPolicy.expiresAt > date,
            currentPolicy.issuedAt <= date.addingTimeInterval(Self.allowedClockSkew),
            currentPolicy.expiresAt > currentPolicy.issuedAt,
            currentPolicy.expiresAt.timeIntervalSince(currentPolicy.issuedAt)
                <= Self.maximumPolicyLifetime,
            buildIsCovered(by: currentPolicy.payload)
        else {
            return nil
        }
        return currentPolicy
    }

    private func buildIsCovered(
        by payload: ProviderCapabilityPolicyPayload
    ) -> Bool {
        if let minimumBuild = payload.minimumBuild, currentBuild < minimumBuild {
            return false
        }
        if let maximumBuild = payload.maximumBuild, currentBuild > maximumBuild {
            return false
        }
        return true
    }

    private func makeSnapshot(at date: Date) -> ProviderCapabilityPolicySnapshot {
        switch configuration {
        case .failure(let error):
            return ProviderCapabilityPolicySnapshot(
                state: .unconfigured,
                isConfigured: false,
                disabledCapabilities: [],
                incidentID: nil,
                expiresAt: nil,
                lastCheckedAt: lastSuccessfulRefresh ?? lastRefreshAttempt,
                detail: error.localizedDescription
            )
        case .success:
            break
        }

        if let policy = effectivePolicy(at: date) {
            let disabled = policy.payload.disabledCapabilities
                .sorted { $0.rawValue < $1.rawValue }
            if !disabled.isEmpty {
                return ProviderCapabilityPolicySnapshot(
                    state: .disabled,
                    isConfigured: true,
                    disabledCapabilities: disabled,
                    incidentID: policy.payload.incidentID,
                    expiresAt: policy.expiresAt,
                    lastCheckedAt: lastSuccessfulRefresh ?? lastRefreshAttempt,
                    detail: L10n.format(
                        "Signed safety policy %@ is active and has disabled %ld provider capability.",
                        policy.payload.incidentID,
                        disabled.count
                    )
                )
            }
        }

        if let lastRefreshError {
            return ProviderCapabilityPolicySnapshot(
                state: .refreshFailed,
                isConfigured: true,
                disabledCapabilities: [],
                incidentID: nil,
                expiresAt: nil,
                lastCheckedAt: lastSuccessfulRefresh ?? lastRefreshAttempt,
                detail: L10n.format(
                    "The signed provider safety policy could not be refreshed: %@",
                    lastRefreshError
                )
            )
        }

        return ProviderCapabilityPolicySnapshot(
            state: .ready,
            isConfigured: true,
            disabledCapabilities: [],
            incidentID: nil,
            expiresAt: nil,
            lastCheckedAt: lastSuccessfulRefresh ?? lastRefreshAttempt,
            detail: L10n.text(
                "The signed provider safety policy is current. Managed capabilities are available."
            )
        )
    }

    private func loadCachedPolicyIfNeeded() {
        guard !didLoadCache else {
            return
        }
        didLoadCache = true
        guard case .success(let configuration) = configuration else {
            return
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: cacheURL.path
            )
            guard
                attributes[.type] as? FileAttributeType == .typeRegular,
                (attributes[.size] as? NSNumber)?.intValue ?? 0
                    <= Self.maximumResponseBytes
            else {
                return
            }
            let data = try Data(contentsOf: cacheURL)
            let policy = try Self.decodeVerifiedPolicy(
                envelopeData: data,
                publicKeyData: configuration.publicKeyData
            )
            let validationDate = now()
            guard
                policy.issuedAt
                    <= validationDate.addingTimeInterval(Self.allowedClockSkew),
                policy.expiresAt > policy.issuedAt,
                policy.expiresAt.timeIntervalSince(policy.issuedAt)
                    <= Self.maximumPolicyLifetime
            else {
                return
            }
            highestAcceptedRevision = policy.payload.revision
            currentPolicy = policy
        } catch {
            currentPolicy = nil
            highestAcceptedRevision = 0
        }
    }

    private func persist(_ data: Data) throws {
        let directoryURL = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directoryURL.path
        )
        try data.write(to: cacheURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: cacheURL.path
        )
    }

    private static func fetchPolicy(
        policyURL: URL,
        publicKeyData: Data,
        validationDate: Date,
        dataLoader: DataLoader
    ) async throws -> VerifiedPolicy {
        var request = URLRequest(url: policyURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(ProductIdentity.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await dataLoader(request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw ProviderCapabilityPolicyError.invalidResponse
        }
        guard data.count <= maximumResponseBytes else {
            throw ProviderCapabilityPolicyError.responseTooLarge
        }

        let policy = try decodeVerifiedPolicy(
            envelopeData: data,
            publicKeyData: publicKeyData
        )
        guard policy.expiresAt > validationDate else {
            throw ProviderCapabilityPolicyError.expired
        }
        guard
            policy.issuedAt
                <= validationDate.addingTimeInterval(allowedClockSkew),
            policy.expiresAt > policy.issuedAt,
            policy.expiresAt.timeIntervalSince(policy.issuedAt)
                <= maximumPolicyLifetime
        else {
            throw ProviderCapabilityPolicyError.invalidPayload
        }
        return policy
    }

    private static func decodeVerifiedPolicy(
        envelopeData: Data,
        publicKeyData: Data
    ) throws -> VerifiedPolicy {
        guard
            let envelope = try? JSONDecoder().decode(
                ProviderCapabilityPolicyEnvelope.self,
                from: envelopeData
            ),
            let payloadData = Data(base64Encoded: envelope.payload),
            let signatureData = Data(base64Encoded: envelope.signature)
        else {
            throw ProviderCapabilityPolicyError.invalidEnvelope
        }
        guard
            let publicKey = try? Curve25519.Signing.PublicKey(
                rawRepresentation: publicKeyData
            ),
            publicKey.isValidSignature(signatureData, for: payloadData)
        else {
            throw ProviderCapabilityPolicyError.invalidSignature
        }
        guard
            payloadData.count <= maximumResponseBytes,
            let payload = try? JSONDecoder().decode(
                ProviderCapabilityPolicyPayload.self,
                from: payloadData
            ),
            payload.schemaVersion == 1,
            payload.revision > 0,
            validIncidentID(payload.incidentID),
            Set(payload.disabledCapabilities).count
                == payload.disabledCapabilities.count,
            let issuedAt = parseDate(payload.issuedAt),
            let expiresAt = parseDate(payload.expiresAt),
            validBuildRange(payload)
        else {
            throw ProviderCapabilityPolicyError.invalidPayload
        }

        return VerifiedPolicy(
            payload: payload,
            payloadData: payloadData,
            envelopeData: envelopeData,
            issuedAt: issuedAt,
            expiresAt: expiresAt
        )
    }

    private static func validIncidentID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "._-"))
                .contains($0)
        }
    }

    private static func validBuildRange(
        _ payload: ProviderCapabilityPolicyPayload
    ) -> Bool {
        if let minimumBuild = payload.minimumBuild, minimumBuild < 1 {
            return false
        }
        if let maximumBuild = payload.maximumBuild, maximumBuild < 1 {
            return false
        }
        if
            let minimumBuild = payload.minimumBuild,
            let maximumBuild = payload.maximumBuild,
            minimumBuild > maximumBuild
        {
            return false
        }
        return true
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
