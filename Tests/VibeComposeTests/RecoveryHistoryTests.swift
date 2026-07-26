import Foundation
import Testing
@testable import VibeCompose

@Test
func recoveryStoreRecordsAudioAsrAndPolishCopyItems() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceAudioURL = root.appendingPathComponent("source.wav")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try makeMinimalWaveData().write(to: sourceAudioURL)

    let store = RecoveryStore(directoryURL: root.appendingPathComponent("Recovery", isDirectory: true))
    try store.record(
        RecoveryRecordInput(
            timestamp: Date(timeIntervalSince1970: 1_234),
            sourceAudioURL: sourceAudioURL,
            durationMs: 65_000,
            asrText: " raw transcript ",
            polishText: " polished transcript ",
            appName: "Notes",
            appBundleIdentifier: "com.apple.Notes",
            outcome: "pasted",
            errorMessage: nil
        )
    )

    let records = try store.loadRecent(limit: 10)
    #expect(records.count == 1)

    let record = try #require(records.first)
    #expect(FileManager.default.fileExists(atPath: try store.resolveAudioURL(for: record).path))

    let audioItem = try #require(RecoveryHistoryPreview.recentItems(from: records, kind: .audio, limit: 10).first)
    #expect(audioItem.copyKind == .audioFile)
    #expect(audioItem.text == "01:05 WAV")
    #expect(audioItem.target == "Notes")

    let asrItem = try #require(RecoveryHistoryPreview.recentItems(from: records, kind: .asr, limit: 10).first)
    #expect(asrItem.copyKind == .text)
    #expect(asrItem.copyText == "raw transcript")

    let polishItem = try #require(RecoveryHistoryPreview.recentItems(from: records, kind: .polish, limit: 10).first)
    #expect(polishItem.copyKind == .text)
    #expect(polishItem.copyText == "polished transcript")
}

@Test
func recoveryStoreRetainsNewestRecordsAndPrunesOldAudio() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceAudioURL = root.appendingPathComponent("source.wav")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try makeMinimalWaveData().write(to: sourceAudioURL)

    let store = RecoveryStore(
        directoryURL: root.appendingPathComponent("Recovery", isDirectory: true),
        retainedLimit: 2
    )

    for index in 0..<3 {
        try store.record(
            RecoveryRecordInput(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                sourceAudioURL: sourceAudioURL,
                durationMs: 1_000,
                asrText: "asr \(index)",
                polishText: "polish \(index)",
                appName: nil,
                appBundleIdentifier: nil,
                outcome: "clipboard",
                errorMessage: nil
            )
        )
    }

    let records = try store.loadRecent(limit: 10)
    #expect(records.map(\.asrText) == ["asr 1", "asr 2"])

    let audioDirectory = store.directoryURL.appendingPathComponent("Audio", isDirectory: true)
    let audioFiles = try FileManager.default.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil)
    #expect(audioFiles.map(\.lastPathComponent).sorted() == records.map(\.audioFileName).sorted())
}

@Test
func recoveryStoreDeleteRemovesRecordAndAssociatedAudio() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceAudioURL = root.appendingPathComponent("source.wav")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try makeMinimalWaveData().write(to: sourceAudioURL)

    let store = RecoveryStore(
        directoryURL: root.appendingPathComponent("Recovery", isDirectory: true)
    )
    try store.record(
        RecoveryRecordInput(
            timestamp: Date(),
            sourceAudioURL: sourceAudioURL,
            durationMs: 1_000,
            asrText: "recover me",
            polishText: nil,
            appName: "Notes",
            appBundleIdentifier: "com.apple.Notes",
            outcome: "error",
            errorMessage: "network"
        )
    )

    let record = try #require(store.loadRecent(limit: 1).first)
    let storedAudioURL = try store.resolveAudioURL(for: record)
    try store.delete(id: record.id)

    #expect(try store.loadRecent(limit: 10).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: storedAudioURL.path))
}

@Test
func recoveryPreviewSkipsMissingTextForTextKinds() {
    let record = RecoveryRecord(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 42),
        audioDurationMs: 3_000,
        asrText: "   ",
        polishText: nil,
        appName: nil,
        appBundleIdentifier: nil,
        outcome: "error",
        errorMessage: "Network failed"
    )

    #expect(RecoveryHistoryPreview.recentItems(from: [record], kind: .audio, limit: 10).count == 1)
    #expect(RecoveryHistoryPreview.recentItems(from: [record], kind: .asr, limit: 10).isEmpty)
    #expect(RecoveryHistoryPreview.recentItems(from: [record], kind: .polish, limit: 10).isEmpty)
}

@Test
func recoveryRecordIgnoresLegacyAudioFileNameTraversal() throws {
    let id = UUID()
    let data = Data(
        """
        {
          "id": "\(id.uuidString)",
          "timestamp": "1970-01-01T00:00:42Z",
          "audioFileName": "../../Documents/secret.wav",
          "audioDurationMs": 1000,
          "outcome": "error"
        }
        """.utf8
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let record = try decoder.decode(RecoveryRecord.self, from: data)
    let encoded = try JSONEncoder().encode(record)

    #expect(record.audioFileName == "\(id.uuidString).wav")
    #expect(String(decoding: encoded, as: UTF8.self).contains("audioFileName") == false)
}

@Test
func recoveryResolverRejectsSymbolicLinks() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let recoveryDirectory = root.appendingPathComponent("Recovery", isDirectory: true)
    let sourceAudioURL = root.appendingPathComponent("source.wav")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try makeMinimalWaveData().write(to: sourceAudioURL)

    let store = RecoveryStore(directoryURL: recoveryDirectory)
    try store.record(
        RecoveryRecordInput(
            timestamp: Date(),
            sourceAudioURL: sourceAudioURL,
            durationMs: 1_000,
            asrText: nil,
            polishText: nil,
            appName: nil,
            appBundleIdentifier: nil,
            outcome: "error",
            errorMessage: nil
        )
    )
    let record = try #require(store.loadRecent(limit: 1).first)
    let storedURL = try store.resolveAudioURL(for: record)
    try FileManager.default.removeItem(at: storedURL)
    try FileManager.default.createSymbolicLink(at: storedURL, withDestinationURL: sourceAudioURL)

    #expect(throws: RecoveryAudioError.symbolicLink) {
        try store.resolveAudioURL(for: record)
    }
}

@Test
func recoveryResolverRejectsInvalidWaveContent() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceAudioURL = root.appendingPathComponent("source.wav")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try makeMinimalWaveData().write(to: sourceAudioURL)

    let store = RecoveryStore(directoryURL: root.appendingPathComponent("Recovery", isDirectory: true))
    try store.record(
        RecoveryRecordInput(
            timestamp: Date(),
            sourceAudioURL: sourceAudioURL,
            durationMs: 1_000,
            asrText: nil,
            polishText: nil,
            appName: nil,
            appBundleIdentifier: nil,
            outcome: "error",
            errorMessage: nil
        )
    )
    let record = try #require(store.loadRecent(limit: 1).first)
    let storedURL = try store.resolveAudioURL(for: record)
    try Data("not-a-wave".utf8).write(to: storedURL)

    #expect(throws: RecoveryAudioError.invalidWaveFile) {
        try store.resolveAudioURL(for: record)
    }
}

@Test
func recoveryStoreRejectsInvalidSourceAudio() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sourceAudioURL = root.appendingPathComponent("source.wav")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data("not-a-wave".utf8).write(to: sourceAudioURL)

    let store = RecoveryStore(directoryURL: root.appendingPathComponent("Recovery", isDirectory: true))
    #expect(throws: RecoveryAudioError.invalidWaveFile) {
        try store.record(
            RecoveryRecordInput(
                timestamp: Date(),
                sourceAudioURL: sourceAudioURL,
                durationMs: 1_000,
                asrText: nil,
                polishText: nil,
                appName: nil,
                appBundleIdentifier: nil,
                outcome: "error",
                errorMessage: nil
            )
        )
    }
}

private func makeMinimalWaveData() -> Data {
    var data = Data("RIFF".utf8)
    data.append(contentsOf: [4, 0, 0, 0])
    data.append(Data("WAVE".utf8))
    return data
}
