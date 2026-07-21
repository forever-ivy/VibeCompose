#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

struct WindowActivationEvidence: Codable {
    let bundleIdentifier: String
    let activationPolicyBeforeMinimize: Int
    let iconPresent: Bool
    let minimizeActionResult: Int32
    let minimized: Bool
    let restored: Bool
    let closeActionResult: Int32
    let regularAfterClose: Bool
}

func copyAXValue(
    _ element: AXUIElement,
    _ attribute: String
) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
    ) == .success else {
        return nil
    }
    return value
}

func axBoolean(
    _ element: AXUIElement,
    _ attribute: String
) -> Bool? {
    copyAXValue(element, attribute) as? Bool
}

func waitUntil(
    timeout: TimeInterval = 5,
    condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() {
            return true
        }
        Thread.sleep(forTimeInterval: 0.05)
    } while Date() < deadline
    return condition()
}

guard CommandLine.arguments.count == 3 else {
    fputs(
        "Usage: verify_window_activation.swift <bundle-id> <output-json>\n",
        stderr
    )
    exit(64)
}

let bundleIdentifier = CommandLine.arguments[1]
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let runningApplication = NSRunningApplication
    .runningApplications(
        withBundleIdentifier: bundleIdentifier
    )
    .first
else {
    fputs("OpenWhisper is not running\n", stderr)
    exit(1)
}

let applicationElement = AXUIElementCreateApplication(
    runningApplication.processIdentifier
)
guard
    waitUntil(condition: {
        guard let windows = copyAXValue(
            applicationElement,
            kAXWindowsAttribute
        ) as? [AXUIElement] else {
            return false
        }
        return !windows.isEmpty
    }),
    let windows = copyAXValue(
        applicationElement,
        kAXWindowsAttribute
    ) as? [AXUIElement],
    let window = windows.first
else {
    fputs("OpenWhisper Settings window is missing\n", stderr)
    exit(1)
}

let initialPolicy = runningApplication.activationPolicy
let iconPresent = runningApplication.icon != nil
guard let minimizeButton = copyAXValue(
    window,
    kAXMinimizeButtonAttribute
) else {
    fputs("Settings minimize button is missing\n", stderr)
    exit(1)
}

let minimizeResult = AXUIElementPerformAction(
    minimizeButton as! AXUIElement,
    kAXPressAction as CFString
)
let minimized = waitUntil {
    axBoolean(window, kAXMinimizedAttribute) == true
}

let restoreResult = AXUIElementSetAttributeValue(
    window,
    kAXMinimizedAttribute as CFString,
    kCFBooleanFalse
)
let restored = restoreResult == .success && waitUntil {
    axBoolean(window, kAXMinimizedAttribute) == false
}

guard let closeButton = copyAXValue(
    window,
    kAXCloseButtonAttribute
) else {
    fputs("Settings close button is missing\n", stderr)
    exit(1)
}
let closeResult = AXUIElementPerformAction(
    closeButton as! AXUIElement,
    kAXPressAction as CFString
)
let regularAfterClose = waitUntil {
    runningApplication.activationPolicy == .regular
}

let evidence = WindowActivationEvidence(
    bundleIdentifier: bundleIdentifier,
    activationPolicyBeforeMinimize: initialPolicy.rawValue,
    iconPresent: iconPresent,
    minimizeActionResult: minimizeResult.rawValue,
    minimized: minimized,
    restored: restored,
    closeActionResult: closeResult.rawValue,
    regularAfterClose: regularAfterClose
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(evidence).write(
    to: outputURL,
    options: .atomic
)

guard
    initialPolicy == .regular,
    iconPresent,
    minimizeResult == .success,
    minimized,
    restored,
    closeResult == .success,
    regularAfterClose
else {
    fputs("OpenWhisper window activation acceptance failed\n", stderr)
    exit(1)
}

print("OpenWhisper Dock icon and minimize acceptance passed.")
