import Foundation

struct RecoveryRecordInput: Sendable {
    let timestamp: Date
    let sourceAudioURL: URL
    let durationMs: Int
    let asrText: String?
    let polishText: String?
    let appName: String?
    let appBundleIdentifier: String?
    let outcome: String
    let errorMessage: String?
}

struct RecoveryRecord: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let audioDurationMs: Int
    let asrText: String?
    let polishText: String?
    let appName: String?
    let appBundleIdentifier: String?
    let outcome: String
    let errorMessage: String?

    var audioFileName: String {
        "\(id.uuidString).wav"
    }

    init(
        id: UUID,
        timestamp: Date,
        audioDurationMs: Int,
        asrText: String?,
        polishText: String?,
        appName: String?,
        appBundleIdentifier: String?,
        outcome: String,
        errorMessage: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.audioDurationMs = audioDurationMs
        self.asrText = asrText
        self.polishText = polishText
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.outcome = outcome
        self.errorMessage = errorMessage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        audioDurationMs = try container.decode(Int.self, forKey: .audioDurationMs)
        asrText = try container.decodeIfPresent(String.self, forKey: .asrText)
        polishText = try container.decodeIfPresent(String.self, forKey: .polishText)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        appBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .appBundleIdentifier)
        outcome = try container.decode(String.self, forKey: .outcome)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        _ = try container.decodeIfPresent(String.self, forKey: .audioFileName)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(audioDurationMs, forKey: .audioDurationMs)
        try container.encodeIfPresent(asrText, forKey: .asrText)
        try container.encodeIfPresent(polishText, forKey: .polishText)
        try container.encodeIfPresent(appName, forKey: .appName)
        try container.encodeIfPresent(appBundleIdentifier, forKey: .appBundleIdentifier)
        try container.encode(outcome, forKey: .outcome)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case audioFileName
        case audioDurationMs
        case asrText
        case polishText
        case appName
        case appBundleIdentifier
        case outcome
        case errorMessage
    }
}

enum RecoveryAudioError: LocalizedError, Equatable {
    case missing
    case unsafePath
    case symbolicLink
    case notRegularFile
    case invalidWaveFile
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .missing:
            return L10n.text("Saved recovery audio is missing.")
        case .unsafePath:
            return L10n.text("OpenWhisper blocked an unsafe recovery audio path.")
        case .symbolicLink:
            return L10n.text("OpenWhisper blocked a symbolic link in recovery storage.")
        case .notRegularFile:
            return L10n.text("Saved recovery audio is not a regular file.")
        case .invalidWaveFile:
            return L10n.text("Saved recovery audio is not a valid WAV file.")
        case .payloadTooLarge:
            return L10n.text("Saved recovery audio is too large to retry.")
        }
    }
}

enum RecoveryHistoryKind: String, CaseIterable, Identifiable, Sendable {
    case audio
    case asr
    case polish

    var id: String { rawValue }
}

enum RecoveryCopyKind: Sendable, Equatable {
    case audioFile
    case text
}

struct RecoveryHistoryPreview: Sendable, Equatable, Identifiable {
    let id: String
    let recordID: UUID
    let kind: RecoveryHistoryKind
    let timestamp: Date
    let text: String
    let copyText: String
    let copyKind: RecoveryCopyKind
    let target: String
    let outcome: String
    let errorMessage: String?
    let audioDurationMs: Int

    static func recentItems(
        from records: [RecoveryRecord],
        kind: RecoveryHistoryKind,
        limit: Int
    ) -> [RecoveryHistoryPreview] {
        records
            .sorted { $0.timestamp > $1.timestamp }
            .compactMap { record in
                makePreview(from: record, kind: kind)
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private static func makePreview(
        from record: RecoveryRecord,
        kind: RecoveryHistoryKind
    ) -> RecoveryHistoryPreview? {
        let copyText: String
        let displayText: String
        let copyKind: RecoveryCopyKind

        switch kind {
        case .audio:
            copyText = ""
            copyKind = .audioFile
            displayText = "\(formattedDuration(record.audioDurationMs)) WAV"
        case .asr:
            guard let text = record.asrText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            copyText = text
            copyKind = .text
            displayText = collapsedPreview(text)
        case .polish:
            guard let text = record.polishText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            copyText = text
            copyKind = .text
            displayText = collapsedPreview(text)
        }

        return RecoveryHistoryPreview(
            id: "\(kind.rawValue)-\(record.id.uuidString)",
            recordID: record.id,
            kind: kind,
            timestamp: record.timestamp,
            text: displayText,
            copyText: copyText,
            copyKind: copyKind,
            target: record.appName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? record.appName ?? L10n.text("Unknown target")
                : L10n.text("Unknown target"),
            outcome: record.outcome,
            errorMessage: record.errorMessage,
            audioDurationMs: record.audioDurationMs
        )
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

    private static func formattedDuration(_ durationMs: Int) -> String {
        let seconds = max(0, durationMs) / 1_000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

protocol RecoveryRecording: Sendable {
    var directoryURL: URL { get }
    func record(_ input: RecoveryRecordInput) throws
    func loadRecent(limit: Int) throws -> [RecoveryRecord]
    func resolveAudioURL(for record: RecoveryRecord) throws -> URL
}

final class RecoveryStore: RecoveryRecording, @unchecked Sendable {
    private let fileManager: FileManager
    let directoryURL: URL
    private let lock = NSLock()
    private let retainedLimit: Int

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        retainedLimit: Int = 10
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL ?? ProductIdentity.recoveryURL(
            homeDirectoryURL: fileManager.homeDirectoryForCurrentUser
        )
        self.retainedLimit = retainedLimit
    }

    func record(_ input: RecoveryRecordInput) throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: audioDirectoryURL, withIntermediateDirectories: true)
        try secureDirectory(at: directoryURL)
        try secureDirectory(at: audioDirectoryURL)
        var records = try loadRecentUnlocked(limit: retainedLimit)
        let id = UUID()
        let audioFileName = "\(id.uuidString).wav"
        let destinationURL = audioDirectoryURL.appendingPathComponent(audioFileName)
        try fileManager.copyItem(at: input.sourceAudioURL, to: destinationURL)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: destinationURL.path
        )
        records.append(
            RecoveryRecord(
                id: id,
                timestamp: input.timestamp,
                audioDurationMs: input.durationMs,
                asrText: input.asrText,
                polishText: input.polishText,
                appName: input.appName,
                appBundleIdentifier: input.appBundleIdentifier,
                outcome: input.outcome,
                errorMessage: input.errorMessage
            )
        )
        records = Array(records.sorted { $0.timestamp < $1.timestamp }.suffix(retainedLimit))
        try rewrite(records)
    }

    func loadRecent(limit: Int = 10) throws -> [RecoveryRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try loadRecentUnlocked(limit: limit)
    }

    func resolveAudioURL(for record: RecoveryRecord) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        return try resolveAudioURLUnlocked(for: record)
    }

    private func loadRecentUnlocked(limit: Int) throws -> [RecoveryRecord] {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return []
        }

        let contents = try String(contentsOf: indexURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return contents
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(RecoveryRecord.self, from: Data(line.utf8))
            }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(max(0, limit))
            .map { $0 }
    }

    private func rewrite(_ records: [RecoveryRecord]) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try records.reduce(into: Data()) { partial, record in
            partial.append(try encoder.encode(record))
            partial.append(0x0A)
        }
        try data.write(to: indexURL, options: [.atomic])
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: indexURL.path
        )

        let retainedFileNames = Set(records.map(\.audioFileName))
        let existingAudioFiles = (try? fileManager.contentsOfDirectory(at: audioDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        for audioFile in existingAudioFiles where !retainedFileNames.contains(audioFile.lastPathComponent) {
            try? fileManager.removeItem(at: audioFile)
        }
    }

    private var indexURL: URL {
        directoryURL.appendingPathComponent("recovery-history.jsonl")
    }

    private var audioDirectoryURL: URL {
        directoryURL.appendingPathComponent("Audio", isDirectory: true)
    }

    private func resolveAudioURLUnlocked(for record: RecoveryRecord) throws -> URL {
        guard fileManager.fileExists(atPath: audioDirectoryURL.path) else {
            throw RecoveryAudioError.missing
        }

        let directoryValues = try audioDirectoryURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard directoryValues.isSymbolicLink != true else {
            throw RecoveryAudioError.symbolicLink
        }
        guard directoryValues.isDirectory == true else {
            throw RecoveryAudioError.unsafePath
        }

        let expectedFileName = "\(record.id.uuidString).wav"
        guard expectedFileName == record.audioFileName else {
            throw RecoveryAudioError.unsafePath
        }

        let standardizedDirectory = audioDirectoryURL.standardizedFileURL
        let candidate = standardizedDirectory
            .appendingPathComponent(expectedFileName, isDirectory: false)
            .standardizedFileURL
        guard candidate.deletingLastPathComponent() == standardizedDirectory else {
            throw RecoveryAudioError.unsafePath
        }
        guard fileManager.fileExists(atPath: candidate.path) else {
            throw RecoveryAudioError.missing
        }

        let values = try candidate.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values.isSymbolicLink != true else {
            throw RecoveryAudioError.symbolicLink
        }
        guard values.isRegularFile == true else {
            throw RecoveryAudioError.notRegularFile
        }
        guard (values.fileSize ?? 0) <= 25_000_000 else {
            throw RecoveryAudioError.payloadTooLarge
        }

        let resolvedDirectory = standardizedDirectory.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.resolvingSymlinksInPath()
        guard resolvedCandidate.deletingLastPathComponent() == resolvedDirectory else {
            throw RecoveryAudioError.unsafePath
        }
        guard try hasWaveHeader(at: resolvedCandidate) else {
            throw RecoveryAudioError.invalidWaveFile
        }

        return resolvedCandidate
    }

    private func secureDirectory(at url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: url.path
        )
    }

    private func hasWaveHeader(at url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        let header = try handle.read(upToCount: 12) ?? Data()
        guard header.count == 12 else {
            return false
        }
        return header.prefix(4) == Data("RIFF".utf8)
            && header.suffix(4) == Data("WAVE".utf8)
    }
}
