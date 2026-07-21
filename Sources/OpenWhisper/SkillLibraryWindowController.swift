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
        onUseNext:
            @escaping (UUID) -> Void,
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
            onUseNext: onUseNext,
            onRunTest: onRunTest,
            onVoiceSampleAction: onVoiceSampleAction
        )
        .applyingOpenWhisperBrandTint()
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
            "OpenWhisper Skill Library"
        )
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier(
            "OpenWhisper.SkillLibraryWindow"
        )
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.minSize = NSSize(
            width: 820,
            height: 600
        )
        window.tabbingMode = .disallowed
        let restored = window.setFrameUsingName(
            "OpenWhisper.SkillLibraryWindow"
        )
        window.setFrameAutosaveName(
            "OpenWhisper.SkillLibraryWindow"
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
        case .installed: return L10n.text("Installed")
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
    let onUseNext: (UUID) -> Void
    let onRunTest:
        (SkillTestRunRequest) async
            -> Result<SkillTestRunResult, any Error>
    let onVoiceSampleAction:
        (SkillVoiceSampleAction) async
            -> Result<SkillVoiceSampleResult, any Error>
    let initialSection: Section
    let isEmbedded: Bool

    init(
        initialConfig: AppConfig,
        store: SkillPackageStore,
        localAssetAccessEnabled: Bool,
        initialSection: Section = .discover,
        isEmbedded: Bool = false,
        onSave:
            @escaping (AppConfig) -> Result<Void, any Error>,
        onUseNext:
            @escaping (UUID) -> Void,
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
        self.onUseNext = onUseNext
        self.onRunTest = onRunTest
        self.onVoiceSampleAction = onVoiceSampleAction
        self.initialSection = initialSection
        self.isEmbedded = isEmbedded
        _selection = State(initialValue: initialSection)
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
                    .font(OpenWhisperTypography.micro())
                    .foregroundStyle(Color(nsColor: OpenWhisperPalette.amber))
                    .lineLimit(1)
                }
                .padding(.horizontal, OpenWhisperMetrics.space20)
                .padding(.bottom, OpenWhisperMetrics.space6)
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
    }

    private var header: some View {
        OpenWhisperPaneHeader(title: L10n.text("Skill Library")) {
            sectionPicker
        }
    }

    private var sectionPicker: some View {
        Picker(
            L10n.text("Skill Library"),
            selection: $selection
        ) {
            ForEach(Section.allCases) { section in
                Text(Self.sectionTitle(section))
                    .tag(section)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(isEmbedded ? .large : .regular)
        .frame(width: isEmbedded ? 270 : 300)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .installed:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SkillApplicationDefaultsView(
                        config: $config,
                        inventory: inventory
                    )
                    Divider()
                    CommunitySkillSettingsView(
                        config: $config,
                        inventory: $inventory,
                        store: store,
                        localAssetAccessEnabled:
                            localAssetAccessEnabled,
                        onRunTest: onRunTest
                    )
                }
                .padding(22)
            }
        case .discover:
            BuiltInSkillDiscoveryView(
                config: $config,
                onUseNext: onUseNext,
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

private struct SkillApplicationDefaultsView: View {
    @Binding var config: AppConfig
    let inventory: CommunitySkillInventory

    @State private var appName = ""
    @State private var bundleIdentifier = ""
    @State private var selectedSkillID =
        SkillRegistry.directSkillID
    @State private var message: String?
    @State private var messageIsError = false

    private var registry: SkillRegistry {
        inventory.registry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("Defaults"))
                    .font(.system(size: 16, weight: .semibold))
            }

            LabeledContent(L10n.text("Global default")) {
                Picker(
                    L10n.text("Global default"),
                    selection: Binding(
                        get: {
                            config.transcription.skills
                                .defaultSkillID
                        },
                        set: { skillID in
                            config.transcription.skills
                                .setDefault(
                                    skillID: skillID,
                                    installationID:
                                        installationID(
                                            for: skillID
                                        ),
                                    registry: registry
                                )
                        }
                    )
                ) {
                    ForEach(registry.orderedDefinitions) { skill in
                        Text(skill.localizedName).tag(skill.id)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }

            Divider()

            Text(L10n.text("Application Defaults"))
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Button(L10n.text("Choose App…")) {
                    chooseApplication()
                }
                .buttonStyle(.bordered)
                TextField(
                    L10n.text("App name (optional)"),
                    text: $appName
                )
                .textFieldStyle(.roundedBorder)
                TextField(
                    L10n.text("Bundle identifier"),
                    text: $bundleIdentifier,
                    prompt: Text("com.apple.TextEdit")
                )
                .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                Picker(
                    L10n.text("Skill"),
                    selection: $selectedSkillID
                ) {
                    ForEach(registry.orderedDefinitions) { skill in
                        Text(skill.localizedName).tag(skill.id)
                    }
                }
                .frame(width: 230)
                Button(L10n.text("Add App Default")) {
                    addRule()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    bundleIdentifier.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
                Spacer()
            }

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        messageIsError ? .red : .secondary
                    )
            }

            if !config.transcription.skills.applicationRules.isEmpty {
                VStack(spacing: 7) {
                    ForEach(
                        config.transcription.skills.applicationRules
                    ) { rule in
                        ruleRow(rule)
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: AppSkillRule) -> some View {
        HStack(spacing: 10) {
            Toggle(
                L10n.format(
                    "Enable Skill rule for %@",
                    rule.appName ?? rule.bundleIdentifier
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
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.appName ?? rule.bundleIdentifier)
                    .font(.system(size: 12, weight: .medium))
                Text(rule.bundleIdentifier)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
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
            .frame(width: 190)

            Button(role: .destructive) {
                config.transcription.skills.remove(id: rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(
                L10n.format(
                    "Delete Skill rule for %@",
                    rule.appName ?? rule.bundleIdentifier
                )
            )
        }
        .padding(9)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func addRule() {
        do {
            let rule = try AppSkillRule.validated(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                skillID: selectedSkillID,
                skillInstallationID:
                    installationID(for: selectedSkillID),
                registry: registry
            )
            config.transcription.skills.upsert(
                rule,
                registry: registry
            )
            appName = ""
            bundleIdentifier = ""
            message = L10n.text("Application default saved.")
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
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
        else { return }
        appName = bundle.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String
            ?? bundle.object(
                forInfoDictionaryKey: "CFBundleName"
            ) as? String
            ?? url.deletingPathExtension().lastPathComponent
        bundleIdentifier = identifier
    }
}

extension SkillDefinition {
    /// Brand-forward symbol used for skill tiles in the library.
    /// Falls back to a wand for community/local skills.
    var openWhisperSymbol: String {
        switch id {
        case SkillRegistry.directSkillID:
            return "text.cursor"
        case SkillRegistry.replySkillID:
            return "arrowshape.turn.up.left.fill"
        case SkillRegistry.emailSkillID:
            return "envelope.fill"
        case SkillRegistry.agentPlanSkillID:
            return "brain"
        case SkillRegistry.codePromptSkillID:
            return "chevron.left.forwardslash.chevron.right"
        case SkillRegistry.translateSkillID:
            return "character.bubble.fill"
        case SkillRegistry.contextRewriteSkillID:
            return "text.badge.checkmark"
        case SkillRegistry.contextReplySkillID:
            return "quote.bubble.fill"
        case SkillRegistry.bugReportSkillID:
            return "ladybug.fill"
        case SkillRegistry.commitMessageSkillID:
            return "point.topleft.down.curvedto.point.bottomright.up.fill"
        case SkillRegistry.meetingActionItemsSkillID:
            return "checklist"
        case SkillRegistry.productBriefSkillID:
            return "doc.text.fill"
        case SkillRegistry.customerSupportReplySkillID:
            return "bubble.left.and.bubble.right.fill"
        default:
            return "wand.and.stars"
        }
    }
}

private struct BuiltInSkillDiscoveryView: View {
    @Binding var config: AppConfig
    let onUseNext: (UUID) -> Void
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
                                        cornerRadius: OpenWhisperMetrics.radiusXL,
                                        style: .continuous
                                    )
                                )
                                .onTapGesture {
                                    selectedID = skill.id
                                }
                        }
                    }

                    if skills.isEmpty {
                        OpenWhisperEmptyState(
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
                    config: $config,
                    onUseNext: onUseNext,
                    onRunTest: onRunTest
                )
                .frame(minWidth: 380, idealWidth: 460, maxWidth: 520)
                .background(
                    Color(nsColor: OpenWhisperPalette.insetSurface)
                )
            }
        }
    }

    private func skillCard(_ skill: SkillDefinition) -> some View {
        let isSelected = selected?.id == skill.id
        return VStack(alignment: .leading, spacing: 8) {
            OpenWhisperIconWell(
                systemName: skill.openWhisperSymbol,
                size: 48,
                symbolSize: 22
            )
            Text(skill.localizedName)
                .font(OpenWhisperTypography.headline())
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: OpenWhisperPalette.elevatedSurface),
            in: RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusXL,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OpenWhisperMetrics.radiusXL,
                style: .continuous
            )
            .stroke(
                isSelected
                    ? Color(nsColor: OpenWhisperPalette.brandBlue)
                    : Color.clear,
                lineWidth: 2
            )
        }
        .shadow(
            color: Color.black.opacity(isSelected ? 0.10 : 0.05),
            radius: isSelected ? 10 : 6,
            x: 0,
            y: 3
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct SkillDiscoveryDetail: View {
    let skill: SkillDefinition
    @Binding var config: AppConfig
    let onUseNext: (UUID) -> Void
    let onRunTest:
        (SkillTestRunRequest) async
            -> Result<SkillTestRunResult, any Error>

    @State private var testInput = ""
    @State private var simulatedSelection = ""
    @State private var testMessage: String?
    @State private var testMessageIsError = false
    @State private var isRunningTest = false

    private var installation:
        InstalledSkillIdentity
    {
        InstalledSkillIdentity.normalized(
            definition: skill,
            sourceID: "builtin"
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        L10n.text("Built-in · reviewed"),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: OpenWhisperPalette.brandBlue))
                    Text(skill.localizedName)
                        .font(.system(size: 26, weight: .semibold))
                }

                Divider()
                detailSection(
                    title: "When to use",
                    text: useCaseText
                )
                example
                testRunSection
                contextSection
                outputSection
                safetySection

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        actionControls
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        actionControls
                    }
                }
            }
            .padding(26)
            .frame(maxWidth: 650, alignment: .leading)
        }
    }

    @ViewBuilder
    private var actionControls: some View {
        Button(L10n.text("Use Next Time")) {
            onUseNext(installation.id)
        }
        .buttonStyle(OpenWhisperPrimaryButtonStyle())
        Button(L10n.text("Set as Global Default")) {
            config.transcription.skills
                .setDefault(
                    skillID: skill.id,
                    installationID: installation.id
                )
        }
        .buttonStyle(OpenWhisperSecondaryButtonStyle())
        Button {
            if config.skillEcosystem
                .favoriteInstallationIDs
                .contains(installation.id)
            {
                config.skillEcosystem
                    .favoriteInstallationIDs
                    .removeAll {
                        $0 == installation.id
                    }
            } else {
                config.skillEcosystem
                    .favoriteInstallationIDs
                    .append(installation.id)
            }
        } label: {
            Label(
                config.skillEcosystem
                    .favoriteInstallationIDs
                    .contains(installation.id)
                    ? L10n.text("Favorited")
                    : L10n.text("Favorite"),
                systemImage:
                    config.skillEcosystem
                        .favoriteInstallationIDs
                        .contains(installation.id)
                    ? "star.fill"
                    : "star"
            )
        }
        .buttonStyle(OpenWhisperSecondaryButtonStyle())
    }

    private var useCaseText: String {
        skill.localizedUseCase
    }

    private var example: some View {
        let values = exampleValues
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Before / After example"))
                .font(.system(size: 12, weight: .semibold))
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    detailColumn(
                        title: "Say",
                        text: values.0
                    )
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .padding(.top, 22)
                    detailColumn(
                        title: "Get",
                        text: values.1
                    )
                }
                VStack(alignment: .leading, spacing: 8) {
                    detailColumn(
                        title: "Say",
                        text: values.0
                    )
                    Image(systemName: "arrow.down")
                        .foregroundStyle(.secondary)
                    detailColumn(
                        title: "Get",
                        text: values.1
                    )
                }
            }
        }
    }

    private var exampleValues: (String, String) {
        switch skill.id {
        case SkillRegistry.directSkillID:
            return (
                L10n.text(
                    "明天下午三点和设计团队同步 API v2。"
                ),
                L10n.text(
                    "明天下午 3 点与设计团队同步 API v2。"
                )
            )
        case SkillRegistry.emailSkillID:
            return (
                L10n.text(
                    "给王老师写邮件，确认周五评审，附上最新版。"
                ),
                L10n.text(
                    "主题：确认周五评审\n\n王老师您好，想确认周五的评审安排，最新版材料已附上。"
                )
            )
        case SkillRegistry.bugReportSkillID:
            return (
                L10n.text(
                    "升级到 0.1.0 后，TextEdit 中按 F5 停止录音会偶发只复制不插入。"
                ),
                L10n.text(
                    "Observed Behavior\nTextEdit occasionally receives a copy-only result after F5 stops recording.\n\nExpected Behavior\nVerified insertion when the target is unchanged.\n\nReproduction Steps\n1. Focus TextEdit.\n2. Press F5 to start and stop."
                )
            )
        case SkillRegistry.commitMessageSkillID:
            return (
                L10n.text(
                    "把 Skill 切换器快捷键冲突回滚修好了，也加了测试。"
                ),
                L10n.text(
                    "fix: preserve the previous Skill Switcher shortcut on conflict\n\nKeep dictation registration unchanged and cover rollback with tests."
                )
            )
        case SkillRegistry.meetingActionItemsSkillID:
            return (
                L10n.text(
                    "决定周五发 Beta；小李周三前整理回滚文档，注册表方案下周再评审。"
                ),
                L10n.text(
                    "## Decisions\n- Ship the Beta on Friday.\n\n## Action Items\n- Li: prepare rollback documentation by Wednesday.\n\n## Open Questions\n- Registry proposal review next week."
                )
            )
        case SkillRegistry.productBriefSkillID:
            return (
                L10n.text(
                    "做一个不进设置就能选下次 Skill 的快速切换器，目标三秒内完成。"
                ),
                L10n.text(
                    "## Problem\nSkill selection is too far from the task.\n\n## Goals\nChoose a next-run Skill without opening Settings.\n\n## Success Criteria\nMedian selection time at or below 3 seconds."
                )
            )
        case SkillRegistry.customerSupportReplySkillID:
            return (
                L10n.text(
                    "用户说粘贴没成功，请先让他确认辅助功能权限，再试一次，别承诺一定修好。"
                ),
                L10n.text(
                    "抱歉这次没有成功插入。请先在系统设置中确认 OpenWhisper 的辅助功能权限，然后回到目标文本框重试。如果仍失败，请保留剪贴板中的文本并把诊断导出发给我们。"
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

    private var testRunSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Try this Skill"))
                .font(.system(size: 12, weight: .semibold))
            TextField(
                L10n.text("Test what you would say"),
                text: $testInput
            )
            .textFieldStyle(.roundedBorder)
            if skill.requiredCapabilities.contains(.selection) {
                TextField(
                    L10n.text("Simulated selected text"),
                    text: $simulatedSelection
                )
                .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 10) {
                Button(
                    isRunningTest
                        ? L10n.text("Running Test…")
                        : L10n.text("Test in Preview")
                ) {
                    runTest()
                }
                .buttonStyle(OpenWhisperSecondaryButtonStyle())
                .disabled(
                    isRunningTest
                        || testInput.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        || (
                            skill.requiredCapabilities
                                .contains(.selection)
                            && simulatedSelection
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                        )
                )
                if let testMessage {
                    Text(testMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(
                            testMessageIsError ? .red : .secondary
                        )
                }
            }
        }
    }

    private func runTest() {
        let input = testInput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let selection = simulatedSelection
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let plan = ResolvedSkillExecutionPlan(
            skill: skill,
            source: .manual,
            matchedApplicationRuleID: nil,
            installation: installation
        )
        isRunningTest = true
        testMessage = nil
        Task { @MainActor in
            let result = await onRunTest(
                SkillTestRunRequest(
                    plan: plan,
                    inputText: input,
                    context: SkillPromptContext(
                        selection:
                            selection.isEmpty ? nil : selection
                    )
                )
            )
            isRunningTest = false
            switch result {
            case .success(let result):
                testMessage = result.wasCancelled
                    ? L10n.text("Skill test cancelled.")
                    : (
                        result.validation.isValid
                        ? L10n.text("Validator passed")
                        : L10n.text(
                            "Test result needs Validator fixes."
                        )
                    )
                testMessageIsError =
                    !result.wasCancelled
                        && !result.validation.isValid
            case .failure(let error):
                testMessage = error.localizedDescription
                testMessageIsError = true
                NSSound.beep()
            }
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("Context"))
                .font(.system(size: 12, weight: .semibold))
            contextLine(
                title: "Required",
                capabilities:
                    skill.requiredCapabilities
            )
            contextLine(
                title: "Optional",
                capabilities:
                    skill.optionalCapabilities
            )
        }
    }

    private var outputSection: some View {
        detailSection(
            title: "Output & Delivery",
            text: L10n.format(
                "%@ · %@ · %@ risk",
                skill.output.format.localizedLabel,
                skill.output.delivery.localizedLabel,
                skill.output.risk.localizedLabel
            )
        )
    }

    private var safetySection: some View {
        detailSection(
            title: "Safety boundary",
            text: L10n.text(
                "This Skill can shape text and request declared Context only. It cannot execute code, use credentials, make custom network requests, or bypass Preview and verified delivery."
            )
        )
    }

    private func detailSection(
        title: String,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(title))
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailColumn(
        title: String,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(title))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .topLeading
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contextLine(
        title: String,
        capabilities: [SkillCapability]
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(L10n.text(title))
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 64, alignment: .leading)
            Text(
                capabilities.isEmpty
                    ? L10n.text("None")
                    : capabilities
                        .map(\.localizedLabel)
                        .joined(separator: ", ")
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }
}
