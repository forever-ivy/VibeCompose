import Foundation
import Testing
@testable import OpenWhisper

@Test
func accessibilityRequestSkipsPromptWhenAlreadyTrusted() {
    var didPrompt = false

    let trusted = AccessibilityPermission.requestTrustIfNeeded(
        trustCheck: { true },
        prompt: {
            didPrompt = true
            return true
        }
    )

    #expect(trusted)
    #expect(!didPrompt)
}

@Test
func accessibilityRequestPromptsWhenTrustIsMissing() {
    var didPrompt = false

    let trusted = AccessibilityPermission.requestTrustIfNeeded(
        trustCheck: { false },
        prompt: {
            didPrompt = true
            return false
        }
    )

    #expect(!trusted)
    #expect(didPrompt)
}

@Test
func injectionFallsBackToClipboardWithoutAccessibilityPermission() {
    let outcome = TextInjector.injectionOutcome(
        hasEditableTextFocus: true,
        accessibilityTrusted: false
    )

    #expect(outcome == .copiedToClipboard(reason: .accessibilityPermissionRequired))
}

@Test
func injectionFallsBackToClipboardWithoutEditableFocus() {
    let outcome = TextInjector.injectionOutcome(
        hasEditableTextFocus: false,
        accessibilityTrusted: true
    )

    #expect(outcome == .copiedToClipboard(reason: .noEditableTarget))
}

@Test
func editableFocusOnlyProvesPasteCanBeDispatched() {
    let outcome = TextInjector.injectionOutcome(
        hasEditableTextFocus: true,
        accessibilityTrusted: true
    )

    #expect(outcome == .pasteDispatchedClipboardRetained)
    #expect(outcome.resultStatus == TextDeliveryStatus.pasteDispatched)
}

@Test
func injectionPlanUsesNativePasteForPlainFocusedSnapshot() {
    let snapshot = EditableTextSnapshot(
        value: "hello world",
        selectedRange: CFRange(location: 6, length: 0)
    )

    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper ",
        accessibilityTrusted: true,
        editableTextSnapshot: snapshot,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: true,
        hasFallbackEditableTextFocus: false
    )

    #expect(plan == .keyPressPaste)
}

@Test
func injectionPlanUsesNativePasteForSelectedTextSnapshot() {
    let snapshot = EditableTextSnapshot(
        value: "hello brave world",
        selectedRange: CFRange(location: 6, length: 5)
    )

    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: snapshot,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: true,
        hasFallbackEditableTextFocus: false
    )

    #expect(plan == .keyPressPaste)
}

@Test
func injectionPlanUsesNativePasteForExistingTextSnapshot() {
    let snapshot = EditableTextSnapshot(
        value: "已有的一段 Codex 输入\n第二行",
        selectedRange: CFRange(location: 8, length: 0)
    )

    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: snapshot,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: true,
        hasFallbackEditableTextFocus: false
    )

    #expect(plan == .keyPressPaste)
}

@Test
func injectionPlanUsesNativePasteForFallbackSnapshotWhenLaunchAppEditorHasFocus() {
    let snapshot = EditableTextSnapshot(
        value: "hello world",
        selectedRange: CFRange(location: 11, length: 0)
    )

    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: nil,
        fallbackEditableTextSnapshot: snapshot,
        hasEditableTextFocus: false,
        hasFallbackEditableTextFocus: true
    )

    #expect(plan == .keyPressPaste)
}

@Test
func injectionPlanUsesNativePasteWhenFocusedSnapshotIsOnlyCodexPlaceholder() {
    let snapshot = EditableTextSnapshot(
        value: "Ask for follow-up changes",
        selectedRange: CFRange(location: 0, length: 0)
    )

    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: snapshot,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: true,
        hasFallbackEditableTextFocus: false
    )

    #expect(plan == .keyPressPaste)
}

@Test
func injectionPlanUsesNativePasteForFeishuComposerAccessibilityWrapper() {
    let snapshot = EditableTextSnapshot(
        value: "发送给 项目部\n你们到时候写你的博士论文的时候,也是每个人都要有一个感知决策行动的闭环的。\u{200B}\n\u{200B}\n发送给 项目部\n\u{200B}\n\u{200B}\n\u{200B}",
        selectedRange: CFRange(location: 57, length: 0)
    )

    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: snapshot,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: true,
        hasFallbackEditableTextFocus: false
    )

    #expect(plan == .keyPressPaste)
}

@Test
func injectionPlanDoesNotPasteWithoutAnyEditableTarget() {
    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: nil,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: false,
        hasFallbackEditableTextFocus: false,
        hasLaunchAppContext: false
    )

    #expect(plan == .clipboardFallback(reason: .noEditableTarget))
}

@Test
func injectionPlanDoesNotPasteWhenOnlyLaunchAppContextExists() {
    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: nil,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: false,
        hasFallbackEditableTextFocus: false,
        hasLaunchAppContext: true
    )

    #expect(plan == .clipboardFallback(reason: .noEditableTarget))
}

@Test
func retryInjectionPlanAlwaysUsesClipboardEvenWithEditableFocus() {
    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: nil,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: true,
        hasFallbackEditableTextFocus: true,
        hasLaunchAppContext: true,
        automaticPasteAllowed: false
    )

    #expect(plan == .clipboardFallback(reason: .retryRequiresManualPaste))
}

@Test
func changedOrUnavailableSelectionAlwaysFallsBackToClipboard() {
    #expect(
        TextInjector.selectionFallbackReason(
            verification: .unchanged
        ) == nil
    )
    #expect(
        TextInjector.selectionFallbackReason(
            verification: .changed
        ) == .selectionChanged
    )
    #expect(
        TextInjector.selectionFallbackReason(
            verification: .unavailable
        ) == .selectionChanged
    )
}

@Test
func injectionPlanIgnoresStaleSnapshotsWithoutEditableFocusSignal() {
    let snapshot = EditableTextSnapshot(
        value: "stale editor text",
        selectedRange: CFRange(location: 0, length: 0)
    )

    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: snapshot,
        fallbackEditableTextSnapshot: snapshot,
        hasEditableTextFocus: false,
        hasFallbackEditableTextFocus: false
    )

    #expect(plan == .clipboardFallback(reason: .noEditableTarget))
}

@Test
func injectionPlanUsesNativePasteWhenFocusedEditorIsNotDirectlyWritable() {
    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: nil,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: true,
        hasFallbackEditableTextFocus: false
    )

    #expect(plan == .keyPressPaste)
}

@Test
func injectionPlanUsesNativePasteWhenLaunchAppEditorStillHasFocus() {
    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: nil,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: false,
        hasFallbackEditableTextFocus: true
    )

    #expect(plan == .keyPressPaste)
}

@Test
func injectionPlanStillUsesClipboardWhenNoEditorSignalExists() {
    let plan = TextInjector.injectionPlan(
        text: "OpenWhisper",
        accessibilityTrusted: true,
        editableTextSnapshot: nil,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: false,
        hasFallbackEditableTextFocus: false
    )

    #expect(plan == .clipboardFallback(reason: .noEditableTarget))
}

@Test
func pasteTransitionVerifierConfirmsInsertionAtUTF16Caret() {
    let before = EditableTextSnapshot(
        value: "a🙂b",
        selectedRange: CFRange(location: 3, length: 0)
    )
    let after = EditableTextSnapshot(
        value: "a🙂OpenWhisperb",
        selectedRange: CFRange(location: 14, length: 0)
    )

    #expect(
        PasteTransitionVerifier.result(
            before: before,
            after: after,
            insertedText: "OpenWhisper",
            targetStillMatches: true
        ) == .verified
    )
}

@Test
func pasteTransitionVerifierConfirmsSelectedTextReplacement() {
    let before = EditableTextSnapshot(
        value: "hello brave world",
        selectedRange: CFRange(location: 6, length: 5)
    )
    let after = EditableTextSnapshot(
        value: "hello OpenWhisper world",
        selectedRange: CFRange(location: 17, length: 0)
    )

    #expect(
        PasteTransitionVerifier.result(
            before: before,
            after: after,
            insertedText: "OpenWhisper",
            targetStillMatches: true
        ) == .verified
    )
}

@Test
func pasteTransitionVerifierRequiresObservableChange() {
    let snapshot = EditableTextSnapshot(
        value: "OpenWhisper",
        selectedRange: CFRange(location: 11, length: 0)
    )

    #expect(
        PasteTransitionVerifier.result(
            before: snapshot,
            after: snapshot,
            insertedText: "",
            targetStillMatches: true
        ) == .notObserved
    )
}

@Test
func pasteTransitionVerifierCanProveSameTextReplacementBySelectionCollapse() {
    let before = EditableTextSnapshot(
        value: "OpenWhisper",
        selectedRange: CFRange(location: 0, length: 11)
    )
    let after = EditableTextSnapshot(
        value: "OpenWhisper",
        selectedRange: CFRange(location: 11, length: 0)
    )

    #expect(
        PasteTransitionVerifier.result(
            before: before,
            after: after,
            insertedText: "OpenWhisper",
            targetStillMatches: true
        ) == .verified
    )
}

@Test
func pasteTransitionVerifierRejectsUnrelatedValueChange() {
    let before = EditableTextSnapshot(
        value: "hello",
        selectedRange: CFRange(location: 5, length: 0)
    )
    let after = EditableTextSnapshot(
        value: "hello other",
        selectedRange: CFRange(location: 11, length: 0)
    )

    #expect(
        PasteTransitionVerifier.result(
            before: before,
            after: after,
            insertedText: " OpenWhisper",
            targetStillMatches: true
        ) == .notObserved
    )
}

@Test
func pasteTransitionVerifierDistinguishesUnavailableAndChangedTarget() {
    let snapshot = EditableTextSnapshot(
        value: "hello",
        selectedRange: CFRange(location: 5, length: 0)
    )

    #expect(
        PasteTransitionVerifier.result(
            before: nil,
            after: snapshot,
            insertedText: " world",
            targetStillMatches: true
        ) == .unavailable
    )
    #expect(
        PasteTransitionVerifier.result(
            before: snapshot,
            after: snapshot,
            insertedText: " world",
            targetStillMatches: false
        ) == .targetChanged
    )
}

@Test
func clipboardRestoreRequiresOpenWhisperToStillOwnThePasteboard() {
    #expect(TextInjector.shouldRestoreClipboard(currentChangeCount: 42, ownedChangeCount: 42))
    #expect(!TextInjector.shouldRestoreClipboard(currentChangeCount: 43, ownedChangeCount: 42))
}

@MainActor
@Test
func asyncPasteTargetWaiterYieldsMainActorBetweenChecks() async throws {
    var checks = 0
    var reactivations = 0
    var heartbeatRan = false
    let waiter = AsyncPasteTargetWaiter(
        timeout: .seconds(5),
        pollInterval: .milliseconds(1)
    )

    let heartbeat = Task { @MainActor in
        await Task.yield()
        heartbeatRan = true
    }
    let becameReady = try await waiter.wait(
        isReady: {
            checks += 1
            return checks >= 2
        },
        reactivate: {
            reactivations += 1
        }
    )
    await heartbeat.value

    #expect(becameReady)
    #expect(checks == 2)
    #expect(reactivations == 1)
    #expect(heartbeatRan)
}

@MainActor
@Test
func asyncPasteTargetWaiterIsCancellationAware() async {
    let waiter = AsyncPasteTargetWaiter(
        timeout: .seconds(5),
        pollInterval: .milliseconds(20)
    )
    let task = Task {
        try await waiter.wait(
            isReady: { false },
            reactivate: {}
        )
    }

    try? await Task.sleep(for: .milliseconds(30))
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Cancelled paste-target wait should throw CancellationError")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("Unexpected cancellation error: \(error)")
    }
}

@MainActor
@Test
func asyncPasteVerificationWaiterPollsUntilInsertionIsObserved() async throws {
    var checks = 0
    let waiter = AsyncPasteVerificationWaiter(
        timeout: .seconds(1),
        pollInterval: .milliseconds(1)
    )

    let result = try await waiter.wait {
        checks += 1
        return checks >= 3 ? .verified : .notObserved
    }

    #expect(result == .verified)
    #expect(checks == 3)
}

@MainActor
@Test
func asyncPasteVerificationWaiterStopsWhenTargetChanges() async throws {
    var checks = 0
    let waiter = AsyncPasteVerificationWaiter(
        timeout: .seconds(1),
        pollInterval: .milliseconds(1)
    )

    let result = try await waiter.wait {
        checks += 1
        return .targetChanged
    }

    #expect(result == .targetChanged)
    #expect(checks == 1)
}
