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

    var statusDetail: String {
        switch self {
        case .accessibilityPermissionRequired:
            return L10n.text("Copied to clipboard. Grant Accessibility access for auto-paste.")
        case .noEditableTarget:
            return L10n.text("Copied to clipboard")
        case .retryRequiresManualPaste:
            return L10n.text("Retry completed and was copied to the clipboard.")
        }
    }

    var overlaySubtitle: String {
        switch self {
        case .accessibilityPermissionRequired:
            return L10n.text("Accessibility permission is off, so OpenWhisper left the text in the clipboard.")
        case .noEditableTarget:
            return L10n.text("No editable cursor was found. Paste manually.")
        case .retryRequiresManualPaste:
            return L10n.text("For safety, retry results are copied instead of pasted automatically.")
        }
    }
}

enum InjectionOutcome: Sendable, Equatable {
    case pasted
    case copiedToClipboard(reason: ClipboardFallbackReason)
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

@MainActor
protocol TextInjecting: AnyObject {
    func inject(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?,
        automaticPasteAllowed: Bool
    ) async throws -> InjectionOutcome
}

@MainActor
final class TextInjector: TextInjecting {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? ProductIdentity.defaultBundleIdentifier,
        category: "TextInjector"
    )
    private var clipboardRestoreTask: Task<Void, Never>?
    private let pasteTargetWaiter: AsyncPasteTargetWaiter

    init(pasteTargetWaiter: AsyncPasteTargetWaiter = .init()) {
        self.pasteTargetWaiter = pasteTargetWaiter
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
        return .pasted
    }

    nonisolated static func injectionPlan(
        text _: String,
        accessibilityTrusted: Bool,
        editableTextSnapshot _: EditableTextSnapshot?,
        fallbackEditableTextSnapshot _: EditableTextSnapshot?,
        hasEditableTextFocus: Bool,
        hasFallbackEditableTextFocus: Bool,
        hasLaunchAppContext _: Bool = false,
        automaticPasteAllowed: Bool = true
    ) -> TextInsertionPlan {
        guard automaticPasteAllowed else {
            return .clipboardFallback(reason: .retryRequiresManualPaste)
        }
        guard accessibilityTrusted else {
            return .clipboardFallback(reason: .accessibilityPermissionRequired)
        }

        guard hasEditableTextFocus || hasFallbackEditableTextFocus else {
            return .clipboardFallback(reason: .noEditableTarget)
        }

        return .keyPressPaste
    }

    func inject(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?,
        automaticPasteAllowed: Bool
    ) async throws -> InjectionOutcome {
        clipboardRestoreTask?.cancel()
        clipboardRestoreTask = nil

        let accessibilityTrusted = AccessibilityPermission.isTrusted()
        if !accessibilityTrusted {
            AccessibilityPermission.requestTrustIfNeeded()
        }

        let hasCurrentEditableTextFocus = accessibilityTrusted && FocusedElementInspector.hasEditableTextFocus()
        let hasMatchingLaunchTarget = accessibilityTrusted &&
            FocusedElementInspector.hasEditableTextFocus(in: launchAppContext)
        let plan = Self.injectionPlan(
            text: text,
            accessibilityTrusted: accessibilityTrusted,
            editableTextSnapshot: nil,
            fallbackEditableTextSnapshot: nil,
            hasEditableTextFocus: launchAppContext == nil && hasCurrentEditableTextFocus,
            hasFallbackEditableTextFocus: hasMatchingLaunchTarget,
            hasLaunchAppContext: launchAppContext != nil,
            automaticPasteAllowed: automaticPasteAllowed
        )

        logger.info(
            "Injection plan resolved to \(String(describing: plan), privacy: .public); currentEditableFocus=\(hasCurrentEditableTextFocus, privacy: .public); matchingLaunchTarget=\(hasMatchingLaunchTarget, privacy: .public); hasLaunchAppContext=\(launchAppContext != nil, privacy: .public)"
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
                launchAppContext: launchAppContext
            )
        }
    }

    private func pasteUsingClipboard(
        text: String,
        preserveClipboard: Bool,
        restoreDelayMilliseconds: UInt64,
        launchAppContext: LaunchAppContext?
    ) async throws -> InjectionOutcome {
        let pasteboard = NSPasteboard.general
        let snapshot = preserveClipboard ? PasteboardSnapshot.capture(from: pasteboard) : nil

        restoreLaunchAppIfNeeded(launchAppContext)
        guard try await waitForPasteTarget(launchAppContext: launchAppContext) else {
            logger.error("Paste target did not become frontmost before timeout; leaving transcript in clipboard")
            copyToPasteboard(text)
            return .copiedToClipboard(reason: .noEditableTarget)
        }

        let ownedChangeCount = copyToPasteboard(text)
        try await Task.sleep(for: .milliseconds(60))
        guard isPasteTargetReady(launchAppContext: launchAppContext) else {
            logger.error("Paste target changed after clipboard write; leaving transcript in clipboard")
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
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        if let snapshot {
            let boundedDelayMilliseconds = min(restoreDelayMilliseconds, 10_000)
            let (delayNanoseconds, overflow) = boundedDelayMilliseconds
                .multipliedReportingOverflow(by: 1_000_000)
            if !overflow {
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
        }

        return .pasted
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

        guard
            let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            frontmostApplication.processIdentifier == launchAppContext.processIdentifier,
            frontmostApplication.bundleIdentifier == launchAppContext.bundleIdentifier,
            let currentLaunchDate = frontmostApplication.launchDate,
            let expectedLaunchDate = launchAppContext.processLaunchDate,
            currentLaunchDate == expectedLaunchDate
        else {
            return false
        }

        return FocusedElementInspector.hasEditableTextFocus(in: launchAppContext)
    }

    private func restoreLaunchAppIfNeeded(_ launchAppContext: LaunchAppContext?) {
        guard
            let launchAppContext,
            let currentFrontmostApp = NSWorkspace.shared.frontmostApplication,
            currentFrontmostApp.processIdentifier != launchAppContext.processIdentifier,
            let app = NSRunningApplication(processIdentifier: launchAppContext.processIdentifier)
        else {
            return
        }

        let bundleIdentifier = launchAppContext.bundleIdentifier ?? "unknown"
        logger.info(
            "Reactivating launch app before paste: pid=\(launchAppContext.processIdentifier, privacy: .public) bundleID=\(bundleIdentifier, privacy: .public)"
        )
        app.activate(options: [.activateIgnoringOtherApps])
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

private struct PasteboardSnapshot {
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
}
