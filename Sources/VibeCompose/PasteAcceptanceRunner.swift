import AppKit
import ApplicationServices
import Foundation

enum PasteAcceptanceTarget: String, Codable, CaseIterable, Sendable {
    case textEdit = "textedit"
    case terminal

    var applicationName: String {
        switch self {
        case .textEdit:
            return "TextEdit"
        case .terminal:
            return "Terminal"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .textEdit:
            return "com.apple.TextEdit"
        case .terminal:
            return "com.apple.Terminal"
        }
    }
}

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
    let executionProofObserved: Bool
    let clipboardState: String
    let originalClipboardRestored: Bool
    let passed: Bool
    let error: String?
}

enum PasteAcceptanceError: LocalizedError {
    case accessibilityPermissionRequired
    case targetDidNotLaunch(PasteAcceptanceTarget)
    case editableTargetDidNotAppear(PasteAcceptanceTarget)
    case keyEventFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Installed VibeCompose does not currently have Accessibility permission."
        case .targetDidNotLaunch(let target):
            return "\(target.applicationName) did not launch as an isolated acceptance process."
        case .editableTargetDidNotAppear(let target):
            return "The isolated \(target.applicationName) process did not expose a focused editable target."
        case .keyEventFailed:
            return "VibeCompose could not create the Terminal acceptance key event."
        }
    }
}

enum PasteAcceptanceEvaluation {
    static func passed(
        target: PasteAcceptanceTarget,
        outcome: InjectionOutcome,
        expectedTextObserved: Bool,
        executionProofObserved: Bool,
        clipboardState: String,
        originalClipboardRestored: Bool
    ) -> Bool {
        guard originalClipboardRestored else {
            return false
        }

        switch target {
        case .textEdit:
            return outcome == .insertedAndVerified
                && expectedTextObserved
                && clipboardState == "restored"
        case .terminal:
            guard executionProofObserved else {
                return false
            }
            switch outcome {
            case .insertedAndVerified:
                return clipboardState == "restored"
            case .pasteDispatchedClipboardRetained:
                return clipboardState == "transcript_retained"
            case .copiedToClipboard:
                return false
            }
        }
    }
}

@MainActor
enum PasteAcceptanceRunner {
    private struct TargetSession {
        let target: PasteAcceptanceTarget
        let application: NSRunningApplication
        let temporaryFileURL: URL?
        let proofFileURL: URL?
        let isolatedHomeURL: URL?

        func cleanUp() {
            application.forceTerminate()
            if let temporaryFileURL {
                try? FileManager.default.removeItem(at: temporaryFileURL)
            }
            if let proofFileURL {
                try? FileManager.default.removeItem(at: proofFileURL)
            }
            if let isolatedHomeURL {
                try? FileManager.default.removeItem(at: isolatedHomeURL)
            }
        }
    }

    static func run(
        injector: any TextInjecting,
        target: PasteAcceptanceTarget,
        outputURL: URL
    ) async {
        let generatedAt = Date()
        let accessibilityTrusted = AccessibilityPermission.isTrusted()
        let originalClipboard = PasteboardSnapshot.capture(
            from: NSPasteboard.general
        )
        var originalClipboardRestored = false
        var targetSession: TargetSession?
        var focusedRole: String?
        var targetCaptured = false

        defer {
            if !originalClipboardRestored {
                originalClipboard.restore(to: NSPasteboard.general)
            }
            targetSession?.cleanUp()
        }

        do {
            guard accessibilityTrusted else {
                throw PasteAcceptanceError.accessibilityPermissionRequired
            }

            let session = try await launchTarget(target)
            targetSession = session
            session.application.activate(options: [.activateIgnoringOtherApps])

            let launchContext = try await waitForEditableTarget(
                target: target,
                processIdentifier: session.application.processIdentifier
            )
            guard let focusedTarget = launchContext.focusedTarget else {
                throw PasteAcceptanceError.editableTargetDidNotAppear(target)
            }
            focusedRole = focusedTarget.identity.role
            targetCaptured = true

            let marker = "OW_ACCEPTANCE_"
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let injectedText: String
            switch target {
            case .textEdit:
                injectedText = "VibeCompose acceptance \(marker)"
            case .terminal:
                guard let proofFileURL = session.proofFileURL else {
                    throw PasteAcceptanceError.targetDidNotLaunch(target)
                }
                injectedText = [
                    "/usr/bin/printf '%s' ",
                    shellQuote(marker),
                    " > ",
                    shellQuote(proofFileURL.path),
                ].joined()
            }

            let clipboardSentinel = "VibeCompose clipboard sentinel "
                + UUID().uuidString
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                clipboardSentinel,
                forType: .string
            )

            let outcome = try await injector.inject(
                text: injectedText,
                preserveClipboard: true,
                restoreDelayMilliseconds: 100,
                launchAppContext: launchContext,
                automaticPasteAllowed: true,
                automaticPasteFallbackReason:
                    .deliveryRequiresManualPaste,
                expectedSelectionContext:
                    nil
            )

            var executionProofObserved = false
            let pasteWasDispatched: Bool
            switch outcome {
            case .insertedAndVerified,
                 .pasteDispatchedClipboardRetained:
                pasteWasDispatched = true
            case .copiedToClipboard:
                pasteWasDispatched = false
            }
            if target == .terminal,
               pasteWasDispatched,
               FocusedElementInspector.isCurrentTarget(focusedTarget) {
                try await Task.sleep(for: .milliseconds(150))
                guard
                    FocusedElementInspector.isCurrentTarget(focusedTarget),
                    NSWorkspace.shared.frontmostApplication?
                        .processIdentifier
                        == session.application.processIdentifier
                else {
                    throw PasteAcceptanceError.editableTargetDidNotAppear(
                        target
                    )
                }
                try postReturnKey()
                executionProofObserved = try await waitForTerminalProof(
                    at: session.proofFileURL,
                    marker: marker
                )
            }

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
            } else if clipboardValue == injectedText {
                clipboardState = "transcript_retained"
            } else {
                clipboardState = "changed_by_other_owner"
            }

            originalClipboard.restore(to: NSPasteboard.general)
            originalClipboardRestored = originalClipboard.matches(
                NSPasteboard.general
            )

            let passed = PasteAcceptanceEvaluation.passed(
                target: target,
                outcome: outcome,
                expectedTextObserved: expectedTextObserved,
                executionProofObserved: executionProofObserved,
                clipboardState: clipboardState,
                originalClipboardRestored: originalClipboardRestored
            )
            try write(
                PasteAcceptanceEvidence(
                    generatedAt: generatedAt,
                    targetApplication: target.applicationName,
                    targetBundleIdentifier: target.bundleIdentifier,
                    targetProcessIdentifier:
                        session.application.processIdentifier,
                    focusedRole: focusedRole,
                    accessibilityTrusted: accessibilityTrusted,
                    targetCaptured: targetCaptured,
                    resultStatus: outcome.resultStatus,
                    expectedTextObserved: expectedTextObserved,
                    executionProofObserved: executionProofObserved,
                    clipboardState: clipboardState,
                    originalClipboardRestored:
                        originalClipboardRestored,
                    passed: passed,
                    error: passed
                        ? nil
                        : "Installed \(target.applicationName) verification did not reach an accepted paste-or-copy state."
                ),
                to: outputURL
            )
        } catch {
            originalClipboard.restore(to: NSPasteboard.general)
            originalClipboardRestored = originalClipboard.matches(
                NSPasteboard.general
            )
            try? write(
                PasteAcceptanceEvidence(
                    generatedAt: generatedAt,
                    targetApplication: target.applicationName,
                    targetBundleIdentifier: target.bundleIdentifier,
                    targetProcessIdentifier:
                        targetSession?.application.processIdentifier,
                    focusedRole: focusedRole,
                    accessibilityTrusted: accessibilityTrusted,
                    targetCaptured: targetCaptured,
                    resultStatus: TextDeliveryStatus.error,
                    expectedTextObserved: false,
                    executionProofObserved: false,
                    clipboardState: "unknown",
                    originalClipboardRestored:
                        originalClipboardRestored,
                    passed: false,
                    error: error.localizedDescription
                ),
                to: outputURL
            )
        }
    }

    private static func launchTarget(
        _ target: PasteAcceptanceTarget
    ) async throws -> TargetSession {
        let existingProcessIdentifiers = Set(
            NSRunningApplication
                .runningApplications(
                    withBundleIdentifier: target.bundleIdentifier
                )
                .map(\.processIdentifier)
        )

        let temporaryFileURL: URL?
        let proofFileURL: URL?
        let isolatedHomeURL: URL?
        var arguments = ["-F", "-n"]

        switch target {
        case .textEdit:
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "vibecompose-paste-acceptance-"
                        + UUID().uuidString
                        + ".txt"
                )
            try Data().write(to: fileURL, options: [.atomic])
            temporaryFileURL = fileURL
            proofFileURL = nil
            isolatedHomeURL = nil
            arguments += ["-a", target.applicationName, fileURL.path]
        case .terminal:
            let homeURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "vibecompose-terminal-acceptance-"
                        + UUID().uuidString,
                    isDirectory: true
                )
            try FileManager.default.createDirectory(
                at: homeURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let shellStartup = [
                "unsetopt APPEND_HISTORY INC_APPEND_HISTORY",
                "unsetopt INC_APPEND_HISTORY_TIME SHARE_HISTORY",
                "HISTFILE=/dev/null",
                "",
            ].joined(separator: "\n")
            try shellStartup.data(using: .utf8)?.write(
                to: homeURL.appendingPathComponent(".zshrc"),
                options: [.atomic]
            )
            temporaryFileURL = nil
            proofFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "vibecompose-terminal-proof-"
                        + UUID().uuidString
                )
            isolatedHomeURL = homeURL
            arguments += [
                "--env", "HOME=\(homeURL.path)",
                "--env", "ZDOTDIR=\(homeURL.path)",
                "--env", "HISTFILE=/dev/null",
                "--env", "XDG_CONFIG_HOME=\(homeURL.path)",
                "--env", "XDG_DATA_HOME=\(homeURL.path)",
                "-a", target.applicationName,
            ]
        }

        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = arguments
        try openProcess.run()
        openProcess.waitUntilExit()
        guard openProcess.terminationStatus == 0 else {
            if let temporaryFileURL {
                try? FileManager.default.removeItem(at: temporaryFileURL)
            }
            if let isolatedHomeURL {
                try? FileManager.default.removeItem(at: isolatedHomeURL)
            }
            throw PasteAcceptanceError.targetDidNotLaunch(target)
        }

        guard let application = try await waitForIsolatedApplication(
            target: target,
            excluding: existingProcessIdentifiers
        ) else {
            if let temporaryFileURL {
                try? FileManager.default.removeItem(at: temporaryFileURL)
            }
            if let isolatedHomeURL {
                try? FileManager.default.removeItem(at: isolatedHomeURL)
            }
            throw PasteAcceptanceError.targetDidNotLaunch(target)
        }

        return TargetSession(
            target: target,
            application: application,
            temporaryFileURL: temporaryFileURL,
            proofFileURL: proofFileURL,
            isolatedHomeURL: isolatedHomeURL
        )
    }

    private static func waitForIsolatedApplication(
        target: PasteAcceptanceTarget,
        excluding existingProcessIdentifiers: Set<pid_t>
    ) async throws -> NSRunningApplication? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        while clock.now < deadline {
            try Task.checkCancellation()
            if let application = NSRunningApplication
                .runningApplications(
                    withBundleIdentifier: target.bundleIdentifier
                )
                .first(where: {
                    !existingProcessIdentifiers.contains(
                        $0.processIdentifier
                    )
                })
            {
                return application
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private static func waitForEditableTarget(
        target: PasteAcceptanceTarget,
        processIdentifier: pid_t
    ) async throws -> LaunchAppContext {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        while clock.now < deadline {
            try Task.checkCancellation()
            if let context = LaunchAppContext.current(),
               context.processIdentifier == processIdentifier,
               context.bundleIdentifier == target.bundleIdentifier,
               context.focusedTarget != nil {
                return context
            }
            NSRunningApplication(processIdentifier: processIdentifier)?
                .activate(options: [.activateIgnoringOtherApps])
            try await Task.sleep(for: .milliseconds(50))
        }
        throw PasteAcceptanceError.editableTargetDidNotAppear(target)
    }

    private static func waitForTerminalProof(
        at proofFileURL: URL?,
        marker: String
    ) async throws -> Bool {
        guard let proofFileURL else {
            return false
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            try Task.checkCancellation()
            if let data = try? Data(contentsOf: proofFileURL),
               String(decoding: data, as: UTF8.self) == marker {
                return true
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private static func postReturnKey() throws {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 36,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 36,
                keyDown: false
            )
        else {
            throw PasteAcceptanceError.keyEventFailed
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(
            of: "'",
            with: "'\"'\"'"
        ) + "'"
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
        try encoder.encode(evidence).write(
            to: outputURL,
            options: [.atomic]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: outputURL.path
        )
    }
}
