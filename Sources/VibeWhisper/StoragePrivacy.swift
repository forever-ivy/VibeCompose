import Foundation

struct HistoryRetentionPolicy: Sendable, Equatable {
    let maxRecords: Int
    let maxAge: TimeInterval
    let now: Date

    init(maxRecords: Int, retentionDays: Int, now: Date = Date()) {
        self.maxRecords = max(0, maxRecords)
        maxAge = TimeInterval(max(1, retentionDays)) * 24 * 60 * 60
        self.now = now
    }

    var cutoffDate: Date {
        now.addingTimeInterval(-maxAge)
    }
}

struct RecoveryRetentionPolicy: Sendable, Equatable {
    let maxRecords: Int
    let maxAge: TimeInterval?
    let now: Date

    init(maxRecords: Int, retentionHours: Int? = nil, now: Date = Date()) {
        self.maxRecords = max(0, maxRecords)
        maxAge = retentionHours.map { TimeInterval(max(1, $0)) * 60 * 60 }
        self.now = now
    }

    var cutoffDate: Date? {
        maxAge.map { now.addingTimeInterval(-$0) }
    }
}

struct DiagnosticsRetentionPolicy: Sendable, Equatable {
    let maxRecords: Int
    let maxAge: TimeInterval
    let now: Date

    init(maxRecords: Int, retentionDays: Int, now: Date = Date()) {
        self.maxRecords = max(0, maxRecords)
        maxAge = TimeInterval(max(1, retentionDays)) * 24 * 60 * 60
        self.now = now
    }

    var cutoffDate: Date {
        now.addingTimeInterval(-maxAge)
    }
}

extension PrivacyConfig {
    func historyRetentionPolicy(now: Date = Date()) -> HistoryRetentionPolicy {
        HistoryRetentionPolicy(
            maxRecords: historyEnabled ? historyRecordLimit : 0,
            retentionDays: historyRetentionDays,
            now: now
        )
    }

    func recoveryRetentionPolicy(now: Date = Date()) -> RecoveryRetentionPolicy {
        RecoveryRetentionPolicy(
            maxRecords: failedAudioRecoveryEnabled ? failedAudioRecordLimit : 0,
            retentionHours: failedAudioRetentionHours,
            now: now
        )
    }

    func diagnosticsRetentionPolicy(now: Date = Date()) -> DiagnosticsRetentionPolicy {
        DiagnosticsRetentionPolicy(
            maxRecords: diagnosticsEnabled ? diagnosticsRecordLimit : 0,
            retentionDays: diagnosticsRetentionDays,
            now: now
        )
    }

    func productMetricsRetentionPolicy(
        now: Date = Date()
    ) -> DiagnosticsRetentionPolicy {
        DiagnosticsRetentionPolicy(
            maxRecords:
                productMetricsEnabled ? productMetricsRecordLimit : 0,
            retentionDays: productMetricsRetentionDays,
            now: now
        )
    }
}

enum SensitiveAppPolicy {
    static let builtInBundleIdentifiers: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
        "com.apple.passwords",
        "com.bitwarden.desktop",
        "com.lastpass.lastpass",
        "com.lastpass.lastpassmacdesktop",
    ]

    static func permitsPersistence(
        bundleIdentifier: String?,
        privacy: PrivacyConfig
    ) -> Bool {
        guard privacy.excludeSensitiveApps else {
            return true
        }
        guard let normalized = normalizedBundleIdentifier(bundleIdentifier) else {
            return true
        }

        let additional = Set(
            privacy.additionalSensitiveAppBundleIdentifiers.compactMap(normalizedBundleIdentifier(_:))
        )
        return !builtInBundleIdentifiers.contains(normalized) && !additional.contains(normalized)
    }

    static func permitsContext(
        bundleIdentifier: String?,
        privacy: PrivacyConfig
    ) -> Bool {
        permitsPersistence(
            bundleIdentifier:
                bundleIdentifier,
            privacy: privacy
        )
    }

    private static func normalizedBundleIdentifier(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

enum JSONLTailReader {
    static func lines(
        at url: URL,
        fileManager: FileManager,
        maximumBytes: Int
    ) throws -> [Substring] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let endOffset = try handle.seekToEnd()
        let boundedMaximum = UInt64(max(1, maximumBytes))
        let startOffset = endOffset > boundedMaximum ? endOffset - boundedMaximum : 0
        try handle.seek(toOffset: startOffset)
        let data = try handle.readToEnd() ?? Data()
        guard var text = String(data: data, encoding: .utf8) else {
            return []
        }

        if startOffset > 0 {
            guard let firstNewline = text.firstIndex(of: "\n") else {
                return []
            }
            text = String(text[text.index(after: firstNewline)...])
        }

        return text.split(separator: "\n")
    }
}

enum StorageCleanupError: LocalizedError, Equatable {
    case unsafeApplicationSupportPath(String)
    case symbolicLink(String)

    var errorDescription: String? {
        switch self {
        case .unsafeApplicationSupportPath(let path):
            return L10n.format("VibeWhisper refused to delete an unsafe data path: %@", path)
        case .symbolicLink(let path):
            return L10n.format("VibeWhisper refused to delete data through a symbolic link: %@", path)
        }
    }
}

struct StorageCleanupService {
    let fileManager: FileManager
    let applicationSupportURL: URL

    init(
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.applicationSupportURL = applicationSupportURL ?? ProductIdentity.applicationSupportURL(
            homeDirectoryURL: fileManager.homeDirectoryForCurrentUser
        )
    }

    func clearRetryOrphans() throws {
        try validateApplicationSupportURL()
        let retryURL = applicationSupportURL.appendingPathComponent("Retry", isDirectory: true)
        if fileManager.fileExists(atPath: retryURL.path) {
            try fileManager.removeItem(at: retryURL)
        }
    }

    func deleteAllData() throws {
        try validateApplicationSupportURL()
        if fileManager.fileExists(atPath: applicationSupportURL.path) {
            try fileManager.removeItem(at: applicationSupportURL)
        }
        try fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: applicationSupportURL.path
        )
    }

    private func validateApplicationSupportURL() throws {
        let standardized = applicationSupportURL.standardizedFileURL
        guard
            standardized.lastPathComponent == ProductIdentity.name,
            standardized.path != "/",
            standardized.pathComponents.count >= 4
        else {
            throw StorageCleanupError.unsafeApplicationSupportPath(applicationSupportURL.path)
        }

        if fileManager.fileExists(atPath: standardized.path) {
            let values = try standardized.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw StorageCleanupError.symbolicLink(standardized.path)
            }
        }
    }
}
