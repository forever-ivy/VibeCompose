import Foundation

enum SettingsPane: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general = "General"
    case account = "Account"
    case dictation = "Dictation"
    case appearance = "Appearance & Feedback"
    case polish = "AI Polish"
    case context = "Context"
    case terminology = "Terminology"
    case styleCapsules = "Style Capsules"
    case paste = "Paste"
    case privacy = "Privacy"
    case advanced = "Advanced"
    case skills = "Skills"
    case rules = "Rules"
    case history = "History"

    var id: String { rawValue }

    var launchArgumentValue: String {
        switch self {
        case .general:
            return "general"
        case .account:
            return "account"
        case .dictation:
            return "dictation"
        case .appearance:
            return "appearance"
        case .polish:
            return "ai-polish"
        case .context:
            return "context"
        case .terminology:
            return "terminology"
        case .styleCapsules:
            return "style-capsules"
        case .paste:
            return "paste"
        case .privacy:
            return "privacy"
        case .advanced:
            return "advanced"
        case .skills:
            return "skills"
        case .rules:
            return "rules"
        case .history:
            return "history"
        }
    }

    static func fromLaunchArgument(_ value: String) -> SettingsPane? {
        switch value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        {
        case "general", "language":
            return .general
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
        case "context",
             "selected-text":
            return .context
        case "terminology",
             "terms",
             "domain-packs":
            return .terminology
        case "style-capsules",
             "stylecapsules",
             "style-capsule",
             "stylecapsule":
            return .styleCapsules
        case "paste":
            return .paste
        case "privacy":
            return .privacy
        case "advanced":
            return .advanced
        case "skills",
             "skill-library",
             "skilllibrary",
             "library":
            return .skills
        case "rules",
             "skill-rules",
             "application-rules",
             "app-rules":
            return .rules
        case "history":
            return .history
        default:
            return nil
        }
    }

    var displayTitle: String {
        switch self {
        case .account:
            return L10n.text("General")
        case .dictation, .polish, .paste:
            return L10n.text("Input & Output")
        case .context, .privacy:
            return L10n.text("Context & Privacy")
        case .terminology:
            return L10n.text("Terminology")
        case .styleCapsules:
            return L10n.text("Writing Styles")
        case .skills:
            return L10n.text("Skills")
        case .rules:
            return L10n.text("Rules")
        case .history:
            return L10n.text("History")
        default:
            return L10n.text(rawValue)
        }
    }

    var sidebarGroup: SettingsSidebarGroup {
        switch self {
        case .skills, .rules, .history, .terminology, .styleCapsules:
            return .library
        case .general, .account, .dictation, .polish, .paste, .appearance:
            return .workspace
        case .context, .privacy, .advanced:
            return .system
        }
    }

    var normalizedVisiblePane: SettingsPane {
        switch self {
        case .account:
            return .general
        case .polish, .paste:
            return .dictation
        case .privacy:
            return .context
        default:
            return self
        }
    }

    /// App Store–style product destinations shown in the main shell sidebar.
    static let visiblePanes: [SettingsPane] = [
        .skills,
        .rules,
        .history,
        .terminology,
        .styleCapsules,
        .general,
        .dictation,
        .context,
        .appearance,
        .advanced,
    ]

    static let libraryPanes: [SettingsPane] = [
        .skills,
        .rules,
        .history,
        .terminology,
        .styleCapsules,
    ]

    static let workspacePanes: [SettingsPane] = [
        .general,
        .dictation,
        .appearance,
    ]

    static let systemPanes: [SettingsPane] = [
        .context,
        .advanced,
    ]
}

enum SettingsSidebarGroup: String, CaseIterable, Identifiable, Sendable {
    case library
    case workspace
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library:
            return L10n.text("Library")
        case .workspace:
            return L10n.text("Workspace")
        case .system:
            return L10n.text("System")
        }
    }

    var panes: [SettingsPane] {
        switch self {
        case .library:
            return SettingsPane.libraryPanes
        case .workspace:
            return SettingsPane.workspacePanes
        case .system:
            return SettingsPane.systemPanes
        }
    }
}

struct SettingsWindowStateStore {
    static let frameAutosaveName = "VibeCompose.SettingsWindow"
    static let selectedPaneKey = "VibeCompose.Settings.SelectedPane"
    static let skillLibrarySectionKey =
        "VibeCompose.Settings.SkillLibrarySection"

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
            return focusedPane.normalizedVisiblePane
        }
        guard
            let rawValue = defaults.string(forKey: Self.selectedPaneKey),
            let pane = SettingsPane(rawValue: rawValue)
        else {
            return .general
        }
        return pane.normalizedVisiblePane
    }

    func saveSelectedPane(_ pane: SettingsPane) {
        defaults.set(
            pane.normalizedVisiblePane.rawValue,
            forKey: Self.selectedPaneKey
        )
    }

    /// Restores the last Skill Library segment (Discover / Install / Created).
    /// Deep-link `preferred` values win when provided so launch-mode and
    /// acceptance captures still land on the requested tab.
    func initialSkillLibrarySection(
        preferred: SkillLibrarySection? = nil
    ) -> SkillLibrarySection {
        if let preferred {
            return preferred
        }
        guard
            let rawValue = defaults.string(
                forKey: Self.skillLibrarySectionKey
            ),
            let section = SkillLibrarySection(rawValue: rawValue)
        else {
            return .discover
        }
        return section
    }

    func saveSkillLibrarySection(_ section: SkillLibrarySection) {
        defaults.set(section.rawValue, forKey: Self.skillLibrarySectionKey)
    }
}
