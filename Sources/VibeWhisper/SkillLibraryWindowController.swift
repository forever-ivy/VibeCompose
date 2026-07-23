import AppKit
import SwiftUI

enum SkillLibrarySection: String, CaseIterable, Identifiable, Sendable {
    case installed
    case discover
    case created

    var id: String { rawValue }
}

@MainActor
final class SkillLibraryWindowController:
    NSWindowController
{
    init(
        config: AppConfig,
        store: SkillPackageStore,
        localAssetAccessEnabled: Bool,
        initialSection: SkillLibrarySection = .discover,
        onSave:
            @escaping (AppConfig) -> Result<Void, any Error>,
        onRunTest:
            @escaping (SkillTestRunRequest) async
                -> Result<SkillTestRunResult, any Error>,
        onVoiceSampleAction:
            @escaping (SkillVoiceSampleAction) async
                -> Result<SkillVoiceSampleResult, any Error>
    ) {
        let root = SkillLibraryView(
            initialConfig: config,
            store: store,
            localAssetAccessEnabled:
                localAssetAccessEnabled,
            initialSection: initialSection,
            onSave: onSave,
            onRunTest: onRunTest,
            onVoiceSampleAction: onVoiceSampleAction
        )
        .applyingVibeWhisperBrandTint()
        .applyingAccessibilityDisplayOptionsOverride(
            .currentVisualAcceptance
        )
        let hosting = NSHostingController(
            rootView: root
        )
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 1_040,
                height: 720
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(
            "VibeWhisper Skill Library"
        )
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier(
            "VibeWhisper.SkillLibraryWindow"
        )
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.minSize = NSSize(
            width: 820,
            height: 600
        )
        window.tabbingMode = .disallowed
        let restored = window.setFrameUsingName(
            "VibeWhisper.SkillLibraryWindow"
        )
        window.setFrameAutosaveName(
            "VibeWhisper.SkillLibraryWindow"
        )
        if !restored {
            window.center()
        }
        window.contentViewController = hosting
        AccessibilityDisplayOptionsOverride
            .currentVisualAcceptance
            .applyAppearance(to: window)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError(
            "init(coder:) has not been implemented"
        )
    }

    func show() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func writeSnapshot(to url: URL) throws {
        try ProductSurfaceSnapshot.write(window: window, to: url)
    }
}

struct SkillLibraryView: View {
    typealias Section = SkillLibrarySection

    private static func sectionTitle(_ section: Section) -> String {
        switch section {
        // Product chrome: Discover / Install (Created stays hidden from the segment).
        case .installed: return L10n.text("Install")
        case .discover: return L10n.text("Discover")
        case .created: return L10n.text("Created")
        }
    }

    private static func sectionSymbol(_ section: Section) -> String {
        switch section {
        case .installed:
            return "square.stack.3d.up"
        case .discover:
            return "sparkle.magnifyingglass"
        case .created:
            return "hammer"
        }
    }

    @State private var config: AppConfig
    @State private var inventory:
        CommunitySkillInventory
    @State private var selection:
        Section = .discover
    @State private var saveMessage: String?

    let store: SkillPackageStore
    let localAssetAccessEnabled: Bool
    let onSave:
        (AppConfig) -> Result<Void, any Error>
    let onRunTest:
        (SkillTestRunRequest) async
            -> Result<SkillTestRunResult, any Error>
    let onVoiceSampleAction:
        (SkillVoiceSampleAction) async
            -> Result<SkillVoiceSampleResult, any Error>
    let initialSection: Section
    let isEmbedded: Bool
    /// Shared with the Settings shell so remounting Skills (after popup /
    /// switcher dismiss rebuilds the pane) restores Discover vs Install.
    let windowStateStore: SettingsWindowStateStore

    init(
        initialConfig: AppConfig,
        store: SkillPackageStore,
        localAssetAccessEnabled: Bool,
        initialSection: Section = .discover,
        isEmbedded: Bool = false,
        windowStateStore: SettingsWindowStateStore =
            SettingsWindowStateStore(),
        preferredSection: Section? = nil,
        onSave:
            @escaping (AppConfig) -> Result<Void, any Error>,
        onRunTest:
            @escaping (SkillTestRunRequest) async
                -> Result<SkillTestRunResult, any Error>,
        onVoiceSampleAction:
            @escaping (SkillVoiceSampleAction) async
                -> Result<SkillVoiceSampleResult, any Error>
    ) {
        _config = State(initialValue: initialConfig)
        _inventory = State(
            initialValue: CommunitySkillInventory(
                packages: [],
                rejected: []
            )
        )
        self.store = store
        self.localAssetAccessEnabled =
            localAssetAccessEnabled
        self.onSave = onSave
        self.onRunTest = onRunTest
        self.onVoiceSampleAction = onVoiceSampleAction
        // Resolution order:
        // 1. explicit preferredSection (one-shot deep link)
        // 2. non-default initialSection (standalone window / first create)
        //    — also seeds the store so later remounts stay put
        // 3. last persisted Discover/Install tab
        // Default `.discover` as initialSection is treated as "no preference"
        // so closing a popup never forces users back onto Discover ("home").
        let effectiveSection: Section = {
            if let preferredSection {
                return preferredSection
            }
            if initialSection != .discover {
                windowStateStore.saveSkillLibrarySection(initialSection)
                return initialSection
            }
            return windowStateStore.initialSkillLibrarySection()
        }()
        self.initialSection = effectiveSection
        self.isEmbedded = isEmbedded
        self.windowStateStore = windowStateStore
        _selection = State(initialValue: effectiveSection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let saveMessage {
                HStack {
                    Spacer(minLength: 0)
                    Label(
                        saveMessage,
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .font(VibeWhisperTypography.micro())
                    .foregroundStyle(Color(nsColor: VibeWhisperPalette.amber))
                    .lineLimit(1)
                }
                .padding(.horizontal, VibeWhisperMetrics.space20)
                .padding(.bottom, VibeWhisperMetrics.space6)
            }
            Divider().opacity(0.45)
            content
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        }
        .frame(
            minWidth: 620,
            minHeight: 520
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: config.communitySkills) {
            guard localAssetAccessEnabled else {
                inventory = CommunitySkillInventory(
                    packages: [],
                    rejected: []
                )
                return
            }
            let packageStore = store
            let communitySkills = config.communitySkills
            let loadedInventory = await Task.detached(priority: .utility) {
                packageStore.loadInventory(config: communitySkills)
            }.value
            guard !Task.isCancelled, config.communitySkills == communitySkills else {
                return
            }
            inventory = loadedInventory
        }
        .onChange(of: config) { value in
            switch onSave(value) {
            case .success:
                saveMessage = nil
            case let .failure(error):
                saveMessage = error.localizedDescription
            }
        }
        .onChange(of: selection) { section in
            // Persist every user segment change so remounting Skills (e.g.
            // after Skill Switcher / sheet dismiss rebuilds the pane via
            // `.id(activeSection)`) restores the same tab.
            windowStateStore.saveSkillLibrarySection(section)
        }
        .onAppear {
            windowStateStore.saveSkillLibrarySection(selection)
        }
    }

    private var header: some View {
        VibeWhisperPaneHeader(title: L10n.text("Skill Library")) {
            sectionPicker
        }
    }

    /// UI-visible tabs only. `.created` stays in the model for launch args /
    /// acceptance, but is temporarily hidden from the segment control.
    /// Order matches product chrome: Discover → Install.
    private static let visibleSections: [Section] = [
        .discover,
        .installed,
    ]

    private var sectionPicker: some View {
        Picker(
            L10n.text("Skill Library"),
            selection: $selection
        ) {
            ForEach(Self.visibleSections) { section in
                Text(Self.sectionTitle(section))
                    .tag(section)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(isEmbedded ? .large : .regular)
        // Two segments only while Created is off the chrome.
        .frame(width: isEmbedded ? 180 : 200)
        .onAppear {
            // If a deep link / acceptance pass still targets Created, leave
            // selection alone so content can render; the segment just won't
            // highlight. Everyday opens fall back to a visible tab.
            if !Self.visibleSections.contains(selection),
               selection != .created
            {
                selection = .discover
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .installed:
            ScrollView {
                CommunitySkillSettingsView(
                    config: $config,
                    inventory: $inventory,
                    store: store,
                    localAssetAccessEnabled:
                        localAssetAccessEnabled,
                    onRunTest: onRunTest
                )
                .padding(22)
            }
        case .discover:
            BuiltInSkillDiscoveryView(
                config: $config,
                onRunTest: onRunTest
            )
        case .created:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    createdSummary
                    Divider()
                    SkillCreatorSettingsView(
                        config: $config,
                        inventory: $inventory,
                        store: store,
                        localAssetAccessEnabled:
                            localAssetAccessEnabled,
                        onRunTest: onRunTest,
                        onVoiceSampleAction:
                            onVoiceSampleAction
                    )
                }
                .padding(22)
            }
        }
    }

    private var createdSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text("Created Skills"))
                .font(.system(size: 15, weight: .semibold))
        }
    }
}

/// Global default Skill + per-app application rules.
/// Hosted as Settings → Library → Rules (not inside Skill Install).
struct SkillRulesSettingsView: View {
    private enum RulesTab: String, CaseIterable, Identifiable {
        case globalDefault
        case applicationRules

        var id: String { rawValue }

        var title: String {
            switch self {
            case .globalDefault:
                return L10n.text("Global default")
            case .applicationRules:
                return L10n.text("Application Rules")
            }
        }
    }

    @Binding var config: AppConfig
    let inventory: CommunitySkillInventory

    @State private var selectedTab: RulesTab = .applicationRules
    @State private var showsAddRuleSheet = false
    @State private var ruleName = ""
    @State private var bundleIdentifier = ""
    @State private var selectedSkillID = SkillRegistry.directSkillID
    @State private var sheetMessage: String?
    @State private var sheetMessageIsError = false

    private var registry: SkillRegistry {
        inventory.registry
    }

    private var applicationRules: [AppSkillRule] {
        config.transcription.skills.applicationRules
    }

    private var canAddRule: Bool {
        !bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var defaultSkillBinding: Binding<String> {
        Binding(
            get: {
                config.transcription.skills.defaultSkillID
            },
            set: { skillID in
                config.transcription.skills.setDefault(
                    skillID: skillID,
                    installationID: installationID(for: skillID),
                    registry: registry
                )
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title + segmented only. A status chip in this header used to
            // compress into a thin vertical pill between title and tabs when
            // the detail column was narrow (screenshot regression).
            VibeWhisperPaneHeader(title: L10n.text("Rules")) {
                tabBar
            }

            ScrollView {
                Group {
                    switch selectedTab {
                    case .globalDefault:
                        globalDefaultCard
                    case .applicationRules:
                        applicationRulesCard
                    }
                }
                .padding(22)
                .frame(
                    maxWidth: VibeWhisperMetrics.contentMaxWidth,
                    alignment: .leading
                )
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(VibeWhisperMotion.standardSpring, value: selectedTab)
        .sheet(isPresented: $showsAddRuleSheet) {
            addRuleSheet
        }
    }

    private var tabBar: some View {
        Picker(L10n.text("Rules"), selection: $selectedTab) {
            ForEach(RulesTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        // Intrinsic width so zh-Hans labels ("全局默认" / "应用规则")
        // never clip; a fixed 280 frame left dead space that read as a
        // stray divider next to the title.
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityLabel(L10n.text("Rules"))
    }

    private var globalDefaultCard: some View {
        SettingsCardContainer(title: "Global default") {
            SettingsRow(title: L10n.text("Default Skill")) {
                Picker(
                    L10n.text("Default Skill"),
                    selection: defaultSkillBinding
                ) {
                    ForEach(registry.orderedDefinitions) { skill in
                        Text(skill.localizedName).tag(skill.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(
                    width: GeneralSettingsChrome.controlClusterWidth,
                    alignment: .trailing
                )
            }
        }
    }

    private var applicationRulesCard: some View {
        SettingsCardContainer(title: "Application Rules") {
            VStack(alignment: .leading, spacing: VibeWhisperMetrics.space14) {
                HStack(spacing: VibeWhisperMetrics.space12) {
                    if !applicationRules.isEmpty {
                        VibeWhisperStatusChip(
                            text: L10n.format(
                                "%ld rules",
                                applicationRules.count
                            ),
                            kind: .neutral
                        )
                        .fixedSize()
                    }
                    Spacer(minLength: 0)
                    Button(L10n.text("Add Rule")) {
                        openAddRuleSheet()
                    }
                    .buttonStyle(VibeWhisperPrimaryButtonStyle())
                    .controlSize(.large)
                }

                rulesTable
            }
        }
    }

    private var rulesTable: some View {
        VStack(spacing: 0) {
            rulesTableHeader

            Divider().opacity(0.45)

            if applicationRules.isEmpty {
                emptyRulesState
            } else {
                ForEach(
                    Array(applicationRules.enumerated()),
                    id: \.element.id
                ) { index, rule in
                    if index > 0 {
                        Divider()
                            .opacity(0.35)
                            .padding(.leading, 16)
                    }
                    ruleTableRow(rule)
                }
            }
        }
        .openWhisperInset(
            padding: 0,
            cornerRadius: VibeWhisperMetrics.radiusL
        )
    }

    private var rulesTableHeader: some View {
        HStack(spacing: VibeWhisperMetrics.space12) {
            Text(L10n.text("Enabled"))
                .frame(width: 44, alignment: .leading)
            Text(L10n.text("Rule name"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.text("Application"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.text("Skill"))
                .frame(width: 168, alignment: .leading)
            // Align with trash control.
            Color.clear.frame(width: 32, height: 1)
        }
        .font(VibeWhisperTypography.caption(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, VibeWhisperMetrics.space14)
        .padding(.vertical, VibeWhisperMetrics.space10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("Application Rules"))
    }

    private var emptyRulesState: some View {
        VStack(spacing: VibeWhisperMetrics.space12) {
            Image(systemName: "tablecells")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Text(L10n.text("No application rules"))
                .font(VibeWhisperTypography.callout(.medium))
                .foregroundStyle(.secondary)
            Button(L10n.text("Add Rule")) {
                openAddRuleSheet()
            }
            .buttonStyle(VibeWhisperSecondaryButtonStyle())
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, VibeWhisperMetrics.space32)
        .padding(.horizontal, VibeWhisperMetrics.space16)
        .accessibilityElement(children: .combine)
    }

    private func ruleTableRow(_ rule: AppSkillRule) -> some View {
        HStack(spacing: VibeWhisperMetrics.space12) {
            Toggle(
                L10n.format(
                    "Enable Skill rule for %@",
                    displayRuleName(for: rule)
                ),
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: { enabled in
                        guard let index = config.transcription
                            .skills.applicationRules.firstIndex(
                                where: { $0.id == rule.id }
                            )
                        else { return }
                        config.transcription.skills
                            .applicationRules[index]
                            .isEnabled = enabled
                    }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .frame(width: 44, alignment: .leading)

            HStack(spacing: VibeWhisperMetrics.space10) {
                applicationIcon(
                    for: rule.bundleIdentifier,
                    enabled: rule.isEnabled,
                    size: 22
                )
                Text(displayRuleName(for: rule))
                    .font(VibeWhisperTypography.body(.medium))
                    .foregroundStyle(
                        rule.isEnabled ? .primary : .secondary
                    )
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(rule.bundleIdentifier)
                .font(VibeWhisperTypography.mono(11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker(
                L10n.text("Skill"),
                selection: Binding(
                    get: { rule.skillID },
                    set: { skillID in
                        replaceRule(rule, skillID: skillID)
                    }
                )
            ) {
                ForEach(registry.orderedDefinitions) { skill in
                    Text(skill.localizedName).tag(skill.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 168, alignment: .leading)
            .opacity(rule.isEnabled ? 1 : 0.5)
            .disabled(!rule.isEnabled)

            Button(role: .destructive) {
                withAnimation(VibeWhisperMotion.snappySpring) {
                    config.transcription.skills.remove(id: rule.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(VibeWhisperSecondaryButtonStyle())
            .controlSize(.small)
            .help(L10n.text("Delete"))
            .accessibilityLabel(
                L10n.format(
                    "Delete Skill rule for %@",
                    displayRuleName(for: rule)
                )
            )
        }
        .padding(.horizontal, VibeWhisperMetrics.space14)
        .padding(.vertical, VibeWhisperMetrics.space12)
        .opacity(rule.isEnabled ? 1 : 0.78)
        .accessibilityElement(children: .contain)
    }

    private var addRuleSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.text("Add Rule"))
                    .font(VibeWhisperTypography.title2())
                Spacer(minLength: 0)
                Button {
                    showsAddRuleSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.text("Cancel"))
            }
            .padding(.horizontal, VibeWhisperMetrics.space20)
            .padding(.top, VibeWhisperMetrics.space18)
            .padding(.bottom, VibeWhisperMetrics.space14)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: VibeWhisperMetrics.space16) {
                sheetField(title: L10n.text("Rule name")) {
                    TextField(
                        L10n.text("Rule name"),
                        text: $ruleName,
                        prompt: Text(L10n.text("e.g. Claude coding"))
                    )
                    .textFieldStyle(.roundedBorder)
                }

                sheetField(title: L10n.text("Application")) {
                    HStack(spacing: VibeWhisperMetrics.space10) {
                        Button(L10n.text("Choose App…")) {
                            chooseApplication()
                        }
                        .buttonStyle(VibeWhisperPrimaryButtonStyle())
                        .controlSize(.regular)

                        if !bundleIdentifier
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                        {
                            applicationIcon(
                                for: bundleIdentifier,
                                enabled: true,
                                size: 22
                            )
                        }

                        TextField(
                            L10n.text("Bundle identifier"),
                            text: $bundleIdentifier,
                            prompt: Text("com.apple.TextEdit")
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(VibeWhisperTypography.mono(12))
                    }
                }

                sheetField(title: L10n.text("Skill")) {
                    Picker(
                        L10n.text("Skill"),
                        selection: $selectedSkillID
                    ) {
                        ForEach(registry.orderedDefinitions) { skill in
                            Text(skill.localizedName).tag(skill.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let sheetMessage {
                    InlineStatus(
                        text: sheetMessage,
                        kind: sheetMessageIsError ? .error : .success
                    )
                }
            }
            .padding(.horizontal, VibeWhisperMetrics.space20)
            .padding(.vertical, VibeWhisperMetrics.space18)

            Spacer(minLength: 0)

            Divider().opacity(0.4)

            HStack {
                Spacer(minLength: 0)
                Button(L10n.text("Cancel")) {
                    showsAddRuleSheet = false
                }
                .buttonStyle(VibeWhisperSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(L10n.text("Add Rule")) {
                    addRuleFromSheet()
                }
                .buttonStyle(VibeWhisperPrimaryButtonStyle())
                .disabled(!canAddRule)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, VibeWhisperMetrics.space20)
            .padding(.vertical, VibeWhisperMetrics.space14)
        }
        .frame(width: 520, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sheetField<Field: View>(
        title: String,
        @ViewBuilder field: () -> Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(VibeWhisperTypography.caption(.medium))
                .foregroundStyle(.secondary)
            field()
        }
    }

    private func displayRuleName(for rule: AppSkillRule) -> String {
        if let name = rule.appName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty
        {
            return name
        }
        return rule.bundleIdentifier
    }

    private func openAddRuleSheet() {
        ruleName = ""
        bundleIdentifier = ""
        selectedSkillID = SkillRegistry.directSkillID
        sheetMessage = nil
        sheetMessageIsError = false
        showsAddRuleSheet = true
    }

    private func applicationIcon(
        for bundleIdentifier: String,
        enabled: Bool,
        size: CGFloat = 28
    ) -> some View {
        let image = Self.iconImage(for: bundleIdentifier)
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: size * 0.25,
                    style: .continuous
                )
            )
            .opacity(enabled ? 1 : 0.55)
            .accessibilityHidden(true)
    }

    private static func iconImage(
        for bundleIdentifier: String
    ) -> NSImage {
        let workspace = NSWorkspace.shared
        let trimmed = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty,
           let url = workspace.urlForApplication(
               withBundleIdentifier: trimmed
           )
        {
            let icon = workspace.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            return icon
        }
        let fallback = NSImage(
            systemSymbolName: "app.fill",
            accessibilityDescription: nil
        ) ?? NSImage(
            size: NSSize(width: 32, height: 32)
        )
        fallback.size = NSSize(width: 32, height: 32)
        return fallback
    }

    private func addRuleFromSheet() {
        do {
            let rule = try AppSkillRule.validated(
                appName: ruleName,
                bundleIdentifier: bundleIdentifier,
                skillID: selectedSkillID,
                skillInstallationID:
                    installationID(for: selectedSkillID),
                registry: registry
            )
            withAnimation(VibeWhisperMotion.standardSpring) {
                config.transcription.skills.upsert(
                    rule,
                    registry: registry
                )
            }
            showsAddRuleSheet = false
            ruleName = ""
            bundleIdentifier = ""
            sheetMessage = nil
            sheetMessageIsError = false
        } catch {
            sheetMessage = error.localizedDescription
            sheetMessageIsError = true
            NSSound.beep()
        }
    }

    private func replaceRule(
        _ rule: AppSkillRule,
        skillID: String
    ) {
        guard let replacement = try? AppSkillRule.validated(
            id: rule.id,
            appName: rule.appName,
            bundleIdentifier: rule.bundleIdentifier,
            skillID: skillID,
            skillInstallationID: installationID(for: skillID),
            isEnabled: rule.isEnabled,
            registry: registry
        ) else { return }
        config.transcription.skills.upsert(
            replacement,
            registry: registry
        )
    }

    private func installationID(
        for skillID: String
    ) -> UUID? {
        inventory.packages.first {
            $0.isActive
                && $0.definition.id == skillID
        }?.installation.id
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(
            fileURLWithPath: "/Applications",
            isDirectory: true
        )
        panel.title = L10n.text("Choose an Application")
        panel.prompt = L10n.text("Choose App")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              AppModeRule.isValidBundleIdentifier(identifier)
        else {
            if panel.url != nil {
                sheetMessage = L10n.text(
                    "The selected application does not expose a valid bundle identifier."
                )
                sheetMessageIsError = true
                NSSound.beep()
            }
            return
        }

        let displayName = bundle.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String
            ?? bundle.object(
                forInfoDictionaryKey: "CFBundleName"
            ) as? String
            ?? url.deletingPathExtension().lastPathComponent
        bundleIdentifier = AppModeRule.normalizedBundleIdentifier(
            identifier
        )
        // Prefer an explicit rule name; seed from app name when empty.
        if ruleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ruleName = displayName
        }
        sheetMessage = nil
        sheetMessageIsError = false
    }
}

/// Visual presentation for a Skill — shared chassis with a family façade.
/// Accents drive hero atmosphere, icon tint, and example chrome without
/// inventing per-skill one-off layouts.
enum SkillPresentationFamily: String, Sendable, Equatable {
    case faithful
    case conversational
    case compose
    case structure
    case technical
    case transform
    case generic

    var accent: NSColor {
        switch self {
        case .faithful:
            return VibeWhisperPalette.brandBlue
        case .conversational:
            return VibeWhisperPalette.brandSpectrumCoral
        case .compose:
            return VibeWhisperPalette.brandSpectrumViolet
        case .structure:
            return VibeWhisperPalette.brandSpectrumAmber
        case .technical:
            return VibeWhisperPalette.brandSpectrumCyan
        case .transform:
            return VibeWhisperPalette.atmospherePeriwinkle
        case .generic:
            return VibeWhisperPalette.brandBlue
        }
    }

    /// Second stop for the atmospheric banner gradient.
    var atmosphereSecondary: NSColor {
        switch self {
        case .faithful:
            return VibeWhisperPalette.atmosphereDeep
        case .conversational:
            return VibeWhisperPalette.brandSpectrumAmber
        case .compose:
            return VibeWhisperPalette.atmosphereIndigo
        case .structure:
            return VibeWhisperPalette.brandSpectrumCoral
        case .technical:
            return VibeWhisperPalette.brandSpectrumSky
        case .transform:
            return VibeWhisperPalette.atmosphereLavender
        case .generic:
            return VibeWhisperPalette.atmosphereIndigo
        }
    }
}

enum SkillShowcaseMode: String, Sendable, Equatable {
    /// Plain-text Say → Get transformation.
    case transform
    /// Markdown multi-section outline (validators-driven pills + sample).
    case structure
    /// Message / letter-style compose sheet.
    case compose
}

struct SkillPresentation: Sendable, Equatable {
    let family: SkillPresentationFamily
    let showcase: SkillShowcaseMode
    let symbolName: String

    var accent: NSColor { family.accent }
    var atmosphereSecondary: NSColor { family.atmosphereSecondary }

    static func forSkill(_ skill: SkillDefinition) -> SkillPresentation {
        forSkillID(skill.id, outputFormat: skill.output.format)
    }

    static func forSkillID(
        _ id: String,
        outputFormat: SkillOutputFormat = .plainText
    ) -> SkillPresentation {
        switch id {
        case SkillRegistry.directSkillID:
            return .init(
                family: .faithful,
                showcase: .transform,
                symbolName: "text.cursor"
            )
        case SkillRegistry.replySkillID:
            return .init(
                family: .conversational,
                showcase: .transform,
                symbolName: "arrowshape.turn.up.left.fill"
            )
        case SkillRegistry.emailSkillID:
            return .init(
                family: .compose,
                showcase: .compose,
                symbolName: "envelope.fill"
            )
        case SkillRegistry.agentPlanSkillID:
            return .init(
                family: .structure,
                showcase: .structure,
                symbolName: "brain"
            )
        case SkillRegistry.codePromptSkillID:
            return .init(
                family: .technical,
                showcase: .transform,
                symbolName: "chevron.left.forwardslash.chevron.right"
            )
        case SkillRegistry.translateSkillID:
            return .init(
                family: .transform,
                showcase: .transform,
                symbolName: "character.bubble.fill"
            )
        case SkillRegistry.contextRewriteSkillID:
            return .init(
                family: .transform,
                showcase: .transform,
                symbolName: "text.badge.checkmark"
            )
        case SkillRegistry.contextReplySkillID:
            return .init(
                family: .conversational,
                showcase: .transform,
                symbolName: "quote.bubble.fill"
            )
        case SkillRegistry.bugReportSkillID:
            return .init(
                family: .structure,
                showcase: .structure,
                symbolName: "ladybug.fill"
            )
        case SkillRegistry.commitMessageSkillID:
            return .init(
                family: .technical,
                showcase: .transform,
                symbolName: "point.topleft.down.curvedto.point.bottomright.up.fill"
            )
        case SkillRegistry.meetingActionItemsSkillID:
            return .init(
                family: .structure,
                showcase: .structure,
                symbolName: "checklist"
            )
        case SkillRegistry.productBriefSkillID:
            return .init(
                family: .compose,
                showcase: .structure,
                symbolName: "doc.text.fill"
            )
        case SkillRegistry.customerSupportReplySkillID:
            return .init(
                family: .conversational,
                showcase: .compose,
                symbolName: "bubble.left.and.bubble.right.fill"
            )
        default:
            let showcase: SkillShowcaseMode =
                outputFormat == .markdown ? .structure : .transform
            return .init(
                family: .generic,
                showcase: showcase,
                symbolName: "wand.and.stars"
            )
        }
    }
}

extension SkillDefinition {
    /// Brand-forward symbol used for skill tiles in the library.
    /// Falls back to a wand for community/local skills.
    var openWhisperSymbol: String {
        SkillPresentation.forSkill(self).symbolName
    }

    var presentation: SkillPresentation {
        SkillPresentation.forSkill(self)
    }
}

private struct BuiltInSkillDiscoveryView: View {
    @Binding var config: AppConfig
    let onRunTest:
        (SkillTestRunRequest) async
            -> Result<SkillTestRunResult, any Error>

    @State private var searchText = ""
    @State private var selectedID =
        SkillRegistry.directSkillID

    private var skills: [SkillDefinition] {
        let query = searchText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .folding(
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                ],
                locale: .current
            )
        return SkillRegistry.builtIn
            .orderedDefinitions
            .filter { skill in
                query.isEmpty
                    || [
                        skill.localizedName,
                        skill.localizedSummary,
                        skill.localizedUseCase,
                        skill.author,
                    ]
                    .joined(separator: " ")
                    .folding(
                        options: [
                            .caseInsensitive,
                            .diacriticInsensitive,
                        ],
                        locale: .current
                    )
                    .contains(query)
            }
    }

    private var selected: SkillDefinition? {
        skills.first { $0.id == selectedID }
            ?? skills.first
    }

    private let cardColumns = [
        GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 14)
    ]

    var body: some View {
        HStack(spacing: 0) {
            // App Store–style collection: search + card grid
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(
                            L10n.text("Search Skills"),
                            text: $searchText
                        )
                        .textFieldStyle(.plain)
                    }
                    .openWhisperSearchField()
                    .frame(maxWidth: 340)

                    LazyVGrid(columns: cardColumns, spacing: 14) {
                        ForEach(skills) { skill in
                            skillCard(skill)
                                .contentShape(
                                    RoundedRectangle(
                                        cornerRadius: VibeWhisperMetrics.radiusXL,
                                        style: .continuous
                                    )
                                )
                                .onTapGesture {
                                    selectedID = skill.id
                                }
                        }
                    }

                    if skills.isEmpty {
                        VibeWhisperEmptyState(
                            systemImage: "magnifyingglass",
                            title: L10n.text("No matching Skills")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                }
                .padding(22)
            }
            .frame(maxWidth: .infinity)

            Divider().opacity(0.45)

            if let selected {
                SkillDiscoveryDetail(
                    skill: selected,
                    config: $config
                )
                .frame(minWidth: 380, idealWidth: 460, maxWidth: 520)
                .background(
                    Color(nsColor: VibeWhisperPalette.insetSurface)
                )
            }
        }
    }

    private func skillCard(_ skill: SkillDefinition) -> some View {
        let isSelected = selected?.id == skill.id
        let presentation = skill.presentation
        let accent = Color(nsColor: presentation.accent)
        return VStack(alignment: .leading, spacing: VibeWhisperMetrics.space12) {
            // Icon + title share a horizontal band so the name isn't stranded
            // under a large empty well (was reading as sparse on white cards).
            HStack(alignment: .center, spacing: VibeWhisperMetrics.space12) {
                VibeWhisperIconWell(
                    systemName: presentation.symbolName,
                    size: 36,
                    symbolSize: 16,
                    tint: accent,
                    fillOpacity: isSelected ? 0.16 : 0.11
                )
                Text(skill.localizedName)
                    .font(VibeWhisperTypography.title2(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            Text(skill.localizedSummary)
                .font(VibeWhisperTypography.callout())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(VibeWhisperMetrics.space16)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(
            Color(nsColor: VibeWhisperPalette.elevatedSurface),
            in: RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusXL,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusXL,
                style: .continuous
            )
            .stroke(
                isSelected
                    ? accent.opacity(0.85)
                    : Color.primary.opacity(0.06),
                lineWidth: isSelected ? 1.5 : 0.5
            )
        }
        .shadow(
            color: Color.black.opacity(isSelected ? 0.08 : 0.03),
            radius: isSelected ? 10 : 4,
            x: 0,
            y: isSelected ? 4 : 2
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(skill.localizedName). \(skill.localizedSummary)"
        )
        .accessibilityAddTraits(.isButton)
    }
}

private struct SkillDiscoveryDetail: View {
    let skill: SkillDefinition
    @Binding var config: AppConfig

    private var presentation: SkillPresentation {
        skill.presentation
    }

    private var accent: Color {
        Color(nsColor: presentation.accent)
    }

    private var installation: InstalledSkillIdentity {
        InstalledSkillIdentity.normalized(
            definition: skill,
            sourceID: "builtin"
        )
    }

    private var isGlobalDefault: Bool {
        config.transcription.skills.defaultSkillID == skill.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Codex / App Store editorial stack:
                // identity → atmospheric promise → prose → showcase → specs → safety
                identityHeader
                    .padding(.bottom, VibeWhisperMetrics.space20)

                atmosphericBanner
                    .padding(.bottom, VibeWhisperMetrics.space20)

                proseBlock
                    .padding(.bottom, VibeWhisperMetrics.space28)

                showcaseSection
                    .padding(.bottom, VibeWhisperMetrics.space28)

                specsSection
                    .padding(.bottom, VibeWhisperMetrics.space24)

                safetySection
            }
            .padding(VibeWhisperMetrics.space24)
            .frame(maxWidth: 650, alignment: .leading)
        }
    }

    // MARK: Identity (Codex-style header)

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: VibeWhisperMetrics.space14) {
            HStack(alignment: .top, spacing: VibeWhisperMetrics.space14) {
                VibeWhisperIconWell(
                    systemName: presentation.symbolName,
                    size: 56,
                    symbolSize: 24,
                    tint: accent,
                    fillOpacity: 0.14
                )

                Spacer(minLength: VibeWhisperMetrics.space12)

                defaultActionButton
            }

            VStack(alignment: .leading, spacing: VibeWhisperMetrics.space6) {
                HStack(spacing: VibeWhisperMetrics.space6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.text("Built-in · reviewed"))
                        .font(VibeWhisperTypography.micro(.semibold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                }
                .foregroundStyle(accent)

                Text(skill.localizedName)
                    .font(VibeWhisperTypography.display())
                    .tracking(-0.5)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(skill.localizedSummary)
                    .font(VibeWhisperTypography.callout())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
    }

    @ViewBuilder
    private var defaultActionButton: some View {
        if isGlobalDefault {
            defaultSkillStatus
        } else {
            setAsDefaultButton
        }
    }

    /// Quiet system control in the detail header — secondary glass on macOS 26,
    /// bordered earlier. Not a primary CTA: the page is a catalog, not a funnel.
    private var setAsDefaultButton: some View {
        Button(L10n.text("Set as Global Default")) {
            setAsDefault()
        }
        .buttonStyle(VibeWhisperSecondaryButtonStyle())
        .controlSize(.regular)
        .help(L10n.text("Set as Global Default"))
        .accessibilityLabel(L10n.text("Set as Global Default"))
    }

    /// Status only — matches the Built-in seal chip language, no button chrome.
    private var defaultSkillStatus: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
            Text(L10n.text("Default Skill"))
                .font(VibeWhisperTypography.body(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("Default Skill"))
        .accessibilityAddTraits(.isStaticText)
    }

    private func setAsDefault() {
        config.transcription.skills.setDefault(
            skillID: skill.id,
            installationID: installation.id
        )
    }

    // MARK: Atmospheric banner (Codex hero strip)

    private var atmosphericBanner: some View {
        let values = exampleValues
        return ZStack {
            RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusXXL,
                style: .continuous
            )
            .fill(atmosphereGradient)
            .overlay {
                // Soft bloom orbs — family-tinted, not decorative noise.
                Circle()
                    .fill(accent.opacity(0.35))
                    .frame(width: 160, height: 160)
                    .blur(radius: 48)
                    .offset(x: 120, y: -20)
                Circle()
                    .fill(
                        Color(nsColor: presentation.atmosphereSecondary)
                            .opacity(0.28)
                    )
                    .frame(width: 140, height: 140)
                    .blur(radius: 44)
                    .offset(x: -100, y: 30)
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: VibeWhisperMetrics.radiusXXL,
                    style: .continuous
                )
            )

            // Promise capsule — the one-line capability story.
            HStack(alignment: .center, spacing: VibeWhisperMetrics.space10) {
                Image(systemName: presentation.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 28, height: 28)
                    .background(
                        Color.white.opacity(0.12),
                        in: RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.localizedName)
                        .font(VibeWhisperTypography.micro(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(bannerPromise)
                        .font(VibeWhisperTypography.callout(.medium))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(
                        Color.white.opacity(0.14),
                        in: Circle()
                    )
            }
            .padding(.horizontal, VibeWhisperMetrics.space14)
            .padding(.vertical, VibeWhisperMetrics.space12)
            .background(
                Color.black.opacity(0.42),
                in: RoundedRectangle(
                    cornerRadius: VibeWhisperMetrics.radiusXL,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: VibeWhisperMetrics.radiusXL,
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .padding(.horizontal, VibeWhisperMetrics.space18)
            .padding(.vertical, VibeWhisperMetrics.space28)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(skill.localizedName). \(bannerPromise)"
            )
            // Keep example values reachable for VoiceOver via showcase section.
            .accessibilityHint(values.0)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 132)
    }

    private var atmosphereGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(nsColor: presentation.accent).opacity(0.92),
                Color(nsColor: presentation.atmosphereSecondary).opacity(0.78),
                Color(nsColor: presentation.accent).opacity(0.55),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Compact capability line for the atmospheric capsule — prefer use-case
    /// when short, otherwise fall back to summary.
    private var bannerPromise: String {
        let useCase = skill.localizedUseCase
        if useCase.count <= 120 {
            return useCase
        }
        return skill.localizedSummary
    }

    // MARK: Prose

    private var proseBlock: some View {
        Text(skill.localizedUseCase)
            .font(VibeWhisperTypography.body())
            .foregroundStyle(.primary.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(4)
    }

    // MARK: Showcase (family-aware)

    @ViewBuilder
    private var showcaseSection: some View {
        let values = exampleValues
        VStack(alignment: .leading, spacing: VibeWhisperMetrics.space12) {
            sectionTitle(L10n.text("Example"))

            switch presentation.showcase {
            case .transform:
                transformShowcase(say: values.0, get: values.1)
            case .structure:
                structureShowcase(say: values.0, get: values.1)
            case .compose:
                composeShowcase(say: values.0, get: values.1)
            }
        }
    }

    private func transformShowcase(say: String, get: String) -> some View {
        SkillShowcasePlayer(
            mode: .transform,
            say: say,
            get: get,
            outline: [],
            symbolName: presentation.symbolName,
            accent: accent
        )
    }

    private func structureShowcase(say: String, get: String) -> some View {
        SkillShowcasePlayer(
            mode: .structure,
            say: say,
            get: get,
            outline: structureOutlineLabels,
            symbolName: presentation.symbolName,
            accent: accent
        )
    }

    private func composeShowcase(say: String, get: String) -> some View {
        let subject = composeSubject(from: get)
        return SkillShowcasePlayer(
            mode: .compose,
            say: say,
            get: get,
            outline: [],
            symbolName: presentation.symbolName,
            accent: accent,
            composeSubject: subject,
            composeBody: subject.map { composeBody(from: get, subject: $0) } ?? get
        )
    }

    private var structureOutlineLabels: [String] {
        skill.validators.requiredSectionAlternatives.compactMap {
            $0.first
        }
    }

    private func composeSubject(from output: String) -> String? {
        // Match "主题：…" or "Subject: …" first line.
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        let prefixes = ["主题：", "主题:", "Subject：", "Subject:"]
        for prefix in prefixes where first.hasPrefix(prefix) {
            let value = first.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }

    private func composeBody(from output: String, subject: String) -> String {
        // Drop the subject line we already rendered.
        let lines = output.components(separatedBy: .newlines)
        var dropped = false
        var kept: [String] = []
        for line in lines {
            if !dropped {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains(subject)
                    || trimmed.hasPrefix("主题")
                    || trimmed.hasPrefix("Subject")
                {
                    dropped = true
                    continue
                }
            }
            kept.append(line)
        }
        return kept
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var exampleValues: (String, String) {
        // English source strings are the L10n keys (see Localization.swift).
        // Chinese UI resolves the matching zh-Hans entries below.
        switch skill.id {
        case SkillRegistry.directSkillID:
            return (
                L10n.text(
                    "Sync with the design team on API v2 tomorrow at 3 PM."
                ),
                L10n.text(
                    "Sync with the design team on API v2 tomorrow at 3 PM."
                )
            )
        case SkillRegistry.replySkillID:
            return (
                L10n.text(
                    "Reply to Zhou: Got it, I'll finish the API v2 compatibility check by Thursday."
                ),
                L10n.text(
                    "Got it. I'll finish the API v2 compatibility check by Thursday."
                )
            )
        case SkillRegistry.emailSkillID:
            return (
                L10n.text(
                    "Email Professor Wang to confirm Friday's review and note that the latest version is attached."
                ),
                L10n.text(
                    "Subject: Confirm Friday review\n\nHi Professor Wang, I'd like to confirm the Friday review schedule. The latest materials are attached."
                )
            )
        case SkillRegistry.agentPlanSkillID:
            return (
                L10n.text(
                    "Have backend add a 25 MB upload limit, return 413 when exceeded, keep existing auth, and add boundary tests."
                ),
                L10n.text(
                    "## Goal\nAdd a 25 MB upload limit.\n\n## Constraints\n- Preserve existing authentication.\n- Return HTTP 413 above the limit.\n\n## Implementation Steps\n1. Enforce the limit in the upload path.\n2. Add boundary tests.\n\n## Edge Cases\n- Exactly 25 MB.\n- More than 25 MB.\n\n## Acceptance Criteria\n- Existing authentication still applies.\n- Oversized uploads return HTTP 413."
                )
            )
        case SkillRegistry.codePromptSkillID:
            return (
                L10n.text(
                    "Update Sources/VibeWhisper/PreviewRuntime.swift so that with no selection it only shows Paste to Target, and run swift test --filter PreviewRuntimeTests."
                ),
                L10n.text(
                    "Update `Sources/VibeWhisper/PreviewRuntime.swift` so Preview shows `Paste to Target` and does not offer selection replacement when no selection is available.\n\nVerify with `swift test --filter PreviewRuntimeTests`."
                )
            )
        case SkillRegistry.translateSkillID:
            return (
                L10n.text(
                    "Translate to English: Please confirm API v2 compatibility by Friday."
                ),
                L10n.text(
                    "Please confirm API v2 compatibility by Friday."
                )
            )
        case SkillRegistry.contextRewriteSkillID:
            return (
                L10n.text(
                    "Select “The API v2 migration must be completed by Friday.”, then say: “Make it shorter, keep it in English.”"
                ),
                L10n.text(
                    "Finish the API v2 migration by Friday."
                )
            )
        case SkillRegistry.contextReplySkillID:
            return (
                L10n.text(
                    "Select “Can you confirm the API v2 review date?”, then say: “Reply Friday at 3 PM.”"
                ),
                L10n.text(
                    "The API v2 review is Friday at 3 PM."
                )
            )
        case SkillRegistry.bugReportSkillID:
            return (
                L10n.text(
                    "After upgrading to 0.1.0, pressing F5 in TextEdit to stop recording occasionally only copies and does not insert."
                ),
                L10n.text(
                    "## Observed Behavior\nTextEdit occasionally receives a copy-only result after F5 stops recording.\n\n## Expected Behavior\nVerified insertion when the target is unchanged.\n\n## Reproduction Steps\n1. Focus TextEdit.\n2. Press F5 to start and stop.\n\n## Environment\nVibeWhisper 0.1.0 with TextEdit.\n\n## Evidence\nNot provided.\n\n## Impact\nNot provided."
                )
            )
        case SkillRegistry.commitMessageSkillID:
            return (
                L10n.text(
                    "Fixed the Skill Switcher shortcut conflict rollback and added tests."
                ),
                L10n.text(
                    "fix: preserve the previous Skill Switcher shortcut on conflict\n\nKeep dictation registration unchanged and cover rollback with tests."
                )
            )
        case SkillRegistry.meetingActionItemsSkillID:
            return (
                L10n.text(
                    "Decided to ship Beta on Friday; Li will prepare rollback docs by Wednesday; registry proposal review next week."
                ),
                L10n.text(
                    "## Decisions\n- Ship the Beta on Friday.\n\n## Action Items\n- Li: prepare rollback documentation by Wednesday.\n\n## Open Questions\n- Registry proposal review next week."
                )
            )
        case SkillRegistry.productBriefSkillID:
            return (
                L10n.text(
                    "Build a quick switcher to pick the next Skill without opening Settings, target under three seconds."
                ),
                L10n.text(
                    "## Problem\nSkill selection is too far from the task.\n\n## Target Users\nNot provided.\n\n## Goals\nChoose a next-run Skill without opening Settings.\n\n## Non-goals\nNot provided.\n\n## Proposed Scope\nA quick switcher for the next recording.\n\n## Risks\nNot provided.\n\n## Success Criteria\nMedian selection time at or below 3 seconds."
                )
            )
        case SkillRegistry.customerSupportReplySkillID:
            return (
                L10n.text(
                    "User says paste failed; ask them to confirm Accessibility permission first, then try again—don't promise a fix."
                ),
                L10n.text(
                    "Sorry the insert didn't go through this time. Please confirm VibeWhisper's Accessibility permission in System Settings, then return to the target field and try again. If it still fails, keep the text on the clipboard and send us a diagnostics export."
                )
            )
        default:
            return (
                L10n.text(
                    "Describe the task naturally with the important facts and constraints."
                ),
                L10n.text(
                    "A usable result shaped by this Skill, ready for review before delivery."
                )
            )
        }
    }

    // MARK: Specs (Codex definition list)

    private var specsSection: some View {
        VStack(alignment: .leading, spacing: VibeWhisperMetrics.space14) {
            sectionTitle(L10n.text("Information"))

            VStack(alignment: .leading, spacing: 0) {
                specRow(
                    label: L10n.text("Required"),
                    value: capabilitySummary(skill.requiredCapabilities)
                )
                specDivider
                specRow(
                    label: L10n.text("Optional"),
                    value: capabilitySummary(skill.optionalCapabilities)
                )
                specDivider
                specRow(
                    label: L10n.text("Output"),
                    value: skill.output.format.localizedLabel
                )
                specDivider
                specRow(
                    label: L10n.text("Delivery"),
                    value: skill.output.delivery.localizedLabel
                )
                specDivider
                specRow(
                    label: L10n.text("Risk"),
                    value: L10n.format(
                        "%@ risk",
                        skill.output.risk.localizedLabel
                    )
                )
                if skill.author.isEmpty == false {
                    specDivider
                    specRow(
                        label: L10n.text("Author"),
                        value: skill.author
                    )
                }
                specDivider
                specRow(
                    label: L10n.text("Version"),
                    value: skill.version
                )
            }
        }
    }

    private var specDivider: some View {
        Divider().opacity(0.28)
    }

    private func specRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VibeWhisperMetrics.space16) {
            Text(label)
                .font(VibeWhisperTypography.callout())
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(VibeWhisperTypography.callout(.medium))
                .foregroundStyle(.primary.opacity(0.90))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, VibeWhisperMetrics.space10)
    }

    private func capabilitySummary(
        _ capabilities: [SkillCapability]
    ) -> String {
        if capabilities.isEmpty {
            return L10n.text("None")
        }
        return capabilities
            .map(\.localizedLabel)
            .joined(separator: ", ")
    }

    // MARK: Safety (quiet footer)

    private var safetySection: some View {
        HStack(alignment: .top, spacing: VibeWhisperMetrics.space10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    Color(nsColor: VibeWhisperPalette.success).opacity(0.90)
                )
                .frame(width: 22, height: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: VibeWhisperMetrics.space4) {
                Text(L10n.text("Safety boundary"))
                    .font(VibeWhisperTypography.caption(.semibold))
                    .foregroundStyle(.primary.opacity(0.78))
                Text(
                    L10n.text(
                        "This Skill can shape text and request declared Context only. It cannot execute code, use credentials, make custom network requests, or bypass Preview and verified delivery."
                    )
                )
                .font(VibeWhisperTypography.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            }
        }
        .padding(.top, VibeWhisperMetrics.space4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Shared chrome

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(VibeWhisperTypography.headline())
            .foregroundStyle(.primary.opacity(0.88))
    }
}

/// Simple wrapping pill strip for structure outlines (validators-driven).
private struct FlowOutlinePills: View {
    let labels: [String]
    let accent: Color
    /// Index of the currently focused section, or `nil` for a quiet rest state.
    var activeIndex: Int? = nil
    /// When true, past sections stay lit so the outline “fills in” as we go.
    var lightPast: Bool = true

    var body: some View {
        // Adaptive wrap via LazyVGrid of flexible chips.
        let columns = [
            GridItem(.adaptive(minimum: 72, maximum: 160), spacing: 6)
        ]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let isActive = activeIndex == index
                let isPast =
                    lightPast
                    && (activeIndex.map { index < $0 } ?? false)
                let isLit = isActive || isPast
                HStack(spacing: 4) {
                    Text("\(index + 1)")
                        .font(VibeWhisperTypography.mono(9, weight: .semibold))
                        .foregroundStyle(
                            isActive
                                ? Color.white.opacity(0.95)
                                : accent.opacity(isLit ? 0.95 : 0.55)
                        )
                    Text(label)
                        .font(VibeWhisperTypography.micro(.medium))
                        .foregroundStyle(
                            isActive
                                ? Color.white.opacity(0.95)
                                : Color.primary.opacity(isLit ? 0.88 : 0.55)
                        )
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    isActive
                        ? AnyShapeStyle(accent.opacity(0.92))
                        : AnyShapeStyle(accent.opacity(isLit ? 0.16 : 0.07)),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            accent.opacity(isActive ? 0.0 : (isLit ? 0.28 : 0.12)),
                            lineWidth: 0.5
                        )
                }
                .scaleEffect(isActive ? 1.04 : 1.0)
                .shadow(
                    color: isActive
                        ? accent.opacity(0.35)
                        : .clear,
                    radius: isActive ? 8 : 0,
                    y: isActive ? 2 : 0
                )
                .animation(
                    VibeWhisperMotion.snappySpring,
                    value: activeIndex
                )
            }
        }
    }
}

// MARK: - Skill showcase loop (HUD lifecycle, one capsule)

/// Miniature of the real dictation HUD: listen → process → rewrite lands.
/// Fixed outer stage; one capsule morphs from center with explicit width and
/// height targets (never scaleEffect text). Inactive content is overlaid so it
/// cannot participate in layout and make the shell grow or shrink abruptly.
/// No Say/Get labels; role = color. No per-loop shell blink.
private struct SkillShowcasePlayer: View {
    enum Mode: Equatable {
        case transform
        case structure
        case compose
    }

    let mode: Mode
    let say: String
    let get: String
    let outline: [String]
    let symbolName: String
    let accent: Color
    var composeSubject: String? = nil
    var composeBody: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .seed
    @State private var typedSay = ""
    @State private var typingTextOpacity: Double = 1
    @State private var hasCompletedInitialTyping = false
    @State private var activePill: Int? = nil
    @State private var revealedSections = 0
    @State private var width: CGFloat = 88
    @State private var capsuleHeight: CGFloat = 60
    @State private var resultHeight: CGFloat = 60
    @State private var shellOpacity: Double = 0
    @State private var contentOpacity: Double = 1
    @State private var generation = 0

    private enum Phase: Int, Equatable {
        case seed
        case typing
        case processing
        case result
    }

    private static var appear: Animation { VibeWhisperMotion.panelSpring }
    private static var morph: Animation { VibeWhisperMotion.showcaseMorph }
    private static var crossfade: Animation { VibeWhisperMotion.panelContent }

    private let seedW: CGFloat = 88
    private let waveW: CGFloat = 168
    private let fullW: CGFloat = 320
    private let compactHeight: CGFloat = 60
    private let horizontalPad: CGFloat = 16
    private let typingVerticalPad: CGFloat = 12
    private let expandedVerticalPad: CGFloat = 14
    private let reserveVerticalPad: CGFloat = 16
    private let calloutPointSize: CGFloat = 12

    private var sections: [StructureShowcaseParser.Section] {
        StructureShowcaseParser.sections(from: get)
    }

    private var sectionCount: Int {
        max(sections.count, outline.count, 1)
    }

    private var resolvedComposeBody: String {
        composeBody.isEmpty ? get : composeBody
    }

    /// Continuous radius: true pill when compact, card when full.
    private var radius: CGFloat {
        if width < 140 {
            return width * 0.5
        }
        // Smooth blend toward 16 as we leave compact.
        let t = min(1, max(0, (width - 140) / 80))
        return width * 0.5 * (1 - t) + 16 * t
    }

    var body: some View {
        ZStack {
            stageReserve
                .hidden()

            capsule
                .opacity(shellOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.text("Example"))
        .accessibilityValue("\(say)\n\(get)")
        .onAppear { restartLoop() }
        .onChange(of: say) { _ in restartLoop() }
        .onChange(of: get) { _ in restartLoop() }
        .onChange(of: mode) { _ in restartLoop() }
        .onChange(of: reduceMotion) { _ in restartLoop() }
        .onPreferenceChange(SkillShowcaseResultHeightKey.self) {
            updateMeasuredResultHeight($0)
        }
    }

    /// Largest footprint so outer stage height never jumps.
    private var stageReserve: some View {
        resultBody(fullyRevealed: true)
            .padding(.horizontal, horizontalPad)
            .padding(.vertical, reserveVerticalPad)
            .frame(width: fullW, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SkillShowcaseResultHeightKey.self,
                        value: proxy.size.height
                    )
                }
            }
    }

    // MARK: Capsule

    private var capsule: some View {
        // Overlay children never contribute an intrinsic size. The explicit
        // frame below is therefore the only geometry source, preventing hidden
        // long-form results from reflowing the compact shell mid-animation.
        Color.clear
            .overlay {
                typingBody
                    .opacity(
                        phase == .typing || phase == .seed
                            ? contentOpacity
                            : 0
                    )
            }
            .overlay {
                waveBody
                    .opacity(phase == .processing ? contentOpacity : 0)
            }
            .overlay {
                resultBody(
                    fullyRevealed: phase == .result || reduceMotion
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )
                .opacity(phase == .result ? contentOpacity : 0)
            }
        .padding(.horizontal, horizontalPad)
        .padding(.vertical, verticalPad)
        .frame(width: width, height: capsuleHeight)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: 1)
        )
        .shadow(
            color: phase == .result
                ? accent.opacity(0.18)
                : Color.black.opacity(0.06),
            radius: phase == .result ? 10 : 4,
            y: phase == .result ? 3 : 1
        )
        .clipShape(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }

    private var verticalPad: CGFloat {
        switch phase {
        case .processing, .result: return expandedVerticalPad
        default: return typingVerticalPad
        }
    }

    private var fillColor: Color {
        switch phase {
        case .seed, .typing:
            return Color(nsColor: .controlBackgroundColor).opacity(0.97)
        case .processing:
            return Color.primary.opacity(0.08)
        case .result:
            return accent.opacity(0.14)
        }
    }

    private var strokeColor: Color {
        switch phase {
        case .seed, .typing:
            return Color.primary.opacity(0.10)
        case .processing:
            return accent.opacity(0.42)
        case .result:
            return accent.opacity(0.50)
        }
    }

    // MARK: Content

    private var typingBody: some View {
        Text(typedSay.isEmpty ? "\u{2007}" : typedSay)
            .font(VibeWhisperTypography.callout())
            .foregroundStyle(.primary.opacity(0.90))
            .lineLimit(3)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .center)
            .transaction { $0.animation = nil }
            .opacity(typingTextOpacity)
    }

    private var waveBody: some View {
        ShowcaseHUDWaveform(
            active: phase == .processing && !reduceMotion,
            accent: accent,
            intensity: phase == .processing ? 1 : 0,
            barCount: 7,
            barWidth: 3.5,
            barSpacing: 3.5,
            maxHeight: 28
        )
        .frame(height: 32)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func resultBody(fullyRevealed: Bool) -> some View {
        switch mode {
        case .transform:
            Text(get)
                .font(VibeWhisperTypography.callout())
                .foregroundStyle(.primary.opacity(0.93))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .structure:
            VStack(alignment: .leading, spacing: VibeWhisperMetrics.space10) {
                if !outline.isEmpty {
                    FlowOutlinePills(
                        labels: outline,
                        accent: accent,
                        activeIndex: fullyRevealed ? nil : activePill,
                        lightPast: true
                    )
                }
                structureSections(fullyRevealed: fullyRevealed)
            }
        case .compose:
            composeResult(fullyRevealed: fullyRevealed)
        }
    }

    @ViewBuilder
    private func structureSections(fullyRevealed: Bool) -> some View {
        VStack(alignment: .leading, spacing: VibeWhisperMetrics.space12) {
            if sections.isEmpty {
                Text(get)
                    .font(VibeWhisperTypography.callout())
                    .foregroundStyle(.primary.opacity(0.90))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            } else {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    StructureSectionBlock(
                        section: section,
                        accent: accent,
                        isActive: !fullyRevealed
                            && activePill == index
                            && phase == .result,
                        isRevealed: fullyRevealed
                            || reduceMotion
                            || revealedSections > index
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func composeResult(fullyRevealed: Bool) -> some View {
        if let subject = composeSubject {
            VStack(alignment: .leading, spacing: VibeWhisperMetrics.space8) {
                Text(subject)
                    .font(VibeWhisperTypography.callout(.semibold))
                    .foregroundStyle(.primary.opacity(0.93))
                    .opacity(fullyRevealed || revealedSections >= 1 ? 1 : 0)
                Divider().opacity(0.28)
                Text(resolvedComposeBody)
                    .font(VibeWhisperTypography.callout())
                    .foregroundStyle(.primary.opacity(0.90))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .opacity(fullyRevealed || revealedSections >= 2 ? 1 : 0)
            }
        } else {
            Text(get)
                .font(VibeWhisperTypography.callout())
                .foregroundStyle(.primary.opacity(0.90))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    // MARK: Measured geometry

    private func measuredTypingSize(for text: String) -> CGSize {
        let sample = text.isEmpty ? " " : text
        let font = NSFont.systemFont(ofSize: calloutPointSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let unconstrained = (sample as NSString).boundingRect(
            with: NSSize(width: fullW - horizontalPad * 2, height: 200),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        ).size
        let measuredWidth = min(
            fullW,
            max(
                seedW,
                ceil(unconstrained.width) + horizontalPad * 2 + 8
            )
        )
        let laidOut = (sample as NSString).boundingRect(
            with: NSSize(
                width: max(1, measuredWidth - horizontalPad * 2),
                height: 200
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        ).size
        let lineHeight = ceil(font.boundingRectForFont.height)
        let maximumTextHeight = lineHeight * 3 + 4
        let measuredHeight = max(
            compactHeight,
            min(ceil(laidOut.height), maximumTextHeight)
                + typingVerticalPad * 2
        )
        return CGSize(width: measuredWidth, height: measuredHeight)
    }

    private func updateMeasuredResultHeight(_ reserveHeight: CGFloat) {
        guard reserveHeight.isFinite, reserveHeight > 0 else { return }
        let measuredHeight = max(
            compactHeight,
            ceil(
                reserveHeight
                    - (reserveVerticalPad - expandedVerticalPad) * 2
            )
        )
        guard abs(measuredHeight - resultHeight) > 0.5 else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            resultHeight = measuredHeight
        }

        guard phase == .result, contentOpacity > 0.5 else { return }
        if reduceMotion {
            var reducedTransaction = Transaction()
            reducedTransaction.disablesAnimations = true
            withTransaction(reducedTransaction) {
                capsuleHeight = measuredHeight
            }
        } else {
            withAnimation(Self.morph) {
                capsuleHeight = measuredHeight
            }
        }
    }

    // MARK: Loop

    private func restartLoop() {
        generation &+= 1
        let gen = generation

        if reduceMotion {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                typedSay = say
                typingTextOpacity = 1
                hasCompletedInitialTyping = true
                activePill = nil
                revealedSections = sectionCount
                width = fullW
                capsuleHeight = resultHeight
                shellOpacity = 1
                contentOpacity = 1
                phase = .result
            }
            return
        }

        if shellOpacity < 0.5 {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                phase = .seed
                typedSay = ""
                typingTextOpacity = 1
                hasCompletedInitialTyping = false
                activePill = nil
                revealedSections = 0
                width = seedW
                capsuleHeight = compactHeight
                contentOpacity = 1
                shellOpacity = 0
            }
            withAnimation(Self.appear) {
                shellOpacity = 1
            }
            schedule(after: 0.28, generation: gen) {
                runTyping(generation: gen)
            }
        } else {
            // A new selection can arrive during any phase. Fade its content,
            // then retarget the same spring from the current presentation
            // geometry instead of snapping state back to the seed size.
            withAnimation(Self.crossfade) {
                contentOpacity = 0
            }
            schedule(after: 0.16, generation: gen) {
                guard gen == generation else { return }
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    typedSay = ""
                    typingTextOpacity = 1
                    hasCompletedInitialTyping = false
                    activePill = nil
                    revealedSections = 0
                }
                withAnimation(Self.morph) {
                    phase = .seed
                    width = seedW
                    capsuleHeight = compactHeight
                }
                schedule(after: 0.40, generation: gen) {
                    guard gen == generation else { return }
                    withAnimation(Self.crossfade) {
                        contentOpacity = 1
                    }
                    schedule(after: 0.12, generation: gen) {
                        runTyping(generation: gen)
                    }
                }
            }
        }
    }

    private func runTyping(generation gen: Int) {
        guard gen == generation else { return }

        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            typedSay = ""
            typingTextOpacity = hasCompletedInitialTyping ? 0 : 1
            activePill = nil
            revealedSections = 0
        }
        let typingSize = measuredTypingSize(for: say)
        withAnimation(Self.morph) {
            phase = .typing
            width = typingSize.width
            capsuleHeight = typingSize.height
        }

        if hasCompletedInitialTyping {
            runSubsequentTyping(generation: gen)
            return
        }

        let characters = Array(say)
        guard !characters.isEmpty else {
            hasCompletedInitialTyping = true
            schedule(after: 0.55, generation: gen) {
                runProcessing(generation: gen)
            }
            return
        }

        let perChar = min(0.048, max(0.026, 1.7 / Double(characters.count)))

        for (index, _) in characters.enumerated() {
            schedule(after: perChar * Double(index + 1), generation: gen) {
                guard gen == generation else { return }
                typedSay = String(characters[...index])
                if index == characters.count - 1 {
                    hasCompletedInitialTyping = true
                    schedule(after: 0.55, generation: gen) {
                        runProcessing(generation: gen)
                    }
                }
            }
        }
    }

    /// Repeated showcase passes reveal the complete transcription at once.
    /// A short opacity settle keeps continuity without replaying the slow
    /// character-by-character treatment from the initial pass.
    private func runSubsequentTyping(generation gen: Int) {
        guard gen == generation else { return }

        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            typedSay = say
            typingTextOpacity = 0
        }
        // Let the shell cover most of its width morph before the complete line
        // becomes legible, so the text never looks horizontally clipped.
        schedule(after: 0.24, generation: gen) {
            withAnimation(Self.crossfade) {
                typingTextOpacity = 1
            }
        }
        schedule(after: 0.95, generation: gen) {
            runProcessing(generation: gen)
        }
    }

    private func runProcessing(generation gen: Int) {
        guard gen == generation else { return }

        withAnimation(Self.crossfade) {
            contentOpacity = 0
        }
        schedule(after: 0.16, generation: gen) {
            guard gen == generation else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                typedSay = ""
            }
            withAnimation(Self.morph) {
                phase = .processing
                width = waveW
                capsuleHeight = compactHeight
            }
            withAnimation(Self.crossfade) {
                contentOpacity = 1
            }
            schedule(after: 1.50, generation: gen) {
                runResult(generation: gen)
            }
        }
    }

    private func runResult(generation gen: Int) {
        guard gen == generation else { return }

        withAnimation(Self.crossfade) {
            contentOpacity = 0
        }
        schedule(after: 0.16, generation: gen) {
            guard gen == generation else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                revealedSections = mode == .transform ? 1 : 0
            }
            withAnimation(Self.morph) {
                phase = .result
                width = fullW
                capsuleHeight = resultHeight
            }
            withAnimation(Self.crossfade) {
                contentOpacity = 1
            }
            revealResultDetails(generation: gen)
        }
    }

    private func revealResultDetails(generation gen: Int) {
        switch mode {
        case .transform:
            revealedSections = 1
            schedule(after: 2.80, generation: gen) {
                runBridge(generation: gen)
            }
        case .structure:
            let pillCount = max(outline.count, sections.count, 1)
            for index in 0..<pillCount {
                schedule(after: 0.28 * Double(index), generation: gen) {
                    guard gen == generation else { return }
                    withAnimation(VibeWhisperMotion.snappySpring) {
                        activePill = index
                        revealedSections = index + 1
                    }
                }
            }
            schedule(after: 0.28 * Double(pillCount) + 2.40, generation: gen) {
                runBridge(generation: gen)
            }
        case .compose:
            schedule(after: 0.28, generation: gen) {
                guard gen == generation else { return }
                withAnimation(Self.crossfade) { revealedSections = 1 }
            }
            schedule(after: 0.70, generation: gen) {
                guard gen == generation else { return }
                withAnimation(Self.crossfade) { revealedSections = 2 }
            }
            schedule(after: 2.80, generation: gen) {
                runBridge(generation: gen)
            }
        }
    }

    /// Soft handoff back to typing — no shell blink.
    private func runBridge(generation gen: Int) {
        guard gen == generation else { return }

        withAnimation(Self.crossfade) {
            contentOpacity = 0
        }
        schedule(after: 0.16, generation: gen) {
            guard gen == generation else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                typedSay = ""
                activePill = nil
                revealedSections = 0
                // shellOpacity stays 1
            }
            withAnimation(Self.morph) {
                phase = .seed
                width = seedW
                capsuleHeight = compactHeight
            }
            schedule(after: 0.40, generation: gen) {
                guard gen == generation else { return }
                withAnimation(Self.crossfade) {
                    contentOpacity = 1
                }
                schedule(after: 0.12, generation: gen) {
                    runTyping(generation: gen)
                }
            }
        }
    }

    private func schedule(
        after delay: TimeInterval,
        generation gen: Int,
        _ work: @escaping () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard gen == generation else { return }
            work()
        }
    }
}

private struct SkillShowcaseResultHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - HUD-matching showcase waveform

/// Single recognition glyph. Fixed barCount — never remounts as a second capsule.
private struct ShowcaseHUDWaveform: View {
    let active: Bool
    let accent: Color
    var intensity: CGFloat = 1
    var barCount: Int = 7
    var barWidth: CGFloat = 3.5
    var barSpacing: CGFloat = 3.5
    var maxHeight: CGFloat = 28

    private let minHeight: CGFloat = 4

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: active ? 1.0 / 30.0 : 1.0,
                paused: !active
            )
        ) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let levels = WaveformNormalizer.processingPulseLevels(
                time: t,
                barCount: barCount
            )
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let level = index < levels.count ? levels[index] : 0
                    let height = minHeight
                        + (maxHeight - minHeight)
                        * level
                        * max(0, min(1, intensity))
                    Capsule(style: .continuous)
                        .fill(accent.opacity(0.55 + Double(level) * 0.40))
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: maxHeight)
            .opacity(active ? 0.95 : 0)
        }
    }
}

// MARK: - Structure section + parser

/// One markdown section (heading + body) for the structure showcase.
private struct StructureSectionBlock: View {
    let section: StructureShowcaseParser.Section
    let accent: Color
    let isActive: Bool
    let isRevealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let heading = section.heading {
                Text(heading)
                    .font(VibeWhisperTypography.callout(.semibold))
                    .foregroundStyle(
                        isActive
                            ? accent
                            : Color.primary.opacity(0.88)
                    )
            }
            if !section.body.isEmpty {
                Text(section.body)
                    .font(VibeWhisperTypography.callout())
                    .foregroundStyle(.primary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isRevealed ? 1 : 0)
        .offset(y: isRevealed ? 0 : 6)
        .scaleEffect(isRevealed ? 1 : 0.985, anchor: .topLeading)
        .animation(VibeWhisperMotion.softSettle, value: isRevealed)
        .animation(VibeWhisperMotion.snappySpring, value: isActive)
        .accessibilityHidden(!isRevealed)
    }
}

/// Splits sample markdown into heading-led sections for staged reveal.
private enum StructureShowcaseParser {
    struct Section: Equatable {
        var heading: String?
        var body: String
    }

    static func sections(from markdown: String) -> [Section] {
        let lines = markdown.components(separatedBy: .newlines)
        var result: [Section] = []
        var currentHeading: String?
        var bodyLines: [String] = []

        func flush() {
            let body = bodyLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if currentHeading != nil || !body.isEmpty {
                result.append(Section(heading: currentHeading, body: body))
            }
            currentHeading = nil
            bodyLines = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                flush()
                currentHeading = trimmed
                    .replacingOccurrences(
                        of: #"^#+\s*"#,
                        with: "",
                        options: .regularExpression
                    )
            } else {
                bodyLines.append(line)
            }
        }
        flush()
        return result
    }
}
