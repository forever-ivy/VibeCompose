import Foundation
import Testing

@Test
func communityPilotLaunchKitIsPrivacyBoundedAndExecutable() throws {
    let root = communityPilotRepositoryRoot()
    let runbook = try communityPilotText(
        root,
        "docs/product/community-pilot-runbook-2026-07-17.md"
    )
    let launchKit = try communityPilotText(
        root,
        "docs/product/community-pilot-launch-kit-2026-07-18.md"
    )
    let plan = try communityPilotText(
        root,
        "docs/product/community-skills-core-next-step-plan-2026-07-15.md"
    )
    let checkScript = try communityPilotText(
        root,
        "scripts/check.sh"
    )
    let gitignore = try communityPilotText(
        root,
        ".gitignore"
    )

    #expect(
        runbook.contains(
            "community-pilot-launch-kit-2026-07-18.md"
        )
    )
    #expect(launchKit.contains("30–50 target users"))
    #expect(launchKit.contains("at least one participant has explicitly consented"))
    #expect(launchKit.contains("never makes the Registry decision"))
    #expect(plan.contains("Community Skills Roadmap"))
    #expect(plan.contains("ChatGPT browser OAuth"))
    #expect(plan.contains("Community Skill quality"))
    #expect(checkScript.contains("summarize_community_pilot.py"))
    #expect(checkScript.contains("--self-test"))
    #expect(gitignore.contains("/.pilot-data/"))

    let participantHeader = try communityPilotText(
        root,
        "docs/product/community-pilot-participants-template.csv"
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let observationHeader = try communityPilotText(
        root,
        "docs/product/community-pilot-observations-template.csv"
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let incidentHeader = try communityPilotText(
        root,
        "docs/product/community-pilot-incidents-template.csv"
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    #expect(participantHeader.contains("cohort_code"))
    #expect(observationHeader.contains("selection_identity_match"))
    #expect(observationHeader.contains("target_outcome"))
    #expect(incidentHeader.contains("incident_class"))
    for forbidden in [
        "email",
        "transcript",
        "generated_text",
        "selection_text",
        "file_path",
        "window_title",
        "account_id",
        "device_id",
        "notes",
    ] {
        #expect(!participantHeader.contains(forbidden))
        #expect(!observationHeader.contains(forbidden))
        #expect(!incidentHeader.contains(forbidden))
    }

    let scriptURL = root.appendingPathComponent(
        "scripts/summarize_community_pilot.py"
    )
    let selfTest = try runCommunityPilotPython(
        scriptURL,
        arguments: ["--self-test"]
    )
    #expect(selfTest.status == 0)
    #expect(
        selfTest.stdout.contains(
            "Community Pilot summarizer self-test passed."
        )
    )

    let emptyReport = try runCommunityPilotPython(
        scriptURL,
        arguments: [
            "--participants",
            root.appendingPathComponent(
                "docs/product/community-pilot-participants-template.csv"
            ).path,
            "--observations",
            root.appendingPathComponent(
                "docs/product/community-pilot-observations-template.csv"
            ).path,
            "--incidents",
            root.appendingPathComponent(
                "docs/product/community-pilot-incidents-template.csv"
            ).path,
        ]
    )
    #expect(emptyReport.status == 0)
    #expect(emptyReport.stdout.contains("\"status\": \"not_started\""))
    #expect(emptyReport.stdout.contains("\"cohortCodesIncluded\": false"))
}

private func communityPilotRepositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func communityPilotText(
    _ root: URL,
    _ path: String
) throws -> String {
    try String(
        contentsOf: root.appendingPathComponent(path),
        encoding: .utf8
    )
}

private func runCommunityPilotPython(
    _ scriptURL: URL,
    arguments: [String]
) throws -> (
    status: Int32,
    stdout: String,
    stderr: String
) {
    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = URL(
        fileURLWithPath: "/usr/bin/python3"
    )
    process.arguments = [scriptURL.path] + arguments
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()

    return (
        process.terminationStatus,
        String(
            data: stdout.fileHandleForReading
                .readDataToEndOfFile(),
            encoding: .utf8
        ) ?? "",
        String(
            data: stderr.fileHandleForReading
                .readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    )
}
