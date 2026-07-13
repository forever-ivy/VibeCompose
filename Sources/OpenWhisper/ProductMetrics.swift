import Foundation

enum ProductMetricEvent: String, Codable, CaseIterable, Sendable {
    case appLaunch = "app_launch"
    case onboardingStepCompleted = "onboarding_step_completed"
    case dictationStarted = "dictation_started"
    case dictationSucceeded = "dictation_succeeded"
    case dictationFailed = "dictation_failed"
    case dictationDiscarded = "dictation_discarded"
    case retryStarted = "retry_started"
    case retrySucceeded = "retry_succeeded"
    case retryFailed = "retry_failed"
}

enum ProductMetricOnboardingStep: String, Codable, CaseIterable, Sendable {
    case welcome
    case connect
    case microphone
    case practice

    init(_ step: OnboardingStep) {
        switch step {
        case .welcome:
            self = .welcome
        case .connect:
            self = .connect
        case .microphone:
            self = .microphone
        case .practice:
            self = .practice
        }
    }
}

enum ProductMetricDeliveryStatus: String, Codable, CaseIterable, Sendable {
    case insertedVerified = "inserted_verified"
    case pasteDispatched = "paste_dispatched"
    case clipboard

    init(_ outcome: InjectionOutcome) {
        switch outcome {
        case .insertedAndVerified:
            self = .insertedVerified
        case .pasteDispatchedClipboardRetained:
            self = .pasteDispatched
        case .copiedToClipboard:
            self = .clipboard
        }
    }
}

enum ProductMetricFailureCategory: String, Codable, CaseIterable, Sendable {
    case setup
    case recording
    case transcription
    case transcriptionAuthentication = "transcription_authentication"
    case transcriptionChallenge = "transcription_challenge"
    case transcriptionRateLimited = "transcription_rate_limited"
    case transcriptionContractChanged = "transcription_contract_changed"
    case transcriptionServiceUnavailable =
        "transcription_service_unavailable"
    case transcriptionNetwork = "transcription_network"
    case transcriptionInvalidResponse =
        "transcription_invalid_response"
    case injection
}

enum ProductMetricAudioDurationBucket: String, Codable, CaseIterable, Sendable {
    case under5Seconds = "under_5s"
    case seconds5To15 = "5_to_15s"
    case seconds15To30 = "15_to_30s"
    case seconds30To60 = "30_to_60s"
    case over60Seconds = "over_60s"

    init(milliseconds: Int) {
        switch max(0, milliseconds) {
        case ..<5_000:
            self = .under5Seconds
        case ..<15_000:
            self = .seconds5To15
        case ..<30_000:
            self = .seconds15To30
        case ..<60_000:
            self = .seconds30To60
        default:
            self = .over60Seconds
        }
    }
}

enum ProductMetricLatencyBucket: String, Codable, CaseIterable, Sendable {
    case under2Seconds = "under_2s"
    case seconds2To5 = "2_to_5s"
    case seconds5To10 = "5_to_10s"
    case seconds10To30 = "10_to_30s"
    case over30Seconds = "over_30s"

    init(milliseconds: Int) {
        switch max(0, milliseconds) {
        case ..<2_000:
            self = .under2Seconds
        case ..<5_000:
            self = .seconds2To5
        case ..<10_000:
            self = .seconds5To10
        case ..<30_000:
            self = .seconds10To30
        default:
            self = .over30Seconds
        }
    }
}

struct ProductMetricsEnvironment: Sendable, Equatable {
    let productVersion: String
    let productBuild: String

    static func live() -> ProductMetricsEnvironment {
        let bundle = Bundle.main
        return ProductMetricsEnvironment(
            productVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? ProductIdentity.runtimeVersion,
            productBuild: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "development"
        )
    }
}

enum ProductMetricsPrivacy {
    static func safeVersion(_ value: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "0123456789.-+"
        )
        let bounded = String(value.prefix(32))
        guard
            !bounded.isEmpty,
            bounded.unicodeScalars.allSatisfy(allowed.contains)
        else {
            return "other"
        }
        return bounded
    }
}

struct ProductMetricSample: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let timestamp: Date
    let productVersion: String
    let productBuild: String
    let event: ProductMetricEvent
    let onboardingStep: ProductMetricOnboardingStep?
    let provider: TranscriptionProvider?
    let audioDurationBucket: ProductMetricAudioDurationBucket?
    let latencyBucket: ProductMetricLatencyBucket?
    let deliveryStatus: ProductMetricDeliveryStatus?
    let failureCategory: ProductMetricFailureCategory?

    init(
        timestamp: Date = Date(),
        environment: ProductMetricsEnvironment = .live(),
        event: ProductMetricEvent,
        onboardingStep: ProductMetricOnboardingStep? = nil,
        provider: TranscriptionProvider? = nil,
        audioDurationMs: Int? = nil,
        totalProcessingMs: Int? = nil,
        deliveryStatus: ProductMetricDeliveryStatus? = nil,
        failureCategory: ProductMetricFailureCategory? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.timestamp = timestamp
        productVersion = environment.productVersion
        productBuild = environment.productBuild
        self.event = event
        self.onboardingStep = onboardingStep
        self.provider = provider
        audioDurationBucket = audioDurationMs.map(
            ProductMetricAudioDurationBucket.init(milliseconds:)
        )
        latencyBucket = totalProcessingMs.map(
            ProductMetricLatencyBucket.init(milliseconds:)
        )
        self.deliveryStatus = deliveryStatus
        self.failureCategory = failureCategory
    }
}

enum ProductMetricsStorageError: LocalizedError {
    case unsafeStorage(String)

    var errorDescription: String? {
        switch self {
        case .unsafeStorage(let path):
            return "OpenWhisper refused unsafe product metrics storage at \(path)."
        }
    }
}

protocol ProductMetricsRecording: Sendable {
    func record(
        _ sample: ProductMetricSample,
        retention: DiagnosticsRetentionPolicy
    ) throws
    func prune(retention: DiagnosticsRetentionPolicy) throws
}

final class ProductMetricsRecorder: ProductMetricsRecording, @unchecked Sendable {
    private let fileManager: FileManager
    let directoryURL: URL
    private let lock = NSLock()
    private let maximumReadBytes: Int

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        maximumReadBytes: Int = 2_000_000
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
            ?? ProductIdentity.applicationSupportURL(
                homeDirectoryURL: fileManager.homeDirectoryForCurrentUser
            )
        self.maximumReadBytes = max(64_000, maximumReadBytes)
    }

    func record(
        _ sample: ProductMetricSample,
        retention: DiagnosticsRetentionPolicy
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        var samples = try loadSamplesUnlocked()
        samples.append(sample)
        try rewrite(retained(samples, policy: retention))
    }

    func loadRecent(limit: Int = 5_000) throws -> [ProductMetricSample] {
        lock.lock()
        defer { lock.unlock() }
        return Array(
            try loadSamplesUnlocked().suffix(max(0, limit))
        )
    }

    func prune(retention: DiagnosticsRetentionPolicy) throws {
        lock.lock()
        defer { lock.unlock() }
        try rewrite(
            retained(
                try loadSamplesUnlocked(),
                policy: retention
            )
        )
    }

    private func loadSamplesUnlocked() throws -> [ProductMetricSample] {
        try validateExistingStorage()
        let lines = try JSONLTailReader.lines(
            at: dataURL,
            fileManager: fileManager,
            maximumBytes: maximumReadBytes
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return lines.compactMap { line in
            try? decoder.decode(
                ProductMetricSample.self,
                from: Data(line.utf8)
            )
        }
        .filter {
            $0.schemaVersion
                == ProductMetricSample.currentSchemaVersion
        }
    }

    private func retained(
        _ samples: [ProductMetricSample],
        policy: DiagnosticsRetentionPolicy
    ) -> [ProductMetricSample] {
        guard policy.maxRecords > 0 else {
            return []
        }
        return samples
            .filter { $0.timestamp >= policy.cutoffDate }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(policy.maxRecords)
            .map { $0 }
    }

    private func rewrite(_ samples: [ProductMetricSample]) throws {
        try validateExistingStorage()
        if samples.isEmpty {
            if fileManager.fileExists(atPath: dataURL.path) {
                try fileManager.removeItem(at: dataURL)
            }
            return
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directoryURL.path
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try samples.reduce(into: Data()) { partial, sample in
            partial.append(try encoder.encode(sample))
            partial.append(0x0A)
        }
        try data.write(to: dataURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: dataURL.path
        )
    }

    private func validateExistingStorage() throws {
        if fileManager.fileExists(atPath: directoryURL.path) {
            let values = try directoryURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard
                values.isDirectory == true,
                values.isSymbolicLink != true
            else {
                throw ProductMetricsStorageError.unsafeStorage(
                    directoryURL.path
                )
            }
        }

        guard fileManager.fileExists(atPath: dataURL.path) else {
            return
        }
        let values = try dataURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw ProductMetricsStorageError.unsafeStorage(dataURL.path)
        }
    }

    private var dataURL: URL {
        directoryURL.appendingPathComponent("product-metrics.jsonl")
    }
}

struct ProductMetricsReport: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let sampleCount: Int
    let eventCounts: [String: Int]
    let onboardingStepCounts: [String: Int]
    let providerCounts: [String: Int]
    let audioDurationBucketCounts: [String: Int]
    let latencyBucketCounts: [String: Int]
    let deliveryStatusCounts: [String: Int]
    let failureCategoryCounts: [String: Int]
    let productVersionCounts: [String: Int]
    let productBuildCounts: [String: Int]

    init(
        samples: [ProductMetricSample],
        generatedAt: Date = Date()
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        sampleCount = samples.count

        var eventCounts: [String: Int] = [:]
        var onboardingStepCounts: [String: Int] = [:]
        var providerCounts: [String: Int] = [:]
        var audioDurationBucketCounts: [String: Int] = [:]
        var latencyBucketCounts: [String: Int] = [:]
        var deliveryStatusCounts: [String: Int] = [:]
        var failureCategoryCounts: [String: Int] = [:]
        var productVersionCounts: [String: Int] = [:]
        var productBuildCounts: [String: Int] = [:]

        for sample in samples {
            Self.increment(sample.event.rawValue, in: &eventCounts)
            Self.increment(
                sample.onboardingStep?.rawValue,
                in: &onboardingStepCounts
            )
            Self.increment(
                sample.provider?.rawValue,
                in: &providerCounts
            )
            Self.increment(
                sample.audioDurationBucket?.rawValue,
                in: &audioDurationBucketCounts
            )
            Self.increment(
                sample.latencyBucket?.rawValue,
                in: &latencyBucketCounts
            )
            Self.increment(
                sample.deliveryStatus?.rawValue,
                in: &deliveryStatusCounts
            )
            Self.increment(
                sample.failureCategory?.rawValue,
                in: &failureCategoryCounts
            )
            Self.increment(
                ProductMetricsPrivacy.safeVersion(
                    sample.productVersion
                ),
                in: &productVersionCounts
            )
            Self.increment(
                ProductMetricsPrivacy.safeVersion(
                    sample.productBuild
                ),
                in: &productBuildCounts
            )
        }

        self.eventCounts = eventCounts
        self.onboardingStepCounts = onboardingStepCounts
        self.providerCounts = providerCounts
        self.audioDurationBucketCounts = audioDurationBucketCounts
        self.latencyBucketCounts = latencyBucketCounts
        self.deliveryStatusCounts = deliveryStatusCounts
        self.failureCategoryCounts = failureCategoryCounts
        self.productVersionCounts = productVersionCounts
        self.productBuildCounts = productBuildCounts
    }

    private static func increment(
        _ value: String?,
        in counts: inout [String: Int]
    ) {
        guard let value else {
            return
        }
        counts[value, default: 0] += 1
    }
}

enum ProductMetricsExportError: LocalizedError, Equatable {
    case destinationIsDirectory(String)

    var errorDescription: String? {
        switch self {
        case .destinationIsDirectory(let name):
            return L10n.format(
                "OpenWhisper cannot replace the folder named %@ with a product metrics report.",
                name
            )
        }
    }
}

struct ProductMetricsExporter {
    let fileManager: FileManager
    let applicationSupportURL: URL

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL
            ?? ProductIdentity.applicationSupportURL(
                homeDirectoryURL:
                    fileManager.homeDirectoryForCurrentUser
            )
    }

    static func suggestedFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "OpenWhisper-Product-Metrics-\(formatter.string(from: now)).json"
    }

    func export(
        to requestedDestinationURL: URL,
        generatedAt: Date = Date()
    ) throws -> URL {
        let destinationURL = normalizedDestinationURL(
            requestedDestinationURL
        )
        try validateDestination(destinationURL)

        let samples = try ProductMetricsRecorder(
            fileManager: fileManager,
            directoryURL: applicationSupportURL
        ).loadRecent(limit: 50_000)
        let report = ProductMetricsReport(
            samples: samples,
            generatedAt: generatedAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        let reportData = try encoder.encode(report)
        let stagedURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".openwhisper-product-metrics-\(UUID().uuidString).json"
            )
        defer {
            try? fileManager.removeItem(at: stagedURL)
        }

        try reportData.write(to: stagedURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: stagedURL.path
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(
            at: stagedURL,
            to: destinationURL
        )
        return destinationURL
    }

    private func normalizedDestinationURL(_ requestedURL: URL) -> URL {
        guard requestedURL.pathExtension.lowercased() != "json" else {
            return requestedURL
        }
        return requestedURL.appendingPathExtension("json")
    }

    private func validateDestination(_ destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }
        let values = try destinationURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        if values.isDirectory == true, values.isSymbolicLink != true {
            throw ProductMetricsExportError.destinationIsDirectory(
                destinationURL.lastPathComponent
            )
        }
    }
}
