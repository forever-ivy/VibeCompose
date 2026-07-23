import AppKit
import ApplicationServices
import Carbon
import Foundation
import OSLog

/// Read-only fallback for hosts whose document surface is completely opaque to
/// macOS Accessibility (notably current WeChat builds).
///
/// This runs only after ContextBroker policy and permission checks. It sends the
/// host's ordinary Copy command, reads plain text, and restores the full prior
/// pasteboard snapshot before returning.
enum ClipboardSelectionContextCapture {
    private static let logger = Logger(
        subsystem:
            Bundle.main.bundleIdentifier
                ?? ProductIdentity.defaultBundleIdentifier,
        category: "ClipboardSelectionContext"
    )
    private static let copyTimeoutMilliseconds = 400
    private static let pollMilliseconds = 20

    @MainActor
    static func capture(
        in launchAppContext:
            LaunchAppContext?,
        maximumCharacters: Int
    ) async -> SelectionContextCaptureResult {
        guard
            AXIsProcessTrusted(),
            let launchAppContext,
            launchAppContext.processIdentifier > 0,
            let application = NSRunningApplication(
                processIdentifier:
                    launchAppContext.processIdentifier
            ),
            !application.isTerminated,
            application.bundleIdentifier
                == launchAppContext.bundleIdentifier,
            launchAppContext.processLaunchDate == nil
                || application.launchDate
                    == launchAppContext.processLaunchDate,
            NSWorkspace.shared.frontmostApplication?
                .processIdentifier
                == launchAppContext.processIdentifier
        else {
            return .unavailable
        }

        let pasteboard = NSPasteboard.general
        let priorClipboard =
            PasteboardSnapshot.capture(
                from: pasteboard
            )
        let initialChangeCount =
            pasteboard.changeCount

        guard postCopyCommand() else {
            return .unavailable
        }

        var copiedText: String?
        let attempts =
            copyTimeoutMilliseconds
            / pollMilliseconds
        for _ in 0..<attempts {
            try? await Task.sleep(
                for: .milliseconds(
                    pollMilliseconds
                )
            )
            guard
                pasteboard.changeCount
                    != initialChangeCount
            else {
                continue
            }
            copiedText = pasteboard.string(
                forType: .string
            )
            break
        }

        // Restore all previous pasteboard item types, not just plain text.
        priorClipboard.restore(to: pasteboard)

        guard
            let copiedText,
            !copiedText.isEmpty
        else {
            logger.info(
                "Copy fallback found no plain-text selection"
            )
            return .noSelection
        }

        let boundedMaximum =
            FocusedElementInspector
                .boundedSelectionMaximum(
                    maximumCharacters
                )
        guard copiedText.count <= boundedMaximum else {
            return .tooLarge(
                actual: copiedText.count,
                maximum: boundedMaximum
            )
        }

        let target =
            launchAppContext.focusedTarget
            ?? applicationTarget(
                processIdentifier:
                    launchAppContext
                        .processIdentifier
            )
        logger.info(
            "Copy fallback captured selectedCharacters=\(copiedText.count, privacy: .public)"
        )
        return .captured(
            SelectionContextSnapshot(
                target: target,
                selectedRange:
                    CFRange(
                        location: -1,
                        length:
                            (copiedText as NSString)
                                .length
                    ),
                selectedText: copiedText,
                textDigest:
                    SelectionContextSnapshot
                        .digest(for: copiedText)
            )
        )
    }

    private static func postCopyCommand()
        -> Bool
    {
        guard
            let source = CGEventSource(
                stateID: .hidSystemState
            ),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey:
                    CGKeyCode(kVK_ANSI_C),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey:
                    CGKeyCode(kVK_ANSI_C),
                keyDown: false
            )
        else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func applicationTarget(
        processIdentifier: pid_t
    ) -> FocusedAXElementReference {
        let element =
            AXUIElementCreateApplication(
                processIdentifier
            )
        return FocusedAXElementReference(
            processIdentifier:
                processIdentifier,
            element: element,
            window: nil,
            identity:
                FocusedTargetIdentity(
                    elementHash:
                        UInt64(CFHash(element)),
                    role:
                        kAXApplicationRole
                            as String,
                    subrole: nil,
                    identifier: nil,
                    windowHash: nil
                )
        )
    }
}
