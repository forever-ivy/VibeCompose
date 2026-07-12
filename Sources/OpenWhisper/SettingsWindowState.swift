import Foundation

enum SettingsPane: String, CaseIterable, Identifiable, Hashable, Sendable {
    case account = "Account"
    case dictation = "Dictation"
    case polish = "AI Polish"
    case recovery = "History"
    case terminology = "Terminology"
    case paste = "Paste"
    case privacy = "Privacy"
    case advanced = "Advanced"

    var id: String { rawValue }
}

struct SettingsWindowStateStore {
    static let frameAutosaveName = "OpenWhisper.SettingsWindow"
    static let selectedPaneKey = "OpenWhisper.Settings.SelectedPane"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func initialPane(
        focusRecoveryHistory: Bool,
        focusPrivacy: Bool
    ) -> SettingsPane {
        if focusPrivacy {
            return .privacy
        }
        if focusRecoveryHistory {
            return .recovery
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
