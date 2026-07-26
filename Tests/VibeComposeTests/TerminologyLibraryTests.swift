import Foundation
import Testing
@testable import VibeCompose

@Test
func terminologyImportPreviewSeparatesNewDuplicatesAndConflicts() throws {
    let existing = [
        terminologyEntry(type: .term, original: "VibeCompose"),
        terminologyEntry(
            type: .correction,
            original: "vibecompose",
            replacement: "VibeCompose"
        ),
    ]
    let incoming = [
        terminologyEntry(type: .term, original: "vibecompose"),
        terminologyEntry(
            type: .correction,
            original: "VibeCompose",
            replacement: "VibeCompose"
        ),
        terminologyEntry(
            type: .correction,
            original: "vibecompose",
            replacement: "VibeCompose Pro"
        ),
        terminologyEntry(type: .term, original: "Shadowd"),
    ]
    let result = TerminologyTextImportResult(
        entries: incoming,
        source: "terms.csv",
        importedAt: "2026-07-13T00:00:00Z"
    )

    let preview = TerminologyLibrary.importPreview(existing: existing, result: result)

    #expect(preview.newEntries.map(\.original) == ["Shadowd"])
    #expect(preview.duplicateEntries.count == 2)
    #expect(preview.conflictingEntries.map(\.replacement) == ["VibeCompose Pro"])
    #expect(
        TerminologyLibrary.merge(existing: existing, incoming: incoming)
            .map(\.original) == ["VibeCompose", "vibecompose", "Shadowd"]
    )
}

@Test
func terminologyCSVExportRoundTripsStructuredFields() throws {
    let entries = [
        terminologyEntry(
            type: .correction,
            original: "open, whisper",
            replacement: "VibeCompose",
            aliases: ["Open \"Whisper\"", "VibeCompose"],
            isEnabled: false
        ),
        terminologyEntry(type: .term, original: "Shadowd"),
    ]

    let result = try TerminologyTextImporter().importEntries(
        from: TerminologyLibrary.csvData(entries: entries),
        sourceName: "roundtrip.csv"
    )

    #expect(result.entries.count == 2)
    let correction = try #require(
        result.entries.first(where: { $0.type == .correction })
    )
    #expect(correction.original == "open, whisper")
    #expect(correction.replacement == "VibeCompose")
    #expect(correction.aliases == ["Open \"Whisper\"", "VibeCompose"])
    #expect(!correction.isEnabled)
}

@Test
func terminologyQuickAddBuildsValidatedEntriesAndRejectsIdentityConflicts() throws {
    let now = Date(timeIntervalSince1970: 1_752_364_800)
    let draft = TerminologyQuickAddDraft(
        type: .correction,
        original: " open wisper ",
        replacement: " VibeCompose ",
        aliases: "OW, ow, VibeCompose"
    )

    let entry = try draft.makeEntry(existing: [], now: now)

    #expect(entry.type == .correction)
    #expect(entry.original == "open wisper")
    #expect(entry.replacement == "VibeCompose")
    #expect(entry.aliases == ["OW", "VibeCompose"])
    #expect(entry.source == "user")

    #expect(throws: TerminologyQuickAddError.duplicate) {
        try draft.makeEntry(existing: [entry], now: now)
    }
}

@Test
func terminologyQuickAddRequiresCorrectionReplacement() {
    let draft = TerminologyQuickAddDraft(
        type: .correction,
        original: "wrong",
        replacement: " ",
        aliases: ""
    )

    #expect(throws: TerminologyQuickAddError.replacementRequired) {
        try draft.makeEntry(existing: [])
    }
}

private func terminologyEntry(
    type: TerminologyEntryType,
    original: String,
    replacement: String? = nil,
    aliases: [String] = [],
    isEnabled: Bool = true
) -> TerminologyEntry {
    TerminologyEntry(
        type: type,
        original: original,
        replacement: replacement,
        aliases: aliases,
        isEnabled: isEnabled,
        source: "test",
        usageCount: 0,
        createdAt: "2026-07-13T00:00:00Z"
    )
}
