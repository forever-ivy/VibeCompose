import Foundation

struct LatencySample: Codable, Sendable, Equatable {
    let timestamp: Date
    let audioDurationMs: Int
    let audioBytes: Int
    let provider: String
    let textPolishProvider: String?
    let authMs: Int
    let transcribeMs: Int
    let normalizationMs: Int
    let polishMs: Int
    let textPolishAttempted: Bool?
    let textPolishError: String?
    let estimatedPolishInputTokens: Int
    let estimatedPolishOutputTokens: Int
    let injectMs: Int
    let totalProcessingMs: Int
    let resultStatus: String
    let errorCategory: String?

    init(
        timestamp: Date,
        audioDurationMs: Int,
        audioBytes: Int,
        provider: String,
        textPolishProvider: String? = nil,
        authMs: Int,
        transcribeMs: Int,
        normalizationMs: Int,
        polishMs: Int = 0,
        textPolishAttempted: Bool? = nil,
        textPolishError: String? = nil,
        estimatedPolishInputTokens: Int = 0,
        estimatedPolishOutputTokens: Int = 0,
        injectMs: Int,
        totalProcessingMs: Int,
        resultStatus: String,
        errorCategory: String?
    ) {
        self.timestamp = timestamp
        self.audioDurationMs = audioDurationMs
        self.audioBytes = audioBytes
        self.provider = provider
        self.textPolishProvider = textPolishProvider
        self.authMs = authMs
        self.transcribeMs = transcribeMs
        self.normalizationMs = normalizationMs
        self.polishMs = polishMs
        self.textPolishAttempted = textPolishAttempted
        self.textPolishError = textPolishError
        self.estimatedPolishInputTokens = estimatedPolishInputTokens
        self.estimatedPolishOutputTokens = estimatedPolishOutputTokens
        self.injectMs = injectMs
        self.totalProcessingMs = totalProcessingMs
        self.resultStatus = resultStatus
        self.errorCategory = errorCategory
    }
}

protocol LatencyRecording: Sendable {
    func record(_ sample: LatencySample, retention: DiagnosticsRetentionPolicy) throws
    func prune(retention: DiagnosticsRetentionPolicy) throws
}

extension LatencyRecording {
    func record(_ sample: LatencySample) throws {
        try self.record(
            sample,
            retention: DiagnosticsRetentionPolicy(maxRecords: 1_000, retentionDays: 14)
        )
    }
}

final class LatencyRecorder: LatencyRecording, @unchecked Sendable {
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
        _ sample: LatencySample,
        retention: DiagnosticsRetentionPolicy
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        var samples = try loadSamplesUnlocked()
        samples.append(sample)
        try rewrite(retained(samples, policy: retention))
    }

    func loadRecent(limit: Int = 1_000) throws -> [LatencySample] {
        lock.lock()
        defer { lock.unlock() }
        return Array(try loadSamplesUnlocked().suffix(max(0, limit)))
    }

    func prune(retention: DiagnosticsRetentionPolicy) throws {
        lock.lock()
        defer { lock.unlock() }
        try rewrite(retained(try loadSamplesUnlocked(), policy: retention))
    }

    private func loadSamplesUnlocked() throws -> [LatencySample] {
        let lines = try JSONLTailReader.lines(
            at: dataURL,
            fileManager: fileManager,
            maximumBytes: maximumReadBytes
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return lines.compactMap { line in
            try? decoder.decode(LatencySample.self, from: Data(line.utf8))
        }
    }

    private func retained(
        _ samples: [LatencySample],
        policy: DiagnosticsRetentionPolicy
    ) -> [LatencySample] {
        guard policy.maxRecords > 0 else {
            return []
        }
        return samples
            .filter { $0.timestamp >= policy.cutoffDate }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(policy.maxRecords)
            .map { $0 }
    }

    private func rewrite(_ samples: [LatencySample]) throws {
        if samples.isEmpty {
            if fileManager.fileExists(atPath: dataURL.path) {
                try fileManager.removeItem(at: dataURL)
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

    private var dataURL: URL {
        directoryURL.appendingPathComponent("latency.jsonl")
    }
}
