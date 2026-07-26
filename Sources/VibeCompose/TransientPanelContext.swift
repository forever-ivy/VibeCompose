import AppKit
import ApplicationServices

struct TransientPanelScreen: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

enum TransientPanelPlacement {
    static func preferredScreen(
        focusedWindowFrame: CGRect?,
        screens: [TransientPanelScreen],
        fallback: TransientPanelScreen?
    ) -> TransientPanelScreen? {
        guard let focusedWindowFrame else {
            return fallback ?? screens.first
        }

        let bestMatch = screens.max { lhs, rhs in
            intersectionArea(lhs.frame, focusedWindowFrame)
                < intersectionArea(rhs.frame, focusedWindowFrame)
        }
        guard let bestMatch,
              intersectionArea(bestMatch.frame, focusedWindowFrame) > 0
        else {
            return fallback ?? screens.first
        }
        return bestMatch
    }

    static func shouldReuseSavedFrame(
        _ savedFrame: CGRect,
        on screen: TransientPanelScreen
    ) -> Bool {
        let intersection = savedFrame.intersection(screen.visibleFrame)
        return intersection.width > 8 && intersection.height > 8
    }

    private static func intersectionArea(
        _ lhs: CGRect,
        _ rhs: CGRect
    ) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}

enum TransientPanelKeyRouting {
    private static let panelCommandKeyCodes: Set<UInt16> = [
        53, // Escape
        125, // Down arrow
        126, // Up arrow
        36, // Return
        76, // Keypad Enter
    ]

    /// Panel chrome (↑/↓/↩/Esc) must not steal keys while the input method owns
    /// marked/preedit text — otherwise Chinese IME arrows and commit never land.
    static func shouldHandlePanelCommand(
        keyCode: UInt16,
        hasMarkedText: Bool
    ) -> Bool {
        panelCommandKeyCodes.contains(keyCode) && !hasMarkedText
    }

    /// Esc mapped to `cancelOperation:` must also defer to the IME so composition
    /// can be cancelled without dismissing the whole panel.
    static func shouldDismissOnCancelOperation(hasMarkedText: Bool) -> Bool {
        !hasMarkedText
    }

    @MainActor
    static func inputMethodHasMarkedText(in window: NSWindow) -> Bool {
        // Walk the responder chain: SwiftUI TextField often sits behind a field
        // editor or intermediate responder that is not itself the input client.
        var responder = window.firstResponder
        while let current = responder {
            if let inputClient = current as? NSTextInputClient,
               inputClient.hasMarkedText()
            {
                return true
            }
            responder = current.nextResponder
        }
        return false
    }
}

@MainActor
struct TransientPanelPresentationContext {
    let restoreTarget: LaunchAppContext?
    let screen: TransientPanelScreen?

    static func capture() -> TransientPanelPresentationContext {
        let screens = NSScreen.screens.map {
            TransientPanelScreen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let fallback = NSScreen.main.map {
            TransientPanelScreen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let screen = TransientPanelPlacement.preferredScreen(
            focusedWindowFrame: focusedWindowFrame(),
            screens: screens,
            fallback: fallback
        )
        return TransientPanelPresentationContext(
            restoreTarget: LaunchAppContext.externalFrontmostForTransientRestore(),
            screen: screen
        )
    }

    private static func focusedWindowFrame() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedApplicationValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApplicationValue
        ) == .success,
        let focusedApplicationValue,
        CFGetTypeID(focusedApplicationValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedApplication = unsafeDowncast(
            focusedApplicationValue as AnyObject,
            to: AXUIElement.self
        )
        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedApplication,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindowValue,
        CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedWindow = unsafeDowncast(
            focusedWindowValue as AnyObject,
            to: AXUIElement.self
        )
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedWindow,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            focusedWindow,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(
            unsafeDowncast(positionValue as AnyObject, to: AXValue.self),
            .cgPoint,
            &position
        ),
        AXValueGetValue(
            unsafeDowncast(sizeValue as AnyObject, to: AXValue.self),
            .cgSize,
            &size
        ),
        size.width > 0,
        size.height > 0
        else {
            return nil
        }

        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGRect(
            x: position.x,
            y: desktopTop - position.y - size.height,
            width: size.width,
            height: size.height
        )
    }
}
