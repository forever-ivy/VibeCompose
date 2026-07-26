import Foundation

enum HistoryUndoState: String, Codable, Sendable, Equatable {
    case available
    case restored
    case originalCopied
    case unavailable
}

/// The redacted explanation of one Skill execution. This is the durable
/// contract shared by History, retry diagnostics, and future product surfaces;
/// it never contains transcript, Prompt, selection, or resource contents.
struct SkillRunReceipt:
    Codable,
    Sendable,
    Equatable,
    Identifiable
{
    let runID: UUID
    let timestamp: Date
    let skillInstallationID: UUID
    let skillID: String
    let displayName: String
    let source: String
    let version: String?
    let revision: String
    let contentDigest: String
    let resolutionReason: String
    let targetApplicationBundleIdentifier: String?
    let contextDecisions: [ContextDecision]
    let resourceIDs: [String]
    let validatorIssueCodes: [String]
    let fallbackCode: String?
    let requestedOutputRoute: String
    let actualOutputRoute: String
    let targetVerification: String
    let finalUserAction: String

    var id: UUID { runID }

    init(
        runID: UUID,
        timestamp: Date = Date(),
        skillInstallationID: UUID,
        skillID: String,
        displayName: String,
        source: String,
        version: String?,
        revision: String,
        contentDigest: String,
        resolutionReason: String,
        targetApplicationBundleIdentifier: String?,
        contextDecisions: [ContextDecision] = [],
        resourceIDs: [String] = [],
        validatorIssueCodes: [String] = [],
        fallbackCode: String? = nil,
        requestedOutputRoute: String,
        actualOutputRoute: String,
        targetVerification: String,
        finalUserAction: String
    ) {
        self.runID = runID
        self.timestamp = timestamp
        self.skillInstallationID = skillInstallationID
        self.skillID = skillID
        self.displayName = displayName
        self.source = source
        self.version = version
        self.revision = revision
        self.contentDigest = contentDigest
        self.resolutionReason = resolutionReason
        self.targetApplicationBundleIdentifier =
            targetApplicationBundleIdentifier
        self.contextDecisions = Array(contextDecisions.prefix(32))
        self.resourceIDs = Array(resourceIDs.prefix(64))
        self.validatorIssueCodes = Array(validatorIssueCodes.prefix(20))
        self.fallbackCode = fallbackCode
        self.requestedOutputRoute = requestedOutputRoute
        self.actualOutputRoute = actualOutputRoute
        self.targetVerification = targetVerification
        self.finalUserAction = finalUserAction
    }

    static func make(
        runID: UUID,
        preparedContext: PreparedSkillContext,
        prepared: PreparedDictation,
        executionPlan: ResolvedSkillExecutionPlan,
        launchAppContext: LaunchAppContext?,
        outcome: InjectionOutcome,
        deliveryAction: String,
        resultWasEdited: Bool
    ) -> SkillRunReceipt {
        let issueCodes = prepared.metrics.skillValidationIssueCodes
        let fallbackCode: String?
        if let first = issueCodes.first {
            fallbackCode = first
        } else if prepared.metrics.textPolishErrorMessage?.isEmpty == false {
            fallbackCode = "provider_or_validator_fallback"
        } else {
            fallbackCode = nil
        }
        return SkillRunReceipt(
            runID: runID,
            skillInstallationID: executionPlan.installation.id,
            skillID: executionPlan.skill.id,
            displayName: executionPlan.skill.localizedName,
            source: executionPlan.installation.sourceID,
            version: executionPlan.installation.version,
            revision: executionPlan.installation.revision,
            contentDigest: executionPlan.package.contentSHA256,
            resolutionReason: executionPlan.source.rawValue,
            targetApplicationBundleIdentifier:
                launchAppContext?.bundleIdentifier,
            contextDecisions:
                preparedContext.contextReceipt?.decisions ?? [],
            resourceIDs: executionPlan.resources.map(\.id),
            validatorIssueCodes: issueCodes,
            fallbackCode: fallbackCode,
            requestedOutputRoute:
                executionPlan.profile.output.delivery.rawValue,
            actualOutputRoute: deliveryAction,
            targetVerification: outcome.resultStatus,
            finalUserAction:
                resultWasEdited
                ? "edited_\(deliveryAction)"
                : deliveryAction
        )
    }
}

struct TranscriptionHistoryRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let rawText: String?
    let finalText: String
    let appName: String?
    let appBundleIdentifier: String?
    let outcome: String
    let textPolishProvider: String?
    let skillID: String?
    let skillVersion: String?
    let skillInstallationID: UUID?
    let skillName: String?
    let skillSource: String?
    let skillRevision: String?
    let skillValidationIssueCodes: [String]
    let skillFallbackMessage: String?
    let skillDeliveryAction: String?
    let skillResultEdited: Bool
    let undoState: HistoryUndoState?
    let skillRunReceipt: SkillRunReceipt?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        rawText: String? = nil,
        finalText: String,
        appName: String?,
        appBundleIdentifier: String?,
        outcome: String,
        textPolishProvider: String? = nil,
        skillID: String? = nil,
        skillVersion: String? = nil,
        skillInstallationID: UUID? = nil,
        skillName: String? = nil,
        skillSource: String? = nil,
        skillRevision: String? = nil,
        skillValidationIssueCodes: [String] = [],
        skillFallbackMessage: String? = nil,
        skillDeliveryAction: String? = nil,
        skillResultEdited: Bool = false,
        undoState: HistoryUndoState? = nil,
        skillRunReceipt: SkillRunReceipt? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.finalText = finalText
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.outcome = outcome
        self.textPolishProvider = textPolishProvider
        self.skillID = skillID
        self.skillVersion = skillVersion
        self.skillInstallationID = skillInstallationID
        self.skillName = skillName
        self.skillSource = skillSource
        self.skillRevision = skillRevision
        self.skillValidationIssueCodes = Array(
            skillValidationIssueCodes.prefix(20)
        )
        self.skillFallbackMessage = skillFallbackMessage
        self.skillDeliveryAction =
            skillDeliveryAction
        self.skillResultEdited =
            skillResultEdited
        self.undoState = undoState
        self.skillRunReceipt = skillRunReceipt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText)
        finalText = try container.decode(String.self, forKey: .finalText)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        appBundleIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .appBundleIdentifier
        )
        outcome = try container.decode(String.self, forKey: .outcome)
        textPolishProvider = try container.decodeIfPresent(
            String.self,
            forKey: .textPolishProvider
        )
        skillID = try container.decodeIfPresent(
            String.self,
            forKey: .skillID
        )
        skillVersion =
            try container.decodeIfPresent(
                String.self,
                forKey: .skillVersion
            )
        skillInstallationID = try container.decodeIfPresent(
            UUID.self,
            forKey: .skillInstallationID
        )
        skillName = try container.decodeIfPresent(
            String.self,
            forKey: .skillName
        )
        skillSource = try container.decodeIfPresent(
            String.self,
            forKey: .skillSource
        )
        skillRevision = try container.decodeIfPresent(
            String.self,
            forKey: .skillRevision
        )
        skillValidationIssueCodes = try container.decodeIfPresent(
            [String].self,
            forKey: .skillValidationIssueCodes
        ) ?? []
        skillFallbackMessage = try container.decodeIfPresent(
            String.self,
            forKey: .skillFallbackMessage
        )
        skillDeliveryAction = try container.decodeIfPresent(
            String.self,
            forKey: .skillDeliveryAction
        )
        skillResultEdited = try container.decodeIfPresent(
            Bool.self,
            forKey: .skillResultEdited
        ) ?? false
        undoState = try container.decodeIfPresent(
            HistoryUndoState.self,
            forKey: .undoState
        )
        skillRunReceipt = try container.decodeIfPresent(
            SkillRunReceipt.self,
            forKey: .skillRunReceipt
        )
        id = decodedID ?? StableIdentifier.uuid(
            namespace: "VibeCompose.TranscriptionHistoryRecord",
            components: [
                String(timestamp.timeIntervalSince1970.bitPattern, radix: 16),
                rawText,
                finalText,
                appName,
                appBundleIdentifier,
                outcome,
                textPolishProvider,
                skillID,
                skillVersion,
                skillInstallationID?.uuidString,
                skillName,
                skillSource,
                skillRevision,
                skillValidationIssueCodes.joined(separator: ","),
                skillFallbackMessage,
                skillDeliveryAction,
                String(skillResultEdited),
                undoState?.rawValue,
            ]
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(rawText, forKey: .rawText)
        try container.encode(finalText, forKey: .finalText)
        try container.encodeIfPresent(appName, forKey: .appName)
        try container.encodeIfPresent(appBundleIdentifier, forKey: .appBundleIdentifier)
        try container.encode(outcome, forKey: .outcome)
        try container.encodeIfPresent(textPolishProvider, forKey: .textPolishProvider)
        try container.encodeIfPresent(
            skillID,
            forKey: .skillID
        )
        try container.encodeIfPresent(
            skillVersion,
            forKey: .skillVersion
        )
        try container.encodeIfPresent(skillInstallationID, forKey: .skillInstallationID)
        try container.encodeIfPresent(skillName, forKey: .skillName)
        try container.encodeIfPresent(skillSource, forKey: .skillSource)
        try container.encodeIfPresent(skillRevision, forKey: .skillRevision)
        if !skillValidationIssueCodes.isEmpty {
            try container.encode(skillValidationIssueCodes, forKey: .skillValidationIssueCodes)
        }
        try container.encodeIfPresent(skillFallbackMessage, forKey: .skillFallbackMessage)
        try container.encodeIfPresent(
            skillDeliveryAction,
            forKey: .skillDeliveryAction
        )
        if skillResultEdited {
            try container.encode(
                true,
                forKey: .skillResultEdited
            )
        }
        try container.encodeIfPresent(
            undoState,
            forKey: .undoState
        )
        try container.encodeIfPresent(
            skillRunReceipt,
            forKey: .skillRunReceipt
        )
    }

    func replacingUndoState(
        _ value: HistoryUndoState
    ) -> TranscriptionHistoryRecord {
        TranscriptionHistoryRecord(
            id: id,
            timestamp: timestamp,
            rawText: rawText,
            finalText: finalText,
            appName: appName,
            appBundleIdentifier: appBundleIdentifier,
            outcome: outcome,
            textPolishProvider: textPolishProvider,
            skillID: skillID,
            skillVersion: skillVersion,
            skillInstallationID: skillInstallationID,
            skillName: skillName,
            skillSource: skillSource,
            skillRevision: skillRevision,
            skillValidationIssueCodes:
                skillValidationIssueCodes,
            skillFallbackMessage: skillFallbackMessage,
            skillDeliveryAction: skillDeliveryAction,
            skillResultEdited: skillResultEdited,
            undoState: value,
            skillRunReceipt: skillRunReceipt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case rawText
        case finalText
        case appName
        case appBundleIdentifier
        case outcome
        case textPolishProvider
        case skillID
        case skillVersion
        case skillInstallationID
        case skillName
        case skillSource
        case skillRevision
        case skillValidationIssueCodes
        case skillFallbackMessage
        case skillDeliveryAction
        case skillResultEdited
        case undoState
        case skillRunReceipt
    }
}

enum TranscriptionHistoryTextSource: Sendable {
    case dictation
    case polish
}

struct TranscriptionHistoryPreview: Sendable, Equatable, Identifiable {
    let id: String
    let timestamp: Date
    let text: String
    let copyText: String
    let target: String
    let outcome: String
    let sourceLabel: String

    static func recentItems(
        from records: [TranscriptionHistoryRecord],
        limit: Int
    ) -> [TranscriptionHistoryPreview] {
        records
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(max(0, limit))
            .map { record in
                let copyText = record.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                return TranscriptionHistoryPreview(
                    id: "final-\(record.timestamp.timeIntervalSince1970)-\(record.outcome)-\(copyText.hashValue)",
                    timestamp: record.timestamp,
                    text: collapsedPreview(copyText),
                    copyText: copyText,
                    target: record.appName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? record.appName ?? L10n.text("Unknown target")
                        : L10n.text("Unknown target"),
                    outcome: record.outcome,
                    sourceLabel: record.textPolishProvider ?? L10n.text("Final text")
                )
            }
    }

    static func recentItems(
        from records: [TranscriptionHistoryRecord],
        limit: Int,
        textSource: TranscriptionHistoryTextSource
    ) -> [TranscriptionHistoryPreview] {
        records
            .sorted { $0.timestamp > $1.timestamp }
            .filter { record in
                switch textSource {
                case .dictation:
                    return selectedText(from: record, textSource: textSource).isEmpty == false
                case .polish:
                    return selectedText(from: record, textSource: textSource).isEmpty == false
                }
            }
            .prefix(max(0, limit))
            .map { record in
                let copyText = selectedText(from: record, textSource: textSource)
                return TranscriptionHistoryPreview(
                    id: "\(textSource)-\(record.timestamp.timeIntervalSince1970)-\(record.outcome)-\(copyText.hashValue)",
                    timestamp: record.timestamp,
                    text: collapsedPreview(copyText),
                    copyText: copyText,
                    target: record.appName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? record.appName ?? L10n.text("Unknown target")
                        : L10n.text("Unknown target"),
                    outcome: record.outcome,
                    sourceLabel: sourceLabel(for: record, textSource: textSource)
                )
            }
    }

    private static func selectedText(
        from record: TranscriptionHistoryRecord,
        textSource: TranscriptionHistoryTextSource
    ) -> String {
        switch textSource {
        case .dictation:
            return (record.rawText ?? record.finalText).trimmingCharacters(in: .whitespacesAndNewlines)
        case .polish:
            return record.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func sourceLabel(
        for record: TranscriptionHistoryRecord,
        textSource: TranscriptionHistoryTextSource
    ) -> String {
        switch textSource {
        case .dictation:
            return L10n.text("Direct ASR")
        case .polish:
            return record.textPolishProvider ?? L10n.text("AI Polish")
        }
    }

    private static func collapsedPreview(_ text: String, maxCharacters: Int = 120) -> String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > maxCharacters else {
            return collapsed
        }

        return String(collapsed.prefix(maxCharacters)) + "..."
    }
}

protocol TranscriptionHistoryRecording: Sendable {
    func record(_ record: TranscriptionHistoryRecord, retention: HistoryRetentionPolicy) throws
    func loadRecent(limit: Int) throws -> [TranscriptionHistoryRecord]
    func delete(id: UUID) throws
    func updateUndoState(
        id: UUID,
        state: HistoryUndoState
    ) throws
    func prune(retention: HistoryRetentionPolicy) throws
}

extension TranscriptionHistoryRecording {
    func record(_ record: TranscriptionHistoryRecord) throws {
        try self.record(
            record,
            retention: HistoryRetentionPolicy(maxRecords: 500, retentionDays: 30)
        )
    }

    func updateUndoState(
        id: UUID,
        state: HistoryUndoState
    ) throws {
        _ = id
        _ = state
    }
}

final class TranscriptionHistoryRecorder: TranscriptionHistoryRecording, @unchecked Sendable {
    private let fileManager: FileManager
    let directoryURL: URL
    private let lock = NSLock()
    private let maximumReadBytes: Int

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        maximumReadBytes: Int = 4_000_000
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? ProductIdentity.applicationSupportURL(
            homeDirectoryURL: fileManager.homeDirectoryForCurrentUser
        )
        self.maximumReadBytes = max(64_000, maximumReadBytes)
    }

    func record(
        _ record: TranscriptionHistoryRecord,
        retention: HistoryRetentionPolicy
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        var records = try loadRecordsUnlocked()
        records.append(record)
        try rewrite(retained(records, policy: retention))
    }

    func loadRecent(limit: Int = 200) throws -> [TranscriptionHistoryRecord] {
        lock.lock()
        defer { lock.unlock() }

        return Array(try loadRecordsUnlocked().suffix(max(0, limit)))
    }

    func prune(retention: HistoryRetentionPolicy) throws {
        lock.lock()
        defer { lock.unlock() }
        try rewrite(retained(try loadRecordsUnlocked(), policy: retention))
    }

    func delete(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        try rewrite(try loadRecordsUnlocked().filter { $0.id != id })
    }

    func updateUndoState(
        id: UUID,
        state: HistoryUndoState
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        var records = try loadRecordsUnlocked()
        guard let index = records.firstIndex(where: {
            $0.id == id
        }) else {
            return
        }
        records[index] = records[index]
            .replacingUndoState(state)
        try rewrite(records)
    }

    private func loadRecordsUnlocked() throws -> [TranscriptionHistoryRecord] {
        let lines = try JSONLTailReader.lines(
            at: historyURL,
            fileManager: fileManager,
            maximumBytes: maximumReadBytes
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return lines.compactMap { line in
            try? decoder.decode(TranscriptionHistoryRecord.self, from: Data(line.utf8))
        }
    }

    private func retained(
        _ records: [TranscriptionHistoryRecord],
        policy: HistoryRetentionPolicy
    ) -> [TranscriptionHistoryRecord] {
        guard policy.maxRecords > 0 else {
            return []
        }
        return records
            .filter { $0.timestamp >= policy.cutoffDate }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(policy.maxRecords)
            .map { $0 }
    }

    private func rewrite(_ records: [TranscriptionHistoryRecord]) throws {
        if records.isEmpty {
            if fileManager.fileExists(atPath: historyURL.path) {
                try fileManager.removeItem(at: historyURL)
            }
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: directoryURL.path
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try records.reduce(into: Data()) { partial, record in
            partial.append(try encoder.encode(record))
            partial.append(0x0A)
        }
        try data.write(to: historyURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: historyURL.path
        )
    }

    private var historyURL: URL {
        directoryURL.appendingPathComponent("transcription-history.jsonl")
    }
}
