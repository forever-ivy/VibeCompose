import CoreGraphics
import Foundation

let appName = CommandLine.arguments.dropFirst().first ?? "VibeWhisper"
let timeoutSeconds = CommandLine.arguments.dropFirst(2).first.flatMap(Double.init) ?? 5
let deadline = Date().addingTimeInterval(timeoutSeconds)

func visibleWindowID(for appName: String) -> Int? {
    let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] ?? []

    for window in windows {
        guard
            (window[kCGWindowOwnerName as String] as? String) == appName,
            let alpha = window[kCGWindowAlpha as String] as? Double,
            alpha > 0,
            let bounds = window[kCGWindowBounds as String] as? [String: Any],
            let width = bounds["Width"] as? Double,
            let height = bounds["Height"] as? Double,
            width > 0,
            height > 0,
            let windowID = window[kCGWindowNumber as String] as? Int
        else {
            continue
        }

        return windowID
    }

    return nil
}

while Date() < deadline {
    if let windowID = visibleWindowID(for: appName) {
        print(windowID)
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.1)
}

exit(1)
