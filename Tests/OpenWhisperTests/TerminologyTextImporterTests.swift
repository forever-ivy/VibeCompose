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
func terminologyTextImporterRejectsEmptyDictionary() {
    #expect(throws: TerminologyTextImportError.noValidEntries("empty.txt")) {
        try TerminologyTextImporter().importEntries(
            from: Data("# only comments\n\n".utf8),
            sourceName: "empty.txt"
        )
    }
}
