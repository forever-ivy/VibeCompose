import Foundation
import Testing
@testable import VibeCompose

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
        text: "VibeCompose ",
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
        text: "VibeCompose",
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
        text: "VibeCompose",
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
        text: "VibeCompose",
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
        text: "VibeCompose",
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
        text: "VibeCompose",
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
        text: "VibeCompose",
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
        text: "VibeCompose",
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
func injectionPlanUsesNativePasteForSameAppBestEffortWhenAXTargetMissing() {
    // WeChat-style: dictation started on an app that never exposes a focused
    // editable AX element. Same-process reactivation is still enough to try
    // Cmd+V; verification remains unavailable.
    let plan = TextInjector.injectionPlan(
        text: "VibeCompose",
        accessibilityTrusted: true,
        editableTextSnapshot: nil,
        fallbackEditableTextSnapshot: nil,
        hasEditableTextFocus: false,
        hasFallbackEditableTextFocus: false,
        hasLaunchAppContext: true,
        allowsSameAppBestEffortPaste: true
    )

    #expect(plan == .keyPressPaste)
}

@Test
func sameAppBestEffortPasteRequiresLaunchContextWithoutCapturedTarget() {
    #expect(
        !TextInjector.allowsSameAppBestEffortPaste(
            launchAppContext: nil
        )
    )

    // WeChat-style: process known, no AX editor ever captured.
    let withoutTarget = LaunchAppContext(
        bundleIdentifier: "com.tencent.xinWeChat",
        localizedName: "WeChat",
        processIdentifier: 2_125,
        processLaunchDate: Date(timeIntervalSince1970: 1),
        focusedTarget: nil
    )
    #expect(
        TextInjector.allowsSameAppBestEffortPaste(
            launchAppContext: withoutTarget
        )
    )

    // Invalid pid must never unlock paste.
    #expect(
        !TextInjector.allowsSameAppBestEffortPaste(
            launchAppContext: LaunchAppContext(
                bundleIdentifier: "com.tencent.xinWeChat",
                localizedName: "WeChat",
                processIdentifier: 0,
                processLaunchDate: nil,
                focusedTarget: nil
            )
        )
    )
}

@Test
func ghosttyStyleTextRoleIsEditableEvenWhenAttributesAreNotSettable() {
    #expect(
        FocusedElementInspector.isEditableTextFocusDecision(
            role: "AXTextArea",
            subrole: nil,
            enabled: nil,
            hidden: nil,
            valueIsSettable: false,
            selectionIsSettable: false
        )
    )
    #expect(
        FocusedElementInspector.isEditableTextFocusDecision(
            role: "AXTextField",
            subrole: nil,
            enabled: true,
            hidden: false,
            valueIsSettable: false,
            selectionIsSettable: false
        )
    )
    #expect(
        !FocusedElementInspector.isEditableTextFocusDecision(
            role: "AXTextField",
            subrole: "AXSecureTextField",
            enabled: true,
            hidden: false,
            valueIsSettable: false,
            selectionIsSettable: false
        )
    )
    #expect(
        !FocusedElementInspector.isEditableTextFocusDecision(
            role: "AXGroup",
            subrole: nil,
            enabled: true,
            hidden: false,
            valueIsSettable: false,
            selectionIsSettable: false
        )
    )
    #expect(
        FocusedElementInspector.isEditableTextFocusDecision(
            role: "AXGroup",
            subrole: nil,
            enabled: true,
            hidden: false,
            valueIsSettable: true,
            selectionIsSettable: true
        )
    )
}

@Test
func selectionContextAcceptsNonTextRolesWhenSelectedTextIsReadable() {
    // Word / Feishu / contenteditable: focused AXGroup with AXSelectedText but
    // neither value nor selected-text-range marked settable — must still qualify
    // for Context Rewrite capture (paste-target editability stays strict).
    #expect(
        FocusedElementInspector.canExposeSelectionContextDecision(
            role: "AXGroup",
            subrole: nil,
            enabled: true,
            hidden: false,
            valueIsSettable: false,
            selectionIsSettable: false,
            hasReadableSelectedText: true,
            hasValueAndRangeSelection: false
        )
    )
    #expect(
        FocusedElementInspector.canExposeSelectionContextDecision(
            role: "AXWebArea",
            subrole: nil,
            enabled: true,
            hidden: false,
            valueIsSettable: false,
            selectionIsSettable: false,
            hasReadableSelectedText: false,
            hasValueAndRangeSelection: true
        )
    )
    // Word compatibility-mode document nodes can report AXEnabled=false while
    // still exposing a real, readable selection. Selection capture is read-only
    // and must not confuse that host quirk with a disabled UI control.
    #expect(
        FocusedElementInspector.canExposeSelectionContextDecision(
            role: "AXTextArea",
            subrole: nil,
            enabled: false,
            hidden: false,
            valueIsSettable: true,
            selectionIsSettable: true,
            hasReadableSelectedText: true,
            hasValueAndRangeSelection: true
        )
    )
    // Bare chrome without any selection surface must not unlock capture.
    #expect(
        !FocusedElementInspector.canExposeSelectionContextDecision(
            role: "AXGroup",
            subrole: nil,
            enabled: true,
            hidden: false,
            valueIsSettable: false,
            selectionIsSettable: false,
            hasReadableSelectedText: false,
            hasValueAndRangeSelection: false
        )
    )
    // Secure fields stay blocked even if selected text is present.
    #expect(
        !FocusedElementInspector.canExposeSelectionContextDecision(
            role: "AXTextField",
            subrole: "AXSecureTextField",
            enabled: true,
            hidden: false,
            valueIsSettable: false,
            selectionIsSettable: false,
            hasReadableSelectedText: true,
            hasValueAndRangeSelection: false
        )
    )
    // Classic text roles remain accepted via the editable-focus path.
    #expect(
        FocusedElementInspector.canExposeSelectionContextDecision(
            role: "AXTextArea",
            subrole: nil,
            enabled: true,
            hidden: false,
            valueIsSettable: false,
            selectionIsSettable: false,
            hasReadableSelectedText: false,
            hasValueAndRangeSelection: false
        )
    )
}

@Test
func retryInjectionPlanAlwaysUsesClipboardEvenWithEditableFocus() {
    let plan = TextInjector.injectionPlan(
        text: "VibeCompose",
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
        text: "VibeCompose",
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
        text: "VibeCompose",
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
        text: "VibeCompose",
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
        text: "VibeCompose",
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
        value: "a🙂VibeComposeb",
        selectedRange: CFRange(location: 14, length: 0)
    )

    #expect(
        PasteTransitionVerifier.result(
            before: before,
            after: after,
            insertedText: "VibeCompose",
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
        value: "hello VibeCompose world",
        selectedRange: CFRange(location: 17, length: 0)
    )

    #expect(
        PasteTransitionVerifier.result(
            before: before,
            after: after,
            insertedText: "VibeCompose",
            targetStillMatches: true
        ) == .verified
    )
}

@Test
func pasteTransitionVerifierRequiresObservableChange() {
    let snapshot = EditableTextSnapshot(
        value: "VibeCompose",
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
        value: "VibeCompose",
        selectedRange: CFRange(location: 0, length: 11)
    )
    let after = EditableTextSnapshot(
        value: "VibeCompose",
        selectedRange: CFRange(location: 11, length: 0)
    )

    #expect(
        PasteTransitionVerifier.result(
            before: before,
            after: after,
            insertedText: "VibeCompose",
            targetStillMatches: true
        ) == .verified
    )
}

@Test
func safeUndoRequiresExactInsertedTextButAllowsCursorMovement() {
    let before = EditableTextSnapshot(
        value: "hello world",
        selectedRange: CFRange(location: 6, length: 5)
    )
    let expected = PasteTransitionVerifier.expectedSnapshot(
        before: before,
        insertedText: "VibeCompose"
    )!
    let movedCursor = EditableTextSnapshot(
        value: expected.value,
        selectedRange: CFRange(location: 0, length: 0)
    )

    #expect(
        SafeUndoVerifier.canRestore(
            expectedAfter: expected,
            current: movedCursor,
            targetStillMatches: true
        )
    )
    #expect(
        !SafeUndoVerifier.canRestore(
            expectedAfter: expected,
            current: EditableTextSnapshot(
                value: expected.value + "!",
                selectedRange: movedCursor.selectedRange
            ),
            targetStillMatches: true
        )
    )
    #expect(
        !SafeUndoVerifier.canRestore(
            expectedAfter: expected,
            current: movedCursor,
            targetStillMatches: false
        )
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
            insertedText: " VibeCompose",
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
func clipboardRestoreRequiresVibeComposeToStillOwnThePasteboard() {
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
        // The full suite runs many MainActor tests concurrently. Give the
        // scheduler enough wall-clock headroom without changing the
        // production waiter's deliberately short timeout.
        timeout: .seconds(10),
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

@Test
func selectionMaximumIsClampedToSafeBounds() {
    #expect(FocusedElementInspector.boundedSelectionMaximum(0) == 100)
    #expect(FocusedElementInspector.boundedSelectionMaximum(50) == 100)
    #expect(FocusedElementInspector.boundedSelectionMaximum(6_000) == 6_000)
    #expect(FocusedElementInspector.boundedSelectionMaximum(100_000) == 20_000)
}

@Test
func selectedTextExtractionPrefersValueRangeThenAttribute() {
    let valueRange = FocusedElementInspector.selectedTextFromValueAndRange(
        value: "hello brave world",
        selectedRange: CFRange(location: 6, length: 5)
    )
    #expect(valueRange == "brave")

    // Zero-length caret must not produce selected text from the value path.
    #expect(
        FocusedElementInspector.selectedTextFromValueAndRange(
            value: "hello",
            selectedRange: CFRange(location: 2, length: 0)
        ) == nil
    )

    // Out-of-bounds range is rejected.
    #expect(
        FocusedElementInspector.selectedTextFromValueAndRange(
            value: "hi",
            selectedRange: CFRange(location: 0, length: 99)
        ) == nil
    )

    // Prefer value+range text when both are available.
    #expect(
        FocusedElementInspector.preferredSelectedText(
            valueAndRangeText: "from-range",
            attributeText: "from-attribute"
        ) == "from-range"
    )
    // Fall back to AXSelectedText when range extraction fails.
    #expect(
        FocusedElementInspector.preferredSelectedText(
            valueAndRangeText: nil,
            attributeText: "from-attribute"
        ) == "from-attribute"
    )
    #expect(
        FocusedElementInspector.preferredSelectedText(
            valueAndRangeText: "",
            attributeText: "from-attribute"
        ) == "from-attribute"
    )
    #expect(
        FocusedElementInspector.preferredSelectedText(
            valueAndRangeText: nil,
            attributeText: nil
        ) == nil
    )
}

@Test
func softIdentityMatchingSurvivesProxyRebuild() {
    let expected = FocusedTargetIdentity(
        elementHash: 1,
        role: "AXTextArea",
        subrole: nil,
        identifier: "editor",
        windowHash: 99
    )
    // Same control, different CFHash (proxy rebuild) still matches.
    let rebuilt = FocusedTargetIdentity(
        elementHash: 9_999,
        role: "AXTextArea",
        subrole: nil,
        identifier: "editor",
        windowHash: 99
    )
    #expect(FocusedElementInspector.identitiesMatch(rebuilt, expected))

    // Wrong role must not match.
    let wrongRole = FocusedTargetIdentity(
        elementHash: 9_999,
        role: "AXTextField",
        subrole: nil,
        identifier: "editor",
        windowHash: 99
    )
    #expect(!FocusedElementInspector.identitiesMatch(wrongRole, expected))

    // Wrong identifier must not match when expected has one.
    let wrongID = FocusedTargetIdentity(
        elementHash: 9_999,
        role: "AXTextArea",
        subrole: nil,
        identifier: "other",
        windowHash: 99
    )
    #expect(!FocusedElementInspector.identitiesMatch(wrongID, expected))

    // Without an expected identifier, role + window is enough.
    let noIDExpected = FocusedTargetIdentity(
        elementHash: 1,
        role: "AXTextArea",
        subrole: nil,
        identifier: nil,
        windowHash: 99
    )
    let noIDCurrent = FocusedTargetIdentity(
        elementHash: 2,
        role: "AXTextArea",
        subrole: nil,
        identifier: nil,
        windowHash: 99
    )
    #expect(FocusedElementInspector.identitiesMatch(noIDCurrent, noIDExpected))

    // Window hash mismatch rejects.
    let wrongWindow = FocusedTargetIdentity(
        elementHash: 2,
        role: "AXTextArea",
        subrole: nil,
        identifier: nil,
        windowHash: 1
    )
    #expect(!FocusedElementInspector.identitiesMatch(wrongWindow, noIDExpected))
}
