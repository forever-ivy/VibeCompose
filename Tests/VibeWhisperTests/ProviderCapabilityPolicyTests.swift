import CryptoKit
import Foundation
import Testing
@testable import VibeWhisper

private struct TestCapabilityEnvelope: Codable {
    let payload: String
    let signature: String
}

private final class CapabilityPolicyResponses: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Data]
    private(set) var requestCount = 0

    init(_ responses: [Data]) {
        self.responses = responses
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        lock.lock()
        requestCount += 1
        let data = responses.isEmpty ? Data() : responses.removeFirst()
        lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }
}

private struct AlwaysDisabledCapabilityPolicy: ProviderCapabilityChecking {
    let capability: ProviderCapability

    func require(_ requestedCapability: ProviderCapability) async throws {
        guard requestedCapability == capability else {
            return
        }
        throw ProviderCapabilityPolicyError.disabled(
            capability: capability,
            incidentID: "OW-INC-TEST",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000)
        )
    }

    func refresh(force: Bool) async -> ProviderCapabilityPolicySnapshot {
        snapshotValue
    }

    func snapshot() async -> ProviderCapabilityPolicySnapshot {
        snapshotValue
    }

    private var snapshotValue: ProviderCapabilityPolicySnapshot {
        ProviderCapabilityPolicySnapshot(
            state: .disabled,
            isConfigured: true,
            disabledCapabilities: [capability],
            incidentID: "OW-INC-TEST",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_800_000_000),
            detail: "disabled"
        )
    }
}

private func policyConfiguration(
    publicKey: Curve25519.Signing.PublicKey
) throws -> ProviderCapabilityPolicyConfiguration {
    try ProviderCapabilityPolicyConfiguration(
        infoDictionary: [
            "OWCapabilityPolicyURL":
                "https://updates.vibewhisper.example/provider-capabilities.json",
            "OWCapabilityPublicEDKey":
                publicKey.rawRepresentation.base64EncodedString(),
        ]
    )
}

private func policyPayload(
    revision: Int,
    incidentID: String,
    now: Date,
    disabled: [ProviderCapability],
    minimumBuild: Int? = 1,
    maximumBuild: Int? = nil
) -> ProviderCapabilityPolicyPayload {
    ProviderCapabilityPolicyPayload(
        schemaVersion: 1,
        revision: revision,
        incidentID: incidentID,
        issuedAt: policyDate(now.addingTimeInterval(-60)),
        expiresAt: policyDate(now.addingTimeInterval(3_600)),
        minimumBuild: minimumBuild,
        maximumBuild: maximumBuild,
        disabledCapabilities: disabled
    )
}

private func signedPolicy(
    _ payload: ProviderCapabilityPolicyPayload,
    privateKey: Curve25519.Signing.PrivateKey
) throws -> Data {
    let payloadEncoder = JSONEncoder()
    payloadEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let payloadData = try payloadEncoder.encode(payload)
    let signature = try privateKey.signature(for: payloadData)
    let envelope = TestCapabilityEnvelope(
        payload: payloadData.base64EncodedString(),
        signature: signature.base64EncodedString()
    )
    let envelopeEncoder = JSONEncoder()
    envelopeEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try envelopeEncoder.encode(envelope)
}

private func policyDate(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func capabilityTestDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "VibeWhisperCapabilityPolicyTests-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}

@Test
func capabilityPolicyConfigurationRequiresPairedHTTPSURLAndEd25519Key() throws {
    let key = Curve25519.Signing.PrivateKey()
    let configuration = try policyConfiguration(publicKey: key.publicKey)

    #expect(
        configuration.policyURL.absoluteString
            == "https://updates.vibewhisper.example/provider-capabilities.json"
    )
    #expect(configuration.publicKeyData == key.publicKey.rawRepresentation)

    #expect(
        throws: ProviderCapabilityPolicyConfiguration.ValidationError.incomplete
    ) {
        _ = try ProviderCapabilityPolicyConfiguration(infoDictionary: [:])
    }
    #expect(
        throws: ProviderCapabilityPolicyConfiguration.ValidationError.invalidURL
    ) {
        _ = try ProviderCapabilityPolicyConfiguration(
            infoDictionary: [
                "OWCapabilityPolicyURL":
                    "https://updates.vibewhisper.example/policy.json?token=secret",
                "OWCapabilityPublicEDKey":
                    key.publicKey.rawRepresentation.base64EncodedString(),
            ]
        )
    }
    #expect(
        throws: ProviderCapabilityPolicyConfiguration.ValidationError.invalidPublicKey
    ) {
        _ = try ProviderCapabilityPolicyConfiguration(
            infoDictionary: [
                "OWCapabilityPolicyURL":
                    "https://updates.vibewhisper.example/policy.json",
                "OWCapabilityPublicEDKey":
                    Data(repeating: 0x11, count: 31).base64EncodedString(),
            ]
        )
    }
}

@Test
func signedCapabilityPolicyBlocksBeforeManagedProviderUseAndCachesOwnerOnly()
    async throws
{
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let key = Curve25519.Signing.PrivateKey()
    let envelope = try signedPolicy(
        policyPayload(
            revision: 4,
            incidentID: "OW-INC-UPSTREAM-004",
            now: now,
            disabled: [.managedTranscription]
        ),
        privateKey: key
    )
    let responses = CapabilityPolicyResponses([envelope])
    let directoryURL = try capabilityTestDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let cacheURL = directoryURL.appendingPathComponent("policy.json")
    let controller = ProviderCapabilityPolicyController(
        configuration: .success(
            try policyConfiguration(publicKey: key.publicKey)
        ),
        cacheURL: cacheURL,
        currentBuild: 1,
        refreshInterval: 900,
        now: { now },
        dataLoader: { request in
            try responses.load(request)
        }
    )

    let snapshot = await controller.refresh(force: true)
    #expect(snapshot.state == .disabled)
    #expect(snapshot.disabledCapabilities == [.managedTranscription])
    #expect(snapshot.incidentID == "OW-INC-UPSTREAM-004")

    do {
        try await controller.require(.managedTranscription)
        Issue.record("Signed policy did not block managed transcription.")
    } catch let error as ProviderCapabilityPolicyError {
        guard case .disabled(let capability, let incidentID, _) = error else {
            Issue.record("Unexpected policy error: \(error)")
            return
        }
        #expect(capability == .managedTranscription)
        #expect(incidentID == "OW-INC-UPSTREAM-004")
    }

    #expect(responses.count() == 1)
    let attributes = try FileManager.default.attributesOfItem(
        atPath: cacheURL.path
    )
    #expect(
        ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777
            == 0o600
    )
}

@Test
func managedTranscriberChecksSignedPolicyBeforeReadingAudioOrResolvingAuth()
    async throws
{
    var config = AppConfig().transcription
    config.provider = .chatGPTManagedAuth
    let authManager = FakeChatGPTAuthManager()
    let transcriber = ChatGPTTranscriber(
        authManager: authManager,
        config: config,
        providerCapabilityPolicy: AlwaysDisabledCapabilityPolicy(
            capability: .managedTranscription
        ),
        uploadLoader: { _, _ in
            Issue.record("Disabled managed transcription attempted an upload.")
            throw URLError(.cancelled)
        }
    )
    let missingAudio = RecordedAudio(
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).wav"),
        durationMs: 1_000
    )

    do {
        _ = try await transcriber.transcribe(missingAudio)
        Issue.record("Disabled managed transcription unexpectedly proceeded.")
    } catch let error as ProviderCapabilityPolicyError {
        guard case .disabled(let capability, _, _) = error else {
            Issue.record("Unexpected policy error: \(error)")
            return
        }
        #expect(capability == .managedTranscription)
    }
    #expect(authManager.bestCallCount == 0)
    #expect(authManager.refreshCallCount == 0)
}

@Test
func textPolisherChecksSignedPolicyBeforeResolvingAuthOrSendingText()
    async throws
{
    let authManager = FakeChatGPTAuthManager()
    let polisher = OpenAICompatibleTextPolisher(
        config: TextPolishConfig(),
        chatGPTAuthProvider: authManager,
        chatGPTAuthAvailable: true,
        providerCapabilityPolicy: AlwaysDisabledCapabilityPolicy(
            capability: .chatGPTTextPolish
        ),
        dataLoader: { _ in
            Issue.record("Disabled ChatGPT AI Polish attempted a request.")
            throw URLError(.cancelled)
        }
    )

    do {
        _ = try await polisher.polish(
            text: "private transcript",
            terminologyEntries: [],
            hintTerms: []
        )
        Issue.record("Disabled ChatGPT AI Polish unexpectedly proceeded.")
    } catch let error as ProviderCapabilityPolicyError {
        guard case .disabled(let capability, _, _) = error else {
            Issue.record("Unexpected policy error: \(error)")
            return
        }
        #expect(capability == .chatGPTTextPolish)
    }
    #expect(authManager.bestCallCount == 0)
    #expect(authManager.refreshCallCount == 0)
}

@Test
func invalidOrReplayedPolicyCannotReplaceActiveSignedDisable() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let key = Curve25519.Signing.PrivateKey()
    let otherKey = Curve25519.Signing.PrivateKey()
    let validDisable = try signedPolicy(
        policyPayload(
            revision: 7,
            incidentID: "OW-INC-007",
            now: now,
            disabled: [.managedTranscription]
        ),
        privateKey: key
    )
    let invalidEnable = try signedPolicy(
        policyPayload(
            revision: 8,
            incidentID: "OW-INC-008",
            now: now,
            disabled: []
        ),
        privateKey: otherKey
    )
    let replayedEnable = try signedPolicy(
        policyPayload(
            revision: 6,
            incidentID: "OW-INC-006",
            now: now,
            disabled: []
        ),
        privateKey: key
    )
    let responses = CapabilityPolicyResponses([
        validDisable,
        invalidEnable,
        replayedEnable,
    ])
    let directoryURL = try capabilityTestDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let cacheURL = directoryURL.appendingPathComponent("policy.json")
    let controller = ProviderCapabilityPolicyController(
        configuration: .success(
            try policyConfiguration(publicKey: key.publicKey)
        ),
        cacheURL: cacheURL,
        currentBuild: 1,
        refreshInterval: 0,
        now: { now },
        dataLoader: { request in
            try responses.load(request)
        }
    )

    _ = await controller.refresh(force: true)
    let cachedDisable = try Data(contentsOf: cacheURL)
    _ = await controller.refresh(force: true)
    #expect(try Data(contentsOf: cacheURL) == cachedDisable)
    _ = await controller.refresh(force: true)
    #expect(try Data(contentsOf: cacheURL) == cachedDisable)

    do {
        try await controller.require(.managedTranscription)
        Issue.record("Invalid or replayed policy cleared an active disable.")
    } catch let error as ProviderCapabilityPolicyError {
        guard case .disabled = error else {
            Issue.record("Unexpected policy error: \(error)")
            return
        }
    }
}

@Test
func higherRevisionSignedPolicyCanRestoreCapabilities() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let key = Curve25519.Signing.PrivateKey()
    let disable = try signedPolicy(
        policyPayload(
            revision: 10,
            incidentID: "OW-INC-010",
            now: now,
            disabled: [.managedTranscription, .chatGPTTextPolish]
        ),
        privateKey: key
    )
    let restore = try signedPolicy(
        policyPayload(
            revision: 11,
            incidentID: "OW-INC-011-RESOLVED",
            now: now,
            disabled: []
        ),
        privateKey: key
    )
    let responses = CapabilityPolicyResponses([disable, restore])
    let directoryURL = try capabilityTestDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let controller = ProviderCapabilityPolicyController(
        configuration: .success(
            try policyConfiguration(publicKey: key.publicKey)
        ),
        cacheURL: directoryURL.appendingPathComponent("policy.json"),
        currentBuild: 1,
        refreshInterval: 0,
        now: { now },
        dataLoader: { request in
            try responses.load(request)
        }
    )

    #expect((await controller.refresh(force: true)).state == .disabled)
    let restoredSnapshot = await controller.refresh(force: true)
    #expect(restoredSnapshot.state == .ready)
    #expect(restoredSnapshot.disabledCapabilities.isEmpty)
    try await controller.require(.managedTranscription)
    try await controller.require(.chatGPTTextPolish)
}

@Test
func capabilityPolicyOutsideCurrentBuildDoesNotBlock() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let key = Curve25519.Signing.PrivateKey()
    let envelope = try signedPolicy(
        policyPayload(
            revision: 12,
            incidentID: "OW-INC-FUTURE",
            now: now,
            disabled: [.managedTranscription],
            minimumBuild: 5
        ),
        privateKey: key
    )
    let directoryURL = try capabilityTestDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let controller = ProviderCapabilityPolicyController(
        configuration: .success(
            try policyConfiguration(publicKey: key.publicKey)
        ),
        cacheURL: directoryURL.appendingPathComponent("policy.json"),
        currentBuild: 1,
        refreshInterval: 900,
        now: { now },
        dataLoader: { request in
            (
                envelope,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
    )

    let snapshot = await controller.refresh(force: true)
    #expect(snapshot.state == .ready)
    try await controller.require(.managedTranscription)
}

@Test
func cachedPolicyCannotBypassMaximumLifetimeValidation() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let key = Curve25519.Signing.PrivateKey()
    let overlongPayload = ProviderCapabilityPolicyPayload(
        schemaVersion: 1,
        revision: 99,
        incidentID: "OW-INC-OVERLONG",
        issuedAt: policyDate(now.addingTimeInterval(-60)),
        expiresAt: policyDate(now.addingTimeInterval(60 * 24 * 60 * 60)),
        minimumBuild: 1,
        maximumBuild: nil,
        disabledCapabilities: [.managedTranscription]
    )
    let envelope = try signedPolicy(overlongPayload, privateKey: key)
    let directoryURL = try capabilityTestDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let cacheURL = directoryURL.appendingPathComponent("policy.json")
    try envelope.write(to: cacheURL)

    let controller = ProviderCapabilityPolicyController(
        configuration: .success(
            try policyConfiguration(publicKey: key.publicKey)
        ),
        cacheURL: cacheURL,
        currentBuild: 1,
        refreshInterval: 900,
        now: { now },
        dataLoader: { request in
            (
                Data(),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }
    )

    let snapshot = await controller.snapshot()
    #expect(snapshot.state == .ready)
    #expect(snapshot.disabledCapabilities.isEmpty)
}
