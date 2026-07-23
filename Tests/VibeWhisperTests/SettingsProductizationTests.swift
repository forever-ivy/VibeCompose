import Foundation
import Testing
@testable import VibeWhisper

@Test
func standardManagementWindowsSupportDockMinimization() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let mainSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/main.swift"
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
            "Sources/VibeWhisper/PreferencesWindowController.swift"
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
    let suiteName = "VibeWhisperTests.Settings.\(UUID().uuidString)"
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
    #expect(store.initialPane(focusedPane: .rules) == .rules)
    #expect(store.initialPane(focusedPane: .history) == .history)
}

@Test
func settingsExposeCanonicalProductPanes() {
    #expect(
        SettingsPane.visiblePanes
            == [
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
    )
    #expect(
        SettingsPane.libraryPanes
            == [.skills, .rules, .history, .terminology, .styleCapsules]
    )
    #expect(SettingsPane.account.normalizedVisiblePane == .general)
    #expect(SettingsPane.polish.normalizedVisiblePane == .dictation)
    #expect(SettingsPane.paste.normalizedVisiblePane == .dictation)
    #expect(SettingsPane.terminology.normalizedVisiblePane == .terminology)
    #expect(SettingsPane.styleCapsules.normalizedVisiblePane == .styleCapsules)
    #expect(SettingsPane.privacy.normalizedVisiblePane == .context)
    #expect(SettingsPane.dictation.displayTitle == L10n.text("Input & Output"))
    #expect(SettingsPane.context.displayTitle == L10n.text("Context & Privacy"))
    #expect(SettingsPane.skills.displayTitle == L10n.text("Skills"))
    #expect(SettingsPane.rules.displayTitle == L10n.text("Rules"))
    #expect(SettingsPane.history.displayTitle == L10n.text("History"))
    #expect(SettingsPane.styleCapsules.displayTitle == L10n.text("Writing Styles"))
    #expect(SettingsPane.fromLaunchArgument("rules") == .rules)
    #expect(SettingsPane.fromLaunchArgument("application-rules") == .rules)
    #expect(SettingsPane.fromLaunchArgument("app-rules") == .rules)
    #expect(SettingsPane.fromLaunchArgument("style-capsules") == .styleCapsules)
}


@Test
func skillRulesLiveOnDedicatedSettingsPaneNotInstall() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let librarySource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/SkillLibraryWindowController.swift"
        ),
        encoding: .utf8
    )
    let preferencesSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/PreferencesWindowController.swift"
        ),
        encoding: .utf8
    )

    #expect(librarySource.contains("struct SkillRulesSettingsView"))
    #expect(librarySource.contains("SettingsCardContainer(title: \"Application Rules\")"))
    #expect(librarySource.contains("SettingsCardContainer(title: \"Global default\")"))
    #expect(librarySource.contains("VibeWhisperPaneHeader(title: L10n.text(\"Rules\")"))
    #expect(librarySource.contains("Button(L10n.text(\"Choose App…\")"))
    #expect(librarySource.contains("AppSkillRule.validated"))
    #expect(librarySource.contains("config.transcription.skills.upsert"))
    #expect(librarySource.contains("panel.allowedContentTypes = [.application]"))
    #expect(librarySource.contains("openWhisperInset("))
    #expect(!librarySource.contains("SkillApplicationDefaultsView"))
    #expect(!librarySource.contains("SkillApplicationDefaultsView("))
    // Install hosts packages only — no Defaults block above CommunitySkillSettingsView.
    #expect(
        !librarySource.contains(
            """
                    SkillApplicationDefaultsView(
                        config: $config,
                        inventory: inventory
                    )
            """
        )
    )
    let installedCase = librarySource.range(of: "private var content: some View")
    let createdCase = librarySource.range(of: "private var createdSummary: some View")
    #expect(installedCase != nil && createdCase != nil)
    if let installedCase, let createdCase {
        let contentBody = librarySource[installedCase.lowerBound..<createdCase.lowerBound]
        #expect(contentBody.contains("CommunitySkillSettingsView("))
        #expect(!contentBody.contains("SkillRulesSettingsView("))
        #expect(!contentBody.contains("Application Rules"))
        #expect(!contentBody.contains("Global default"))
        #expect(!contentBody.contains("SkillApplicationDefaultsView"))
    }

    #expect(preferencesSource.contains("SkillRulesSettingsView("))
    #expect(preferencesSource.contains("case .rules:"))
    #expect(preferencesSource.contains("list.bullet.rectangle"))
    #expect(
        preferencesSource.contains(
            ".skills, .rules, .history, .terminology, .styleCapsules"
        )
    )
    #expect(preferencesSource.contains("StyleCapsuleLibraryView("))
    #expect(preferencesSource.contains("case .styleCapsules:"))
    #expect(!preferencesSource.contains("styleCapsulesCard"))
}

@Test
func skillShowcaseMorphUsesStableInterruptibleGeometry() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/SkillLibraryWindowController.swift"
        ),
        encoding: .utf8
    )
    let playerStart = try #require(
        source.range(of: "private struct SkillShowcasePlayer: View")
    )
    let waveformStart = try #require(
        source.range(of: "// MARK: - HUD-matching showcase waveform")
    )
    let player = source[playerStart.lowerBound..<waveformStart.lowerBound]

    #expect(player.contains("@State private var capsuleHeight"))
    #expect(player.contains("SkillShowcaseResultHeightKey"))
    #expect(player.contains(".frame(width: width, height: capsuleHeight)"))
    #expect(player.contains("let typingSize = measuredTypingSize(for: say)"))
    #expect(player.contains("capsuleHeight = typingSize.height"))
    #expect(player.contains("VibeWhisperMotion.showcaseMorph"))
    #expect(player.contains("generation &+= 1"))
    #expect(player.contains("guard gen == generation"))
    #expect(player.contains("@State private var hasCompletedInitialTyping"))
    #expect(player.contains("private func runSubsequentTyping"))
    #expect(player.contains("typedSay = String(characters[...index])"))
    #expect(player.contains("typedSay = say"))
    #expect(player.contains("typingTextOpacity = 0"))
    #expect(!player.contains("measuredTypingWidth(for: typedSay)"))
    #expect(!player.contains(".scaleEffect("))
}

@Test
func settingsWindowFallsBackFromUnknownPersistedPane() throws {
    let suiteName = "VibeWhisperTests.Settings.Unknown.\(UUID().uuidString)"
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
func settingsWindowStatePersistsSkillLibrarySection() throws {
    let suiteName =
        "VibeWhisperTests.Settings.SkillLibrary.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = SettingsWindowStateStore(defaults: defaults)
    #expect(store.initialSkillLibrarySection() == .discover)

    store.saveSkillLibrarySection(.installed)
    #expect(store.initialSkillLibrarySection() == .installed)
    // Explicit preferred (deep link / acceptance) still wins over restore.
    #expect(
        store.initialSkillLibrarySection(preferred: .created)
            == .created
    )
    // Subsequent restore without preferred keeps the last user tab.
    #expect(store.initialSkillLibrarySection() == .installed)

    store.saveSkillLibrarySection(.discover)
    #expect(store.initialSkillLibrarySection() == .discover)
}

@Test
func settingsWindowStateNormalizesPersistedPaneOnSave() throws {
    let suiteName =
        "VibeWhisperTests.Settings.Normalize.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = SettingsWindowStateStore(defaults: defaults)
    // Legacy collapsed panes must persist their visible destination so a
    // reopen after popup dismiss never lands on a removed sidebar row.
    store.saveSelectedPane(.account)
    #expect(store.initialPane(focusedPane: nil) == .general)
    store.saveSelectedPane(.polish)
    #expect(store.initialPane(focusedPane: nil) == .dictation)
    store.saveSelectedPane(.privacy)
    #expect(store.initialPane(focusedPane: nil) == .context)
}

@Test
func `Skill Library deep links stay inside the Settings window`() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let preferencesSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/PreferencesWindowController.swift"
        ),
        encoding: .utf8
    )
    let coordinatorSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/AppCoordinator.swift"
        ),
        encoding: .utf8
    )
    let librarySource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/SkillLibraryWindowController.swift"
        ),
        encoding: .utf8
    )
    let stateSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/SettingsWindowState.swift"
        ),
        encoding: .utf8
    )

    // Deep-link section still flows through openSettings → PreferencesView.
    #expect(
        coordinatorSource.contains(
            "skillLibraryInitialSection: section"
        )
    )
    #expect(coordinatorSource.contains("case .skillLibrary:"))
    #expect(!coordinatorSource.contains("skillLibraryWindowController"))
    #expect(!coordinatorSource.contains("_ = section"))
    // Embedded Skills always remounts from the store (not a sticky ctor arg)
    // so popup dismiss never re-forces the original deep-link tab.
    #expect(
        preferencesSource.contains(
            "initialSection: .discover"
        )
    )
    #expect(
        preferencesSource.contains(
            "windowStateStore: windowStateStore"
        )
    )
    #expect(
        preferencesSource.contains(
            "saveSkillLibrarySection"
        )
    )
    #expect(
        librarySource.contains(
            "saveSkillLibrarySection"
        )
    )
    #expect(
        stateSource.contains(
            "skillLibrarySectionKey"
        )
    )
}

@Test
func openSettingsWithoutFocusPaneDoesNotNavigateExistingShell() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let coordinatorSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/AppCoordinator.swift"
        ),
        encoding: .utf8
    )
    let preferencesSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/PreferencesWindowController.swift"
        ),
        encoding: .utf8
    )

    // Existing shell + nil focusPane must only show(), never re-navigate.
    #expect(
        coordinatorSource.contains(
            "focusPane == nil: reopen without resetting the current page."
        )
    )
    #expect(
        coordinatorSource.contains(
            "never reopen Settings"
        )
    )
    // Optional selectedSection → hard General reset is gone.
    #expect(
        !preferencesSource.contains(
            "selectedSection = .general"
        )
    )
    #expect(
        preferencesSource.contains(
            "@State private var selectedSection: SettingsPane"
        )
    )
    // Skill switcher selection stays capsule-only (no Settings navigate).
    #expect(
        coordinatorSource.contains(
            "Does not navigate back to Settings."
        )
    )
}

@Test
func transientPanelsRestoreHostFrontmostInsteadOfSettings() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let injectorSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/TextInjector.swift"
        ),
        encoding: .utf8
    )
    let switcherSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/SkillSwitcherWindowController.swift"
        ),
        encoding: .utf8
    )
    let previewSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/PreviewRuntime.swift"
        ),
        encoding: .utf8
    )
    let coordinatorSource = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/AppCoordinator.swift"
        ),
        encoding: .utf8
    )

    // Capture + restore helpers exist and refuse to re-activate VibeWhisper.
    #expect(
        injectorSource.contains(
            "externalFrontmostForTransientRestore"
        )
    )
    #expect(
        injectorSource.contains(
            "Never \"restore\" into ourselves"
        )
        || injectorSource.contains(
            "Never “restore” into ourselves"
        )
        || injectorSource.contains(
            "Never restore into ourselves"
        )
        || injectorSource.contains(
            "re-keys whatever VW window"
        )
    )
    // Skill Switcher captures host on show and restores on dismiss.
    #expect(switcherSource.contains("priorExternalFrontmost"))
    #expect(
        switcherSource.contains(
            "externalFrontmostForTransientRestore"
        )
    )
    #expect(
        switcherSource.contains(
            "restoreFrontmostIfNeeded(priorExternalFrontmost)"
        )
    )
    #expect(
        switcherSource.contains(
            "prepareForExplicitSettingsNavigation"
        )
    )
    // Result Preview captures host before activate and restores on finish.
    #expect(previewSource.contains("priorExternalFrontmost"))
    #expect(
        previewSource.contains(
            "externalFrontmostForTransientRestore"
        )
    )
    #expect(
        previewSource.contains(
            "restoreFrontmostIfNeeded(restoreTarget)"
        )
    )
    // Library navigation is the only path that suppresses host restore.
    #expect(
        coordinatorSource.contains(
            "prepareForExplicitSettingsNavigation"
        )
    )
    #expect(
        coordinatorSource.contains(
            "never reopen Settings"
        )
    )
}

@Test
func settingsSourceKeepsTheMacOSSidebarAndAutosavingContract() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = root.appendingPathComponent(
        "Sources/VibeWhisper/PreferencesWindowController.swift"
    )
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("private enum SettingsLayoutMetrics"))
    #expect(source.contains("static let sidebarWidth: CGFloat = 236"))
    #expect(source.contains("static let sidebarInsetLeading: CGFloat = 10"))
    #expect(source.contains("static let sidebarInsetTop: CGFloat = 10"))
    #expect(source.contains("static let sidebarInsetBottom: CGFloat = 10"))
    #expect(source.contains("static let sidebarToDetailGap: CGFloat = 10"))
    #expect(source.contains("static let sidebarContentTopPadding: CGFloat = 44"))
    #expect(source.contains("static let sidebarRowVerticalPadding: CGFloat = 5"))
    #expect(source.contains("static let detailHorizontalPadding: CGFloat = 40"))
    #expect(source.contains("static let embeddedTopPadding: CGFloat = 6"))
    #expect(source.contains("static var sidebarColumnWidth: CGFloat"))
    #expect(source.contains("private var settingsSidebarList: some View"))
    #expect(!source.contains("List(selection: $selectedSection)"))
    #expect(source.contains("SettingsSidebarRowButton("))
    #expect(source.contains("private var settingsSidebar: some View"))
    #expect(source.contains("ZStack(alignment: .topLeading)"))
    #expect(source.contains(".frame(width: SettingsLayoutMetrics.sidebarWidth)"))
    #expect(source.contains("openWhisperFloatingSidebarGlass("))
    #expect(source.contains("materializationID: sidebarGlassMaterializationID"))
    #expect(source.contains("NSWindow.didDeminiaturizeNotification"))
    #expect(source.contains("sidebarGlassMaterializationID"))

    #expect(source.contains("RoundedRectangle("))
    #expect(source.contains("VibeWhisperFloatingChrome.sidebarCornerRadius"))
    #expect(source.contains(".ignoresSafeArea(.container, edges: .top)"))
    // Traffic lights stay in the system leading slot (HIG). Never re-center
    // over the rail — that walks them mid/right on every show.
    #expect(source.contains("restoreSystemTrafficLightPlacement"))
    #expect(!source.contains("alignTrafficLightsWithSidebar"))
    #expect(!source.contains("SettingsSidebarMaterialView("))
    #expect(!source.contains("view.material = .sidebar"))
    #expect(!source.contains("GeometryReader { geometry in"))
    #expect(!source.contains("HStack(spacing: 0) {\n                settingsSidebar"))
    #expect(!source.contains("settingsSidebar\n                Divider()"))
    #expect(source.contains("VibeWhisperPalette.sidebarSelectionBackground"))
    #expect(source.contains("VibeWhisperPalette.sidebarSelectionForeground"))
    #expect(source.contains("window.collectionBehavior.remove(.fullScreenPrimary)"))
    #expect(source.contains("window.standardWindowButton(.zoomButton)?.isEnabled = false"))
    #expect(source.contains("sidebarArrowKeyMonitor"))
    #expect(
        !source.contains(
            "NavigationSplitView(columnVisibility: .constant(.all))"
        )
    )
    #expect(!source.contains("VibeWhisperWindowBackdrop"))
    #expect(!source.contains("accessibilityReduceTransparency"))
    #expect(source.contains("Label("))
    #expect(!source.contains(".tag(pane)"))
    #expect(!source.contains("SettingsSidebarPresentationModel"))
    #expect(!source.contains("SettingsSidebarToggleButton"))
    #expect(!source.contains("installSidebarToggleButton"))
    #expect(!source.contains("Show or hide sidebar"))
    #expect(!source.contains("toolbar(removing: .sidebarToggle)"))
    #expect(source.contains("VibeWhisperSidebarSymbol("))
    #expect(!source.contains("VibeWhisperSidebarIconWell("))
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
    #expect(source.contains("selectedSection = .rules"))
    #expect(source.contains(".help(L10n.text(\"Open Rules…\"))"))
    #expect(!source.contains("Button(L10n.text(\"Open Skill Library…\")"))
    #expect(!source.contains("Button(L10n.text(\"Open Setup Guide\")"))
    #expect(source.contains("SkillRulesSettingsView("))
    #expect(source.contains("case .rules:"))
    #expect(source.contains("list.bullet.rectangle"))
    #expect(source.contains("window.minSize = NSSize(width: 900, height: 620)"))
    #expect(source.contains(".fullSizeContentView"))
    #expect(source.contains("window.toolbarStyle = .unified"))
    #expect(source.contains("window.titlebarSeparatorStyle = .none"))
    // Transparent plate is required so Liquid Glass continuous corners are not
    // backfilled by a rectangular NSHostingView / window layer.
    #expect(source.contains("window.isOpaque = false"))
    #expect(source.contains("window.backgroundColor = .clear"))
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
    #expect(source.contains("recoveryModelDraft"))
    #expect(source.contains("ProductModelCatalog.dictationPresets"))
    #expect(!source.contains("text: $config.transcription.openAITranscriptionURL"))
    #expect(!source.contains("text: $config.transcription.openAIModel"))
    #expect(source.contains("detectAvailableModels"))
    #expect(source.contains("setFrameAutosaveName"))
    #expect(source.contains(".resizable"))
    #expect(source.contains("case .saved:"))
    #expect(source.contains("EmptyView()"))
    #expect(!source.contains("Button(L10n.text(\"Save Settings\")"))
    #expect(source.contains("@State private var editingTerminologyID: UUID?"))
    #expect(!source.contains("editingTerminologyIndex"))
    #expect(!source.contains("prefix(5)"))
    #expect(!source.contains("edit config.json for bulk changes"))
    #expect(!source.contains("$config.transcription.languagePreference"))
    #expect(!source.contains("Chinese output"))
    #expect(source.contains("$config.transcription.punctuationPreference"))
    #expect(source.contains("$config.visualFeedback"))
    #expect(source.contains("case .appearance:"))
    #expect(source.contains("VisualFeedbackMode"))
    #expect(source.contains("appearanceAndFeedbackCard"))
    #expect(!source.contains("Preview feedback"))
    #expect(source.contains("authSnapshot.state == .ready"))
    #expect(!source.contains("private var skillSection: some View"))
    #expect(!source.contains("License & Pro"))
    #expect(!source.contains("Import Signed License…"))
    #expect(!source.contains("licenseManager"))
    #expect(!source.contains("Skills require VibeWhisper Pro"))
    #expect(source.contains("settingsCard(title: \"Context\""))
    #expect(source.contains("ContextSourceKind.userVisibleSettingsSources"))
    #expect(!source.contains("L10n.text(\"Planned\")"))
    #expect(source.contains("$config.context"))
    #expect(source.contains(".selectionEnabled"))
    #expect(source.contains("SkillPermissionScope"))
    #expect(source.contains("Reset Permissions"))
    #expect(source.contains("Open Terminologies…"))
    #expect(source.contains("onOpenTerminology()"))
    #expect(!source.contains("Technical literals such as paths"))
    // Advanced tools section is intentionally hidden this release; helpers remain.
    #expect(source.contains("onExportSupportDiagnostics"))
    #expect(source.contains("func exportSupportDiagnostics"))
    #expect(source.contains("onOpenConfigFolder"))
    #expect(!source.contains("Button(L10n.text(\"Export Diagnostics…\")"))
    #expect(!source.contains("Button(L10n.text(\"Open Config Folder\")"))
    #expect(!source.contains("Button(L10n.text(\"View Third-Party Licenses…\")"))
    #expect(!source.contains("account email, tokens, API keys"))
    #expect(source.contains("Export Product Metrics"))
    #expect(source.contains("onExportProductMetrics"))
    #expect(source.contains("if config.privacy.productMetricsEnabled"))
    #expect(!source.contains("no event timestamps"))
    // Software updates / safety remain as code paths (may be elsewhere or unused UI).
    #expect(source.contains("onSetAutomaticallyChecksForUpdates"))
    #expect(source.contains("providerCapabilityPolicy.refresh"))
    #expect(source.contains("permissionStatusMonitor.requestMicrophoneAccess"))
    #expect(source.contains("isRequestingMicrophoneAccess"))
    #expect(
        source.contains(
            "VibeWhisper still cannot confirm microphone access."
        )
    )
    #expect(source.contains("SecureField("))
    #expect(source.contains("Save API Key"))
    #expect(source.contains("Remove API Key"))
    #expect(source.contains("OpenAICompatibleConnectionTester("))
    #expect(!source.contains("generated 0.1-second silent WAV"))
    #expect(source.contains("Import Your Own API?"))
    #expect(source.contains("Use My API"))
    #expect(source.contains("Compatible Fallback"))
    #expect(source.contains("advancedRecognitionCard"))
    #expect(source.contains("advancedPolishCard"))
    #expect(source.contains("advancedAPIAccessRow"))
    #expect(source.contains("ownAPIConfigurationSheet"))
    #expect(source.contains("OwnAPIConfigurationTab"))
    #expect(source.contains("ownAPIRecognitionPane"))
    #expect(source.contains("ownAPIPolishPane"))
    #expect(source.contains("setPolishCompatibleFallback"))
    #expect(!source.contains("ProductModelCatalog.customModelTag"))
    #expect(source.contains("detectAvailableModels"))
    #expect(source.contains("ChatGPTAccountModelCatalog"))
    #expect(source.contains("availableAccountPolishModels"))
    #expect(source.contains("refreshAccountPolishModels"))
    #expect(source.contains("Configure…"))
    #expect(source.contains("ProductModelCatalog"))
    #expect(source.contains("openAIFallbackEnabled"))
    #expect(source.contains("openAICompatibleEnabled"))
    #expect(!source.contains("advancedProductRouteCard"))
    #expect(!source.contains("AI Polish remains on the ChatGPT-authenticated route"))
    #expect(!source.contains("ASR environment variable"))
    #expect(!source.contains("OPENAI_API_KEY"))
    // Advanced has no stacked route captions or explanatory small print.
    #expect(!source.contains("Choose how VibeWhisper transcribes"))
    #expect(!source.contains("API key stored in Keychain"))
    #expect(!source.contains("Optional. Save your API here"))
}


@Test
func liquidGlassStaysInSystemNavigationChrome() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let visualSystem = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/VibeWhisperVisualSystem.swift"
        ),
        encoding: .utf8
    )
    let history = try String(
        contentsOf: root.appendingPathComponent(
            "Sources/VibeWhisper/HistoryWindowController.swift"
        ),
        encoding: .utf8
    )

    #expect(!visualSystem.contains("VibeWhisperWindowBackdrop"))
    #expect(!visualSystem.contains("LinearGradient("))
    #expect(!visualSystem.contains("RadialGradient("))
    #expect(visualSystem.contains("VibeWhisperSecondaryButtonStyle: PrimitiveButtonStyle"))
    #expect(visualSystem.contains(".buttonStyle(.glass)"))
    #expect(visualSystem.contains(".buttonStyle(.glassProminent)"))
    #expect(visualSystem.contains("VibeWhisperFloatingSidebarChrome"))
    #expect(visualSystem.contains("openWhisperFloatingSidebarGlass"))
    #expect(visualSystem.contains("floatingSidebarPlate"))
    #expect(visualSystem.contains("sidebarPlateColor"))
    #expect(visualSystem.contains("materializationID"))
    #expect(visualSystem.contains("sidebarCornerRadius"))
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
        "Sources/VibeWhisper/HistoryWindowController.swift",
        "Sources/VibeWhisper/TerminologyWindowController.swift",
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
        "VibeWhisperVisualSystem.swift",
        "PreferencesWindowController.swift",
        "OnboardingWindowController.swift",
        "MicrophonePermissionWindowController.swift",
        "TerminologyQuickAddWindowController.swift",
        "SkillLibraryWindowController.swift",
    ].map {
        try String(
            contentsOf: root
                .appendingPathComponent("Sources/VibeWhisper")
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
            "Sources/VibeWhisper/StatusMenuController.swift"
        ),
        encoding: .utf8
    )

    #expect(source.contains("title: L10n.text(\"Check for Updates…\")"))
    #expect(source.contains("action: #selector(checkForUpdates)"))
    #expect(source.contains("checkForUpdatesHandler()"))
    #expect(source.contains("Retry last dictation"))
    #expect(source.contains("setRetryDictationAvailable"))
}
