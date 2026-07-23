import Foundation
import Testing
@testable import OpenWhisper

@Test
func terminologyImportPreviewSeparatesNewDuplicatesAndConflicts() throws {
    let existing = [
        terminologyEntry(type: .term, original: "OpenWhisper"),
        terminologyEntry(
            type: .correction,
            original: "open whisper",
            replacement: "OpenWhisper"
        ),
    ]
    let incoming = [
        terminologyEntry(type: .term, original: "openwhisper"),
        terminologyEntry(
            type: .correction,
            original: "Open Whisper",
            replacement: "OpenWhisper"
        ),
        terminologyEntry(
            type: .correction,
            original: "open whisper",
            replacement: "Open Whisper Pro"
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
    #expect(preview.conflictingEntries.map(\.replacement) == ["Open Whisper Pro"])
    #expect(
        TerminologyLibrary.merge(existing: existing, incoming: incoming)
            .map(\.original) == ["OpenWhisper", "open whisper", "Shadowd"]
    )
}

@Test
func terminologyCSVExportRoundTripsStructuredFields() throws {
    let entries = [
        terminologyEntry(
            type: .correction,
            original: "open, whisper",
            replacement: "OpenWhisper",
            aliases: ["Open \"Whisper\"", "Open Whisper"],
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
    #expect(correction.replacement == "OpenWhisper")
    #expect(correction.aliases == ["Open \"Whisper\"", "Open Whisper"])
    #expect(!correction.isEnabled)
}

@Test
func terminologyQuickAddBuildsValidatedEntriesAndRejectsIdentityConflicts() throws {
    let now = Date(timeIntervalSince1970: 1_752_364_800)
    let draft = TerminologyQuickAddDraft(
        type: .correction,
        original: " open wisper ",
        replacement: " OpenWhisper ",
        aliases: "OW, ow, Open Whisper"
    )

    let entry = try draft.makeEntry(existing: [], now: now)

    #expect(entry.type == .correction)
    #expect(entry.original == "open wisper")
    #expect(entry.replacement == "OpenWhisper")
    #expect(entry.aliases == ["OW", "Open Whisper"])
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
