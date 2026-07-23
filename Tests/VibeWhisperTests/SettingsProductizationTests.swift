import Foundation
import Testing
@testable import OpenWhisper

@Test
func standardManagementWindowsSupportDockMinimization() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let mainSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/OpenWhisper/main.swift"
        ),
        encoding: .utf8
    )
    #expect(
        mainSource.contains(
            "app.setActivationPolicy(.regular)"
        )
    )
    #expect(
        !mainSource.contains(
            "app.setActivationPolicy(.accessory)"
        )
    )
    let settingsSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/OpenWhisper/PreferencesWindowController.swift"
        ),
        encoding: .utf8
    )
    #expect(settingsSource.contains(".miniaturizable"))
    #expect(settingsSource.contains("DispatchQueue.main.async"))
    #expect(settingsSource.contains("makeKeyAndOrderFront"))
    #expect(settingsSource.contains("NSApp.activate"))
}

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
        ) == .general
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
        ) == .context
    )
    #expect(
        store.initialPane(
            focusedPane: .advanced
        ) == .advanced
    )
    #expect(store.initialPane(focusedPane: .account) == .general)
    #expect(store.initialPane(focusedPane: .polish) == .dictation)
    #expect(store.initialPane(focusedPane: .paste) == .dictation)
    #expect(store.initialPane(focusedPane: .terminology) == .terminology)
    #expect(store.initialPane(focusedPane: .privacy) == .context)
    #expect(store.initialPane(focusedPane: .skills) == .skills)
    #expect(store.initialPane(focusedPane: .history) == .history)
}

@Test
func settingsExposeEightCanonicalProductPanes() {
    #expect(
        SettingsPane.visiblePanes
            == [
                .skills,
                .history,
                .terminology,
                .general,
                .dictation,
                .context,
                .appearance,
                .advanced,
            ]
    )
    #expect(SettingsPane.account.normalizedVisiblePane == .general)
    #expect(SettingsPane.polish.normalizedVisiblePane == .dictation)
    #expect(SettingsPane.paste.normalizedVisiblePane == .dictation)
    #expect(SettingsPane.terminology.normalizedVisiblePane == .terminology)
    #expect(SettingsPane.privacy.normalizedVisiblePane == .context)
    #expect(SettingsPane.dictation.displayTitle == L10n.text("Input & Output"))
    #expect(SettingsPane.context.displayTitle == L10n.text("Context & Privacy"))
    #expect(SettingsPane.skills.displayTitle == L10n.text("Skills"))
    #expect(SettingsPane.history.displayTitle == L10n.text("History"))
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
        ) == .general
    )
}

@Test
func `Skill Library deep links stay inside the Settings window`() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let preferencesSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/OpenWhisper/PreferencesWindowController.swift"
        ),
        encoding: .utf8
    )
    let coordinatorSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/OpenWhisper/AppCoordinator.swift"
        ),
        encoding: .utf8
    )

    #expect(
        preferencesSource.contains(
            "initialSection: skillLibraryInitialSection"
        )
    )
    #expect(
        coordinatorSource.contains(
            "skillLibraryInitialSection: section"
        )
    )
    #expect(coordinatorSource.contains("case .skillLibrary:"))
    #expect(!coordinatorSource.contains("skillLibraryWindowController"))
    #expect(!coordinatorSource.contains("_ = section"))
}

@Test
func settingsSourceKeepsTheMacOSSidebarAndAutosavingContract() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = root.appendingPathComponent(
        "Sources/OpenWhisper/PreferencesWindowController.swift"
    )
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("private enum SettingsLayoutMetrics"))
    #expect(source.contains("static let sidebarWidth: CGFloat = 236"))
    #expect(source.contains("static let sidebarTopPadding: CGFloat = 52"))
    #expect(source.contains("static let sidebarRowVerticalPadding: CGFloat = 5"))
    #expect(source.contains("static let detailHorizontalPadding: CGFloat = 40"))
    #expect(source.contains("static let embeddedTopPadding: CGFloat = 6"))
    #expect(!source.contains("sidebarInset"))
    #expect(!source.contains("sidebarCornerRadius"))
    #expect(source.contains("private var settingsSidebarList: some View"))
    #expect(!source.contains("List(selection: $selectedSection)"))
    #expect(source.contains("SettingsSidebarRowButton("))
    #expect(source.contains("private var settingsSidebar: some View"))
    #expect(source.contains("GeometryReader { geometry in"))
    #expect(source.contains("HStack(spacing: 0)"))
    #expect(source.contains(".frame(width: SettingsLayoutMetrics.sidebarWidth)"))
    #expect(source.contains("SettingsSidebarMaterialView("))
    #expect(source.contains("view.material = .sidebar"))
    #expect(source.contains("view.blendingMode = .behindWindow"))
    #expect(source.contains("OpenWhisperPalette.sidebarSelectionBackground"))
    #expect(source.contains("OpenWhisperPalette.sidebarSelectionForeground"))
    #expect(source.contains("window.collectionBehavior.remove(.fullScreenPrimary)"))
    #expect(source.contains("window.standardWindowButton(.zoomButton)?.isEnabled = false"))
    #expect(source.contains("sidebarArrowKeyMonitor"))
    #expect(
        !source.contains(
            "NavigationSplitView(columnVisibility: .constant(.all))"
        )
    )
    #expect(!source.contains(".glassEffect("))
    #expect(!source.contains("OpenWhisperWindowBackdrop"))
    #expect(!source.contains("accessibilityReduceTransparency"))
    #expect(source.contains("Label("))
    #expect(!source.contains(".tag(pane)"))
    #expect(!source.contains("SettingsSidebarPresentationModel"))
    #expect(!source.contains("SettingsSidebarToggleButton"))
    #expect(!source.contains("installSidebarToggleButton"))
    #expect(!source.contains("Show or hide sidebar"))
    #expect(!source.contains("toolbar(removing: .sidebarToggle)"))
    #expect(source.contains("OpenWhisperSidebarSymbol("))
    #expect(!source.contains("OpenWhisperSidebarIconWell("))
    #expect(!source.contains("var sidebarIconColor: Color"))
    #expect(source.contains("ScrollView"))
    #expect(!source.contains("Form {"))
    #expect(!source.contains(".formStyle(.grouped)"))
    #expect(source.contains("SettingsRow("))
    #expect(source.contains("SettingsPane.visiblePanes"))
    #expect(source.contains("SettingsSidebarGroup"))
    #expect(source.contains("embeddedDestination"))
    #expect(source.contains("SkillLibraryView("))
    #expect(source.contains("HistoryWindowView("))
    #expect(source.contains("TerminologyManagerView("))
    #expect(source.contains(".easeOut(duration: 0.18)"))
    #expect(!source.contains("SettingsPane.basicPanes"))
    #expect(!source.contains("SettingsPane.intelligencePanes"))
    #expect(source.contains("$config.appLanguage"))
    #expect(source.contains("currentGlobalDefaultSkill"))
    #expect(source.contains("Button(L10n.text(\"Open Skill Library…\")"))
    #expect(source.contains("window.minSize = NSSize(width: 900, height: 620)"))
    #expect(source.contains(".fullSizeContentView"))
    #expect(source.contains("window.toolbarStyle = .unified"))
    #expect(source.contains("window.titlebarSeparatorStyle = .none"))
    #expect(!source.contains("window.isOpaque = false"))
    #expect(!source.contains("window.backgroundColor = .clear"))
    #expect(source.contains("private var settingsSplitView: some View"))
    #expect(source.contains("let settingsToolbar = NSToolbar("))
    #expect(!source.contains("SidebarToggleSuppressingToolbar"))
    #expect(!source.contains("com.apple.SwiftUI.navigationSplitView.toggleSidebar"))
    #expect(source.contains("settingsToolbar.allowsUserCustomization = false"))
    #expect(!source.contains(".sidebarTrackingSeparator"))
    #expect(!source.contains("#selector(NSSplitViewController.toggleSidebar(_:))"))
    #expect(!source.contains("withAnimation(.easeInOut(duration: 0.22))"))
    #expect(!source.contains("NSToolbarDelegate"))
    #expect(!source.contains("NSTitlebarAccessoryViewController"))
    #expect(!source.contains("isNavigational"))
    #expect(!source.contains("ToolbarItem(placement: .navigation)"))
    #expect(source.contains(".onChange(of: config)"))
    #expect(source.contains("persistEmbeddedConfig(updated)"))
    #expect(source.contains("suppressNextPersist = true"))
    #expect(source.contains("text: $recoveryEndpointDraft"))
    #expect(source.contains("text: $recoveryModelDraft"))
    #expect(!source.contains("text: $config.transcription.openAITranscriptionURL"))
    #expect(!source.contains("text: $config.transcription.openAIModel"))
    #expect(source.contains("Task.sleep(for: .milliseconds(450))"))
    #expect(source.contains("setFrameAutosaveName"))
    #expect(source.contains(".resizable"))
    #expect(source.contains("case .saved:"))
    #expect(source.contains("EmptyView()"))
    #expect(!source.contains("Button(L10n.text(\"Save Settings\")"))
    #expect(source.contains("@State private var editingTerminologyID: UUID?"))
    #expect(!source.contains("editingTerminologyIndex"))
    #expect(!source.contains("prefix(5)"))
    #expect(!source.contains("edit config.json for bulk changes"))
    #expect(source.contains("$config.transcription.languagePreference"))
    #expect(source.contains("$config.transcription.punctuationPreference"))
    #expect(source.contains("$config.visualFeedback"))
    #expect(source.contains("case .appearance:"))
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
    #expect(!source.contains("License & Pro"))
    #expect(!source.contains("Import Signed License…"))
    #expect(!source.contains("licenseManager"))
    #expect(!source.contains("Skills require OpenWhisper Pro"))
    #expect(source.contains("Context Sources"))
    #expect(
        source.contains(
            "ContextSourceKind\n                            .userVisibleSettingsSources"
        )
    )
    #expect(!source.contains("L10n.text(\"Planned\")"))
    #expect(source.contains("$config.context"))
    #expect(source.contains(".selectionEnabled"))
    #expect(source.contains("SkillPermissionScope"))
    #expect(source.contains("Reset Permissions"))
    #expect(source.contains("Open Terminologies…"))
    #expect(source.contains("onOpenTerminology()"))
    #expect(!source.contains("Technical literals such as paths"))
    #expect(source.contains("Button(L10n.text(\"Export Diagnostics…\")"))
    #expect(source.contains("onExportSupportDiagnostics"))
    #expect(!source.contains("account email, tokens, API keys"))
    #expect(source.contains("Export Product Metrics…"))
    #expect(source.contains("onExportProductMetrics"))
    #expect(
        source.contains(
            ".disabled(!config.privacy.productMetricsEnabled)"
        )
    )
    #expect(!source.contains("no event timestamps"))
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
    #expect(!source.contains("generated 0.1-second silent WAV"))
    #expect(source.contains("Use OpenAI-Compatible Recovery?"))
    #expect(source.contains("Use Recovery API"))
    #expect(source.contains("Switch Back to ChatGPT Account"))
    #expect(!source.contains("AI Polish remains on the ChatGPT-authenticated route"))
    #expect(!source.contains("ASR environment variable"))
    #expect(!source.contains("OPENAI_API_KEY"))

    let configFolderButtonCount = source
        .components(separatedBy: "Button(L10n.text(\"Open Config Folder\")")
        .count - 1
    #expect(configFolderButtonCount == 1)
}

@Test
func liquidGlassStaysInSystemNavigationChrome() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let visualSystem = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/OpenWhisper/OpenWhisperVisualSystem.swift"
        ),
        encoding: .utf8
    )
    let history = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/OpenWhisper/HistoryWindowController.swift"
        ),
        encoding: .utf8
    )

    #expect(!visualSystem.contains("OpenWhisperWindowBackdrop"))
    #expect(!visualSystem.contains("LinearGradient("))
    #expect(!visualSystem.contains("RadialGradient("))
    #expect(visualSystem.contains("OpenWhisperSecondaryButtonStyle: PrimitiveButtonStyle"))
    #expect(visualSystem.contains(".buttonStyle(.glass)"))
    #expect(visualSystem.contains(".buttonStyle(.glassProminent)"))
    #expect(history.contains(".searchable("))
    #expect(history.contains("placement: .toolbar"))
    #expect(history.contains("ToolbarItem(placement: .principal)"))
    #expect(history.contains("HistoryChromeModifier"))
    #expect(history.contains("isEmbedded"))
    #expect(!history.contains("GlassEffectContainer"))
}

@Test
func embeddedManagementSurfacesDoNotForceTheSettingsDetailWiderThanItsWindow() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    for relativePath in [
        "Sources/OpenWhisper/HistoryWindowController.swift",
        "Sources/OpenWhisper/TerminologyWindowController.swift",
    ] {
        let source = try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )

        #expect(source.contains("window.minSize = NSSize(width: 760, height: 500)"))
        #expect(!source.contains(".frame(minWidth: 760, minHeight: 500)"))
        #expect(source.contains("ViewThatFits(in: .horizontal)"))
        #expect(source.contains("compactLayout"))
    }
}

@Test
func primaryProductSurfacesDoNotRenderExplanatorySmallPrint() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sources = try [
        "SettingsComponents.swift",
        "OpenWhisperVisualSystem.swift",
        "PreferencesWindowController.swift",
        "OnboardingWindowController.swift",
        "MicrophonePermissionWindowController.swift",
        "TerminologyQuickAddWindowController.swift",
        "SkillLibraryWindowController.swift",
    ].map {
        try String(
            contentsOf: root
                .appendingPathComponent("Sources/OpenWhisper")
                .appendingPathComponent($0),
            encoding: .utf8
        )
    }.joined(separator: "\n")

    for removedCopy in [
        "Language, account, default Skill, and shortcuts.",
        "Technical literals such as paths",
        "Ready in four steps.",
        "Used only while recording.",
        "Global shortcut: Control–Option–Space",
        "Choose, understand, test, and create trusted voice workflows.",
        "Create one portable Agent Skill behavior at a time.",
        "Examples are written into the standard SKILL.md",
    ] {
        #expect(!sources.contains(removedCopy))
    }
    #expect(sources.contains(".accessibilityHint(detail ?? \"\")"))
    #expect(!sources.contains("private var sectionSubtitle: String"))
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
