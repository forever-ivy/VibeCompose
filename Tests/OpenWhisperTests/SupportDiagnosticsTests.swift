import CryptoKit
import Foundation
import Testing
@testable import OpenWhisper

@Test
func supportDiagnosticsExportIsRedactedBoundedAndChecksummed() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(
            "OpenWhisperSupportDiagnosticsTests-\(UUID().uuidString)",
            isDirectory: true
        )
    let applicationSupportURL = root
        .appendingPathComponent("Application Support/OpenWhisper", isDirectory: true)
    let diagnosticReportsURL = root
        .appendingPathComponent("DiagnosticReports", isDirectory: true)
    let exporterTemporaryURL = root
        .appendingPathComponent("ExporterTemporary", isDirectory: true)
    let outputDirectoryURL = root
        .appendingPathComponent("Output", isDirectory: true)
    let extractionURL = root
        .appendingPathComponent("Extracted", isDirectory: true)
    try fileManager.createDirectory(
        at: applicationSupportURL,
        withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
        at: diagnosticReportsURL,
        withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
        at: exporterTemporaryURL,
        withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
        at: outputDirectoryURL,
        withIntermediateDirectories: true
    )
    try fileManager.createDirectory(
        at: extractionURL,
        withIntermediateDirectories: true
    )
    defer {
        try? fileManager.removeItem(at: root)
    }

    let generatedAt = Date(timeIntervalSince1970: 1_783_900_000)
    try LatencyRecorder(directoryURL: applicationSupportURL).record(
        LatencySample(
            timestamp: generatedAt,
            audioDurationMs: 1_500,
            audioBytes: 72_000,
            provider: TranscriptionProvider.chatGPTManagedAuth.rawValue,
            textPolishProvider: TextPolishProviderID.chatGPTAuth.rawValue,
            authMs: 12,
            transcribeMs: 340,
            normalizationMs: 4,
            polishMs: 120,
            textPolishAttempted: true,
            textPolishError: "Bearer secret-token /Users/alice/private-transcript.txt",
            estimatedPolishInputTokens: 300,
            estimatedPolishOutputTokens: 80,
            injectMs: 10,
            totalProcessingMs: 486,
            resultStatus: TextDeliveryStatus.pasteDispatched,
            errorCategory: nil
        ),
        retention: DiagnosticsRetentionPolicy(
            maxRecords: 10,
            retentionDays: 14,
            now: generatedAt
        )
    )

    try Data("PRIVATE HISTORY BODY".utf8).write(
        to: applicationSupportURL
            .appendingPathComponent("transcription-history.jsonl")
    )
    try Data("PRIVATE CONFIG BODY".utf8).write(
        to: applicationSupportURL.appendingPathComponent("config.json")
    )
    let recoveryURL = applicationSupportURL
        .appendingPathComponent("Recovery/Audio", isDirectory: true)
    try fileManager.createDirectory(
        at: recoveryURL,
        withIntermediateDirectories: true
    )
    try Data("PRIVATE AUDIO BODY".utf8).write(
        to: recoveryURL.appendingPathComponent("private.wav")
    )

    let crashHeader: [String: Any] = [
        "app_name": "OpenWhisper",
        "app_version": "0.1.0",
        "build_version": "1",
        "bundleID": "app.openwhisper.mac",
        "bug_type": "309",
        "os_version": [
            "build": "25F90",
            "secret": "PRIVATE CRASH HEADER",
        ],
        "user_email": "private@example.com",
        "authorization": "Bearer crash-secret",
    ]
    let crashHeaderData = try JSONSerialization.data(withJSONObject: crashHeader)
    var crashData = crashHeaderData
    crashData.append(0x0A)
    crashData.append(Data("PRIVATE CRASH BODY".utf8))
    try crashData.write(
        to: diagnosticReportsURL
            .appendingPathComponent("OpenWhisper-2026-07-13.ips")
    )

    let outsideCrashURL = root.appendingPathComponent("outside-secret.ips")
    try Data("PRIVATE SYMLINK TARGET".utf8).write(to: outsideCrashURL)
    try fileManager.createSymbolicLink(
        at: diagnosticReportsURL
            .appendingPathComponent("OpenWhisper-symlink.ips"),
        withDestinationURL: outsideCrashURL
    )

    var config = AppConfig()
    config.transcription.provider = .openAICompatible
    config.transcription.openAITranscriptionURL =
        "https://secret.example.invalid/private"
    config.transcription.hintTerms = ["PRIVATE TERMINOLOGY"]
    config.transcription.terminology.entries = [
        TerminologyEntry(
            canonical: "PRIVATE CANONICAL",
            aliases: ["PRIVATE ALIAS"]
        ),
    ]
    config.privacy.additionalSensitiveAppBundleIdentifiers = [
        "com.private.secret",
    ]

    let exporter = SupportDiagnosticsExporter(
        applicationSupportURL: applicationSupportURL,
        diagnosticReportsURL: diagnosticReportsURL,
        temporaryDirectoryURL: exporterTemporaryURL,
        environment: SupportDiagnosticsEnvironment(
            generatedAt: generatedAt,
            productVersion: "0.1.0",
            productBuild: "1",
            bundleIdentifier: "app.openwhisper.mac",
            operatingSystem: "macOS 26.5",
            architecture: "arm64",
            localeIdentifier: "zh_CN",
            installedInApplications: true
        )
    )

    let archiveURL = try exporter.export(
        to: outputDirectoryURL.appendingPathComponent("diagnostics"),
        config: config,
        authSnapshot: ChatGPTAuthSnapshot(
            state: .ready,
            detail: "PRIVATE AUTH DETAIL",
            userEmail: "private@example.com"
        ),
        permissionSnapshot: PermissionStatusSnapshot(
            microphone: .granted,
            accessibilityTrusted: true
        ),
        signatureState: .stable(teamIdentifier: "PRIVATE_TEAM_ID")
    )

    #expect(archiveURL.pathExtension == "zip")
    #expect(fileManager.fileExists(atPath: archiveURL.path))
    let archiveAttributes = try fileManager.attributesOfItem(
        atPath: archiveURL.path
    )
    #expect(
        (archiveAttributes[.posixPermissions] as? NSNumber)?.intValue
            == 0o600
    )

    try extractZip(archiveURL, to: extractionURL)
    let bundleURL = extractionURL
        .appendingPathComponent("OpenWhisper-Support", isDirectory: true)
    let exportedNames = Set(
        try fileManager.contentsOfDirectory(atPath: bundleURL.path)
    )
    #expect(
        exportedNames
            == [
                "README.txt",
                "summary.json",
                "latency.jsonl",
                "crash-summary.json",
                "SHA256SUMS",
            ]
    )

    var exportedText = ""
    for name in exportedNames.sorted() {
        exportedText += String(
            data: try Data(
                contentsOf: bundleURL.appendingPathComponent(name)
            ),
            encoding: .utf8
        ) ?? ""
    }

    for forbidden in [
        "secret-token",
        "/Users/alice",
        "PRIVATE HISTORY BODY",
        "PRIVATE CONFIG BODY",
        "PRIVATE AUDIO BODY",
        "PRIVATE CRASH HEADER",
        "PRIVATE CRASH BODY",
        "PRIVATE SYMLINK TARGET",
        "private@example.com",
        "crash-secret",
        "secret.example.invalid",
        "PRIVATE_API_KEY",
        "PRIVATE TERMINOLOGY",
        "PRIVATE CANONICAL",
        "PRIVATE ALIAS",
        "com.private.secret",
        "PRIVATE AUTH DETAIL",
        "PRIVATE_TEAM_ID",
    ] {
        #expect(!exportedText.contains(forbidden))
    }

    #expect(exportedText.contains("\"authenticationState\" : \"ready\""))
    #expect(exportedText.contains("\"signatureState\" : \"stableTeamIdentity\""))
    #expect(exportedText.contains("\"resultStatus\":\"paste_dispatched\""))
    #expect(exportedText.contains("\"textPolishErrorPresent\":true"))
    #expect(exportedText.contains("\"crashSummaryCount\" : 1"))
    #expect(exportedText.contains("\"buildVersion\" : \"1\""))
    #expect(exportedText.contains("\"operatingSystemBuild\" : \"25F90\""))

    try verifyChecksums(in: bundleURL)
    #expect(
        (try fileManager.contentsOfDirectory(
            at: exporterTemporaryURL,
            includingPropertiesForKeys: nil
        )).isEmpty
    )
}

@Test
func supportDiagnosticsRefusesToReplaceDirectoryDestination() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let destinationURL = root
        .appendingPathComponent("Existing.zip", isDirectory: true)
    try fileManager.createDirectory(
        at: destinationURL,
        withIntermediateDirectories: true
    )
    defer {
        try? fileManager.removeItem(at: root)
    }

    let exporter = SupportDiagnosticsExporter(
        applicationSupportURL: root.appendingPathComponent("Support"),
        diagnosticReportsURL: root.appendingPathComponent("Crashes"),
        temporaryDirectoryURL: root,
        environment: SupportDiagnosticsEnvironment(
            generatedAt: Date(timeIntervalSince1970: 0),
            productVersion: "0.1.0",
            productBuild: "1",
            bundleIdentifier: "app.openwhisper.mac",
            operatingSystem: "macOS",
            architecture: "arm64",
            localeIdentifier: "en_US",
            installedInApplications: false
        )
    )

    #expect(
        throws: SupportDiagnosticsExportError.destinationIsDirectory(
            "Existing.zip"
        )
    ) {
        _ = try exporter.export(
            to: destinationURL,
            config: AppConfig(),
            authSnapshot: ChatGPTAuthSnapshot(
                state: .signedOut,
                detail: "",
                userEmail: nil
            ),
            permissionSnapshot: PermissionStatusSnapshot(
                microphone: .undetermined,
                accessibilityTrusted: false
            ),
            signatureState: .adHocOrUnsigned
        )
    }
}

private func extractZip(_ archiveURL: URL, to destinationURL: URL) throws {
    let process = Process()
    let stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = [
        "-x",
        "-k",
        archiveURL.path,
        destinationURL.path,
    ]
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let message = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        throw NSError(
            domain: "OpenWhisper.SupportDiagnosticsTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

private func verifyChecksums(in bundleURL: URL) throws {
    let manifest = try String(
        contentsOf: bundleURL.appendingPathComponent("SHA256SUMS"),
        encoding: .utf8
    )
    for line in manifest.split(separator: "\n") {
        let expected = String(line.prefix(64))
        let name = String(line.dropFirst(64))
            .trimmingCharacters(in: .whitespaces)
        _ = try #require(expected.count == 64 && !name.isEmpty)
        let data = try Data(contentsOf: bundleURL.appendingPathComponent(name))
        let actual = SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }
        .joined()
        #expect(actual == expected)
    }
}
