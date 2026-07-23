import CryptoKit
import Darwin
import Foundation

enum SupportDiagnosticsExportError: LocalizedError, Equatable {
    case destinationIsDirectory(String)
    case archiveCreationFailed
    case archiveOutputMissing

    var errorDescription: String? {
        switch self {
        case .destinationIsDirectory(let name):
            return L10n.format(
                "VibeWhisper cannot replace the folder named %@ with a diagnostics archive.",
                name
            )
        case .archiveCreationFailed:
            return L10n.text("VibeWhisper could not create the diagnostics archive.")
        case .archiveOutputMissing:
            return L10n.text("VibeWhisper created no diagnostics archive.")
        }
    }
}

struct SupportDiagnosticsEnvironment: Sendable, Equatable {
    let generatedAt: Date
    let productVersion: String
    let productBuild: String
    let bundleIdentifier: String
    let operatingSystem: String
    let architecture: String
    let localeIdentifier: String
    let installedInApplications: Bool

    static func live(now: Date = Date()) -> Self {
        let bundle = Bundle.main
        return Self(
            generatedAt: now,
            productVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? ProductIdentity.runtimeVersion,
            productBuild: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "development",
            bundleIdentifier: bundle.bundleIdentifier
                ?? ProductIdentity.defaultBundleIdentifier,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture,
            localeIdentifier: Locale.current.identifier,
            installedInApplications: bundle.bundleURL.standardizedFileURL.path
                .hasPrefix("/Applications/")
        )
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

private struct SupportDiagnosticsSummary: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let product: Product
    let system: System
    let runtime: Runtime
    let configuration: Configuration
    let privacy: Privacy
    let included: Included

    struct Product: Codable, Sendable, Equatable {
        let name: String
        let version: String
        let build: String
        let bundleIdentifier: String
    }

    struct System: Codable, Sendable, Equatable {
        let operatingSystem: String
        let architecture: String
        let localeIdentifier: String
    }

    struct Runtime: Codable, Sendable, Equatable {
        let installedInApplications: Bool
        let microphonePermission: String
        let accessibilityTrusted: Bool
        let authenticationState: String
        let signatureState: String
    }

    struct Configuration: Codable, Sendable, Equatable {
        let transcriptionProvider: String
        let sampleRateHz: Int
        let maximumDurationSeconds: Int
        let speechCleanupEnabled: Bool
        let feedbackSoundsEnabled: Bool
        let languagePreference: String
        let punctuationPreference: String
        let terminologyEnabled: Bool
        let enabledTerminologyEntryCount: Int
        let enabledTerminologyPackCount:
            Int
        let highRiskTerminologyPackEnabled:
            Bool
        let styleCapsulesEnabled: Bool
        let styleCapsuleAssignmentCount:
            Int
        let configuredCommunitySkillCount:
            Int
        let textPolishMode: String
        let textPolishEnabled: Bool
        let preserveClipboard: Bool
    }

    struct Privacy: Codable, Sendable, Equatable {
        let historyEnabled: Bool
        let historyRetentionDays: Int
        let historyRecordLimit: Int
        let storesRawTranscripts: Bool
        let failedAudioRecoveryEnabled: Bool
        let failedAudioRetentionHours: Int
        let failedAudioRecordLimit: Int
        let diagnosticsEnabled: Bool
        let diagnosticsRetentionDays: Int
        let diagnosticsRecordLimit: Int
        let productMetricsEnabled: Bool
        let productMetricsRetentionDays: Int
        let productMetricsRecordLimit: Int
        let excludesSensitiveApps: Bool
        let additionalSensitiveAppCount: Int
    }

    struct Included: Codable, Sendable, Equatable {
        let redactedLatencySampleCount: Int
        let productMetricSampleCount: Int
        let crashSummaryCount: Int
    }
}

private struct SupportProductMetricSample:
    Codable,
    Sendable,
    Equatable
{
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

    init(_ sample: ProductMetricSample) {
        schemaVersion = ProductMetricSample.currentSchemaVersion
        timestamp = sample.timestamp
        productVersion = ProductMetricsPrivacy.safeVersion(
            sample.productVersion
        )
        productBuild = ProductMetricsPrivacy.safeVersion(
            sample.productBuild
        )
        event = sample.event
        onboardingStep = sample.onboardingStep
        provider = sample.provider
        audioDurationBucket = sample.audioDurationBucket
        latencyBucket = sample.latencyBucket
        deliveryStatus = sample.deliveryStatus
        failureCategory = sample.failureCategory
    }
}

private struct SupportLatencySample: Codable, Sendable, Equatable {
    let timestamp: Date
    let audioDurationMs: Int
    let audioBytes: Int
    let provider: String
    let textPolishProvider: String?
    let authMs: Int
    let transcribeMs: Int
    let normalizationMs: Int
    let polishMs: Int
    let textPolishAttempted: Bool
    let textPolishDecisionReason: String?
    let textPolishErrorPresent: Bool
    let skillID: String?
    let skillVersion: String?
    let skillValidationIssueCodes:
        [String]
    let contextCapabilityCodes:
        [String]
    let selectionCharacterCount: Int
    let estimatedPolishInputTokens: Int
    let estimatedPolishOutputTokens: Int
    let injectMs: Int
    let totalProcessingMs: Int
    let resultStatus: String
    let errorCategory: String?

    init(_ sample: LatencySample) {
        timestamp = sample.timestamp
        audioDurationMs = Self.nonnegative(sample.audioDurationMs)
        audioBytes = Self.nonnegative(sample.audioBytes)
        provider = Self.allowedValue(
            sample.provider,
            allowed: [
                TranscriptionProvider.chatGPTManagedAuth.rawValue,
                TranscriptionProvider.openAICompatible.rawValue,
            ]
        )
        textPolishProvider = sample.textPolishProvider.map {
            Self.allowedValue(
                $0,
                allowed: [
                    TextPolishProviderID.chatGPTAuth.rawValue,
                    TextPolishProviderID.openAICompatible.rawValue,
                ]
            )
        }
        authMs = Self.nonnegative(sample.authMs)
        transcribeMs = Self.nonnegative(sample.transcribeMs)
        normalizationMs = Self.nonnegative(sample.normalizationMs)
        polishMs = Self.nonnegative(sample.polishMs)
        textPolishAttempted = sample.textPolishAttempted
            ?? (sample.polishMs > 0 || sample.textPolishProvider != nil)
        textPolishDecisionReason = sample.textPolishDecisionReason.map {
            Self.allowedValue(
                $0,
                allowed: Set(
                    TextPolishDecisionReason.allCases.map(\.rawValue)
                )
            )
        }
        textPolishErrorPresent = sample.textPolishError != nil
        skillID = sample.skillID.map {
            Self.allowedValue(
                $0,
                allowed: Set(
                    SkillRegistry.builtIn
                        .skillIDs
                )
            )
        }
        skillVersion =
            sample.skillVersion.map {
                SkillDefinition.isValidVersion(
                    $0
                ) ? $0 : "other"
            }
        let allowedValidationIssues =
            Set(
                [
                    SkillValidationIssueCode
                        .empty,
                    .tooLong,
                    .invalidJSON,
                    .unclosedMarkdownFence,
                    .missingRequiredSection,
                    .changedTechnicalLiteral,
                    .forbiddenPhrase,
                    .leakedInternalMarker,
                ].map(\.rawValue)
            )
        skillValidationIssueCodes =
            (sample
                .skillValidationIssueCodes
                ?? [])
            .prefix(20)
            .map {
                Self.allowedValue(
                    $0,
                    allowed:
                        allowedValidationIssues
                )
            }
        let allowedContextCapabilities =
            Set(
                [
                    SkillCapability
                        .selection,
                    .focusedParagraph,
                    .conversationWindow,
                    .clipboard,
                    .styleCapsule,
                ].map(\.rawValue)
            )
        contextCapabilityCodes =
            (sample
                .contextCapabilityCodes
                ?? [])
            .prefix(10)
            .map {
                Self.allowedValue(
                    $0,
                    allowed:
                        allowedContextCapabilities
                )
            }
        selectionCharacterCount =
            min(
                20_000,
                Self.nonnegative(
                    sample
                        .selectionCharacterCount
                        ?? 0
                )
            )
        estimatedPolishInputTokens = Self.nonnegative(
            sample.estimatedPolishInputTokens
        )
        estimatedPolishOutputTokens = Self.nonnegative(
            sample.estimatedPolishOutputTokens
        )
        injectMs = Self.nonnegative(sample.injectMs)
        totalProcessingMs = Self.nonnegative(sample.totalProcessingMs)
        resultStatus = Self.allowedValue(
            sample.resultStatus,
            allowed: TextDeliveryStatus.diagnosticsAllowedValues
        )
        errorCategory = sample.errorCategory.map {
            Self.allowedValue(
                $0,
                allowed: [
                    "transcribe",
                    "transcribe.authentication",
                    "transcribe.challenge",
                    "transcribe.rate_limited",
                    "transcribe.request_rejected",
                    "transcribe.contract_changed",
                    "transcribe.service_unavailable",
                    "transcribe.network",
                    "transcribe.invalid_response",
                    "transcribe.unknown",
                    "inject",
                    "preview_cancelled",
                ]
            )
        }
    }

    private static func nonnegative(_ value: Int) -> Int {
        max(0, value)
    }

    private static func allowedValue(
        _ value: String,
        allowed: Set<String>
    ) -> String {
        allowed.contains(value) ? value : "other"
    }
}

private struct SupportCrashSummary: Codable, Sendable, Equatable {
    let format: String
    let modifiedAt: Date?
    let byteCount: Int
    let appName: String?
    let appVersion: String?
    let buildVersion: String?
    let bundleIdentifier: String?
    let bugType: String?
    let operatingSystemBuild: String?
}

struct SupportDiagnosticsExporter {
    let applicationSupportURL: URL
    let diagnosticReportsURL: URL
    let temporaryDirectoryURL: URL
    let environment: SupportDiagnosticsEnvironment

    init(
        applicationSupportURL: URL = ProductIdentity.applicationSupportURL(
            homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
        ),
        diagnosticReportsURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true),
        temporaryDirectoryURL: URL = FileManager.default.temporaryDirectory,
        environment: SupportDiagnosticsEnvironment = .live()
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.diagnosticReportsURL = diagnosticReportsURL
        self.temporaryDirectoryURL = temporaryDirectoryURL
        self.environment = environment
    }

    static func suggestedFileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "VibeWhisper-Support-\(formatter.string(from: now)).zip"
    }

    func export(
        to requestedDestinationURL: URL,
        config: AppConfig,
        authSnapshot: ChatGPTAuthSnapshot,
        permissionSnapshot: PermissionStatusSnapshot,
        signatureState: AccessibilityPermission.SignatureState
    ) throws -> URL {
        let fileManager = FileManager.default
        let destinationURL = normalizedDestinationURL(requestedDestinationURL)
        try validateDestination(destinationURL, fileManager: fileManager)

        let workspaceURL = temporaryDirectoryURL
            .appendingPathComponent(
                "vibewhisper-support-\(UUID().uuidString)",
                isDirectory: true
            )
        let bundleURL = workspaceURL
            .appendingPathComponent("VibeWhisper-Support", isDirectory: true)
        let temporaryArchiveURL = workspaceURL
            .appendingPathComponent("VibeWhisper-Support.zip")
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        try fileManager.createDirectory(
            at: bundleURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )

        let latencySamples = loadRedactedLatencySamples(
            fileManager: fileManager
        )
        let productMetricSamples = loadRedactedProductMetricSamples(
            fileManager: fileManager
        )
        let crashSummaries = loadCrashSummaries(fileManager: fileManager)
        let summary = makeSummary(
            config: config,
            authSnapshot: authSnapshot,
            permissionSnapshot: permissionSnapshot,
            signatureState: signatureState,
            latencySampleCount: latencySamples.count,
            productMetricSampleCount: productMetricSamples.count,
            crashSummaryCount: crashSummaries.count
        )

        var files: [String: Data] = [
            "README.txt": Data(Self.readmeText.utf8),
            "summary.json": try encodedJSON(summary),
            "latency.jsonl": try encodedJSONLines(latencySamples),
            "product-metrics.jsonl": try encodedJSONLines(
                productMetricSamples
            ),
            "crash-summary.json": try encodedJSON(crashSummaries),
        ]
        files["SHA256SUMS"] = Data(
            files.keys.sorted().map { fileName in
                "\(sha256Hex(files[fileName] ?? Data()))  \(fileName)"
            }
            .joined(separator: "\n")
            .appending("\n")
            .utf8
        )

        for fileName in files.keys.sorted() {
            let fileURL = bundleURL.appendingPathComponent(fileName)
            try (files[fileName] ?? Data()).write(to: fileURL, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: fileURL.path
            )
        }

        try createArchive(
            sourceDirectoryURL: bundleURL,
            archiveURL: temporaryArchiveURL
        )
        guard fileManager.fileExists(atPath: temporaryArchiveURL.path) else {
            throw SupportDiagnosticsExportError.archiveOutputMissing
        }

        let stagedDestinationURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".vibewhisper-support-\(UUID().uuidString).zip"
            )
        defer {
            try? fileManager.removeItem(at: stagedDestinationURL)
        }
        try fileManager.copyItem(
            at: temporaryArchiveURL,
            to: stagedDestinationURL
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: stagedDestinationURL.path
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(
            at: stagedDestinationURL,
            to: destinationURL
        )
        return destinationURL
    }

    private func makeSummary(
        config: AppConfig,
        authSnapshot: ChatGPTAuthSnapshot,
        permissionSnapshot: PermissionStatusSnapshot,
        signatureState: AccessibilityPermission.SignatureState,
        latencySampleCount: Int,
        productMetricSampleCount: Int,
        crashSummaryCount: Int
    ) -> SupportDiagnosticsSummary {
        SupportDiagnosticsSummary(
            schemaVersion: 1,
            generatedAt: environment.generatedAt,
            product: .init(
                name: ProductIdentity.name,
                version: environment.productVersion,
                build: environment.productBuild,
                bundleIdentifier: environment.bundleIdentifier
            ),
            system: .init(
                operatingSystem: environment.operatingSystem,
                architecture: environment.architecture,
                localeIdentifier: environment.localeIdentifier
            ),
            runtime: .init(
                installedInApplications: environment.installedInApplications,
                microphonePermission: microphoneValue(
                    permissionSnapshot.microphone
                ),
                accessibilityTrusted: permissionSnapshot.accessibilityTrusted,
                authenticationState: authenticationValue(authSnapshot.state),
                signatureState: signatureValue(signatureState)
            ),
            configuration: .init(
                transcriptionProvider: config.transcription.provider.rawValue,
                sampleRateHz: max(0, config.transcription.sampleRateHz),
                maximumDurationSeconds: max(
                    0,
                    config.transcription.maxDurationSeconds
                ),
                speechCleanupEnabled: config.transcription.speechCleanupEnabled,
                feedbackSoundsEnabled: config.transcription.feedbackSoundsEnabled,
                languagePreference: "follow_input",
                punctuationPreference: config.transcription.punctuationPreference.rawValue,
                terminologyEnabled: config.transcription.terminology.enabled,
                enabledTerminologyEntryCount: config.transcription
                    .activeDictionaryEntries.count,
                enabledTerminologyPackCount:
                    config.terminologyPacks
                        .enabledPackIDs
                        .count,
                highRiskTerminologyPackEnabled:
                    config.terminologyPacks
                        .enabledPackIDs
                        .contains {
                            TerminologyPackRegistry
                                .definition(
                                    id: $0
                                )?.risk
                                == .high
                        },
                styleCapsulesEnabled:
                    config.styleCapsules
                        .enabled,
                styleCapsuleAssignmentCount:
                    config.styleCapsules
                        .skillAssignments
                        .count,
                configuredCommunitySkillCount:
                    config.transcription
                        .skills
                        .enabledSkillIDs
                        .filter {
                            !SkillRegistry
                                .builtIn
                                .contains(
                                    id: $0
                                )
                        }.count,
                textPolishMode: config.transcription.textPolish.mode.rawValue,
                textPolishEnabled: config.transcription.textPolish
                    .chatGPTAuthEnabled,
                preserveClipboard: config.injection.preserveClipboard
            ),
            privacy: .init(
                historyEnabled: config.privacy.historyEnabled,
                historyRetentionDays: config.privacy.historyRetentionDays,
                historyRecordLimit: config.privacy.historyRecordLimit,
                storesRawTranscripts: config.privacy.storeRawTranscripts,
                failedAudioRecoveryEnabled: config.privacy
                    .failedAudioRecoveryEnabled,
                failedAudioRetentionHours: config.privacy
                    .failedAudioRetentionHours,
                failedAudioRecordLimit: config.privacy.failedAudioRecordLimit,
                diagnosticsEnabled: config.privacy.diagnosticsEnabled,
                diagnosticsRetentionDays: config.privacy
                    .diagnosticsRetentionDays,
                diagnosticsRecordLimit: config.privacy
                    .diagnosticsRecordLimit,
                productMetricsEnabled:
                    config.privacy.productMetricsEnabled,
                productMetricsRetentionDays:
                    config.privacy.productMetricsRetentionDays,
                productMetricsRecordLimit:
                    config.privacy.productMetricsRecordLimit,
                excludesSensitiveApps: config.privacy.excludeSensitiveApps,
                additionalSensitiveAppCount: config.privacy
                    .additionalSensitiveAppBundleIdentifiers.count
            ),
            included: .init(
                redactedLatencySampleCount: latencySampleCount,
                productMetricSampleCount: productMetricSampleCount,
                crashSummaryCount: crashSummaryCount
            )
        )
    }

    private func loadRedactedLatencySamples(
        fileManager: FileManager
    ) -> [SupportLatencySample] {
        let dataURL = applicationSupportURL
            .appendingPathComponent("latency.jsonl")
        guard isRegularNonSymbolicFile(dataURL, fileManager: fileManager) else {
            return []
        }

        return (
            (try? LatencyRecorder(
                fileManager: fileManager,
                directoryURL: applicationSupportURL
            ).loadRecent(limit: 1_000)) ?? []
        ).map(SupportLatencySample.init)
    }

    private func loadRedactedProductMetricSamples(
        fileManager: FileManager
    ) -> [SupportProductMetricSample] {
        let dataURL = applicationSupportURL
            .appendingPathComponent("product-metrics.jsonl")
        guard isRegularNonSymbolicFile(
            dataURL,
            fileManager: fileManager
        ) else {
            return []
        }

        return (
            (try? ProductMetricsRecorder(
                fileManager: fileManager,
                directoryURL: applicationSupportURL
            ).loadRecent(limit: 5_000)) ?? []
        ).map(SupportProductMetricSample.init)
    }

    private func loadCrashSummaries(
        fileManager: FileManager
    ) -> [SupportCrashSummary] {
        guard
            let candidates = try? fileManager.contentsOfDirectory(
                at: diagnosticReportsURL,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return candidates
            .filter {
                let name = $0.lastPathComponent.lowercased()
                return name.hasPrefix(ProductIdentity.name.lowercased())
                    && ["ips", "crash"].contains($0.pathExtension.lowercased())
                    && isRegularNonSymbolicFile($0, fileManager: fileManager)
            }
            .compactMap { url -> (URL, Date?, Int)? in
                guard let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey]
                ) else {
                    return nil
                }
                return (url, values.contentModificationDate, values.fileSize ?? 0)
            }
            .sorted { ($0.1 ?? .distantPast) > ($1.1 ?? .distantPast) }
            .prefix(5)
            .map { url, modifiedAt, byteCount in
                crashSummary(
                    at: url,
                    modifiedAt: modifiedAt,
                    byteCount: byteCount
                )
            }
    }

    private func crashSummary(
        at url: URL,
        modifiedAt: Date?,
        byteCount: Int
    ) -> SupportCrashSummary {
        let format = url.pathExtension.lowercased()
        guard
            format == "ips",
            let prefix = try? readPrefix(
                at: url,
                maximumBytes: 64 * 1_024
            ),
            let firstLine = prefix.split(separator: 0x0A).first,
            let object = try? JSONSerialization.jsonObject(
                with: Data(firstLine)
            ) as? [String: Any]
        else {
            return SupportCrashSummary(
                format: format,
                modifiedAt: modifiedAt,
                byteCount: max(0, byteCount),
                appName: nil,
                appVersion: nil,
                buildVersion: nil,
                bundleIdentifier: nil,
                bugType: nil,
                operatingSystemBuild: nil
            )
        }

        let osVersion = object["os_version"] as? [String: Any]
        return SupportCrashSummary(
            format: format,
            modifiedAt: modifiedAt,
            byteCount: max(0, byteCount),
            appName: exactValue(
                object["app_name"] as? String,
                expected: ProductIdentity.name
            ),
            appVersion: safeVersionValue(object["app_version"] as? String),
            buildVersion: safeVersionValue(object["build_version"] as? String),
            bundleIdentifier: exactValue(
                object["bundleID"] as? String,
                expected: ProductIdentity.defaultBundleIdentifier
            ),
            bugType: safeNumericValue(object["bug_type"] as? String),
            operatingSystemBuild: safeOperatingSystemValue(
                osVersion?["build"] as? String
                    ?? osVersion?["train"] as? String
            )
        )
    }

    private func encodedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func encodedJSONLines<T: Encodable>(
        _ values: [T]
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try values.reduce(into: Data()) { output, value in
            output.append(try encoder.encode(value))
            output.append(0x0A)
        }
    }

    private func createArchive(
        sourceDirectoryURL: URL,
        archiveURL: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            sourceDirectoryURL.path,
            archiveURL.path,
        ]
        var processEnvironment = ProcessInfo.processInfo.environment
        processEnvironment["COPYFILE_DISABLE"] = "1"
        process.environment = processEnvironment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SupportDiagnosticsExportError.archiveCreationFailed
        }
    }

    private func normalizedDestinationURL(_ requestedURL: URL) -> URL {
        guard requestedURL.pathExtension.lowercased() != "zip" else {
            return requestedURL
        }
        return requestedURL.appendingPathExtension("zip")
    }

    private func validateDestination(
        _ destinationURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }
        let values = try destinationURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        if values.isDirectory == true, values.isSymbolicLink != true {
            throw SupportDiagnosticsExportError.destinationIsDirectory(
                destinationURL.lastPathComponent
            )
        }
    }

    private func isRegularNonSymbolicFile(
        _ url: URL,
        fileManager _: FileManager
    ) -> Bool {
        guard
            let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
        else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func readPrefix(
        at url: URL,
        maximumBytes: Int
    ) throws -> Data {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        defer {
            Darwin.close(descriptor)
        }

        var status = stat()
        guard
            Darwin.fstat(descriptor, &status) == 0,
            (status.st_mode & S_IFMT) == S_IFREG
        else {
            throw CocoaError(.fileReadUnknown)
        }

        var buffer = [UInt8](
            repeating: 0,
            count: min(max(1, maximumBytes), Int(status.st_size))
        )
        var offset = 0
        while offset < buffer.count {
            let remaining = buffer.count - offset
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(
                    descriptor,
                    rawBuffer.baseAddress?.advanced(by: offset),
                    remaining
                )
            }
            if count < 0, errno == EINTR {
                continue
            }
            guard count >= 0 else {
                throw CocoaError(.fileReadUnknown)
            }
            if count == 0 {
                break
            }
            offset += count
        }
        return Data(buffer.prefix(offset))
    }

    private func exactValue(
        _ value: String?,
        expected: String
    ) -> String? {
        value == expected ? expected : nil
    }

    private func safeVersionValue(_ value: String?) -> String? {
        safeValue(
            value,
            maximumLength: 32,
            allowed: CharacterSet(charactersIn: "0123456789.-+")
        )
    }

    private func safeNumericValue(_ value: String?) -> String? {
        safeValue(
            value,
            maximumLength: 8,
            allowed: .decimalDigits
        )
    }

    private func safeOperatingSystemValue(_ value: String?) -> String? {
        safeValue(
            value,
            maximumLength: 80,
            allowed: CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: " ._-()")
            )
        )
    }

    private func safeValue(
        _ value: String?,
        maximumLength: Int,
        allowed: CharacterSet
    ) -> String? {
        guard
            let value,
            !value.isEmpty,
            value.count <= maximumLength,
            value.unicodeScalars.allSatisfy(allowed.contains)
        else {
            return nil
        }
        return value
    }

    private func microphoneValue(
        _ state: MicrophonePermissionState
    ) -> String {
        switch state {
        case .granted:
            return "granted"
        case .undetermined:
            return "undetermined"
        case .denied:
            return "denied"
        }
    }

    private func authenticationValue(_ state: ChatGPTAuthState) -> String {
        switch state {
        case .signedOut:
            return "signedOut"
        case .ready:
            return "ready"
        case .expired:
            return "expired"
        case .unavailable:
            return "unavailable"
        }
    }

    private func signatureValue(
        _ state: AccessibilityPermission.SignatureState
    ) -> String {
        switch state {
        case .stable:
            return "stableTeamIdentity"
        case .adHocOrUnsigned:
            return "adHocOrUnsigned"
        case .unavailable:
            return "unavailable"
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }
        .joined()
    }

    private static let readmeText = """
    VibeWhisper Support Diagnostics

    This archive is generated locally and is not uploaded automatically.

    Included:
    - product, operating-system, permission, authentication-state, and signing-state summaries
    - non-secret configuration flags and retention values
    - redacted local latency records
    - opt-in local product metrics with enum and bucket values only
    - whitelisted metadata from up to five recent VibeWhisper crash reports
    - SHA-256 checksums for every included file

    Excluded:
    - audio and failed recordings
    - transcript and clipboard text
    - terminology entries and imported source paths
    - Writing Style summaries, examples, and source samples
    - community Skill prompts, terminology, localizations, and package file names
    - account email, access tokens, refresh tokens, API keys, cookies, and authorization headers
    - custom endpoint URLs and environment-variable values
    - raw crash-report bodies, history, Recovery metadata, and config.json

    Review this archive before sharing it with support.
    """
}
