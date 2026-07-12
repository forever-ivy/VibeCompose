import Foundation

enum OverlayDemoState: String, Equatable, Sendable, CaseIterable {
    case recording
    case processing
    case result
    case error
    case retryableError = "retryable-error"
}

enum AppLaunchMode: Equatable {
    case normal
    case settings
    case accessibilityGuide
    case overlayDemo
    case overlayDemoState(OverlayDemoState)
    case benchmark

    static func resolve(
        environment: [String: String],
        arguments: [String] = []
    ) -> AppLaunchMode {
        let benchmarkValue = environment["OPENWHISPER_BENCHMARK"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch benchmarkValue {
        case "1", "true", "yes", "benchmark":
            return .benchmark
        default:
            break
        }

        if arguments.contains("--guide-accessibility") {
            return .accessibilityGuide
        }

        if arguments.contains("--settings") || arguments.contains("--open-settings") {
            return .settings
        }

        if let state = overlayDemoState(environment: environment, arguments: arguments) {
            return .overlayDemoState(state)
        }

        if arguments.contains("--overlay-demo") || arguments.contains("--openwhisper-overlay-demo") {
            return .overlayDemo
        }

        let rawValue = environment["OPENWHISPER_OVERLAY_DEMO"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch rawValue {
        case "1", "true", "yes", "demo":
            return .overlayDemo
        default:
            return .normal
        }
    }

    private static func overlayDemoState(
        environment: [String: String],
        arguments: [String]
    ) -> OverlayDemoState? {
        if let rawState = environment["OPENWHISPER_OVERLAY_DEMO_STATE"],
           let state = OverlayDemoState(rawValue: rawState.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return state
        }

        for (index, argument) in arguments.enumerated() {
            if argument == "--overlay-demo-state", index + 1 < arguments.count {
                return OverlayDemoState(rawValue: arguments[index + 1])
            }

            if argument.hasPrefix("--overlay-demo-state=") {
                let rawState = String(argument.dropFirst("--overlay-demo-state=".count))
                return OverlayDemoState(rawValue: rawState)
            }
        }

        return nil
    }
}
