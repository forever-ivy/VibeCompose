import Foundation
import Testing
@testable import OpenWhisper

@Test
func settingsWindowStateRestoresLastPaneAndHonorsDeepLinks() throws {
    let suiteName = "OpenWhisperTests.Settings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = SettingsWindowStateStore(defaults: defaults)
    #expect(
        store.initialPane(
            focusRecoveryHistory: false,
            focusPrivacy: false
        ) == .account
    )

    store.saveSelectedPane(.terminology)
    #expect(
        store.initialPane(
            focusRecoveryHistory: false,
            focusPrivacy: false
        ) == .terminology
    )
    #expect(
        store.initialPane(
            focusRecoveryHistory: true,
            focusPrivacy: false
        ) == .recovery
    )
    #expect(
        store.initialPane(
            focusRecoveryHistory: true,
            focusPrivacy: true
        ) == .privacy
    )
}

@Test
func settingsWindowFallsBackFromUnknownPersistedPane() throws {
    let suiteName = "OpenWhisperTests.Settings.Unknown.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }
    defaults.set("Removed Pane", forKey: SettingsWindowStateStore.selectedPaneKey)

    let store = SettingsWindowStateStore(defaults: defaults)
    #expect(
        store.initialPane(
            focusRecoveryHistory: false,
            focusPrivacy: false
        ) == .account
    )
}

@Test
func settingsSourceKeepsTheNativeAutosavingContract() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = root.appendingPathComponent(
        "Sources/OpenWhisper/PreferencesWindowController.swift"
    )
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("NavigationSplitView"))
    #expect(source.contains("List(selection: $selectedSection)"))
    #expect(source.contains("Form {"))
    #expect(source.contains(".formStyle(.grouped)"))
    #expect(source.contains(".onChange(of: config)"))
    #expect(source.contains("setFrameAutosaveName"))
    #expect(source.contains(".resizable"))
    #expect(source.contains("Saved automatically"))
    #expect(!source.contains("Button(L10n.text(\"Save Settings\")"))
    #expect(source.contains("@State private var editingTerminologyID: UUID?"))
    #expect(!source.contains("editingTerminologyIndex"))
    #expect(!source.contains("prefix(5)"))
    #expect(!source.contains("edit config.json for bulk changes"))

    let configFolderButtonCount = source
        .components(separatedBy: "Button(L10n.text(\"Open Config Folder\")")
        .count - 1
    #expect(configFolderButtonCount == 1)
}
