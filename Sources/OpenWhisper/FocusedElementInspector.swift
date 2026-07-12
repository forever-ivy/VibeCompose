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
    let element: AXUIElement
    let window: AXUIElement?
    let identity: FocusedTargetIdentity

    init(
        element: AXUIElement,
        window: AXUIElement?,
        identity: FocusedTargetIdentity
    ) {
        self.element = element
        self.window = window
        self.identity = identity
    }
}

enum FocusedElementInspector {
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
            element: element,
            window: window,
            identity: identity(for: element, window: window)
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
        guard status == .success, let focusedElement else {
            return nil
        }
        return focusedElement as! AXUIElement
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard status == .success, let focusedElement else {
            return nil
        }
        return focusedElement as! AXUIElement
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
        guard let value else {
            return nil
        }
        return value as! AXUIElement
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
