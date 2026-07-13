import Foundation

enum OverlayDemoState: String, Equatable, Sendable, CaseIterable {
    case recording
    case processing
    case result
    case pasteSent = "paste-sent"
    case copied
    case error
    case retryableError = "retryable-error"
}

struct SettingsSnapshotSize: Equatable, Sendable {
    let width: Int
    let height: Int
}

enum AppLaunchMode: Equatable {
    case normal
    case settings
    case privacySettings
    case advancedSettings
    case accessibilityGuide
    case onboarding
    case history
    case terminology
    case quickAdd
    case overlayDemo
    case overlayDemoState(OverlayDemoState)
    case pasteAcceptance
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

        if settingsSnapshotOutputURL(
            environment: environment,
            arguments: arguments
        ) != nil {
            if requestedSettingsPane(arguments: arguments) == "privacy" {
                return .privacySettings
            }
            if requestedSettingsPane(arguments: arguments) == "advanced" {
                return .advancedSettings
            }
            return .settings
        }

        if arguments.contains("--guide-accessibility") {
            return .accessibilityGuide
        }

        if arguments.contains("--onboarding") || arguments.contains("--open-onboarding") {
            return .onboarding
        }

        if arguments.contains("--history") || arguments.contains("--open-history") {
            return .history
        }

        if arguments.contains("--terminology") || arguments.contains("--open-terminology") {
            return .terminology
        }

        if arguments.contains("--quick-add") || arguments.contains("--open-quick-add") {
            return .quickAdd
        }

        if requestedSettingsPane(arguments: arguments) == "privacy" {
            return .privacySettings
        }
        if requestedSettingsPane(arguments: arguments) == "advanced" {
            return .advancedSettings
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

        if arguments.contains("--paste-acceptance") {
            return .pasteAcceptance
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

    static func visualAcceptanceOutputURL(
        environment: [String: String],
        arguments: [String] = []
    ) -> URL? {
        if let value = environment["OPENWHISPER_VISUAL_ACCEPTANCE_OUTPUT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return URL(fileURLWithPath: value)
        }

        for (index, argument) in arguments.enumerated() {
            if argument == "--visual-acceptance-output", index + 1 < arguments.count {
                let value = arguments[index + 1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : URL(fileURLWithPath: value)
            }

            if argument.hasPrefix("--visual-acceptance-output=") {
                let value = String(
                    argument.dropFirst("--visual-acceptance-output=".count)
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : URL(fileURLWithPath: value)
            }
        }

        return nil
    }

    static func visualAcceptanceFollowupOutputURL(
        environment: [String: String],
        arguments: [String] = []
    ) -> URL? {
        productSurfaceSnapshotOutputURL(
            environment: environment,
            arguments: arguments,
            environmentKey: "OPENWHISPER_VISUAL_ACCEPTANCE_FOLLOWUP_OUTPUT",
            argumentName: "--visual-acceptance-followup-output"
        )
    }

    static func feedbackSurfaceDebugOutputURL(
        environment: [String: String],
        arguments: [String] = []
    ) -> URL? {
        productSurfaceSnapshotOutputURL(
            environment: environment,
            arguments: arguments,
            environmentKey:
                "OPENWHISPER_FEEDBACK_SURFACE_DEBUG_OUTPUT",
            argumentName:
                "--feedback-surface-debug-output"
        )
    }

    static func visualFeedbackModeOverride(
        environment: [String: String],
        arguments: [String] = []
    ) -> VisualFeedbackMode? {
        for (index, argument) in arguments
            .enumerated()
        {
            if argument
                == "--visual-feedback-mode",
               index + 1 < arguments.count
            {
                return VisualFeedbackMode
                    .fromLaunchValue(
                        arguments[index + 1]
                    )
            }

            let prefix =
                "--visual-feedback-mode="
            if argument.hasPrefix(prefix) {
                return VisualFeedbackMode
                    .fromLaunchValue(
                        String(
                            argument.dropFirst(
                                prefix.count
                            )
                        )
                    )
            }
        }

        guard
            let rawValue = environment[
                "OPENWHISPER_VISUAL_FEEDBACK_MODE"
            ]
        else {
            return nil
        }
        return VisualFeedbackMode
            .fromLaunchValue(rawValue)
    }

    static func visualAcceptanceDisplayOptionsOverride(
        environment: [String: String],
        arguments: [String] = []
    ) -> AccessibilityDisplayOptionsOverride {
        AccessibilityDisplayOptionsOverride(
            reduceMotion: optionalBooleanLaunchValue(
                environment: environment,
                arguments: arguments,
                environmentKey: "OPENWHISPER_VISUAL_ACCEPTANCE_REDUCE_MOTION",
                argumentName: "--visual-acceptance-reduce-motion"
            ),
            increaseContrast: optionalBooleanLaunchValue(
                environment: environment,
                arguments: arguments,
                environmentKey: "OPENWHISPER_VISUAL_ACCEPTANCE_INCREASE_CONTRAST",
                argumentName: "--visual-acceptance-increase-contrast"
            )
        )
    }

    static func pasteAcceptanceOutputURL(
        environment: [String: String],
        arguments: [String] = []
    ) -> URL? {
        if let value = environment["OPENWHISPER_PASTE_ACCEPTANCE_OUTPUT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return URL(fileURLWithPath: value)
        }

        for (index, argument) in arguments.enumerated() {
            if argument == "--paste-acceptance-output",
               index + 1 < arguments.count {
                let value = arguments[index + 1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : URL(fileURLWithPath: value)
            }
            if argument.hasPrefix("--paste-acceptance-output=") {
                let value = String(
                    argument.dropFirst("--paste-acceptance-output=".count)
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : URL(fileURLWithPath: value)
            }
        }
        return nil
    }

    static func pasteAcceptanceTarget(
        environment: [String: String],
        arguments: [String] = []
    ) -> PasteAcceptanceTarget? {
        if let value = environment[
            "OPENWHISPER_PASTE_ACCEPTANCE_TARGET"
        ]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased(),
            !value.isEmpty
        {
            return PasteAcceptanceTarget(rawValue: value)
        }

        for (index, argument) in arguments.enumerated() {
            if argument == "--paste-acceptance-target",
               index + 1 < arguments.count {
                let value = arguments[index + 1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return PasteAcceptanceTarget(rawValue: value)
            }
            if argument.hasPrefix("--paste-acceptance-target=") {
                let value = String(
                    argument.dropFirst(
                        "--paste-acceptance-target=".count
                    )
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                return PasteAcceptanceTarget(rawValue: value)
            }
        }
        return .textEdit
    }

    static func accessibilityAuditOutputURL(
        environment: [String: String],
        arguments: [String] = []
    ) -> URL? {
        productSurfaceSnapshotOutputURL(
            environment: environment,
            arguments: arguments,
            environmentKey: "OPENWHISPER_ACCESSIBILITY_AUDIT_OUTPUT",
            argumentName: "--accessibility-audit-output"
        )
    }

    static func interactionAcceptanceRequested(
        environment: [String: String],
        arguments: [String] = []
    ) -> Bool {
        let environmentValue = environment[
            "OPENWHISPER_INTERACTION_ACCEPTANCE"
        ]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        if ["1", "true", "yes", "acceptance"].contains(
            environmentValue ?? ""
        ) {
            return true
        }

        return arguments.contains("--interaction-acceptance")
            || arguments.contains("--private-acceptance")
    }

    static func settingsPane(arguments: [String]) -> SettingsPane? {
        requestedSettingsPane(arguments: arguments)
            .flatMap(SettingsPane.fromLaunchArgument)
    }

    static func onboardingStep(arguments: [String]) -> OnboardingStep? {
        requestedOnboardingStep(arguments: arguments)
            .flatMap(OnboardingStep.fromLaunchArgument)
    }

    static func settingsSnapshotOutputURL(
        environment: [String: String],
        arguments: [String] = []
    ) -> URL? {
        if let value = environment["OPENWHISPER_SETTINGS_SNAPSHOT_OUTPUT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return URL(fileURLWithPath: value)
        }

        for (index, argument) in arguments.enumerated() {
            if argument == "--settings-snapshot-output", index + 1 < arguments.count {
                let value = arguments[index + 1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : URL(fileURLWithPath: value)
            }

            if argument.hasPrefix("--settings-snapshot-output=") {
                let value = String(
                    argument.dropFirst("--settings-snapshot-output=".count)
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : URL(fileURLWithPath: value)
            }
        }

        return nil
    }

    static func onboardingSnapshotOutputURL(
        environment: [String: String],
        arguments: [String] = []
    ) -> URL? {
        if let value = environment["OPENWHISPER_ONBOARDING_SNAPSHOT_OUTPUT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return URL(fileURLWithPath: value)
        }

        for (index, argument) in arguments.enumerated() {
            if argument == "--onboarding-snapshot-output", index + 1 < arguments.count {
                let value = arguments[index + 1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : URL(fileURLWithPath: value)
            }

            if argument.hasPrefix("--onboarding-snapshot-output=") {
                let value = String(
                    argument.dropFirst("--onboarding-snapshot-output=".count)
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : URL(fileURLWithPath: value)
            }
        }

        return nil
    }

    static func historySnapshotOutputURL(
        environment: [String: String],
        arguments: [String] = []
    ) -> URL? {
        productSurfaceSnapshotOutputURL(
            environment: environment,
            arguments: arguments,
            environmentKey: "OPENWHISPER_HISTORY_SNAPSHOT_OUTPUT",
            argumentName: "--history-snapshot-output"
        )
    }

    static func terminologySnapshotOutputURL(
        environment: [String: String],
        arguments: [String] = []
    ) -> URL? {
        productSurfaceSnapshotOutputURL(
            environment: environment,
            arguments: arguments,
            environmentKey: "OPENWHISPER_TERMINOLOGY_SNAPSHOT_OUTPUT",
            argumentName: "--terminology-snapshot-output"
        )
    }

    static func quickAddSnapshotOutputURL(
        environment: [String: String],
        arguments: [String] = []
    ) -> URL? {
        productSurfaceSnapshotOutputURL(
            environment: environment,
            arguments: arguments,
            environmentKey: "OPENWHISPER_QUICK_ADD_SNAPSHOT_OUTPUT",
            argumentName: "--quick-add-snapshot-output"
        )
    }

    static func settingsSnapshotSize(
        environment: [String: String],
        arguments: [String] = []
    ) -> SettingsSnapshotSize? {
        if let value = environment["OPENWHISPER_SETTINGS_SNAPSHOT_SIZE"],
           let size = parseSettingsSnapshotSize(value) {
            return size
        }

        for (index, argument) in arguments.enumerated() {
            if argument == "--settings-snapshot-size", index + 1 < arguments.count {
                return parseSettingsSnapshotSize(arguments[index + 1])
            }

            if argument.hasPrefix("--settings-snapshot-size=") {
                return parseSettingsSnapshotSize(
                    String(argument.dropFirst("--settings-snapshot-size=".count))
                )
            }
        }

        return nil
    }

    private static func requestedSettingsPane(arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == "--settings-pane", index + 1 < arguments.count {
                return arguments[index + 1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }

            if argument.hasPrefix("--settings-pane=") {
                return String(argument.dropFirst("--settings-pane=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
        }

        return nil
    }

    private static func requestedOnboardingStep(
        arguments: [String]
    ) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == "--onboarding-step",
               index + 1 < arguments.count {
                return arguments[index + 1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }

            if argument.hasPrefix("--onboarding-step=") {
                return String(
                    argument.dropFirst("--onboarding-step=".count)
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            }
        }

        return nil
    }

    private static func productSurfaceSnapshotOutputURL(
        environment: [String: String],
        arguments: [String],
        environmentKey: String,
        argumentName: String
    ) -> URL? {
        if let value = environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return URL(fileURLWithPath: value)
        }

        for (index, argument) in arguments.enumerated() {
            if argument == argumentName, index + 1 < arguments.count {
                let value = arguments[index + 1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : URL(fileURLWithPath: value)
            }

            let prefix = "\(argumentName)="
            if argument.hasPrefix(prefix) {
                let value = String(argument.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : URL(fileURLWithPath: value)
            }
        }

        return nil
    }

    private static func optionalBooleanLaunchValue(
        environment: [String: String],
        arguments: [String],
        environmentKey: String,
        argumentName: String
    ) -> Bool? {
        for (index, argument) in arguments.enumerated() {
            if argument == argumentName {
                if index + 1 < arguments.count,
                   let value = parseOptionalBoolean(arguments[index + 1]) {
                    return value
                }
                return true
            }

            let prefix = "\(argumentName)="
            if argument.hasPrefix(prefix) {
                return parseOptionalBoolean(String(argument.dropFirst(prefix.count)))
            }
        }

        if let rawValue = environment[environmentKey],
           let value = parseOptionalBoolean(rawValue) {
            return value
        }

        return nil
    }

    private static func parseOptionalBoolean(_ rawValue: String) -> Bool? {
        switch rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "1", "true", "yes", "on", "enabled":
            return true
        case "0", "false", "no", "off", "disabled":
            return false
        default:
            return nil
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

    private static func parseSettingsSnapshotSize(_ rawValue: String) -> SettingsSnapshotSize? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "×", with: "x")
        let components = normalized.split(separator: "x", omittingEmptySubsequences: false)
        guard
            components.count == 2,
            let width = Int(components[0]),
            let height = Int(components[1]),
            (820...2_000).contains(width),
            (560...1_600).contains(height)
        else {
            return nil
        }
        return SettingsSnapshotSize(width: width, height: height)
    }
}
