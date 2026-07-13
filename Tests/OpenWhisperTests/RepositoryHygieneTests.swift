import Foundation
import Testing

@Test
func canonicalCheckRunsRepositoryHygieneGate() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let checkScript = try String(
        contentsOf: root.appendingPathComponent("scripts/check.sh"),
        encoding: .utf8
    )
    let verifier = try String(
        contentsOf: root.appendingPathComponent(
            "scripts/verify_repository_hygiene.py"
        ),
        encoding: .utf8
    )

    #expect(checkScript.contains("verify_repository_hygiene.py"))
    #expect(verifier.contains("verify_canonical_identity"))
    #expect(verifier.contains("verify_no_committed_secrets"))
    #expect(verifier.contains("verify_localization"))
    #expect(verifier.contains("verify_markdown_links"))
    #expect(verifier.contains("LEGACY_MARKERS"))
    #expect(verifier.contains("SECRET_PATTERNS"))
    #expect(verifier.contains("LOCALIZATION_CALL_PATTERN"))
    #expect(verifier.contains("MARKDOWN_LINK_PATTERN"))
}
