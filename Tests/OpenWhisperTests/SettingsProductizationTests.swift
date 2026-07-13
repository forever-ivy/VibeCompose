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
            focusPrivacy: false
        ) == .account
    )

    store.saveSelectedPane(.advanced)
    #expect(
        store.initialPane(
            focusPrivacy: false
        ) == .advanced
    )
    #expect(
        store.initialPane(
            focusPrivacy: true
        ) == .privacy
    )
    #expect(
        store.initialPane(
            focusedPane: .advanced
        ) == .advanced
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
    #expect(source.contains("$config.transcription.languagePreference"))
    #expect(source.contains("$config.transcription.punctuationPreference"))
    #expect(source.contains("$config.visualFeedback"))
    #expect(source.contains("Appearance & Feedback"))
    #expect(source.contains("VisualFeedbackMode"))
    #expect(source.contains("VisualFeedbackPreview"))
    #expect(source.contains("$config.transcription.skills.defaultSkillID"))
    #expect(source.contains("Application Rules"))
    #expect(source.contains("Button(L10n.text(\"Choose App…\")"))
    #expect(source.contains("panel.allowedContentTypes = [.application]"))
    #expect(source.contains("AppSkillRule.validated"))
    #expect(source.contains("config.transcription.skills.upsert"))
    #expect(source.contains("skills.requiresTextPolish"))
    #expect(source.contains("authSnapshot.state != .ready"))
    #expect(source.contains("License & Pro"))
    #expect(source.contains("Import Signed License…"))
    #expect(source.contains("licenseManager.installReceipt"))
    #expect(source.contains("licenseSnapshot.allows(.voiceModes)"))
    #expect(source.contains("Skills require OpenWhisper Pro"))
    #expect(source.contains("Selected Text Context"))
    #expect(source.contains("$config.context"))
    #expect(source.contains(".selectionEnabled"))
    #expect(source.contains("SkillPermissionScope"))
    #expect(source.contains("Reset Permissions"))
    #expect(source.contains("Technical literals such as paths"))
    #expect(source.contains("Button(L10n.text(\"Export Diagnostics…\")"))
    #expect(source.contains("onExportSupportDiagnostics"))
    #expect(source.contains("account email, tokens, API keys"))
    #expect(source.contains("Export Product Metrics…"))
    #expect(source.contains("onExportProductMetrics"))
    #expect(
        source.contains(
            ".disabled(!config.privacy.productMetricsEnabled)"
        )
    )
    #expect(source.contains("no event timestamps"))
    #expect(source.contains("Button(L10n.text(\"Check for Updates…\")"))
    #expect(source.contains("Automatically check for updates"))
    #expect(source.contains("onSetAutomaticallyChecksForUpdates"))
    #expect(source.contains("Provider Safety"))
    #expect(source.contains("Refresh Safety Policy"))
    #expect(source.contains("providerCapabilityPolicy.refresh"))
    #expect(source.contains("permissionStatusMonitor.requestMicrophoneAccess"))
    #expect(source.contains("isRequestingMicrophoneAccess"))
    #expect(
        source.contains(
            "OpenWhisper still cannot confirm microphone access."
        )
    )
    #expect(source.contains("SecureField("))
    #expect(source.contains("Save API Key"))
    #expect(source.contains("Remove API Key"))
    #expect(source.contains("API key stored in Keychain"))
    #expect(source.contains("OpenAICompatibleConnectionTester("))
    #expect(source.contains("generated 0.1-second silent WAV"))
    #expect(source.contains("Use OpenAI-Compatible Recovery?"))
    #expect(source.contains("Use Paid API"))
    #expect(source.contains("Switch Back to ChatGPT Account"))
    #expect(source.contains("AI Polish remains on the ChatGPT-authenticated route"))
    #expect(!source.contains("ASR environment variable"))
    #expect(!source.contains("OPENAI_API_KEY"))

    let configFolderButtonCount = source
        .components(separatedBy: "Button(L10n.text(\"Open Config Folder\")")
        .count - 1
    #expect(configFolderButtonCount == 1)
}

@Test
func statusMenuExposesSoftwareUpdateEntry() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/OpenWhisper/StatusMenuController.swift"
        ),
        encoding: .utf8
    )

    #expect(source.contains("title: L10n.text(\"Check for Updates…\")"))
    #expect(source.contains("action: #selector(checkForUpdates)"))
    #expect(source.contains("checkForUpdatesHandler()"))
    #expect(source.contains("Retry last dictation"))
    #expect(source.contains("setRetryDictationAvailable"))
}
