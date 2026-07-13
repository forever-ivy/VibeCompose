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

    static func captureSelectionContext(
        in launchAppContext:
            LaunchAppContext?,
        maximumCharacters: Int
    ) -> SelectionContextCaptureResult {
        guard
            AXIsProcessTrusted(),
            let launchAppContext,
            launchAppContext
                .processIdentifier > 0,
            let expectedTarget =
                launchAppContext.focusedTarget,
            let currentElement =
                focusedElement(
                    in: launchAppContext
                        .processIdentifier
                ),
            matches(
                currentElement:
                    currentElement,
                expectedTarget:
                    expectedTarget,
                processIdentifier:
                    launchAppContext
                        .processIdentifier
            )
        else {
            return launchAppContext?
                .focusedTarget == nil
                ? .unavailable
                : .targetChanged
        }

        guard
            let snapshot =
                editableTextSnapshot(
                    from: currentElement
                )
        else {
            return .unavailable
        }
        guard
            snapshot.selectedRange.length > 0
        else {
            return .noSelection
        }
        guard
            let selectedText =
                selectedText(
                    from: snapshot
                )
        else {
            return .unavailable
        }

        let boundedMaximum =
            min(
                20_000,
                max(
                    100,
                    maximumCharacters
                )
            )
        guard selectedText.count
            <= boundedMaximum
        else {
            return .tooLarge(
                actual:
                    selectedText.count,
                maximum:
                    boundedMaximum
            )
        }

        return .captured(
            SelectionContextSnapshot(
                target: expectedTarget,
                selectedRange:
                    snapshot
                        .selectedRange,
                selectedText:
                    selectedText,
                textDigest:
                    SelectionContextSnapshot
                        .digest(
                            for:
                                selectedText
                        )
            )
        )
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
                ),
            matches(
                currentElement:
                    currentElement,
                expectedTarget:
                    expected.target,
                processIdentifier:
                    expected.target
                        .processIdentifier
            )
        else {
            return .changed
        }

        guard
            let snapshot =
                editableTextSnapshot(
                    from: currentElement
                ),
            let selectedText =
                selectedText(
                    from: snapshot
                )
        else {
            return .unavailable
        }

        guard
            snapshot.selectedRange.location
                == expected
                    .selectedRange.location,
            snapshot.selectedRange.length
                == expected
                    .selectedRange.length,
            SelectionContextSnapshot.digest(
                for: selectedText
            ) == expected.textDigest
        else {
            return .changed
        }
        return .unchanged
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
        if let enabled = attributeValue(kAXEnabledAttribute, on: element) as? Bool,
           !enabled {
            return false
        }
        if let hidden = attributeValue(kAXHiddenAttribute, on: element) as? Bool,
           hidden {
            return false
        }
        if let subrole = attributeValue(kAXSubroleAttribute, on: element) as? String,
           subrole == "AXSecureTextField" {
            return false
        }

        let role = attributeValue(kAXRoleAttribute, on: element) as? String
        let hasTextRole = role.map(textRoles.contains) ?? false
        let valueIsSettable = isAttributeSettable(kAXValueAttribute, on: element)
        let selectionIsSettable = isAttributeSettable(kAXSelectedTextRangeAttribute, on: element)

        if hasTextRole {
            return valueIsSettable || selectionIsSettable
        }
        return valueIsSettable && selectionIsSettable
    }

    private static func matches(
        currentElement: AXUIElement,
        expectedTarget: FocusedAXElementReference,
        processIdentifier expectedProcessIdentifier: pid_t
    ) -> Bool {
        guard
            self.processIdentifier(of: currentElement) == expectedProcessIdentifier,
            isEditableTextFocus(currentElement),
            CFEqual(currentElement, expectedTarget.element)
        else {
            return false
        }

        if let expectedWindow = expectedTarget.window,
           let currentWindow = axElementAttributeValue(kAXWindowAttribute, on: currentElement) {
            return CFEqual(expectedWindow, currentWindow)
        }

        return expectedTarget.window == nil
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
        guard AXValueGetValue(rawRange as! AXValue, .cfRange, &range) else {
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
