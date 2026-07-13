import Foundation

enum SettingsPane: String, CaseIterable, Identifiable, Hashable, Sendable {
    case account = "Account"
    case dictation = "Dictation"
    case appearance = "Appearance & Feedback"
    case polish = "AI Polish"
    case paste = "Paste"
    case privacy = "Privacy"
    case advanced = "Advanced"

    var id: String { rawValue }

    var launchArgumentValue: String {
        switch self {
        case .account:
            return "account"
        case .dictation:
            return "dictation"
        case .appearance:
            return "appearance"
        case .polish:
            return "ai-polish"
        case .paste:
            return "paste"
        case .privacy:
            return "privacy"
        case .advanced:
            return "advanced"
        }
    }

    static func fromLaunchArgument(_ value: String) -> SettingsPane? {
        switch value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        {
        case "account":
            return .account
        case "dictation":
            return .dictation
        case "appearance",
             "appearance-feedback",
             "feedback":
            return .appearance
        case "polish", "ai-polish", "aipolish":
            return .polish
        case "paste":
            return .paste
        case "privacy":
            return .privacy
        case "advanced":
            return .advanced
        default:
            return nil
        }
    }
}

struct SettingsWindowStateStore {
    static let frameAutosaveName = "OpenWhisper.SettingsWindow"
    static let selectedPaneKey = "OpenWhisper.Settings.SelectedPane"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func initialPane(
        focusPrivacy: Bool
    ) -> SettingsPane {
        initialPane(focusedPane: focusPrivacy ? .privacy : nil)
    }

    func initialPane(
        focusedPane: SettingsPane?
    ) -> SettingsPane {
        if let focusedPane {
            return focusedPane
        }
        guard
            let rawValue = defaults.string(forKey: Self.selectedPaneKey),
            let pane = SettingsPane(rawValue: rawValue)
        else {
            return .account
        }
        return pane
    }

    func saveSelectedPane(_ pane: SettingsPane) {
        defaults.set(pane.rawValue, forKey: Self.selectedPaneKey)
    }
}
