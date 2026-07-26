import AppKit
import ApplicationServices
import Foundation
import OSLog

struct EditableTextSnapshot: Sendable, Equatable {
    let value: String
    let selectedRange: CFRange

    static func == (lhs: EditableTextSnapshot, rhs: EditableTextSnapshot) -> Bool {
        lhs.value == rhs.value &&
            lhs.selectedRange.location == rhs.selectedRange.location &&
            lhs.selectedRange.length == rhs.selectedRange.length
    }
}

enum TextInsertionPlan: Sendable, Equatable {
    case keyPressPaste
    case clipboardFallback(reason: ClipboardFallbackReason)
}

struct LaunchAppContext: Sendable, Equatable {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t
    let processLaunchDate: Date?
    let focusedTarget: FocusedAXElementReference?

    init(
        bundleIdentifier: String?,
        localizedName: String?,
        processIdentifier: pid_t,
        processLaunchDate: Date? = nil,
        focusedTarget: FocusedAXElementReference? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
        self.processLaunchDate = processLaunchDate
        self.focusedTarget = focusedTarget
    }

    static func == (lhs: LaunchAppContext, rhs: LaunchAppContext) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
            lhs.localizedName == rhs.localizedName &&
            lhs.processIdentifier == rhs.processIdentifier &&
            lhs.processLaunchDate == rhs.processLaunchDate &&
            lhs.focusedTarget?.identity == rhs.focusedTarget?.identity
    }

    @MainActor
    static func current() -> LaunchAppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        return LaunchAppContext(
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName,
            processIdentifier: app.processIdentifier,
            processLaunchDate: app.launchDate,
            focusedTarget: FocusedElementInspector.captureTarget(in: app.processIdentifier)
        )
    }

    /// Capture the process that should own focus again after a transient
    /// VibeCompose panel (Skill Switcher, Result Preview) closes.
    ///
    /// When another app is frontmost, that app is returned. When VibeCompose is
    /// already frontmost, returns `nil` so dismiss does not re-activate us and
    /// accidentally promote a background Settings window over the host.
    @MainActor
    static func externalFrontmostForTransientRestore() -> LaunchAppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let selfBundle = Bundle.main.bundleIdentifier
        if let selfBundle,
           app.bundleIdentifier == selfBundle
        {
            return nil
        }
        return LaunchAppContext(
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName,
            processIdentifier: app.processIdentifier,
            processLaunchDate: app.launchDate,
            focusedTarget: nil
        )
    }

    /// Bring the launch-app process back to the front before AX selection reads
    /// or paste. Permission alerts and mic prompts may have fronted VibeCompose;
    /// without this, some hosts clear selection or refuse AXSelectedText while
    /// backgrounded. No-op when already frontmost or context is missing.
    ///
    /// Also used after Skill Switcher / Result Preview dismiss so AppKit does not
    /// fall through to a still-open Settings window as the new key window.
    ///
    /// - Returns: `true` when an activate was issued (caller may want a short
    ///   settle delay before reading AX).
    @MainActor
    @discardableResult
    static func restoreFrontmostIfNeeded(
        _ context: LaunchAppContext?
    ) -> Bool {
        guard
            let context,
            context.processIdentifier > 0,
            let currentFrontmost = NSWorkspace.shared.frontmostApplication,
            currentFrontmost.processIdentifier != context.processIdentifier,
            let app = NSRunningApplication(
                processIdentifier: context.processIdentifier
            )
        else {
            return false
        }
        // Never "restore" into ourselves — that re-keys whatever VW window is
        // still ordered (often Settings) after a transient panel closes.
        if let selfBundle = Bundle.main.bundleIdentifier,
           context.bundleIdentifier == selfBundle
        {
            return false
        }
        app.activate(options: [.activateIgnoringOtherApps])
        return true
    }
}

enum InjectionError: LocalizedError {
    case keyEventFailed

    var errorDescription: String? {
        switch self {
        case .keyEventFailed:
            return L10n.text("Could not create the Cmd+V event.")
        }
    }
}

enum ClipboardFallbackReason: Sendable, Equatable {
    case accessibilityPermissionRequired
    case noEditableTarget
    case retryRequiresManualPaste
    case deliveryRequiresManualPaste
    case selectionChanged

    var statusDetail: String {
        switch self {
        case .accessibilityPermissionRequired:
            return L10n.text("Copied to clipboard. Grant Accessibility access for auto-paste.")
        case .noEditableTarget:
            return L10n.text("Copied to clipboard")
        case .retryRequiresManualPaste:
            return L10n.text("Retry completed and was copied to the clipboard.")
        case .deliveryRequiresManualPaste:
            return L10n.text("Copied after preview.")
        case .selectionChanged:
            return L10n.text("Copied — selection changed")
        }
    }

    var overlaySubtitle: String {
        switch self {
        case .accessibilityPermissionRequired:
            return L10n.text("Accessibility permission is off, so VibeCompose left the text in the clipboard.")
        case .noEditableTarget:
            return L10n.text("No editable cursor was found. Paste manually.")
        case .retryRequiresManualPaste:
            return L10n.text("For safety, retry results are copied instead of pasted automatically.")
        case .deliveryRequiresManualPaste:
            return L10n.text("The result was copied for manual paste.")
        case .selectionChanged:
            return L10n.text("The original selection changed, so VibeCompose did not replace it.")
        }
    }
}

enum InjectionOutcome: Sendable, Equatable {
    case insertedAndVerified
    case pasteDispatchedClipboardRetained
    case copiedToClipboard(reason: ClipboardFallbackReason)

    var resultStatus: String {
        switch self {
        case .insertedAndVerified:
            return TextDeliveryStatus.insertedAndVerified
        case .pasteDispatchedClipboardRetained:
            return TextDeliveryStatus.pasteDispatched
        case .copiedToClipboard:
            return TextDeliveryStatus.clipboard
        }
    }
}

enum PasteVerificationResult: Sendable, Equatable {
    case verified
    case unavailable
    case notObserved
    case targetChanged
}

enum SafeUndoFailureReason: String, Sendable, Equatable {
    case unavailable
    case targetChanged
    case textChanged
    case restoreFailed
}

enum SafeUndoOutcome: Sendable, Equatable {
    case restored
    case copiedOriginal(reason: SafeUndoFailureReason)
    case unavailable

    var statusDetail: String {
        switch self {
        case .restored:
            return L10n.text("Last verified insertion was undone.")
        case .copiedOriginal(let reason):
            return L10n.format(
                "VibeCompose could not safely undo because %@. The original selected text was copied instead.",
                reason.localizedLabel
            )
        case .unavailable:
            return L10n.text(
                "Safe Undo is unavailable because VibeCompose cannot verify the last inserted result."
            )
        }
    }
}

private extension SafeUndoFailureReason {
    var localizedLabel: String {
        switch self {
        case .unavailable:
            return L10n.text("the target cannot be inspected")
        case .targetChanged:
            return L10n.text("the focused target changed")
        case .textChanged:
            return L10n.text("the target text changed")
        case .restoreFailed:
            return L10n.text("the target rejected the exact restore")
        }
    }
}

enum SafeUndoVerifier {
    static func canRestore(
        expectedAfter: EditableTextSnapshot,
        current: EditableTextSnapshot?,
        targetStillMatches: Bool
    ) -> Bool {
        guard targetStillMatches, let current else {
            return false
        }
        // Cursor movement alone is harmless. Any text change makes automatic
        // reversal unsafe, even when the inserted substring still appears.
        return current.value == expectedAfter.value
    }
}

enum PasteTransitionVerifier {
    nonisolated static func result(
        before: EditableTextSnapshot?,
        after: EditableTextSnapshot?,
        insertedText: String,
        targetStillMatches: Bool
    ) -> PasteVerificationResult {
        guard targetStillMatches else {
            return .targetChanged
        }
        guard
            let before,
            let after,
            let expected = expectedSnapshot(
                before: before,
                insertedText: insertedText
            )
        else {
            return .unavailable
        }
        guard after.value == expected.value else {
            return .notObserved
        }

        let valueChanged = before.value != after.value
        let selectionChanged = before.selectedRange.location != after.selectedRange.location ||
            before.selectedRange.length != after.selectedRange.length
        guard valueChanged || selectionChanged else {
            return .notObserved
        }

        if valueChanged {
            return .verified
        }

        return after.selectedRange.location == expected.selectedRange.location &&
            after.selectedRange.length == expected.selectedRange.length
            ? .verified
            : .notObserved
    }

    nonisolated static func expectedSnapshot(
        before: EditableTextSnapshot,
        insertedText: String
    ) -> EditableTextSnapshot? {
        let source = before.value as NSString
        let selectedRange = before.selectedRange
        guard
            selectedRange.location >= 0,
            selectedRange.length >= 0,
            selectedRange.location <= source.length,
            selectedRange.length <= source.length - selectedRange.location
        else {
            return nil
        }

        let replacementRange = NSRange(
            location: selectedRange.location,
            length: selectedRange.length
        )
        let expectedValue = source.replacingCharacters(
            in: replacementRange,
            with: insertedText
        )
        let expectedSelection = CFRange(
            location: selectedRange.location + (insertedText as NSString).length,
            length: 0
        )
        return EditableTextSnapshot(
            value: expectedValue,
            selectedRange: expectedSelection
        )
    }
}

struct AsyncPasteTargetWaiter: Sendable {
    var timeout: Duration = .seconds(1)
    var pollInterval: Duration = .milliseconds(25)

    func wait(
        isReady: @escaping @MainActor @Sendable () -> Bool,
        reactivate: @escaping @MainActor @Sendable () -> Void
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            try Task.checkCancellation()
            if await isReady() {
                return true
            }
            await reactivate()
            try await Task.sleep(for: pollInterval)
        }

        try Task.checkCancellation()
        return await isReady()
    }
}

struct AsyncPasteVerificationWaiter: Sendable {
    var timeout: Duration = .milliseconds(500)
    var pollInterval: Duration = .milliseconds(25)

    func wait(
        check: @escaping @MainActor @Sendable () -> PasteVerificationResult
    ) async throws -> PasteVerificationResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            try Task.checkCancellation()
            let result = await check()
            switch result {
            case .verified, .unavailable, .targetChanged:
                return result
            case .notObserved:
                try await Task.sleep(for: pollInterval)
            }
        }

        try Task.checkCancellation()
        return await check()
    }
}

@MainActor
protocol TextInjecting: AnyObject {
    func inject(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?,
        automaticPasteAllowed: Bool,
        automaticPasteFallbackReason:
            ClipboardFallbackReason,
        expectedSelectionContext:
            SelectionContextSnapshot?
    ) async throws -> InjectionOutcome

    var hasUndoableVerifiedInsertion: Bool { get }

    func undoLastVerifiedInsertion() async -> SafeUndoOutcome
}

extension TextInjecting {
    var hasUndoableVerifiedInsertion: Bool { false }

    func undoLastVerifiedInsertion() async -> SafeUndoOutcome {
        .unavailable
    }
}

@MainActor
final class TextInjector: TextInjecting {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? ProductIdentity.defaultBundleIdentifier,
        category: "TextInjector"
    )
    private var clipboardRestoreTask: Task<Void, Never>?
    private let pasteTargetWaiter: AsyncPasteTargetWaiter
    private let pasteVerificationWaiter: AsyncPasteVerificationWaiter
    private var undoTransaction: VerifiedInsertionUndoTransaction?

    private struct VerifiedInsertionUndoTransaction {
        let target: FocusedAXElementReference
        let before: EditableTextSnapshot
        let expectedAfter: EditableTextSnapshot
        let originalSelectedText: String
        let launchAppContext: LaunchAppContext?
    }

    var hasUndoableVerifiedInsertion: Bool {
        undoTransaction != nil
    }

    init(
        pasteTargetWaiter: AsyncPasteTargetWaiter = .init(),
        pasteVerificationWaiter: AsyncPasteVerificationWaiter = .init()
    ) {
        self.pasteTargetWaiter = pasteTargetWaiter
        self.pasteVerificationWaiter = pasteVerificationWaiter
    }

    nonisolated static func injectionOutcome(
        hasEditableTextFocus: Bool,
        accessibilityTrusted: Bool
    ) -> InjectionOutcome {
        guard accessibilityTrusted else {
            return .copiedToClipboard(reason: .accessibilityPermissionRequired)
        }
        guard hasEditableTextFocus else {
            return .copiedToClipboard(reason: .noEditableTarget)
        }
        return .pasteDispatchedClipboardRetained
    }

    nonisolated static func injectionPlan(
        text _: String,
        accessibilityTrusted: Bool,
        editableTextSnapshot _: EditableTextSnapshot?,
        fallbackEditableTextSnapshot _: EditableTextSnapshot?,
        hasEditableTextFocus: Bool,
        hasFallbackEditableTextFocus: Bool,
        hasLaunchAppContext _: Bool = false,
        allowsSameAppBestEffortPaste: Bool = false,
        automaticPasteAllowed: Bool = true,
        automaticPasteFallbackReason:
            ClipboardFallbackReason =
                .retryRequiresManualPaste
    ) -> TextInsertionPlan {
        guard automaticPasteAllowed else {
            return .clipboardFallback(
                reason:
                    automaticPasteFallbackReason
            )
        }
        guard accessibilityTrusted else {
            return .clipboardFallback(reason: .accessibilityPermissionRequired)
        }

        if hasEditableTextFocus || hasFallbackEditableTextFocus {
            return .keyPressPaste
        }

        // AX-opaque hosts (WeChat composers, some Electron shells) often expose
        // no focused editable element at all. When dictation started against
        // that process, allow a same-app Cmd+V attempt after reactivation.
        // Identity is re-checked by process/bundle/launchDate before dispatch;
        // the outcome stays paste_dispatched (never verified) because AX cannot
        // prove the insertion.
        if allowsSameAppBestEffortPaste {
            return .keyPressPaste
        }

        return .clipboardFallback(reason: .noEditableTarget)
    }

    /// Best-effort paste is only for launch contexts that never captured an AX
    /// editor. A captured target must still match that exact element.
    nonisolated static func allowsSameAppBestEffortPaste(
        launchAppContext: LaunchAppContext?
    ) -> Bool {
        guard let launchAppContext else {
            return false
        }
        return launchAppContext.focusedTarget == nil
            && launchAppContext.processIdentifier > 0
    }

    nonisolated static func selectionFallbackReason(
        verification:
            SelectionContextVerification
    ) -> ClipboardFallbackReason? {
        verification == .unchanged
            ? nil
            : .selectionChanged
    }

    func inject(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?,
        automaticPasteAllowed: Bool,
        automaticPasteFallbackReason:
            ClipboardFallbackReason,
        expectedSelectionContext:
            SelectionContextSnapshot?
    ) async throws -> InjectionOutcome {
        try Task.checkCancellation()
        clipboardRestoreTask?.cancel()
        clipboardRestoreTask = nil
        undoTransaction = nil

        let accessibilityTrusted = AccessibilityPermission.isTrusted()
        if !accessibilityTrusted {
            AccessibilityPermission.requestTrustIfNeeded()
        }

        let hasCurrentEditableTextFocus = accessibilityTrusted && FocusedElementInspector.hasEditableTextFocus()
        let hasMatchingLaunchTarget = accessibilityTrusted &&
            FocusedElementInspector.hasEditableTextFocus(in: launchAppContext)
        let allowsSameAppBestEffortPaste = accessibilityTrusted &&
            Self.allowsSameAppBestEffortPaste(launchAppContext: launchAppContext)
        let plan = Self.injectionPlan(
            text: text,
            accessibilityTrusted: accessibilityTrusted,
            editableTextSnapshot: nil,
            fallbackEditableTextSnapshot: nil,
            hasEditableTextFocus: launchAppContext == nil && hasCurrentEditableTextFocus,
            hasFallbackEditableTextFocus: hasMatchingLaunchTarget,
            hasLaunchAppContext: launchAppContext != nil,
            allowsSameAppBestEffortPaste: allowsSameAppBestEffortPaste,
            automaticPasteAllowed: automaticPasteAllowed,
            automaticPasteFallbackReason:
                automaticPasteFallbackReason
        )

        logger.info(
            "Injection plan resolved to \(String(describing: plan), privacy: .public); currentEditableFocus=\(hasCurrentEditableTextFocus, privacy: .public); matchingLaunchTarget=\(hasMatchingLaunchTarget, privacy: .public); sameAppBestEffort=\(allowsSameAppBestEffortPaste, privacy: .public); hasLaunchAppContext=\(launchAppContext != nil, privacy: .public)"
        )

        switch plan {
        case .clipboardFallback(let reason):
            copyToPasteboard(text)
            return .copiedToClipboard(reason: reason)
        case .keyPressPaste:
            return try await pasteUsingClipboard(
                text: text,
                preserveClipboard: preserveClipboard,
                restoreDelayMilliseconds: restoreDelayMilliseconds,
                launchAppContext: launchAppContext,
                expectedSelectionContext:
                    expectedSelectionContext
            )
        }
    }

    private func pasteUsingClipboard(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?,
        expectedSelectionContext:
            SelectionContextSnapshot?
    ) async throws -> InjectionOutcome {
        try Task.checkCancellation()
        let pasteboard = NSPasteboard.general
        let snapshot = preserveClipboard ? PasteboardSnapshot.capture(from: pasteboard) : nil

        restoreLaunchAppIfNeeded(launchAppContext)
        guard try await waitForPasteTarget(launchAppContext: launchAppContext) else {
            logger.error("Paste target did not become frontmost before timeout; leaving transcript in clipboard")
            return copyLeavingTranscript(
                text,
                reason: .noEditableTarget,
                snapshot: snapshot,
                pasteboard: pasteboard,
                restoreDelayMilliseconds: restoreDelayMilliseconds
            )
        }

        if
            let expectedSelectionContext,
            let reason =
                Self.selectionFallbackReason(
                    verification:
                        FocusedElementInspector
                            .verifySelectionContext(
                                expectedSelectionContext
                            )
                )
        {
            logger.info(
                "Selection changed before paste; copying result without replacement"
            )
            return copyLeavingTranscript(
                text,
                reason: reason,
                snapshot: snapshot,
                pasteboard: pasteboard,
                restoreDelayMilliseconds: restoreDelayMilliseconds
            )
        }

        try Task.checkCancellation()
        let ownedChangeCount = copyToPasteboard(text)
        try await Task.sleep(for: .milliseconds(60))
        try Task.checkCancellation()
        guard isPasteTargetReady(launchAppContext: launchAppContext) else {
            logger.error("Paste target changed after clipboard write; leaving transcript in clipboard")
            scheduleClipboardRestore(
                snapshot: snapshot,
                pasteboard: pasteboard,
                ownedChangeCount: ownedChangeCount,
                restoreDelayMilliseconds: restoreDelayMilliseconds
            )
            return .copiedToClipboard(reason: .noEditableTarget)
        }

        let targetCapture = FocusedElementInspector.capturePasteTarget(
            in: launchAppContext
        )
        let usingBestEffortPaste = targetCapture == nil
            && Self.allowsSameAppBestEffortPaste(launchAppContext: launchAppContext)
        if targetCapture == nil && !usingBestEffortPaste {
            logger.error("Paste target could not be captured before dispatch; leaving transcript in clipboard")
            scheduleClipboardRestore(
                snapshot: snapshot,
                pasteboard: pasteboard,
                ownedChangeCount: ownedChangeCount,
                restoreDelayMilliseconds: restoreDelayMilliseconds
            )
            return .copiedToClipboard(reason: .noEditableTarget)
        }

        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            throw InjectionError.keyEventFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        if let targetCapture {
            guard FocusedElementInspector.isCurrentTarget(targetCapture.target) else {
                logger.error("Paste target changed immediately before dispatch; leaving transcript in clipboard")
                scheduleClipboardRestore(
                    snapshot: snapshot,
                    pasteboard: pasteboard,
                    ownedChangeCount: ownedChangeCount,
                    restoreDelayMilliseconds: restoreDelayMilliseconds
                )
                return .copiedToClipboard(reason: .noEditableTarget)
            }
        } else {
            // Best-effort path: process identity is the only stable signal.
            guard isPasteTargetReady(launchAppContext: launchAppContext) else {
                logger.error("Launch app left the front before best-effort paste; leaving transcript in clipboard")
                scheduleClipboardRestore(
                    snapshot: snapshot,
                    pasteboard: pasteboard,
                    ownedChangeCount: ownedChangeCount,
                    restoreDelayMilliseconds: restoreDelayMilliseconds
                )
                return .copiedToClipboard(reason: .noEditableTarget)
            }
        }
        if
            let expectedSelectionContext,
            let reason =
                Self.selectionFallbackReason(
                    verification:
                        FocusedElementInspector
                            .verifySelectionContext(
                                expectedSelectionContext
                            )
                )
        {
            logger.info(
                "Selection changed immediately before paste dispatch; retaining result in clipboard"
            )
            scheduleClipboardRestore(
                snapshot: snapshot,
                pasteboard: pasteboard,
                ownedChangeCount: ownedChangeCount,
                restoreDelayMilliseconds: restoreDelayMilliseconds
            )
            return .copiedToClipboard(
                reason: reason
            )
        }
        try Task.checkCancellation()
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        guard let targetCapture else {
            logger.info(
                "Best-effort paste command dispatched without AX target; retaining transcript in clipboard"
            )
            return .pasteDispatchedClipboardRetained
        }

        guard let beforeSnapshot = targetCapture.editableTextSnapshot else {
            logger.info("Paste command dispatched; AX text verification is unavailable, retaining transcript in clipboard")
            return .pasteDispatchedClipboardRetained
        }

        let verificationResult = try await pasteVerificationWaiter.wait {
            switch FocusedElementInspector.captureEditableTextSnapshot(
                matching: targetCapture.target
            ) {
            case .captured(let afterSnapshot):
                return PasteTransitionVerifier.result(
                    before: beforeSnapshot,
                    after: afterSnapshot,
                    insertedText: text,
                    targetStillMatches: true
                )
            case .unavailable:
                return .unavailable
            case .targetChanged:
                return .targetChanged
            }
        }

        guard verificationResult == .verified else {
            logger.info(
                "Paste command dispatched without verified insertion (\(String(describing: verificationResult), privacy: .public)); retaining transcript in clipboard"
            )
            return .pasteDispatchedClipboardRetained
        }

        guard let expectedAfter = PasteTransitionVerifier
            .expectedSnapshot(
                before: beforeSnapshot,
                insertedText: text
            )
        else {
            return .pasteDispatchedClipboardRetained
        }

        let beforeValue = beforeSnapshot.value as NSString
        let selectedRange = beforeSnapshot.selectedRange
        let originalSelectedText: String
        if selectedRange.location >= 0,
           selectedRange.length > 0,
           selectedRange.location <= beforeValue.length,
           selectedRange.length
                <= beforeValue.length - selectedRange.location
        {
            originalSelectedText = beforeValue.substring(
                with: NSRange(
                    location: selectedRange.location,
                    length: selectedRange.length
                )
            )
        } else {
            originalSelectedText = ""
        }
        undoTransaction = VerifiedInsertionUndoTransaction(
            target: targetCapture.target,
            before: beforeSnapshot,
            expectedAfter: expectedAfter,
            originalSelectedText: originalSelectedText,
            launchAppContext: launchAppContext
        )

        scheduleClipboardRestore(
            snapshot: snapshot,
            pasteboard: pasteboard,
            ownedChangeCount: ownedChangeCount,
            restoreDelayMilliseconds: restoreDelayMilliseconds
        )
        return .insertedAndVerified
    }

    func undoLastVerifiedInsertion() async -> SafeUndoOutcome {
        guard let transaction = undoTransaction else {
            return .unavailable
        }
        // Undo is deliberately one-shot. A failed verification must not become
        // an invitation to retry against a later, potentially different target.
        undoTransaction = nil
        clipboardRestoreTask?.cancel()
        clipboardRestoreTask = nil

        restoreLaunchAppIfNeeded(transaction.launchAppContext)
        do {
            guard try await waitForPasteTarget(
                launchAppContext: transaction.launchAppContext
            ) else {
                return copyOriginalIfAvailable(
                    transaction.originalSelectedText,
                    reason: .targetChanged
                )
            }
        } catch {
            return copyOriginalIfAvailable(
                transaction.originalSelectedText,
                reason: .targetChanged
            )
        }

        let result = FocusedElementInspector
            .restoreEditableTextSnapshot(
                transaction.before,
                ifCurrentMatches: transaction.expectedAfter,
                matching: transaction.target
            )
        switch result {
        case .restored:
            return .restored
        case .targetChanged:
            return copyOriginalIfAvailable(
                transaction.originalSelectedText,
                reason: .targetChanged
            )
        case .textChanged:
            return copyOriginalIfAvailable(
                transaction.originalSelectedText,
                reason: .textChanged
            )
        case .unavailable:
            return copyOriginalIfAvailable(
                transaction.originalSelectedText,
                reason: .unavailable
            )
        case .restoreFailed:
            return copyOriginalIfAvailable(
                transaction.originalSelectedText,
                reason: .restoreFailed
            )
        }
    }

    private func copyOriginalIfAvailable(
        _ original: String,
        reason: SafeUndoFailureReason
    ) -> SafeUndoOutcome {
        guard !original.isEmpty else {
            return .unavailable
        }
        copyToPasteboard(original)
        return .copiedOriginal(reason: reason)
    }

    private func waitForPasteTarget(
        launchAppContext: LaunchAppContext?
    ) async throws -> Bool {
        try await pasteTargetWaiter.wait(
            isReady: { @MainActor [weak self] in
                self?.isPasteTargetReady(launchAppContext: launchAppContext) ?? false
            },
            reactivate: { @MainActor [weak self] in
                self?.restoreLaunchAppIfNeeded(launchAppContext)
            }
        )
    }

    private func isPasteTargetReady(launchAppContext: LaunchAppContext?) -> Bool {
        guard let launchAppContext else {
            return FocusedElementInspector.hasEditableTextFocus()
        }

        guard isLaunchAppFrontmost(launchAppContext) else {
            return false
        }

        if launchAppContext.focusedTarget != nil {
            return FocusedElementInspector.hasEditableTextFocus(in: launchAppContext)
        }

        // No AX editor was captured at session start (WeChat-style). Same-process
        // frontmost state is enough to attempt Cmd+V; never claim verification.
        return Self.allowsSameAppBestEffortPaste(launchAppContext: launchAppContext)
    }

    private func isLaunchAppFrontmost(_ launchAppContext: LaunchAppContext) -> Bool {
        guard
            let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            frontmostApplication.processIdentifier == launchAppContext.processIdentifier,
            frontmostApplication.bundleIdentifier == launchAppContext.bundleIdentifier
        else {
            return false
        }

        // Prefer launch-date identity when both sides expose it. Some processes
        // omit launchDate; fall back to pid + bundle only in that case.
        switch (frontmostApplication.launchDate, launchAppContext.processLaunchDate) {
        case let (current?, expected?):
            return current == expected
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    private func restoreLaunchAppIfNeeded(_ launchAppContext: LaunchAppContext?) {
        guard
            let launchAppContext,
            let currentFrontmostApp = NSWorkspace.shared.frontmostApplication,
            currentFrontmostApp.processIdentifier != launchAppContext.processIdentifier
        else {
            return
        }

        let bundleIdentifier = launchAppContext.bundleIdentifier ?? "unknown"
        logger.info(
            "Reactivating launch app before paste: pid=\(launchAppContext.processIdentifier, privacy: .public) bundleID=\(bundleIdentifier, privacy: .public)"
        )
        LaunchAppContext.restoreFrontmostIfNeeded(launchAppContext)
    }

    /// Copy the delivery text for manual paste / failed auto-paste, and when
    /// `preserveClipboard` was requested schedule a delayed restore so the
    /// user's prior clipboard is not permanently clobbered after a failed inject.
    private func copyLeavingTranscript(
        _ text: String,
        reason: ClipboardFallbackReason,
        snapshot: PasteboardSnapshot?,
        pasteboard: NSPasteboard,
        restoreDelayMilliseconds: UInt64
    ) -> InjectionOutcome {
        let ownedChangeCount = copyToPasteboard(text)
        scheduleClipboardRestore(
            snapshot: snapshot,
            pasteboard: pasteboard,
            ownedChangeCount: ownedChangeCount,
            restoreDelayMilliseconds: restoreDelayMilliseconds
        )
        return .copiedToClipboard(reason: reason)
    }

    private func scheduleClipboardRestore(
        snapshot: PasteboardSnapshot?,
        pasteboard: NSPasteboard,
        ownedChangeCount: Int,
        restoreDelayMilliseconds: UInt64
    ) {
        guard let snapshot else {
            return
        }

        let boundedDelayMilliseconds = min(restoreDelayMilliseconds, 10_000)
        let (delayNanoseconds, overflow) = boundedDelayMilliseconds
            .multipliedReportingOverflow(by: 1_000_000)
        guard !overflow else {
            return
        }

        clipboardRestoreTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard
                let self,
                !Task.isCancelled,
                NSPasteboard.general.changeCount == ownedChangeCount,
                Self.shouldRestoreClipboard(
                    currentChangeCount: NSPasteboard.general.changeCount,
                    ownedChangeCount: ownedChangeCount
                )
            else {
                return
            }
            snapshot.restore(to: pasteboard)
            self.clipboardRestoreTask = nil
        }
    }

    @discardableResult
    private func copyToPasteboard(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    nonisolated static func shouldRestoreClipboard(
        currentChangeCount: Int,
        ownedChangeCount: Int
    ) -> Bool {
        currentChangeCount == ownedChangeCount
    }
}

struct PasteboardSnapshot: Equatable {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let snapshot = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                if let data = item.data(forType: type) {
                    result[type] = data
                }
            }
        } ?? []
        return PasteboardSnapshot(items: snapshot)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for item in items {
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item {
                pasteboardItem.setData(data, forType: type)
            }
            pasteboard.writeObjects([pasteboardItem])
        }
    }

    func matches(_ pasteboard: NSPasteboard) -> Bool {
        Self.capture(from: pasteboard) == self
    }
}
