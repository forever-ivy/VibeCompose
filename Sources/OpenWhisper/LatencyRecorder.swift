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
    func record(_ sample: LatencySample) throws
}

final class LatencyRecorder: LatencyRecording, @unchecked Sendable {
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

    func record(_ sample: LatencySample) throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let dataURL = directoryURL.appendingPathComponent("latency.jsonl")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let line = try encoder.encode(sample) + Data([0x0A])

        if fileManager.fileExists(atPath: dataURL.path) {
            let handle = try FileHandle(forWritingTo: dataURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: dataURL, options: [.atomic])
        }
    }
}
