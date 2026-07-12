import Foundation

struct TranscriptionHistoryRecord: Codable, Sendable, Equatable {
    let timestamp: Date
    let rawText: String?
    let finalText: String
    let appName: String?
    let appBundleIdentifier: String?
    let outcome: String
    let textPolishProvider: String?

    init(
        timestamp: Date,
        rawText: String? = nil,
        finalText: String,
        appName: String?,
        appBundleIdentifier: String?,
        outcome: String,
        textPolishProvider: String? = nil
    ) {
        self.timestamp = timestamp
        self.rawText = rawText
        self.finalText = finalText
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.outcome = outcome
        self.textPolishProvider = textPolishProvider
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
    func record(_ record: TranscriptionHistoryRecord) throws
    func loadRecent(limit: Int) throws -> [TranscriptionHistoryRecord]
}

final class TranscriptionHistoryRecorder: TranscriptionHistoryRecording, @unchecked Sendable {
    private let fileManager: FileManager
    let directoryURL: URL
    private let lock = NSLock()

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? ProductIdentity.applicationSupportURL(
            homeDirectoryURL: fileManager.homeDirectoryForCurrentUser
        )
    }

    func record(_ record: TranscriptionHistoryRecord) throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let dataURL = historyURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let line = try encoder.encode(record) + Data([0x0A])

        if fileManager.fileExists(atPath: dataURL.path) {
            let handle = try FileHandle(forWritingTo: dataURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: dataURL, options: [.atomic])
        }
    }

    func loadRecent(limit: Int = 200) throws -> [TranscriptionHistoryRecord] {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: historyURL.path) else {
            return []
        }

        let contents = try String(contentsOf: historyURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = contents
            .split(separator: "\n")
            .suffix(max(0, limit))
            .compactMap { line -> TranscriptionHistoryRecord? in
                try? decoder.decode(TranscriptionHistoryRecord.self, from: Data(line.utf8))
            }
        return Array(records)
    }

    private var historyURL: URL {
        directoryURL.appendingPathComponent("transcription-history.jsonl")
    }
}
