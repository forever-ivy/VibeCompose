import Foundation
import Testing
@testable import VibeWhisper

@Test
func historyLibraryFiltersByKindStatusDateAndSearch() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = try #require(
        ISO8601DateFormatter().date(from: "2026-07-13T12:00:00Z")
    )
    let transcripts = [
        TranscriptionHistoryRecord(
            timestamp: now.addingTimeInterval(-60),
            finalText: "VibeWhisper verified result",
            appName: "Notes",
            appBundleIdentifier: "com.apple.Notes",
            outcome: TextDeliveryStatus.insertedAndVerified
        ),
        TranscriptionHistoryRecord(
            timestamp: now.addingTimeInterval(-90),
            finalText: "VibeWhisper legacy paste result",
            appName: "TextEdit",
            appBundleIdentifier: "com.apple.TextEdit",
            outcome: TextDeliveryStatus.legacyPasteDispatched
        ),
        TranscriptionHistoryRecord(
            timestamp: now.addingTimeInterval(-8 * 24 * 60 * 60),
            finalText: "Old clipboard result",
            appName: "Mail",
            appBundleIdentifier: "com.apple.Mail",
            outcome: "clipboard"
        ),
    ]
    let recovery = [
        RecoveryRecord(
            id: UUID(),
            timestamp: now.addingTimeInterval(-120),
            audioDurationMs: 2_000,
            asrText: "Retry Shadowd",
            polishText: nil,
            appName: "Terminal",
            appBundleIdentifier: "com.apple.Terminal",
            outcome: "error",
            errorMessage: "Network failed"
        ),
    ]

    let verified = HistoryLibrary.filteredEntries(
        transcripts: transcripts,
        recovery: recovery,
        query: "vibewhisper",
        kindFilter: .transcripts,
        statusFilter: .verified,
        dateFilter: .today,
        now: now,
        calendar: calendar
    )
    #expect(verified.count == 1)
    #expect(verified.first?.target == "Notes")

    let pasteSent = HistoryLibrary.filteredEntries(
        transcripts: transcripts,
        recovery: recovery,
        query: "legacy",
        kindFilter: .transcripts,
        statusFilter: .pasteSent,
        dateFilter: .today,
        now: now,
        calendar: calendar
    )
    #expect(pasteSent.count == 1)
    #expect(pasteSent.first?.target == "TextEdit")

    let errors = HistoryLibrary.filteredEntries(
        transcripts: transcripts,
        recovery: recovery,
        query: "shadowd",
        kindFilter: .all,
        statusFilter: .errors,
        dateFilter: .sevenDays,
        now: now,
        calendar: calendar
    )
    #expect(errors.count == 1)
    #expect(errors.first?.kind == .recovery)

    let recentCopied = HistoryLibrary.filteredEntries(
        transcripts: transcripts,
        recovery: recovery,
        query: "",
        kindFilter: .all,
        statusFilter: .copied,
        dateFilter: .sevenDays,
        now: now,
        calendar: calendar
    )
    #expect(recentCopied.isEmpty)
}
