import AppKit
import Foundation

struct PasteAcceptanceEvidence: Codable, Sendable, Equatable {
    let generatedAt: Date
    let targetApplication: String
    let targetBundleIdentifier: String
    let targetProcessIdentifier: Int32?
    let focusedRole: String?
    let accessibilityTrusted: Bool
    let targetCaptured: Bool
    let resultStatus: String
    let expectedTextObserved: Bool
    let clipboardState: String
    let passed: Bool
    let error: String?
}

enum PasteAcceptanceError: LocalizedError {
    case accessibilityPermissionRequired
    case textEditDidNotLaunchAsIsolatedProcess
    case editableTargetDidNotAppear

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Installed OpenWhisper does not currently have Accessibility permission."
        case .textEditDidNotLaunchAsIsolatedProcess:
            return "TextEdit did not launch as an isolated acceptance process."
        case .editableTargetDidNotAppear:
            return "The isolated TextEdit process did not expose a focused editable target."
        }
    }
}

@MainActor
enum PasteAcceptanceRunner {
    private static let textEditBundleIdentifier = "com.apple.TextEdit"

    static func run(
        injector: any TextInjecting,
        outputURL: URL
    ) async {
        let generatedAt = Date()
        let accessibilityTrusted = AccessibilityPermission.isTrusted()
        var isolatedTextEdit: NSRunningApplication?
        var temporaryFileURL: URL?
        var focusedRole: String?
        var targetCaptured = false

        defer {
            isolatedTextEdit?.forceTerminate()
            if let temporaryFileURL {
                try? FileManager.default.removeItem(at: temporaryFileURL)
            }
        }

        do {
            guard accessibilityTrusted else {
                throw PasteAcceptanceError.accessibilityPermissionRequired
            }

            let existingProcessIdentifiers = Set(
                NSRunningApplication
                    .runningApplications(withBundleIdentifier: textEditBundleIdentifier)
                    .map(\.processIdentifier)
            )
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "openwhisper-paste-acceptance-\(UUID().uuidString).txt"
                )
            temporaryFileURL = fileURL
            try Data().write(to: fileURL, options: [.atomic])

            let openProcess = Process()
            openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            openProcess.arguments = ["-n", "-a", "TextEdit", fileURL.path]
            try openProcess.run()
            openProcess.waitUntilExit()
            guard openProcess.terminationStatus == 0 else {
                throw PasteAcceptanceError.textEditDidNotLaunchAsIsolatedProcess
            }

            isolatedTextEdit = try await waitForIsolatedTextEdit(
                excluding: existingProcessIdentifiers
            )
            guard let isolatedTextEdit else {
                throw PasteAcceptanceError.textEditDidNotLaunchAsIsolatedProcess
            }
            isolatedTextEdit.activate(options: [.activateIgnoringOtherApps])

            let launchContext = try await waitForEditableTarget(
                processIdentifier: isolatedTextEdit.processIdentifier
            )
            guard let focusedTarget = launchContext.focusedTarget else {
                throw PasteAcceptanceError.editableTargetDidNotAppear
            }
            focusedRole = focusedTarget.identity.role
            targetCaptured = true

            let marker = "OpenWhisper acceptance \(UUID().uuidString)"
            let clipboardSentinel = "OpenWhisper clipboard sentinel \(UUID().uuidString)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clipboardSentinel, forType: .string)

            let outcome = try await injector.inject(
                text: marker,
                preserveClipboard: true,
                restoreDelayMilliseconds: 100,
                launchAppContext: launchContext,
                automaticPasteAllowed: true
            )
            try await Task.sleep(for: .milliseconds(300))

            let expectedTextObserved: Bool
            switch FocusedElementInspector.captureEditableTextSnapshot(
                matching: focusedTarget
            ) {
            case .captured(let snapshot):
                expectedTextObserved = snapshot.value.contains(marker)
            case .unavailable, .targetChanged:
                expectedTextObserved = false
            }

            let clipboardValue = NSPasteboard.general.string(forType: .string)
            let clipboardState: String
            if clipboardValue == clipboardSentinel {
                clipboardState = "restored"
            } else if clipboardValue == marker {
                clipboardState = "transcript_retained"
            } else {
                clipboardState = "changed_by_other_owner"
            }

            let passed = outcome == .insertedAndVerified &&
                expectedTextObserved &&
                clipboardState == "restored"
            try write(
                PasteAcceptanceEvidence(
                    generatedAt: generatedAt,
                    targetApplication: "TextEdit",
                    targetBundleIdentifier: textEditBundleIdentifier,
                    targetProcessIdentifier: isolatedTextEdit.processIdentifier,
                    focusedRole: focusedRole,
                    accessibilityTrusted: accessibilityTrusted,
                    targetCaptured: targetCaptured,
                    resultStatus: outcome.resultStatus,
                    expectedTextObserved: expectedTextObserved,
                    clipboardState: clipboardState,
                    passed: passed,
                    error: passed ? nil : "Installed TextEdit verification did not reach the expected verified-insertion state."
                ),
                to: outputURL
            )
        } catch {
            try? write(
                PasteAcceptanceEvidence(
                    generatedAt: generatedAt,
                    targetApplication: "TextEdit",
                    targetBundleIdentifier: textEditBundleIdentifier,
                    targetProcessIdentifier: isolatedTextEdit?.processIdentifier,
                    focusedRole: focusedRole,
                    accessibilityTrusted: accessibilityTrusted,
                    targetCaptured: targetCaptured,
                    resultStatus: TextDeliveryStatus.error,
                    expectedTextObserved: false,
                    clipboardState: "unknown",
                    passed: false,
                    error: error.localizedDescription
                ),
                to: outputURL
            )
        }
    }

    private static func waitForIsolatedTextEdit(
        excluding existingProcessIdentifiers: Set<pid_t>
    ) async throws -> NSRunningApplication? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            try Task.checkCancellation()
            if let application = NSRunningApplication
                .runningApplications(withBundleIdentifier: textEditBundleIdentifier)
                .first(where: {
                    !existingProcessIdentifiers.contains($0.processIdentifier)
                })
            {
                return application
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private static func waitForEditableTarget(
        processIdentifier: pid_t
    ) async throws -> LaunchAppContext {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline {
            try Task.checkCancellation()
            if let context = LaunchAppContext.current(),
               context.processIdentifier == processIdentifier,
               context.bundleIdentifier == textEditBundleIdentifier,
               context.focusedTarget != nil {
                return context
            }
            NSRunningApplication(processIdentifier: processIdentifier)?
                .activate(options: [.activateIgnoringOtherApps])
            try await Task.sleep(for: .milliseconds(50))
        }
        throw PasteAcceptanceError.editableTargetDidNotAppear
    }

    private static func write(
        _ evidence: PasteAcceptanceEvidence,
        to outputURL: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evidence).write(to: outputURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: outputURL.path
        )
    }
}
