import Foundation
import Testing
@testable import OpenWhisper

@Test
func terminologyTextImporterExtractsPlainTextTerms() throws {
    let text = """
    # OpenWhisper terms
    shadowd
    OpenWhisper

    ExampleSDK
    """

    let result = try TerminologyTextImporter().importEntries(
        from: Data(text.utf8),
        sourceName: "terms.txt"
    )

    #expect(result.source == "terms.txt")
    #expect(result.entries.map(\.original) == ["shadowd", "OpenWhisper", "ExampleSDK"])
    #expect(result.entries.allSatisfy { $0.type == .term && $0.isEnabled && $0.source == "terms.txt" })
}

@Test
func terminologyTextImporterExtractsFirstCsvColumnTerms() throws {
    let text = """
    term,notes
    shadowd,daemon name
    OpenWhisper,app
    "OpenAI Compatible",provider
    """

    let result = try TerminologyTextImporter().importEntries(
        from: Data(text.utf8),
        sourceName: "terms.csv"
    )

    #expect(result.entries.map(\.original) == ["shadowd", "OpenWhisper", "OpenAI Compatible"])
}

@Test
func terminologyTextImporterReadsStructuredCorrectionsAndDisabledEntries() throws {
    let text = """
    type,original,replacement,enabled,aliases
    term,OpenWhisper,,true,Open Whisper|OW
    correction,open wisper,OpenWhisper,false,
    correction,missing replacement,,true,
    """

    let result = try TerminologyTextImporter().importEntries(
        from: Data(text.utf8),
        sourceName: "structured.csv"
    )

    #expect(result.entries.count == 2)
    #expect(result.entries[0].type == .term)
    #expect(result.entries[0].aliases == ["Open Whisper", "OW"])
    #expect(result.entries[1].type == .correction)
    #expect(result.entries[1].replacement == "OpenWhisper")
    #expect(!result.entries[1].isEnabled)
}

@Test
func terminologyTextImporterRejectsOversizedFilesAndEntryCounts() {
    #expect(throws: TerminologyTextImportError.fileTooLarge("large.txt")) {
        try TerminologyTextImporter().importEntries(
            from: Data(repeating: 0x61, count: 2_000_001),
            sourceName: "large.txt"
        )
    }

    let rows = (0...10_000).map { "term-\($0)" }.joined(separator: "\n")
    #expect(throws: TerminologyTextImportError.tooManyEntries("many.txt")) {
        try TerminologyTextImporter().importEntries(
            from: Data(rows.utf8),
            sourceName: "many.txt"
        )
    }
}

@Test
func terminologyTextImporterRejectsSymlinkedDictionaryFiles() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("target.txt")
    let link = root.appendingPathComponent("terms.txt")
    try Data("OpenWhisper\n".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    #expect(throws: TerminologyTextImportError.unreadableText("terms.txt")) {
        try TerminologyTextImporter().importEntries(from: link)
    }
}

@Test
func terminologyTextImporterRejectsEmptyDictionary() {
    #expect(throws: TerminologyTextImportError.noValidEntries("empty.txt")) {
        try TerminologyTextImporter().importEntries(
            from: Data("# only comments\n\n".utf8),
            sourceName: "empty.txt"
        )
    }
}
