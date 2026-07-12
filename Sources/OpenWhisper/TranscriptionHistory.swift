import Foundation

struct TranscriptionHistoryRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let rawText: String?
    let finalText: String
    let appName: String?
    let appBundleIdentifier: String?
    let outcome: String
    let textPolishProvider: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        rawText: String? = nil,
        finalText: String,
        appName: String?,
        appBundleIdentifier: String?,
        outcome: String,
        textPolishProvider: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.finalText = finalText
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.outcome = outcome
        self.textPolishProvider = textPolishProvider
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
        id = decodedID ?? StableIdentifier.uuid(
            namespace: "OpenWhisper.TranscriptionHistoryRecord",
            components: [
                String(timestamp.timeIntervalSince1970.bitPattern, radix: 16),
                rawText,
                finalText,
                appName,
                appBundleIdentifier,
                outcome,
                textPolishProvider,
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
    func prune(retention: HistoryRetentionPolicy) throws
}

extension TranscriptionHistoryRecording {
    func record(_ record: TranscriptionHistoryRecord) throws {
        try self.record(
            record,
            retention: HistoryRetentionPolicy(maxRecords: 500, retentionDays: 30)
        )
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
