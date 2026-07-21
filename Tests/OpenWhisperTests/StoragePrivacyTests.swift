import Foundation
import Testing
@testable import OpenWhisper

@Test
func privacyConfigDefaultsAreBoundedAndMinimizeStoredContent() throws {
    let config = AppConfig()

    #expect(config.privacy.historyEnabled)
    #expect(config.privacy.historyRetentionDays == 30)
    #expect(config.privacy.historyRecordLimit == 500)
    #expect(!config.privacy.storeRawTranscripts)
    #expect(config.privacy.failedAudioRecoveryEnabled)
    #expect(config.privacy.failedAudioRetentionHours == 24)
    #expect(config.privacy.failedAudioRecordLimit == 10)
    #expect(config.privacy.diagnosticsEnabled)
    #expect(config.privacy.productMetricsEnabled == false)
    #expect(config.privacy.productMetricsRetentionDays == 30)
    #expect(config.privacy.productMetricsRecordLimit == 5_000)
    #expect(config.privacy.excludeSensitiveApps)

    let decoded = try JSONDecoder().decode(
        AppConfig.self,
        from: Data(
            """
            {
              "privacy": {
                "historyRetentionDays": -4,
                "historyRecordLimit": 999999,
                "failedAudioRetentionHours": 0,
                "diagnosticsRecordLimit": 2,
                "additionalSensitiveAppBundleIdentifiers": [
                  " COM.EXAMPLE.SECRET ",
                  "com.example.secret",
                  ""
                ]
              }
            }
            """.utf8
        )
    )

    #expect(decoded.privacy.historyRetentionDays == 1)
    #expect(decoded.privacy.historyRecordLimit == 10_000)
    #expect(decoded.privacy.failedAudioRetentionHours == 1)
    #expect(decoded.privacy.diagnosticsRecordLimit == 100)
    #expect(decoded.privacy.additionalSensitiveAppBundleIdentifiers == ["com.example.secret"])
}

@Test
func transcriptionHistoryAppliesAgeAndCountRetention() throws {
    let root = temporaryOpenWhisperDirectory()
    let recorder = TranscriptionHistoryRecorder(directoryURL: root)
    let now = Date(timeIntervalSince1970: 1_000_000)
    let policy = HistoryRetentionPolicy(maxRecords: 2, retentionDays: 2, now: now)

    for (offset, text) in [
        (-3 * 24 * 60 * 60, "expired"),
        (-60, "first"),
        (-30, "second"),
        (0, "third"),
    ] {
        try recorder.record(
            TranscriptionHistoryRecord(
                timestamp: now.addingTimeInterval(TimeInterval(offset)),
                finalText: text,
                appName: "Notes",
                appBundleIdentifier: "com.apple.Notes",
                outcome: "pasted"
            ),
            retention: policy
        )
    }

    let records = try recorder.loadRecent(limit: 10)
    #expect(records.map(\.finalText) == ["second", "third"])

    let attributes = try FileManager.default.attributesOfItem(
        atPath: root.appendingPathComponent("transcription-history.jsonl").path
    )
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test
func legacyTranscriptionHistoryUsesStableIdentifiersAndCanBeDeleted() throws {
    let root = temporaryOpenWhisperDirectory()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let historyURL = root.appendingPathComponent("transcription-history.jsonl")
    let legacyLine = #"{"timestamp":"2026-07-13T00:00:00Z","rawText":"raw","finalText":"final","appName":"Notes","appBundleIdentifier":"com.apple.Notes","outcome":"pasted"}"#
    try Data((legacyLine + "\n").utf8).write(to: historyURL)

    let recorder = TranscriptionHistoryRecorder(directoryURL: root)
    let firstLoad = try #require(recorder.loadRecent(limit: 10).first)
    let secondLoad = try #require(recorder.loadRecent(limit: 10).first)

    #expect(firstLoad.id == secondLoad.id)
    try recorder.delete(id: firstLoad.id)
    #expect(try recorder.loadRecent(limit: 10).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: historyURL.path))
}

@Test
func transcriptionHistoryPersistsSafeUndoStateTransitions() throws {
    let root = temporaryOpenWhisperDirectory()
    let recorder = TranscriptionHistoryRecorder(directoryURL: root)
    let record = TranscriptionHistoryRecord(
        timestamp: Date(),
        finalText: "inserted",
        appName: "TextEdit",
        appBundleIdentifier: "com.apple.TextEdit",
        outcome: TextDeliveryStatus.insertedAndVerified,
        undoState: .available
    )
    try recorder.record(record)
    try recorder.updateUndoState(
        id: record.id,
        state: .restored
    )

    let loaded = try #require(
        recorder.loadRecent(limit: 1).first
    )
    #expect(loaded.id == record.id)
    #expect(loaded.undoState == .restored)
}

@Test
func transcriptionHistoryPersistsRedactedSkillRunReceipt() throws {
    let root = temporaryOpenWhisperDirectory()
    let recorder = TranscriptionHistoryRecorder(directoryURL: root)
    let installationID = UUID()
    let receipt = SkillRunReceipt(
        runID: UUID(),
        skillInstallationID: installationID,
        skillID: "com.openwhisper.direct",
        displayName: "Direct",
        source: "builtin",
        version: "1.0.0",
        revision: "1.0.0",
        contentDigest: String(repeating: "a", count: 64),
        resolutionReason: "globalDefault",
        targetApplicationBundleIdentifier: "com.apple.TextEdit",
        contextDecisions: [
            ContextDecision(
                source: .voice,
                requestedAs: "required",
                availability: "available",
                permission: "allowed",
                captureResult: "captured",
                characterCount: 0,
                decisionCode: "granted"
            ),
        ],
        resourceIDs: ["SKILL.md"],
        requestedOutputRoute: "automaticPasteWhenVerified",
        actualOutputRoute: "pasteToTarget",
        targetVerification: TextDeliveryStatus.insertedAndVerified,
        finalUserAction: "pasteToTarget"
    )
    let record = TranscriptionHistoryRecord(
        timestamp: Date(),
        finalText: "safe",
        appName: "TextEdit",
        appBundleIdentifier: "com.apple.TextEdit",
        outcome: TextDeliveryStatus.insertedAndVerified,
        skillRunReceipt: receipt
    )
    try recorder.record(record)

    let loaded = try #require(recorder.loadRecent(limit: 1).first)
    #expect(loaded.skillRunReceipt?.runID == receipt.runID)
    #expect(loaded.skillRunReceipt?.skillInstallationID == installationID)
    #expect(loaded.skillRunReceipt?.contextDecisions == receipt.contextDecisions)
    #expect(loaded.skillRunReceipt?.resourceIDs == ["SKILL.md"])
}

@Test
func latencyRecorderRotatesByAgeAndCount() throws {
    let root = temporaryOpenWhisperDirectory()
    let recorder = LatencyRecorder(directoryURL: root)
    let now = Date(timeIntervalSince1970: 2_000_000)
    let policy = DiagnosticsRetentionPolicy(maxRecords: 2, retentionDays: 7, now: now)

    try recorder.record(makeLatencySample(timestamp: now.addingTimeInterval(-8 * 24 * 60 * 60), status: "expired"), retention: policy)
    try recorder.record(makeLatencySample(timestamp: now.addingTimeInterval(-2), status: "first"), retention: policy)
    try recorder.record(makeLatencySample(timestamp: now.addingTimeInterval(-1), status: "second"), retention: policy)
    try recorder.record(makeLatencySample(timestamp: now, status: "third"), retention: policy)

    #expect(try recorder.loadRecent(limit: 10).map(\.resultStatus) == ["second", "third"])
}

@Test
func recoveryStoreExpiresFailedAudioAndKeepsOnlyBoundedRecords() throws {
    let root = temporaryOpenWhisperDirectory()
    let sourceAudioURL = root.deletingLastPathComponent().appendingPathComponent("source.wav")
    try FileManager.default.createDirectory(
        at: sourceAudioURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try makeMinimalWaveDataForPrivacyTests().write(to: sourceAudioURL)

    let recoveryURL = root.appendingPathComponent("Recovery", isDirectory: true)
    let store = RecoveryStore(directoryURL: recoveryURL)
    let now = Date(timeIntervalSince1970: 3_000_000)
    let policy = RecoveryRetentionPolicy(maxRecords: 1, retentionHours: 24, now: now)

    try store.record(
        RecoveryRecordInput(
            timestamp: now.addingTimeInterval(-48 * 60 * 60),
            sourceAudioURL: sourceAudioURL,
            durationMs: 1_000,
            asrText: nil,
            polishText: nil,
            appName: nil,
            appBundleIdentifier: nil,
            outcome: "error",
            errorMessage: "expired"
        ),
        retention: policy
    )
    #expect(try store.loadRecent(limit: 10).isEmpty)

    for offset in [-60.0, 0.0] {
        try store.record(
            RecoveryRecordInput(
                timestamp: now.addingTimeInterval(offset),
                sourceAudioURL: sourceAudioURL,
                durationMs: 1_000,
                asrText: nil,
                polishText: nil,
                appName: nil,
                appBundleIdentifier: nil,
                outcome: "error",
                errorMessage: "\(offset)"
            ),
            retention: policy
        )
    }

    let records = try store.loadRecent(limit: 10)
    #expect(records.count == 1)
    #expect(records.first?.timestamp == now)

    let audioFiles = try FileManager.default.contentsOfDirectory(
        at: recoveryURL.appendingPathComponent("Audio", isDirectory: true),
        includingPropertiesForKeys: nil
    )
    #expect(audioFiles.map(\.lastPathComponent) == records.map(\.audioFileName))
    let audioAttributes = try FileManager.default.attributesOfItem(
        atPath: try #require(audioFiles.first).path
    )
    #expect((audioAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test
func recoveryStoreTightensLegacyAudioPermissionsWhenPruning() throws {
    let root = temporaryOpenWhisperDirectory()
    let sourceAudioURL = root.deletingLastPathComponent().appendingPathComponent("source.wav")
    try FileManager.default.createDirectory(
        at: sourceAudioURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try makeMinimalWaveDataForPrivacyTests().write(to: sourceAudioURL)

    let store = RecoveryStore(
        directoryURL: root.appendingPathComponent("Recovery", isDirectory: true)
    )
    let now = Date(timeIntervalSince1970: 4_000_000)
    let policy = RecoveryRetentionPolicy(maxRecords: 10, retentionHours: 24, now: now)
    try store.record(
        RecoveryRecordInput(
            timestamp: now,
            sourceAudioURL: sourceAudioURL,
            durationMs: 1_000,
            asrText: nil,
            polishText: nil,
            appName: nil,
            appBundleIdentifier: nil,
            outcome: "error",
            errorMessage: "retry"
        ),
        retention: policy
    )

    let record = try #require(store.loadRecent(limit: 1).first)
    let storedAudioURL = try store.resolveAudioURL(for: record)
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o644))],
        ofItemAtPath: storedAudioURL.path
    )

    try store.prune(retention: policy)

    let attributes = try FileManager.default.attributesOfItem(atPath: storedAudioURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test
func recoveryStoreRejectsSymlinkedStorageWithoutTouchingTarget() throws {
    let root = temporaryOpenWhisperDirectory()
    let outside = root.deletingLastPathComponent()
        .appendingPathComponent("outside-recovery", isDirectory: true)
    let sentinel = outside.appendingPathComponent("sentinel.txt")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: sentinel)

    let recoveryURL = root.appendingPathComponent("Recovery", isDirectory: true)
    try FileManager.default.createSymbolicLink(
        at: recoveryURL,
        withDestinationURL: outside
    )
    let store = RecoveryStore(directoryURL: recoveryURL)

    #expect(throws: RecoveryAudioError.symbolicLink) {
        try store.prune(
            retention: RecoveryRetentionPolicy(
                maxRecords: 10,
                retentionHours: 24
            )
        )
    }
    #expect(FileManager.default.fileExists(atPath: sentinel.path))
}

@Test
func recoveryStoreRejectsSymlinkedIndex() throws {
    let root = temporaryOpenWhisperDirectory()
    let recoveryURL = root.appendingPathComponent("Recovery", isDirectory: true)
    let outsideIndex = root.deletingLastPathComponent().appendingPathComponent("outside-index.jsonl")
    try FileManager.default.createDirectory(at: recoveryURL, withIntermediateDirectories: true)
    try Data("malicious".utf8).write(to: outsideIndex)
    try FileManager.default.createSymbolicLink(
        at: recoveryURL.appendingPathComponent("recovery-history.jsonl"),
        withDestinationURL: outsideIndex
    )

    let store = RecoveryStore(directoryURL: recoveryURL)
    #expect(throws: RecoveryAudioError.symbolicLink) {
        try store.loadRecent(limit: 10)
    }
}

@Test
func sensitiveAppPolicyBlocksBuiltInAndUserDefinedTargets() {
    var privacy = PrivacyConfig()
    privacy.additionalSensitiveAppBundleIdentifiers = ["com.example.private-editor"]

    #expect(!SensitiveAppPolicy.permitsPersistence(
        bundleIdentifier: "com.apple.Passwords",
        privacy: privacy
    ))
    #expect(!SensitiveAppPolicy.permitsPersistence(
        bundleIdentifier: "COM.EXAMPLE.PRIVATE-EDITOR",
        privacy: privacy
    ))
    #expect(SensitiveAppPolicy.permitsPersistence(
        bundleIdentifier: "com.apple.Notes",
        privacy: privacy
    ))

    privacy.excludeSensitiveApps = false
    #expect(SensitiveAppPolicy.permitsPersistence(
        bundleIdentifier: "com.apple.Passwords",
        privacy: privacy
    ))
}

@Test
func storageCleanupDeletesOnlyTheOpenWhisperContainer() throws {
    let parent = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let root = parent.appendingPathComponent(ProductIdentity.name, isDirectory: true)
    let sibling = parent.appendingPathComponent("keep.txt")
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("Recovery/Audio", isDirectory: true),
        withIntermediateDirectories: true
    )
    try Data("private".utf8).write(to: root.appendingPathComponent("transcription-history.jsonl"))
    try Data("keep".utf8).write(to: sibling)

    try StorageCleanupService(applicationSupportURL: root).deleteAllData()

    #expect(FileManager.default.fileExists(atPath: root.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    #expect(FileManager.default.fileExists(atPath: sibling.path))
}

@Test
func temporaryArtifactCleanupRemovesOnlyOwnedCrashOrphans() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let recordingName = "openwhisper-\(UUID().uuidString).wav"
    let uploadName = "openwhisper-upload-\(UUID().uuidString).multipart"
    let symlinkName = "openwhisper-\(UUID().uuidString).wav"
    let recordingURL = root.appendingPathComponent(recordingName)
    let uploadURL = root.appendingPathComponent(uploadName)
    let symlinkURL = root.appendingPathComponent(symlinkName)
    let lookalikeURL = root.appendingPathComponent("openwhisper-not-a-uuid.wav")
    let directoryLookalike = root.appendingPathComponent(
        "openwhisper-\(UUID().uuidString).wav",
        isDirectory: true
    )
    let outsideTarget = root.deletingLastPathComponent()
        .appendingPathComponent("openwhisper-cleanup-sentinel-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: outsideTarget) }

    try Data("recording".utf8).write(to: recordingURL)
    try Data("multipart".utf8).write(to: uploadURL)
    try Data("keep".utf8).write(to: lookalikeURL)
    try Data("outside".utf8).write(to: outsideTarget)
    try FileManager.default.createDirectory(at: directoryLookalike, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
        at: symlinkURL,
        withDestinationURL: outsideTarget
    )

    let report = TemporaryArtifactCleanupService(
        temporaryDirectoryURL: root
    ).cleanupOrphans()

    #expect(report.removedFileNames == [recordingName, symlinkName, uploadName].sorted())
    #expect(report.failedFileNames.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: recordingURL.path))
    #expect(!FileManager.default.fileExists(atPath: uploadURL.path))
    #expect(!FileManager.default.fileExists(atPath: symlinkURL.path))
    #expect(FileManager.default.fileExists(atPath: outsideTarget.path))
    #expect(FileManager.default.fileExists(atPath: lookalikeURL.path))
    #expect(FileManager.default.fileExists(atPath: directoryLookalike.path))
}

private func temporaryOpenWhisperDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent(ProductIdentity.name, isDirectory: true)
}

private func makeLatencySample(timestamp: Date, status: String) -> LatencySample {
    LatencySample(
        timestamp: timestamp,
        audioDurationMs: 1_000,
        audioBytes: 1_000,
        provider: "chatGPTManagedAuth",
        authMs: 10,
        transcribeMs: 20,
        normalizationMs: 1,
        injectMs: 1,
        totalProcessingMs: 32,
        resultStatus: status,
        errorCategory: nil
    )
}

private func makeMinimalWaveDataForPrivacyTests() -> Data {
    var data = Data("RIFF".utf8)
    data.append(contentsOf: [4, 0, 0, 0])
    data.append(Data("WAVE".utf8))
    return data
}
