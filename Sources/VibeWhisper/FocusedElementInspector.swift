import ApplicationServices
import Foundation

struct FocusedTargetIdentity: Sendable, Equatable {
    let elementHash: UInt64
    let role: String?
    let subrole: String?
    let identifier: String?
    let windowHash: UInt64?
}

final class FocusedAXElementReference: @unchecked Sendable {
    let processIdentifier: pid_t
    let element: AXUIElement
    let window: AXUIElement?
    let identity: FocusedTargetIdentity

    init(
        processIdentifier: pid_t,
        element: AXUIElement,
        window: AXUIElement?,
        identity: FocusedTargetIdentity
    ) {
        self.processIdentifier = processIdentifier
        self.element = element
        self.window = window
        self.identity = identity
    }
}

struct FocusedEditableTargetCapture: @unchecked Sendable {
    let target: FocusedAXElementReference
    let editableTextSnapshot: EditableTextSnapshot?
}

enum FocusedEditableSnapshotCapture: Sendable, Equatable {
    case captured(EditableTextSnapshot)
    case unavailable
    case targetChanged
}

enum FocusedEditableRestoreResult: Sendable, Equatable {
    case restored
    case unavailable
    case targetChanged
    case textChanged
    case restoreFailed
}

enum FocusedElementInspector {
    private static let maximumVerificationTextLength = 1_000_000
    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
    ]

    static func hasEditableTextFocus() -> Bool {
        guard AXIsProcessTrusted(), let element = focusedElement() else {
            return false
        }
        return isEditableTextFocus(element)
    }

    static func hasEditableTextFocus(in launchAppContext: LaunchAppContext?) -> Bool {
        guard
            AXIsProcessTrusted(),
            let launchAppContext,
            launchAppContext.processIdentifier > 0,
            let expectedTarget = launchAppContext.focusedTarget,
            let element = focusedElement(in: launchAppContext.processIdentifier)
        else {
            return false
        }

        return matches(
            currentElement: element,
            expectedTarget: expectedTarget,
            processIdentifier: launchAppContext.processIdentifier
        )
    }

    static func captureTarget(in processIdentifier: pid_t) -> FocusedAXElementReference? {
        guard
            AXIsProcessTrusted(),
            processIdentifier > 0,
            let element = focusedElement(in: processIdentifier),
            isEditableTextFocus(element)
        else {
            return nil
        }

        let window = axElementAttributeValue(kAXWindowAttribute, on: element)
        return FocusedAXElementReference(
            processIdentifier: processIdentifier,
            element: element,
            window: window,
            identity: identity(for: element, window: window)
        )
    }

    static func capturePasteTarget(
        in launchAppContext: LaunchAppContext?
    ) -> FocusedEditableTargetCapture? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let element: AXUIElement
        let processIdentifier: pid_t
        if let launchAppContext {
            guard
                launchAppContext.processIdentifier > 0,
                let expectedTarget = launchAppContext.focusedTarget,
                let currentElement = focusedElement(in: launchAppContext.processIdentifier),
                matches(
                    currentElement: currentElement,
                    expectedTarget: expectedTarget,
                    processIdentifier: launchAppContext.processIdentifier
                )
            else {
                return nil
            }
            element = currentElement
            processIdentifier = launchAppContext.processIdentifier
        } else {
            guard
                let currentElement = focusedElement(),
                let currentProcessIdentifier = self.processIdentifier(of: currentElement),
                currentProcessIdentifier > 0,
                isEditableTextFocus(currentElement)
            else {
                return nil
            }
            element = currentElement
            processIdentifier = currentProcessIdentifier
        }

        let window = axElementAttributeValue(kAXWindowAttribute, on: element)
        let target = FocusedAXElementReference(
            processIdentifier: processIdentifier,
            element: element,
            window: window,
            identity: identity(for: element, window: window)
        )
        return FocusedEditableTargetCapture(
            target: target,
            editableTextSnapshot: editableTextSnapshot(from: element)
        )
    }

    static func captureEditableTextSnapshot(
        matching expectedTarget: FocusedAXElementReference
    ) -> FocusedEditableSnapshotCapture {
        guard
            AXIsProcessTrusted(),
            expectedTarget.processIdentifier > 0,
            let currentElement = focusedElement(),
            matches(
                currentElement: currentElement,
                expectedTarget: expectedTarget,
                processIdentifier: expectedTarget.processIdentifier
            )
        else {
            return .targetChanged
        }

        guard let snapshot = editableTextSnapshot(from: currentElement) else {
            return .unavailable
        }
        return .captured(snapshot)
    }

    static func restoreEditableTextSnapshot(
        _ before: EditableTextSnapshot,
        ifCurrentMatches expectedAfter: EditableTextSnapshot,
        matching expectedTarget: FocusedAXElementReference
    ) -> FocusedEditableRestoreResult {
        guard
            AXIsProcessTrusted(),
            expectedTarget.processIdentifier > 0,
            let currentElement = focusedElement(),
            matches(
                currentElement: currentElement,
                expectedTarget: expectedTarget,
                processIdentifier:
                    expectedTarget.processIdentifier
            )
        else {
            return .targetChanged
        }
        guard let current = editableTextSnapshot(
            from: currentElement
        ) else {
            return .unavailable
        }
        guard SafeUndoVerifier.canRestore(
            expectedAfter: expectedAfter,
            current: current,
            targetStillMatches: true
        ) else {
            return .textChanged
        }
        guard isAttributeSettable(
            kAXValueAttribute,
            on: currentElement
        ) else {
            return .unavailable
        }
        guard AXUIElementSetAttributeValue(
            currentElement,
            kAXValueAttribute as CFString,
            before.value as CFTypeRef
        ) == .success else {
            return .restoreFailed
        }

        if isAttributeSettable(
            kAXSelectedTextRangeAttribute,
            on: currentElement
        ) {
            var range = before.selectedRange
            if let value = AXValueCreate(.cfRange, &range) {
                _ = AXUIElementSetAttributeValue(
                    currentElement,
                    kAXSelectedTextRangeAttribute as CFString,
                    value
                )
            }
        }

        guard
            let restored = editableTextSnapshot(
                from: currentElement
            ),
            restored.value == before.value
        else {
            return .restoreFailed
        }
        return .restored
    }

    static func captureSelectionContext(
        in launchAppContext:
            LaunchAppContext?,
        maximumCharacters: Int
    ) -> SelectionContextCaptureResult {
        guard AXIsProcessTrusted() else {
            return .unavailable
        }

        // Prefer the launch-app process so mic/permission dialogs that briefly
        // front VibeWhisper do not make selection look "gone". Fall back to the
        // system-wide focused element when no launch context was captured.
        //
        // Intentionally do NOT require CFEqual against the launch-time target:
        // permission prompts rebuild AX proxies. The live focused control in the
        // launch app is what the user can still see selected.
        //
        // Selection capture is broader than paste-target capture: Word / Feishu
        // / Chromium contenteditable often focus AXGroup / AXWebArea / custom
        // roles that fail `isEditableTextFocus` but still expose AXSelectedText
        // (on the node or a nearby ancestor). Rejecting those as
        // `.targetChanged` / `.unavailable` blocks Context Rewrite before
        // recording even though the user clearly has a selection.

        if
            let launchAppContext,
            launchAppContext.processIdentifier > 0
        {
            if
                let currentElement = focusedElement(
                    in: launchAppContext.processIdentifier
                ),
                canExposeSelectionContext(currentElement)
            {
                return captureSelection(
                    from: currentElement,
                    processIdentifier: launchAppContext.processIdentifier,
                    maximumCharacters: maximumCharacters
                )
            }

            // Same process may surface focus on system-wide differently after
            // activation policy flips; try system-wide only when it still
            // points at the launch app.
            if
                let systemElement = focusedElement(),
                let systemPID = self.processIdentifier(of: systemElement),
                systemPID == launchAppContext.processIdentifier,
                canExposeSelectionContext(systemElement)
            {
                return captureSelection(
                    from: systemElement,
                    processIdentifier: systemPID,
                    maximumCharacters: maximumCharacters
                )
            }

            return launchAppContext.focusedTarget == nil
                ? .unavailable
                : .targetChanged
        }

        if
            let currentElement = focusedElement(),
            let currentPID = self.processIdentifier(of: currentElement),
            currentPID > 0,
            canExposeSelectionContext(currentElement)
        {
            return captureSelection(
                from: currentElement,
                processIdentifier: currentPID,
                maximumCharacters: maximumCharacters
            )
        }

        return .unavailable
    }

    /// Shared capture body once a candidate AX element has been resolved.
    private static func captureSelection(
        from resolvedElement: AXUIElement,
        processIdentifier: pid_t,
        maximumCharacters: Int
    ) -> SelectionContextCaptureResult {
        let boundedMaximum = Self.boundedSelectionMaximum(
            maximumCharacters
        )
        switch readSelectedTextWithSource(from: resolvedElement) {
        case .none:
            return .noSelection
        case .unavailable:
            return .unavailable
        case let .text(selectedText, selectedRange, sourceElement):
            guard selectedText.count <= boundedMaximum else {
                return .tooLarge(
                    actual: selectedText.count,
                    maximum: boundedMaximum
                )
            }
            // Rebind the node that actually exposed the selection (may be an
            // ancestor of the focused chrome) so replace verification and soft
            // identity stay on a stable selection-bearing element.
            let window = axElementAttributeValue(
                kAXWindowAttribute,
                on: sourceElement
            )
            let reboundTarget = FocusedAXElementReference(
                processIdentifier: processIdentifier,
                element: sourceElement,
                window: window,
                identity: identity(for: sourceElement, window: window)
            )
            return .captured(
                SelectionContextSnapshot(
                    target: reboundTarget,
                    selectedRange: selectedRange,
                    selectedText: selectedText,
                    textDigest: SelectionContextSnapshot.digest(
                        for: selectedText
                    )
                )
            )
        }
    }

    static func verifySelectionContext(
        _ expected:
            SelectionContextSnapshot
    ) -> SelectionContextVerification {
        guard
            AXIsProcessTrusted(),
            expected.target
                .processIdentifier > 0,
            let currentElement =
                focusedElement(
                    in: expected.target
                        .processIdentifier
                )
        else {
            return .changed
        }

        // Focus may sit on chrome while capture rebound to an ancestor that
        // actually exposed AXSelectedText. Walk the same short parent chain
        // used at capture time and accept the first soft-matching node (or any
        // node that still reports the same selected text).
        var node: AXUIElement? = currentElement
        for _ in 0..<6 {
            guard let candidate = node else { break }
            let sameProcess =
                self.processIdentifier(of: candidate)
                == expected.target.processIdentifier
            if sameProcess {
                let identityOK = softMatchesElement(
                    candidate,
                    expectedTarget: expected.target
                )
                switch readSelectedTextOnElement(candidate) {
                case .none:
                    if identityOK {
                        return .changed
                    }
                case .unavailable:
                    break
                case let .text(selectedText, selectedRange):
                    let rangeMatches =
                        selectedRange.location
                            == expected.selectedRange.location
                        && selectedRange.length
                            == expected.selectedRange.length
                    let digestMatches =
                        SelectionContextSnapshot.digest(for: selectedText)
                        == expected.textDigest
                    if digestMatches
                        && (rangeMatches
                            || expected.selectedRange.location < 0
                            || selectedText == expected.selectedText)
                    {
                        return .unchanged
                    }
                    // Identity matches but selection moved → treat as changed.
                    if identityOK {
                        return .changed
                    }
                }
            }
            node = axElementAttributeValue(
                kAXParentAttribute,
                on: candidate
            )
        }
        return .changed
    }

    /// Pure decision used by unit tests for selection size bounds.
    nonisolated static func boundedSelectionMaximum(
        _ maximumCharacters: Int
    ) -> Int {
        min(20_000, max(100, maximumCharacters))
    }

    /// Pure decision used by unit tests for soft AX identity matching.
    ///
    /// Exact `CFEqual` is preferred at the call site. When proxies are rebuilt
    /// after focus thrash, match on stable role/subrole/identifier/window hash
    /// instead of the transient `elementHash` (`CFHash` is not stable across
    /// re-created AX proxies for the same control).
    nonisolated static func identitiesMatch(
        _ current: FocusedTargetIdentity,
        _ expected: FocusedTargetIdentity
    ) -> Bool {
        if current.role != expected.role {
            return false
        }
        if current.subrole != expected.subrole {
            return false
        }
        if
            let expectedIdentifier = expected.identifier,
            !expectedIdentifier.isEmpty
        {
            guard current.identifier == expectedIdentifier else {
                return false
            }
        }
        if let expectedWindowHash = expected.windowHash {
            return current.windowHash == expectedWindowHash
        }
        return true
    }

    /// Pure helpers for selected-text extraction decisions (unit-tested).
    nonisolated static func selectedTextFromValueAndRange(
        value: String,
        selectedRange: CFRange
    ) -> String? {
        let nsValue = value as NSString
        guard
            selectedRange.location >= 0,
            selectedRange.length > 0,
            selectedRange.location <= nsValue.length,
            selectedRange.length
                <= nsValue.length - selectedRange.location
        else {
            return nil
        }
        return nsValue.substring(
            with: NSRange(
                location: selectedRange.location,
                length: selectedRange.length
            )
        )
    }

    nonisolated static func preferredSelectedText(
        valueAndRangeText: String?,
        attributeText: String?
    ) -> String? {
        if
            let valueAndRangeText,
            !valueAndRangeText.isEmpty
        {
            return valueAndRangeText
        }
        if
            let attributeText,
            !attributeText.isEmpty
        {
            return attributeText
        }
        return nil
    }

    static func isCurrentTarget(_ expectedTarget: FocusedAXElementReference) -> Bool {
        guard
            AXIsProcessTrusted(),
            expectedTarget.processIdentifier > 0,
            let currentElement = focusedElement()
        else {
            return false
        }

        return matches(
            currentElement: currentElement,
            expectedTarget: expectedTarget,
            processIdentifier: expectedTarget.processIdentifier
        )
    }

    static func isEditableTextFocus(_ element: AXUIElement) -> Bool {
        let role = attributeValue(kAXRoleAttribute, on: element) as? String
        let subrole = attributeValue(kAXSubroleAttribute, on: element) as? String
        let enabled = attributeValue(kAXEnabledAttribute, on: element) as? Bool
        let hidden = attributeValue(kAXHiddenAttribute, on: element) as? Bool
        let valueIsSettable = isAttributeSettable(kAXValueAttribute, on: element)
        let selectionIsSettable = isAttributeSettable(
            kAXSelectedTextRangeAttribute,
            on: element
        )
        return isEditableTextFocusDecision(
            role: role,
            subrole: subrole,
            enabled: enabled,
            hidden: hidden,
            valueIsSettable: valueIsSettable,
            selectionIsSettable: selectionIsSettable
        )
    }

    /// Pure decision used by `isEditableTextFocus` and unit tests.
    ///
    /// Known text roles (field / area / combo box) are treated as paste targets
    /// even when the host does not mark `AXValue` or `AXSelectedTextRange` as
    /// settable. Ghostty is the canonical case: it exposes a focused
    /// `AXTextArea` with readable value/range, but both attributes report
    /// non-settable, so the older gate fell through to clipboard-only while
    /// `Cmd+V` still works. Custom non-text roles still require both attributes
    /// to be settable so random focused chrome is not treated as an editor.
    nonisolated static func isEditableTextFocusDecision(
        role: String?,
        subrole: String?,
        enabled: Bool?,
        hidden: Bool?,
        valueIsSettable: Bool,
        selectionIsSettable: Bool
    ) -> Bool {
        if enabled == false {
            return false
        }
        if hidden == true {
            return false
        }
        if subrole == "AXSecureTextField" {
            return false
        }

        let hasTextRole = role.map(textRoles.contains) ?? false
        if hasTextRole {
            return true
        }
        return valueIsSettable && selectionIsSettable
    }

    /// Pure decision used by selection-context capture and unit tests.
    ///
    /// Broader than paste-target editability: Word / Feishu / Chromium
    /// contenteditable frequently focus `AXGroup` / `AXWebArea` / custom roles
    /// that do not mark AXValue settable, yet still publish `AXSelectedText` or
    /// value+range for the highlighted selection. Rejecting those blocked
    /// Context Rewrite before recording while the user could clearly see a
    /// selection.
    nonisolated static func canExposeSelectionContextDecision(
        role: String?,
        subrole: String?,
        enabled: Bool?,
        hidden: Bool?,
        valueIsSettable: Bool,
        selectionIsSettable: Bool,
        hasReadableSelectedText: Bool,
        hasValueAndRangeSelection: Bool
    ) -> Bool {
        if hidden == true {
            return false
        }
        if subrole == "AXSecureTextField" {
            return false
        }
        // Selection capture is read-only. Word compatibility-mode document
        // nodes commonly publish AXEnabled=false while still exposing a real
        // AXSelectedText / value+range selection. Accept the concrete
        // selection signal before applying the editability-only enabled gate.
        if hasReadableSelectedText || hasValueAndRangeSelection {
            return true
        }
        if enabled == false {
            return false
        }
        if isEditableTextFocusDecision(
            role: role,
            subrole: subrole,
            enabled: enabled,
            hidden: hidden,
            valueIsSettable: valueIsSettable,
            selectionIsSettable: selectionIsSettable
        ) {
            return true
        }
        // Non-text roles that already expose a selection are valid rewrite
        // targets. Do not accept bare chrome with no selection surface.
        return false
    }

    /// Whether this focused AX element can participate in selection capture.
    static func canExposeSelectionContext(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let node = current else { break }
            let role = attributeValue(kAXRoleAttribute, on: node) as? String
            let subrole = attributeValue(kAXSubroleAttribute, on: node) as? String
            let enabled = attributeValue(kAXEnabledAttribute, on: node) as? Bool
            let hidden = attributeValue(kAXHiddenAttribute, on: node) as? Bool
            let valueIsSettable = isAttributeSettable(kAXValueAttribute, on: node)
            let selectionIsSettable = isAttributeSettable(
                kAXSelectedTextRangeAttribute,
                on: node
            )
            let attributeText = selectedTextAttribute(on: node)
            let hasReadableSelectedText =
                attributeText.map { !$0.isEmpty } ?? false
            let hasValueAndRangeSelection: Bool = {
                guard let snapshot = editableTextSnapshot(from: node) else {
                    return false
                }
                return snapshot.selectedRange.length > 0
            }()
            if canExposeSelectionContextDecision(
                role: role,
                subrole: subrole,
                enabled: enabled,
                hidden: hidden,
                valueIsSettable: valueIsSettable,
                selectionIsSettable: selectionIsSettable,
                hasReadableSelectedText: hasReadableSelectedText,
                hasValueAndRangeSelection: hasValueAndRangeSelection
            ) {
                return true
            }
            current = axElementAttributeValue(
                kAXParentAttribute,
                on: node
            )
        }
        return false
    }

    private static func matches(
        currentElement: AXUIElement,
        expectedTarget: FocusedAXElementReference,
        processIdentifier expectedProcessIdentifier: pid_t
    ) -> Bool {
        guard
            self.processIdentifier(of: currentElement) == expectedProcessIdentifier,
            isEditableTextFocus(currentElement)
        else {
            return false
        }
        return softMatchesElement(
            currentElement,
            expectedTarget: expectedTarget
        )
    }

    private static func softMatchesElement(
        _ currentElement: AXUIElement,
        expectedTarget: FocusedAXElementReference
    ) -> Bool {
        // Prefer exact CFEqual when the host keeps a stable proxy. After focus
        // thrash (permission dialogs, overlays), proxies are often rebuilt and
        // CFEqual fails even though the user is still in the same editor — fall
        // back to role/subrole/identifier/window identity.
        if CFEqual(currentElement, expectedTarget.element) {
            // Element proxy matches; do not require window proxy CFEqual —
            // window refs also go stale while the control stays focused.
            return true
        }

        let currentWindow = axElementAttributeValue(
            kAXWindowAttribute,
            on: currentElement
        )
        let currentIdentity = identity(
            for: currentElement,
            window: currentWindow
        )
        return identitiesMatch(currentIdentity, expectedTarget.identity)
    }

    private enum SelectedTextRead {
        case none
        case unavailable
        case text(String, CFRange)
    }

    private enum SelectedTextReadWithSource {
        case none
        case unavailable
        case text(String, CFRange, AXUIElement)
    }

    /// Read the current selection from an AX element.
    ///
    /// Order of preference:
    /// 1. `AXValue` + `AXSelectedTextRange` (stable range for replace verification)
    /// 2. `AXSelectedText` alone (Chromium/Electron often expose this without a
    ///    usable full value or range)
    /// 3. Walk up to a few ancestors (Word / Feishu sometimes put focus on a
    ///    child chrome node while `AXSelectedText` lives on a parent document
    ///    container)
    private static func readSelectedText(
        from element: AXUIElement
    ) -> SelectedTextRead {
        switch readSelectedTextWithSource(from: element) {
        case .none:
            return .none
        case .unavailable:
            return .unavailable
        case let .text(text, range, _):
            return .text(text, range)
        }
    }

    private static func readSelectedTextWithSource(
        from element: AXUIElement
    ) -> SelectedTextReadWithSource {
        var current: AXUIElement? = element
        var sawEditableSnapshot = false
        // Bound ancestor walk — enough for document chrome nesting, not a full
        // tree scan (keeps capture cheap and side-effect free).
        for _ in 0..<6 {
            guard let node = current else { break }
            switch readSelectedTextOnElement(node) {
            case .text(let text, let range):
                return .text(text, range, node)
            case .none:
                // Caret with no selection on this node — keep walking; parent
                // may still hold the real document selection.
                sawEditableSnapshot = true
            case .unavailable:
                break
            }
            current = axElementAttributeValue(
                kAXParentAttribute,
                on: node
            )
        }

        if sawEditableSnapshot {
            return .none
        }
        // Element claims to be editable but yields neither value nor selected
        // text. Treat as unavailable so required-selection Skills block cleanly.
        return .unavailable
    }

    private static func readSelectedTextOnElement(
        _ element: AXUIElement
    ) -> SelectedTextRead {
        if let snapshot = editableTextSnapshot(from: element) {
            if snapshot.selectedRange.length <= 0 {
                // Zero-length caret: also check AXSelectedText in case the host
                // reports a collapsed range while still exposing selected text.
                if
                    let attributeText = selectedTextAttribute(on: element),
                    !attributeText.isEmpty
                {
                    return .text(
                        attributeText,
                        CFRange(
                            location: -1,
                            length: (attributeText as NSString).length
                        )
                    )
                }
                return .none
            }
            if let text = selectedText(from: snapshot), !text.isEmpty {
                return .text(text, snapshot.selectedRange)
            }
        }

        if
            let attributeText = selectedTextAttribute(on: element),
            !attributeText.isEmpty
        {
            // No reliable range — use a sentinel location so verification can
            // fall back to digest-only comparison.
            return .text(
                attributeText,
                CFRange(
                    location: -1,
                    length: (attributeText as NSString).length
                )
            )
        }

        if editableTextSnapshot(from: element) != nil {
            return .none
        }
        return .unavailable
    }

    private static func selectedTextAttribute(
        on element: AXUIElement
    ) -> String? {
        guard
            let rawValue = attributeValue(
                kAXSelectedTextAttribute as String,
                on: element
            )
        else {
            return nil
        }
        return textValue(from: rawValue)
    }

    private static func focusedElement(in processIdentifier: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedElement: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard
            status == .success,
            let focusedElement,
            CFGetTypeID(focusedElement) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(focusedElement, to: AXUIElement.self)
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard
            status == .success,
            let focusedElement,
            CFGetTypeID(focusedElement) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(focusedElement, to: AXUIElement.self)
    }

    private static func processIdentifier(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return nil
        }
        return pid
    }

    private static func identity(
        for element: AXUIElement,
        window: AXUIElement?
    ) -> FocusedTargetIdentity {
        FocusedTargetIdentity(
            elementHash: UInt64(CFHash(element)),
            role: attributeValue(kAXRoleAttribute, on: element) as? String,
            subrole: attributeValue(kAXSubroleAttribute, on: element) as? String,
            identifier: attributeValue(kAXIdentifierAttribute, on: element) as? String,
            windowHash: window.map { UInt64(CFHash($0)) }
        )
    }

    private static func editableTextSnapshot(
        from element: AXUIElement
    ) -> EditableTextSnapshot? {
        guard
            let rawValue = attributeValue(kAXValueAttribute, on: element),
            let value = textValue(from: rawValue),
            let selectedRange = selectedTextRange(on: element)
        else {
            return nil
        }

        let utf16Length = (value as NSString).length
        guard
            utf16Length <= maximumVerificationTextLength,
            selectedRange.location >= 0,
            selectedRange.length >= 0,
            selectedRange.location <= utf16Length,
            selectedRange.length <= utf16Length - selectedRange.location
        else {
            return nil
        }

        return EditableTextSnapshot(
            value: value,
            selectedRange: selectedRange
        )
    }

    private static func selectedText(
        from snapshot:
            EditableTextSnapshot
    ) -> String? {
        let value =
            snapshot.value as NSString
        let range = snapshot.selectedRange
        guard
            range.location >= 0,
            range.length >= 0,
            range.location <= value.length,
            range.length
                <= value.length
                    - range.location
        else {
            return nil
        }
        return value.substring(
            with: NSRange(
                location:
                    range.location,
                length:
                    range.length
            )
        )
    }

    private static func textValue(from rawValue: CFTypeRef) -> String? {
        if let value = rawValue as? String {
            return value
        }
        if let value = rawValue as? NSAttributedString {
            return value.string
        }
        return nil
    }

    private static func selectedTextRange(on element: AXUIElement) -> CFRange? {
        guard
            let rawRange = attributeValue(kAXSelectedTextRangeAttribute, on: element),
            CFGetTypeID(rawRange) == AXValueGetTypeID()
        else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        // CFTypeID already verified above; bridge without force-cast.
        let axValue = unsafeBitCast(rawRange, to: AXValue.self)
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private static func attributeValue(
        _ attribute: String,
        on element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func axElementAttributeValue(
        _ attribute: String,
        on element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        guard
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func isAttributeSettable(
        _ attribute: String,
        on element: AXUIElement
    ) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &settable
        ) == .success && settable.boolValue
    }
}
