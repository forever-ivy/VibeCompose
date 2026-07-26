import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Writing Styles (product surface for StyleCapsule*)

private struct WritingStylePresentation {
    let symbolName: String
    let accent: NSColor

    static func forCapsule(_ capsule: StyleCapsule) -> WritingStylePresentation {
        switch capsule.id {
        case StyleCapsuleRegistry.workFormalID:
            return WritingStylePresentation(
                symbolName: "briefcase.fill",
                accent: VibeComposePalette.brandBlue
            )
        case StyleCapsuleRegistry.teamChatID:
            return WritingStylePresentation(
                symbolName: "bubble.left.and.bubble.right.fill",
                accent: VibeComposePalette.brandSpectrumCyan
            )
        case StyleCapsuleRegistry.technicalWritingID:
            return WritingStylePresentation(
                symbolName: "chevron.left.forwardslash.chevron.right",
                accent: VibeComposePalette.brandSpectrumViolet
            )
        case StyleCapsuleRegistry.englishBusinessID:
            return WritingStylePresentation(
                symbolName: "globe.europe.africa.fill",
                accent: VibeComposePalette.brandSpectrumSky
            )
        case StyleCapsuleRegistry.personalCasualID:
            return WritingStylePresentation(
                symbolName: "face.smiling.fill",
                accent: VibeComposePalette.brandSpectrumCoral
            )
        default:
            return WritingStylePresentation(
                symbolName: "paintbrush.pointed.fill",
                accent: VibeComposePalette.brandSpectrumAmber
            )
        }
    }

    /// Dictated raw sample used only for the before/after Example panel.
    /// Built-in `examples` stay the styled target (also used in the prompt).
    static func rawSample(for capsuleID: String) -> String? {
        switch capsuleID {
        case StyleCapsuleRegistry.workFormalID:
            return "hey can you look at the proposal by friday and tell me if anything looks off before we send it out"
        case StyleCapsuleRegistry.teamChatID:
            return "so thursday ship plan, i'll land the api fix today, can someone do design review by three if possible"
        case StyleCapsuleRegistry.technicalWritingID:
            return "we should retry on 429 and 503 with backoff starting at 250 milliseconds up to 4 seconds max five tries and don't retry non idempotent post"
        case StyleCapsuleRegistry.englishBusinessID:
            return "thanks for the update, next can you confirm the delivery date so we can schedule the customer review"
        case StyleCapsuleRegistry.personalCasualID:
            return "hey im running a bit late should be there in ten minutes grab a table if you get there first"
        default:
            return nil
        }
    }
}

enum WritingStylesPaneTab: String, CaseIterable, Identifiable {
    case library
    case defaults

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return L10n.text("Library")
        case .defaults: return L10n.text("Defaults")
        }
    }
}

struct StyleCapsuleLibraryView: View {
    @Binding var config: AppConfig
    let registry: SkillRegistry
    let store: StyleCapsuleStore
    let localAssetAccessEnabled: Bool

    @State private var activeTab: WritingStylesPaneTab = .library

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VibeComposePaneHeader(
                title: L10n.text("Writing Styles")
            ) {
                HStack(spacing: VibeComposeMetrics.space14) {
                    Picker(L10n.text("Writing Styles"), selection: $activeTab) {
                        ForEach(WritingStylesPaneTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .frame(width: 200)

                    // Keep label + switch as one non-wrapping cluster so
                    // "已启用" never stacks vertically in a narrow header slot.
                    HStack(spacing: VibeComposeMetrics.space8) {
                        Text(L10n.text("Enabled"))
                            .font(VibeComposeTypography.body(.medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Toggle("", isOn: $config.styleCapsules.enabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel(L10n.text("Enabled"))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            StyleCapsuleSettingsView(
                config: $config,
                registry: registry,
                store: store,
                localAssetAccessEnabled: localAssetAccessEnabled,
                activeTab: activeTab,
                showsSectionTitle: false,
                showsEnabledToggle: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(VibeComposeMotion.standardSpring, value: activeTab)
    }
}

struct StyleCapsuleSettingsView: View {
    @Binding var config: AppConfig
    let registry: SkillRegistry
    let store: StyleCapsuleStore
    let localAssetAccessEnabled: Bool
    var activeTab: WritingStylesPaneTab = .library
    var showsSectionTitle = true
    var showsEnabledToggle = true

    @State private var capsules: [StyleCapsule] = StyleCapsuleRegistry.builtIn
    @State private var selectedID: String?
    @State private var editingName = ""
    @State private var editingSummary = ""
    @State private var approvedExample = ""
    @State private var sourceSamples = ""
    @State private var message: String?
    @State private var messageIsError = false
    @State private var showsSamples = false
    @State private var searchText = ""
    @State private var assignmentSearchText = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredCapsules: [StyleCapsule] {
        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !query.isEmpty else { return capsules }
        return capsules.filter { capsule in
            [
                L10n.text(capsule.name),
                displaySummary(for: capsule),
                displayExample(for: capsule),
                capsule.isBuiltIn ? L10n.text("Built-in") : L10n.text("Custom"),
            ]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsSectionTitle || showsEnabledToggle {
                HStack {
                    if showsSectionTitle {
                        Text(L10n.text("Writing Styles"))
                            .font(VibeComposeTypography.title2())
                    }
                    Spacer()
                    if showsEnabledToggle {
                        Toggle(
                            L10n.text("Enabled"),
                            isOn: $config.styleCapsules.enabled
                        )
                        .toggleStyle(.switch)
                    }
                }
                .padding(.horizontal, VibeComposeMetrics.space20)
                .padding(.bottom, VibeComposeMetrics.space12)
            }

            Group {
                switch activeTab {
                case .library:
                    libraryMasterDetail
                case .defaults:
                    defaultsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(config.styleCapsules.enabled ? 1 : 0.48)
            .allowsHitTesting(config.styleCapsules.enabled)

            if let message {
                Text(message)
                    .font(VibeComposeTypography.body(.medium))
                    .foregroundStyle(
                        messageIsError
                            ? Color(nsColor: VibeComposePalette.error)
                            : .secondary
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, VibeComposeMetrics.space20)
                    .padding(.vertical, VibeComposeMetrics.space10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(VibeComposeMotion.standardSpring, value: selectedID)
        .onAppear {
            reload()
            if selectedID == nil, let first = capsules.first {
                select(first)
            }
        }
        .onChange(of: searchText) { _ in
            if let selectedCapsule, filteredCapsules.contains(where: { $0.id == selectedCapsule.id }) {
                return
            }
            if let first = filteredCapsules.first {
                select(first)
            }
        }
    }

    // MARK: Library master–detail

    private var libraryMasterDetail: some View {
        HStack(spacing: 0) {
            libraryColumn
                .frame(maxWidth: .infinity)

            Divider().opacity(0.45)

            detailColumn
                .frame(minWidth: 360, idealWidth: 440, maxWidth: 520)
                .background(Color(nsColor: VibeComposePalette.insetSurface))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Defaults tab (Default Style + managed Skill overrides)

    private var defaultsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VibeComposeMetrics.space28) {
                VStack(alignment: .leading, spacing: VibeComposeMetrics.space10) {
                    Text(L10n.text("Default Style"))
                        .font(VibeComposeTypography.title2())

                    SettingsRow(title: L10n.text("Default Style")) {
                        styleCapsulePicker(
                            selection: Binding(
                                get: { config.styleCapsules.defaultCapsuleID },
                                set: { config.styleCapsules.defaultCapsuleID = $0 }
                            ),
                            includesNone: true,
                            noneTitle: L10n.text("None")
                        )
                    }
                }

                VStack(alignment: .leading, spacing: VibeComposeMetrics.space12) {
                    HStack(alignment: .center, spacing: VibeComposeMetrics.space10) {
                        Text(L10n.text("By Skill"))
                            .font(VibeComposeTypography.title2())
                        Spacer(minLength: 0)
                        addSkillOverrideMenu
                    }

                    if !skillOverrides.isEmpty {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField(
                                L10n.text("Search Skill overrides"),
                                text: $assignmentSearchText
                            )
                            .textFieldStyle(.plain)
                        }
                        .vibeComposeSearchField()
                        .frame(maxWidth: 360)
                    }

                    if styleAwareSkills.isEmpty {
                        Text(L10n.text("No Skills support Writing Styles yet."))
                            .font(VibeComposeTypography.body())
                            .foregroundStyle(.secondary)
                            .padding(.vertical, VibeComposeMetrics.space8)
                    } else if skillOverrides.isEmpty {
                        VibeComposeEmptyState(
                            systemImage: "square.stack.3d.up.slash",
                            title: L10n.text("No Skill overrides")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, VibeComposeMetrics.space20)
                    } else if filteredSkillOverrides.isEmpty {
                        Text(L10n.text("No matching Skill overrides"))
                            .font(VibeComposeTypography.body())
                            .foregroundStyle(.secondary)
                            .padding(.vertical, VibeComposeMetrics.space8)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredSkillOverrides) { skill in
                                SettingsRow(title: skill.localizedName) {
                                    HStack(spacing: VibeComposeMetrics.space8) {
                                        styleCapsulePicker(
                                            selection: Binding(
                                                get: {
                                                    config.styleCapsules
                                                        .assignedCapsuleID(for: skill.id)
                                                },
                                                set: { value in
                                                    config.styleCapsules
                                                        .setCapsuleID(value, for: skill.id)
                                                }
                                            ),
                                            includesNone: false,
                                            noneTitle: L10n.text("Use Default")
                                        )

                                        Button {
                                            withAnimation(VibeComposeMotion.snappySpring) {
                                                config.styleCapsules
                                                    .setCapsuleID(nil, for: skill.id)
                                            }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help(L10n.text("Remove override"))
                                        .accessibilityLabel(L10n.text("Remove override"))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(VibeComposeMetrics.space20)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var addSkillOverrideMenu: some View {
        let candidates = unassignedStyleAwareSkills
        Menu {
            if candidates.isEmpty {
                Text(L10n.text("All eligible Skills already have overrides"))
            } else {
                ForEach(candidates) { skill in
                    Button(skill.localizedName) {
                        withAnimation(VibeComposeMotion.snappySpring) {
                            addSkillOverride(skill)
                        }
                    }
                }
            }
        } label: {
            Label(L10n.text("Add"), systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .fixedSize()
        .disabled(candidates.isEmpty || capsules.isEmpty)
        .help(L10n.text("Add a Skill writing-style override"))
    }

    private func styleCapsulePicker(
        selection: Binding<String?>,
        includesNone: Bool,
        noneTitle: String
    ) -> some View {
        Picker("", selection: selection) {
            if includesNone {
                Text(noneTitle).tag(String?.none)
            }
            ForEach(capsules) { capsule in
                Text(L10n.text(capsule.name))
                    .tag(Optional(capsule.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: GeneralSettingsChrome.controlClusterWidth, alignment: .trailing)
    }

    // MARK: Library column (master)

    private var libraryColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VibeComposeMetrics.space16) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        L10n.text("Search Writing Styles"),
                        text: $searchText
                    )
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let first = filteredCapsules.first {
                            select(first)
                        }
                    }
                }
                .vibeComposeSearchField()
                .frame(maxWidth: 340)

                HStack(alignment: .center, spacing: VibeComposeMetrics.space10) {
                    Text(L10n.text("Library"))
                        .font(VibeComposeTypography.title2())
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(VibeComposeMotion.standardSpring) {
                            beginNew()
                        }
                    } label: {
                        Label(L10n.text("New"), systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!localAssetAccessEnabled || !config.styleCapsules.enabled)
                }

                LazyVStack(spacing: VibeComposeMetrics.space12) {
                    ForEach(filteredCapsules) { capsule in
                        styleCard(capsule)
                    }
                    if isComposingNew {
                        composingCard
                    }
                }
                .focusable()
                .vibeComposeSuppressFocusRing()
                .onMoveCommand { direction in
                    moveStyleSelection(direction)
                }

                if filteredCapsules.isEmpty, !isComposingNew {
                    VibeComposeEmptyState(
                        systemImage: "magnifyingglass",
                        title: L10n.text("No matching Writing Styles")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding(VibeComposeMetrics.space20)
        }
    }

    private func styleCard(_ capsule: StyleCapsule) -> some View {
        let isSelected = selectedID == capsule.id && !isComposingNew
        let isDefault = config.styleCapsules.defaultCapsuleID == capsule.id
        let presentation = WritingStylePresentation.forCapsule(capsule)
        let accent = Color(nsColor: presentation.accent)

        return Button {
            withAnimation(VibeComposeMotion.snappySpring) {
                select(capsule)
            }
        } label: {
            VStack(alignment: .leading, spacing: VibeComposeMetrics.space10) {
                HStack(alignment: .center, spacing: VibeComposeMetrics.space12) {
                    VibeComposeIconWell(
                        systemName: presentation.symbolName,
                        size: 36,
                        symbolSize: 16,
                        tint: accent,
                        fillOpacity: isSelected ? 0.16 : 0.11
                    )
                    Text(L10n.text(capsule.name))
                        .font(VibeComposeTypography.title2(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isDefault {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent)
                    }
                }

                Text(displaySummary(for: capsule))
                    .font(VibeComposeTypography.callout())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(VibeComposeMetrics.space16)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(
                Color(nsColor: VibeComposePalette.elevatedSurface),
                in: RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusXL,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusXL,
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
            .contentShape(
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusXL,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(L10n.text(capsule.name)). \(displaySummary(for: capsule))"
        )
        .accessibilityAddTraits(
            isSelected
                ? [.isButton, .isSelected]
                : [.isButton]
        )
    }

    private var composingCard: some View {
        let accent = Color(nsColor: VibeComposePalette.brandSpectrumAmber)
        return VStack(alignment: .leading, spacing: VibeComposeMetrics.space10) {
            HStack(alignment: .center, spacing: VibeComposeMetrics.space12) {
                VibeComposeIconWell(
                    systemName: "plus.circle.fill",
                    size: 36,
                    symbolSize: 18,
                    tint: accent,
                    fillOpacity: 0.18
                )
                Text(L10n.text("New"))
                    .font(VibeComposeTypography.title2(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "pencil.line")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(L10n.text("Custom"))
                .font(VibeComposeTypography.callout())
                .foregroundStyle(accent)
        }
        .padding(VibeComposeMetrics.space16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(
            Color(nsColor: VibeComposePalette.elevatedSurface),
            in: RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusXL,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeComposeMetrics.radiusXL,
                style: .continuous
            )
            .stroke(accent.opacity(0.90), lineWidth: 1.5)
        }
        .shadow(color: accent.opacity(0.14), radius: 10, x: 0, y: 4)
    }

    // MARK: Detail column

    @ViewBuilder
    private var detailColumn: some View {
        if selectedID != nil || isComposingNew {
            StyleCapsuleDetailPane(
                capsule: selectedCapsule,
                isComposingNew: isComposingNew,
                isDefault: selectedCapsule.map {
                    config.styleCapsules.defaultCapsuleID == $0.id
                } ?? false,
                localAssetAccessEnabled: localAssetAccessEnabled,
                editingName: $editingName,
                editingSummary: $editingSummary,
                approvedExample: $approvedExample,
                sourceSamples: $sourceSamples,
                showsSamples: $showsSamples,
                canSave: canSave,
                onSave: save,
                onExport: exportSelected,
                onDelete: deleteSelected,
                onSetDefault: {
                    guard let selectedCapsule else { return }
                    config.styleCapsules.defaultCapsuleID = selectedCapsule.id
                },
                onGenerate: analyzeSamples
            )
            .id(selectedID ?? "new")
        } else {
            VibeComposeEmptyState(
                systemImage: "paintbrush.pointed",
                title: L10n.text("Select a Writing Style")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Model helpers

    private var selectedCapsule: StyleCapsule? {
        capsules.first { $0.id == selectedID }
    }

    private var isComposingNew: Bool {
        selectedID == nil
            && (
                !editingName.isEmpty
                    || !editingSummary.isEmpty
                    || showsSamples
            )
    }

    private var styleAwareSkills: [SkillDefinition] {
        registry.orderedDefinitions.filter {
            $0.allCapabilities.contains(.styleCapsule)
        }
    }

    /// Only Skills with an explicit override — keeps the list short as the
    /// catalog grows; new overrides are added via the Add menu.
    private var skillOverrides: [SkillDefinition] {
        styleAwareSkills.filter {
            config.styleCapsules.assignedCapsuleID(for: $0.id) != nil
        }
    }

    private var filteredSkillOverrides: [SkillDefinition] {
        let query = assignmentSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !query.isEmpty else { return skillOverrides }
        return skillOverrides.filter {
            $0.localizedName
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .contains(query)
        }
    }

    private var unassignedStyleAwareSkills: [SkillDefinition] {
        styleAwareSkills.filter {
            config.styleCapsules.assignedCapsuleID(for: $0.id) == nil
        }
    }

    private func displaySummary(for capsule: StyleCapsule) -> String {
        capsule.isBuiltIn ? L10n.text(capsule.summary) : capsule.summary
    }

    private func displayExample(for capsule: StyleCapsule) -> String {
        guard let example = capsule.examples.first else { return "" }
        return capsule.isBuiltIn ? L10n.text(example) : example
    }

    private func addSkillOverride(_ skill: SkillDefinition) {
        let preferred =
            config.styleCapsules.defaultCapsuleID
            ?? capsules.first?.id
        guard let preferred else { return }
        config.styleCapsules.setCapsuleID(preferred, for: skill.id)
        assignmentSearchText = ""
    }

    private var canSave: Bool {
        localAssetAccessEnabled
            && selectedCapsule?.isBuiltIn != true
            && !editingName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            && !editingSummary
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }

    private func moveStyleSelection(_ direction: MoveCommandDirection) {
        let items = filteredCapsules
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex(where: { $0.id == selectedID }) ?? 0
        let nextIndex: Int
        switch direction {
        case .up, .left:
            nextIndex = max(0, currentIndex - 1)
        case .down, .right:
            nextIndex = min(items.count - 1, currentIndex + 1)
        @unknown default:
            return
        }
        select(items[nextIndex])
    }

    private func reload() {
        guard localAssetAccessEnabled else {
            capsules = StyleCapsuleRegistry.builtIn
            return
        }
        do {
            capsules = try store.loadAll()
            message = nil
            messageIsError = false
        } catch {
            capsules = StyleCapsuleRegistry.builtIn
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func select(_ capsule: StyleCapsule) {
        selectedID = capsule.id
        editingName = L10n.text(capsule.name)
        editingSummary = displaySummary(for: capsule)
        approvedExample = displayExample(for: capsule)
        sourceSamples = ""
        showsSamples = false
        message = nil
        messageIsError = false
    }

    private func beginNew() {
        selectedID = nil
        editingName = ""
        editingSummary = ""
        approvedExample = ""
        sourceSamples = ""
        showsSamples = true
        message = nil
        messageIsError = false
    }

    private func analyzeSamples() {
        let summary = StyleCapsuleAnalyzer.summarize(samples: sourceSamples)
        guard !summary.isEmpty else { return }
        editingSummary = summary
        sourceSamples = ""
        message = L10n.text("Summary generated.")
        messageIsError = false
    }

    private func save() {
        let now = ISO8601DateFormatter().string(from: Date())
        let existing = selectedCapsule
        let id = existing?.id ?? "user.\(UUID().uuidString.lowercased())"
        let capsule = StyleCapsule(
            id: id,
            name: editingName,
            summary: editingSummary,
            examples: approvedExample
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
                ? []
                : [approvedExample],
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            isBuiltIn: false
        )
        do {
            try store.save(capsule)
            reload()
            if let refreshed = capsules.first(where: { $0.id == capsule.id }) {
                select(refreshed)
            }
            message = L10n.text("Writing Style saved.")
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func deleteSelected() {
        guard let selectedCapsule, !selectedCapsule.isBuiltIn else { return }
        do {
            try store.delete(id: selectedCapsule.id)
            if config.styleCapsules.defaultCapsuleID == selectedCapsule.id {
                config.styleCapsules.defaultCapsuleID = nil
            }
            config.styleCapsules.skillAssignments.removeAll {
                $0.capsuleID == selectedCapsule.id
            }
            reload()
            if let first = capsules.first {
                select(first)
            } else {
                beginNew()
            }
            message = L10n.text("Writing Style deleted.")
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func exportSelected() {
        guard let selectedCapsule else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = selectedCapsule.id + ".json"
        panel.title = L10n.text("Export Writing Style")
        panel.prompt = L10n.text("Export")
        guard
            panel.runModal() == .OK,
            let url = panel.url
        else {
            return
        }
        do {
            try store.export(selectedCapsule, to: url)
            message = L10n.format("Exported %@.", url.lastPathComponent)
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }
}

// MARK: - Writing Style detail (Skill Library editorial layout)

private struct StyleCapsuleDetailPane: View {
    let capsule: StyleCapsule?
    let isComposingNew: Bool
    let isDefault: Bool
    let localAssetAccessEnabled: Bool
    @Binding var editingName: String
    @Binding var editingSummary: String
    @Binding var approvedExample: String
    @Binding var sourceSamples: String
    @Binding var showsSamples: Bool
    let canSave: Bool
    let onSave: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    let onSetDefault: () -> Void
    let onGenerate: () -> Void

    private var presentation: WritingStylePresentation {
        if let capsule {
            return WritingStylePresentation.forCapsule(capsule)
        }
        return WritingStylePresentation(
            symbolName: "paintbrush.pointed.fill",
            accent: VibeComposePalette.brandSpectrumAmber
        )
    }

    private var accent: Color {
        Color(nsColor: presentation.accent)
    }

    private var isBuiltIn: Bool {
        capsule?.isBuiltIn == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                identityHeader
                    .padding(.bottom, VibeComposeMetrics.space20)

                summaryBlock
                    .padding(.bottom, VibeComposeMetrics.space28)

                exampleSection
                    .padding(.bottom, VibeComposeMetrics.space24)

                if !isBuiltIn {
                    samplesSection
                        .padding(.bottom, VibeComposeMetrics.space24)
                }

                actionsRow
            }
            .padding(VibeComposeMetrics.space24)
            .frame(maxWidth: 650, alignment: .leading)
        }
    }

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space14) {
            HStack(alignment: .top, spacing: VibeComposeMetrics.space14) {
                VibeComposeIconWell(
                    systemName: presentation.symbolName,
                    size: 56,
                    symbolSize: 24,
                    tint: accent,
                    fillOpacity: 0.14
                )

                Spacer(minLength: VibeComposeMetrics.space12)

                defaultAction
            }

            VStack(alignment: .leading, spacing: VibeComposeMetrics.space6) {
                HStack(spacing: VibeComposeMetrics.space6) {
                    Image(systemName: isBuiltIn ? "checkmark.seal.fill" : "paintbrush.pointed.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(
                        isComposingNew
                            ? L10n.text("Custom")
                            : (isBuiltIn
                                ? L10n.text("Built-in · reviewed")
                                : L10n.text("Custom"))
                    )
                    .font(VibeComposeTypography.micro(.semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                }
                .foregroundStyle(accent)

                if isBuiltIn {
                    Text(editingName)
                        .font(VibeComposeTypography.display())
                        .tracking(-0.5)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    TextField(L10n.text("Name"), text: $editingName)
                        .textFieldStyle(.plain)
                        .font(VibeComposeTypography.display())
                        .tracking(-0.5)
                    Text(L10n.text("Describe the voice this style should write in."))
                        .font(VibeComposeTypography.callout())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var defaultAction: some View {
        if isComposingNew {
            EmptyView()
        } else if isDefault {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                Text(L10n.text("Default Style"))
                    .font(VibeComposeTypography.body(.semibold))
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
            .accessibilityLabel(L10n.text("Default Style"))
        } else if capsule != nil {
            Button(L10n.text("Set as Default Style")) {
                onSetDefault()
            }
            .buttonStyle(VibeComposeSecondaryButtonStyle())
            .controlSize(.regular)
            .help(L10n.text("Set as Default Style"))
            .accessibilityLabel(L10n.text("Set as Default Style"))
        }
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space10) {
            if isBuiltIn {
                Text(editingSummary)
                    .font(VibeComposeTypography.body())
                    .foregroundStyle(.primary.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            } else {
                Text(L10n.text("Summary"))
                    .font(VibeComposeTypography.body(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $editingSummary)
                    .font(VibeComposeTypography.body())
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110, maxHeight: 160)
                    .padding(VibeComposeMetrics.space10)
                    .background {
                        RoundedRectangle(
                            cornerRadius: VibeComposeMetrics.radiusM,
                            style: .continuous
                        )
                        .fill(Color(nsColor: VibeComposePalette.elevatedSurface))
                    }
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: VibeComposeMetrics.radiusM,
                            style: .continuous
                        )
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityLabel(L10n.text("Summary"))
            }
        }
    }

    private var exampleSection: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space12) {
            Text(L10n.text("Example"))
                .font(VibeComposeTypography.title2(.semibold))

            if isBuiltIn {
                beforeAfterExample
            } else {
                TextField(L10n.text("Example"), text: $approvedExample)
                    .textFieldStyle(.roundedBorder)
                    .font(VibeComposeTypography.body())
            }
        }
    }

    @ViewBuilder
    private var beforeAfterExample: some View {
        let after = approvedExample.trimmingCharacters(in: .whitespacesAndNewlines)
        let beforeKey = capsule.flatMap { WritingStylePresentation.rawSample(for: $0.id) }
        let before = beforeKey.map { L10n.text($0) } ?? ""

        if after.isEmpty, before.isEmpty {
            Text(L10n.text("No example yet."))
                .font(VibeComposeTypography.body())
                .foregroundStyle(Color.secondary.opacity(0.55))
        } else {
            HStack(alignment: .top, spacing: VibeComposeMetrics.space8) {
                examplePanel(
                    title: L10n.text("Original"),
                    body: before.isEmpty ? L10n.text("No example yet.") : before,
                    emphasized: false
                )
                transformConnector
                examplePanel(
                    title: L10n.text("Styled"),
                    body: after.isEmpty ? L10n.text("No example yet.") : after,
                    emphasized: true
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.text("Example"))
            .accessibilityValue(
                "\(L10n.text("Original")): \(before). \(L10n.text("Styled")): \(after)"
            )
        }
    }

    /// Decorative gradient arrow connecting the two example panels.
    private var transformConnector: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.secondary.opacity(0.35), accent.opacity(0.80)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .padding(.top, 38)
            .accessibilityHidden(true)
    }

    private func examplePanel(
        title: String,
        body: String,
        emphasized: Bool
    ) -> some View {
        let radius = VibeComposeMetrics.radiusXL
        return VStack(alignment: .leading, spacing: VibeComposeMetrics.space10) {
            // Title pill badge
            Text(title)
                .font(VibeComposeTypography.micro(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(
                    emphasized ? accent : Color.secondary.opacity(0.80)
                )
                .padding(.horizontal, VibeComposeMetrics.space8)
                .padding(.vertical, VibeComposeMetrics.space4)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            emphasized
                                ? accent.opacity(0.13)
                                : Color.primary.opacity(0.05)
                        )
                }

            // Body text
            Text(body)
                .font(VibeComposeTypography.callout())
                .foregroundStyle(
                    emphasized
                        ? Color.primary.opacity(0.92)
                        : Color.primary.opacity(0.68)
                )
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(VibeComposeMetrics.space16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        // Background — diagonal gradient for the emphasized card; flat for the other
        .background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if emphasized {
                shape.fill(
                    LinearGradient(
                        colors: [accent.opacity(0.12), accent.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else {
                shape.fill(Color(nsColor: VibeComposePalette.elevatedSurface))
            }
        }
        // Gradient stroke border — richer on the emphasized card
        .overlay {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if emphasized {
                shape.stroke(
                    LinearGradient(
                        colors: [accent.opacity(0.46), accent.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            } else {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.10),
                            Color.primary.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
        }
        // Accent shadow lifts the emphasized card off the surface
        .shadow(
            color: emphasized ? accent.opacity(0.14) : Color.clear,
            radius: 14,
            x: 0,
            y: 5
        )
    }

    private var samplesSection: some View {
        DisclosureGroup(isExpanded: $showsSamples) {
            VStack(alignment: .leading, spacing: VibeComposeMetrics.space10) {
                TextEditor(text: $sourceSamples)
                    .font(VibeComposeTypography.body())
                    .scrollContentBackground(.hidden)
                    .padding(VibeComposeMetrics.space10)
                    .frame(minHeight: 88)
                    .background {
                        RoundedRectangle(
                            cornerRadius: VibeComposeMetrics.radiusM,
                            style: .continuous
                        )
                        .fill(Color(nsColor: .textBackgroundColor))
                    }
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: VibeComposeMetrics.radiusM,
                            style: .continuous
                        )
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityLabel(L10n.text("Samples"))

                Button(L10n.text("Generate")) {
                    onGenerate()
                }
                .buttonStyle(.bordered)
                .disabled(
                    sourceSamples
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
            .padding(.top, VibeComposeMetrics.space10)
        } label: {
            Label(L10n.text("Samples"), systemImage: "doc.text.magnifyingglass")
                .font(VibeComposeTypography.body(.semibold))
        }
    }

    private var actionsRow: some View {
        HStack(spacing: VibeComposeMetrics.space10) {
            if !isBuiltIn {
                Button(L10n.text("Save")) {
                    onSave()
                }
                .buttonStyle(VibeComposePrimaryButtonStyle())
                .controlSize(.regular)
                .disabled(!canSave)
            }

            Button(L10n.text("Export…")) {
                onExport()
            }
            .buttonStyle(VibeComposeSecondaryButtonStyle())
            .controlSize(.regular)
            .disabled(capsule == nil || !localAssetAccessEnabled)

            if let capsule, !capsule.isBuiltIn {
                Button(L10n.text("Delete"), role: .destructive) {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Spacer(minLength: 0)
        }
    }
}

struct CommunitySkillSettingsView:
    View
{
    private struct ImportTestInput {
        let transcript: String
        let selection: String
        let style: String
        let terminology: String
    }

    private enum ImportReviewDecision {
        case test(ImportTestInput)
        case install
        case cancel
    }

    @Binding var config: AppConfig
    @Binding var inventory:
        CommunitySkillInventory
    let store: SkillPackageStore
    let localAssetAccessEnabled: Bool
    let onRunTest:
        (SkillTestRunRequest) async
            -> Result<SkillTestRunResult, any Error>

    @State private var selectedPackageID:
        String?
    @State private var message: String?
    @State private var messageIsError =
        false
    @State private var goldenTestMessage:
        String?
    @State private var searchText = ""
    @State private var inspectorExpanded = false
    @State private var isRunningImportTest = false

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        L10n.text(
                            "Skills Library"
                        )
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold
                        )
                    )
                }
                Spacer()
                Button(
                    L10n.text(
                        "Import Skill…"
                    )
                ) {
                    importSkill()
                }
                .buttonStyle(
                    .borderedProminent
                )
                .disabled(
                    !localAssetAccessEnabled
                        || isRunningImportTest
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    L10n.text("Search installed Skills"),
                    text: $searchText
                )
                .textFieldStyle(.plain)
                Spacer()
                Text(L10n.format(
                    "%ld installed · %ld favorites",
                    displayPackages.count,
                    config.skillEcosystem.favoriteInstallationIDs.count
                ))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )

            if !displayPackages.isEmpty {
                VStack(spacing: 6) {
                    ForEach(
                        displayPackages
                    ) { package in
                        communitySkillRow(
                            package
                        )
                    }
                }
            }

            if let selectedPackage {
                installedSkillSummary(selectedPackage)
                DisclosureGroup(
                    L10n.text(
                        "Advanced Inspector"
                    ),
                    isExpanded: $inspectorExpanded
                ) {
                    inspector(
                        selectedPackage
                    )
                    .padding(.top, 7)
                }
                .font(
                    .system(
                        size: 11,
                        weight: .semibold
                    )
                )
            }

            if !inventory.rejected.isEmpty {
                DisclosureGroup(
                    L10n.format(
                        "%ld blocked installed packages",
                        inventory.rejected.count
                    )
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {
                        ForEach(
                            inventory.rejected
                        ) { item in
                            Text(
                                "\(item.path): \(item.reason)"
                            )
                            .font(
                                .system(
                                    size: 9,
                                    design:
                                        .monospaced
                                )
                            )
                            .foregroundStyle(
                                .red
                            )
                            .textSelection(
                                .enabled
                            )
                        }
                    }
                    .padding(.top, 5)
                }
                .font(.system(size: 10))
                .foregroundStyle(.red)
            }

            if let message {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(
                        messageIsError
                            ? .red
                            : .secondary
                    )
            }
        }
        .onAppear {
            refresh()
        }
    }

    private var activePackages:
        [CommunitySkillPackage]
    {
        inventory.packages
            .filter(\.isActive)
    }

    private var displayPackages:
        [CommunitySkillPackage]
    {
        let grouped = Dictionary(
            grouping: inventory.packages,
            by: { $0.definition.id }
        )
        let packages = grouped.values.compactMap { versions in
            versions.first(where: \.isActive)
                ?? versions.first
        }
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        return packages.filter { package in
            guard !query.isEmpty else { return true }
            return [
                package.definition.name,
                package.definition.id,
                package.definition.author,
                package.format.rawValue,
            ].joined(separator: " ")
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                .contains(query)
        }.sorted {
            $0.definition.localizedName
                .localizedStandardCompare(
                    $1.definition.localizedName
                ) == .orderedAscending
        }
    }

    private var selectedPackage:
        CommunitySkillPackage?
    {
        if let selectedPackageID {
            return displayPackages
                .first {
                    $0.id
                        == selectedPackageID
                }
        }
        return displayPackages.first
    }

    private func versions(
        for skillID: String
    ) -> [CommunitySkillPackage] {
        inventory.packages
            .filter {
                $0.definition.id == skillID
            }
    }

    @ViewBuilder
    private func communitySkillRow(
        _ package:
            CommunitySkillPackage
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                communitySkillControls(package)
            }
            VStack(alignment: .leading, spacing: 9) {
                communitySkillControls(package)
            }
        }
        .padding(9)
        .background(
            Color(
                nsColor:
                    .textBackgroundColor
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 8
            )
        )
    }

    @ViewBuilder
    private func communitySkillControls(
        _ package: CommunitySkillPackage
    ) -> some View {
            Toggle(
                package.definition
                    .localizedName,
                isOn: Binding(
                    get: {
                        config.transcription
                            .skills
                            .isEnabled(
                                package
                                    .definition.id
                            )
                    },
                    set: { enabled in
                        config.transcription
                            .skills
                            .setEnabled(
                                enabled,
                                skillID:
                                    package
                                        .definition.id
                            )
                    }
                )
            )
            .font(
                .system(
                    size: 11,
                    weight: .semibold
                )
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .disabled(
                package.compatibility
                    .runtimeStatus
                    != .compatible
            )

            Picker(
                L10n.text(
                    "Active Version"
                ),
                selection: Binding(
                    get: {
                        package.definition
                            .version
                    },
                    set: { version in
                        config.communitySkills
                            .setActiveVersion(
                                version,
                                for:
                                    package
                                        .definition.id
                            )
                        refresh()
                    }
                )
            ) {
                ForEach(
                    versions(
                        for:
                            package
                                .definition.id
                    )
                ) { version in
                    Text(
                        version.definition
                            .version
                    )
                    .tag(
                        version.definition
                            .version
                    )
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(
                minWidth: 90,
                idealWidth: 115,
                maxWidth: 150
            )

            Button(
                L10n.text("Inspect")
            ) {
                selectedPackageID =
                    package.id
                inspectorExpanded = true
            }
            .buttonStyle(.bordered)

            Button {
                toggleFavorite(package)
            } label: {
                Image(systemName:
                    config.skillEcosystem
                        .favoriteInstallationIDs
                        .contains(package.installation.id)
                    ? "star.fill"
                    : "star"
                )
            }
            .buttonStyle(.bordered)
            .help(L10n.text("Favorite"))

            Button(
                L10n.text("Uninstall"),
                role: .destructive
            ) {
                uninstall(
                    skillID:
                        package.definition.id,
                    version:
                        package.definition
                            .version
                )
            }
            .buttonStyle(.bordered)
            .disabled(
                !localAssetAccessEnabled
            )
    }

    @ViewBuilder
    private func installedSkillSummary(
        _ package: CommunitySkillPackage
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(
                package.agentPackage?.metadata.description
                    ?? package.definition.localizedSummary
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Label(
                    L10n.format(
                        "Required: %@",
                        package.profile.contextRequest.required.isEmpty
                            ? L10n.text("None")
                            : package.profile.contextRequest.required
                                .map(\.title)
                                .joined(separator: ", ")
                    ),
                    systemImage: "checkmark.shield"
                )
                Label(
                    L10n.format(
                        "%@ · %@ · %@ risk",
                        package.profile.output.format.localizedLabel,
                        package.profile.output.delivery.localizedLabel,
                        package.profile.risk.localizedLabel
                    ),
                    systemImage: "arrow.right.doc.on.clipboard"
                )
            }
            .font(.system(size: 10, weight: .medium))
        }
        .padding(10)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.5),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    @ViewBuilder
    private func inspector(
        _ package:
            CommunitySkillPackage
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
            inspectorLine(
                "Format",
                package.format.rawValue
            )
            inspectorLine(
                "Compatibility",
                "\(package.compatibility.level.rawValue) · \(package.compatibility.runtimeStatus.rawValue)"
            )
            inspectorLine(
                "Installation ID",
                package.installation.id.uuidString
            )
            inspectorLine(
                "ID",
                package.definition.id
            )
            inspectorLine(
                "Version",
                package.definition.version
            )
            inspectorLine(
                "Author",
                package.definition.author
            )
            inspectorLine(
                "Permissions",
                (
                    package.definition
                        .requiredCapabilities
                    + package.definition
                        .optionalCapabilities
                )
                .map(\.rawValue)
                .joined(separator: ", ")
            )
            inspectorLine(
                "Output",
                "\(package.definition.output.format.rawValue) · \(package.definition.output.delivery.rawValue) · \(package.definition.output.risk.rawValue)"
            )
            inspectorLine(
                "Validators",
                validatorSummary(
                    package.definition
                        .validators
                )
            )
            inspectorLine(
                "Terminology",
                L10n.format(
                    "%ld Skill-local entries",
                    package.definition
                        .terminologyEntries
                        .count
                )
            )
            inspectorLine(
                "SHA-256",
                package.contentSHA256
            )
            if !package.compatibility.issues.isEmpty {
                InlineStatus(
                    text: package.compatibility.issues.joined(separator: " · "),
                    kind: .error
                )
            }
            if !package.compatibility.quarantinedResources.isEmpty {
                InlineStatus(
                    text: L10n.format(
                        "%ld resources quarantined and hidden from runtime.",
                        package.compatibility.quarantinedResources.count
                    ),
                    kind: .warning
                )
            }
            HStack {
                Button(
                    L10n.text(
                        "Run Golden Tests"
                    )
                ) {
                    runGoldenTests(
                        package
                    )
                }
                .buttonStyle(.bordered)
                Button(L10n.text("Fork as Standard Skill…")) {
                    forkPackage(package)
                }
                .buttonStyle(.bordered)
                .disabled(!localAssetAccessEnabled)
                if let goldenTestMessage {
                    Text(
                        goldenTestMessage
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(
                        goldenTestMessage
                            .contains("failed")
                        ? .red
                        : .secondary
                    )
                }
            }

            DisclosureGroup(
                L10n.format(
                    "%ld reviewed files",
                    package.relativeFiles
                        .count
                )
            ) {
                Text(
                    package.relativeFiles
                        .joined(separator: "\n")
                )
                .font(
                    .system(
                        size: 9,
                        design: .monospaced
                    )
                )
                .textSelection(.enabled)
                .padding(.top, 4)
            }
            .font(.system(size: 10))
        }
        .padding(9)
        .background(
            Color(
                nsColor:
                    .controlBackgroundColor
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 8
            )
        )
    }

    private func inspectorLine(
        _ title: String,
        _ value: String
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 8
        ) {
            Text(L10n.text(title))
                .font(
                    .system(
                        size: 9,
                        weight: .semibold
                    )
                )
                .frame(
                    width: 74,
                    alignment: .leading
                )
            Text(value)
                .font(
                    .system(
                        size: 9,
                        design:
                            title
                                == "SHA-256"
                            ? .monospaced
                            : .default
                    )
                )
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
    }

    private func validatorSummary(
        _ policy:
            SkillValidatorPolicy
    ) -> String {
        var values = [
            "non-empty",
            "max \(policy.maximumCharacters)",
        ]
        if policy.preserveTechnicalLiterals {
            values.append(
                "technical literals"
            )
        }
        if policy
            .requireClosedMarkdownFences
        {
            values.append(
                "closed fences"
            )
        }
        if
            !policy
                .requiredSectionAlternatives
                .isEmpty
        {
            values.append(
                "required sections"
            )
        }
        return values.joined(
            separator: ", "
        )
    }

    private func importSkill() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories =
            true
        panel.title = L10n.text(
            "Import VibeCompose Skill"
        )
        panel.message = L10n.text(
            "Choose a standard Agent Skills directory containing SKILL.md, or a legacy .vibecomposeskill v1 directory. Every file is scanned before it is copied into VibeCompose's private Skills directory."
        )
        panel.prompt = L10n.text("Review")
        guard
            panel.runModal() == .OK,
            let url = panel.url
        else {
            return
        }
        do {
            let inspected =
                try store.inspect(
                    packageURL: url
                )
            switch review(inspected) {
            case .test(let input):
                runImportTest(
                    package: inspected,
                    sourceURL: url,
                    input: input
                )
            case .install:
                installReviewedSkill(
                    from: url,
                    inspected: inspected
                )
            case .cancel:
                break
            }
        } catch {
            message = error.localizedDescription
            messageIsError = true
            NSSound.beep()
        }
    }

    private func installReviewedSkill(
        from sourceURL: URL,
        inspected: CommunitySkillPackage
    ) {
        do {
            let previous = activePackages.first {
                $0.definition.id
                    == inspected.definition.id
            }
            let installed = try store.install(
                from: sourceURL
            )
            config.communitySkills
                .setActiveVersion(
                    installed.definition
                        .version,
                    for:
                        installed.definition
                            .id
                )
            config.transcription.skills
                .setEnabled(
                    installed.compatibility
                        .runtimeStatus
                        == .compatible,
                    skillID:
                        installed.definition
                            .id
                )
            resetExpandedContextPermissions(
                previous: previous,
                installed: installed
            )
            refresh()
            selectedPackageID =
                installed.id
            message = L10n.format(
                "Installed %@ %@.",
                installed.definition.name,
                installed.definition
                    .version
            )
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
            NSSound.beep()
        }
    }

    private func runImportTest(
        package: CommunitySkillPackage,
        sourceURL: URL,
        input: ImportTestInput
    ) {
        let transcript = input.transcript
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !transcript.isEmpty else {
            message = SkillTestRunError.emptyInput.localizedDescription
            messageIsError = true
            NSSound.beep()
            return
        }
        let selection = input.selection
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let style = input.style.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let terminology = input.terminology
            .components(
                separatedBy: CharacterSet(
                    charactersIn: ",;\n"
                )
            )
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter { !$0.isEmpty }
            .prefix(80)
            .map {
                TerminologyEntry(
                    canonical: $0,
                    aliases: [],
                    source: "install-test-run"
                )
            }
        let plan = ResolvedSkillExecutionPlan(
            skill: package.definition,
            source: .manual,
            matchedApplicationRuleID: nil,
            installation: package.installation,
            package: package.agentPackage,
            profile: package.profile,
            resources: package.resolvedResources
        )
        isRunningImportTest = true
        message = L10n.text(
            "Running a real installation test…"
        )
        messageIsError = false
        Task { @MainActor in
            let result = await onRunTest(
                SkillTestRunRequest(
                    plan: plan,
                    inputText: transcript,
                    context: SkillPromptContext(
                        styleCapsule:
                            style.isEmpty ? nil : style,
                        selection:
                            selection.isEmpty ? nil : selection
                    ),
                    terminologyEntries: terminology
                )
            )
            isRunningImportTest = false
            switch result {
            case .success(let result):
                guard !result.wasCancelled else {
                    message = L10n.text(
                        "Installation test cancelled; the Skill was not installed."
                    )
                    messageIsError = false
                    return
                }
                message = result.validation.isValid
                    ? L10n.text(
                        "Installation test passed. Review the result before installing."
                    )
                    : L10n.text(
                        "Installation test finished with Validator issues."
                    )
                messageIsError = !result.validation.isValid
                if confirmInstallAfterTest(
                    package: package,
                    result: result
                ) {
                    installReviewedSkill(
                        from: sourceURL,
                        inspected: package
                    )
                }
            case .failure(let error):
                message = error.localizedDescription
                messageIsError = true
                NSSound.beep()
            }
        }
    }

    private func runGoldenTests(
        _ package:
            CommunitySkillPackage
    ) {
        do {
            let result =
                try store.runGoldenTests(
                    package: package
                )
            if result.total == 0 {
                goldenTestMessage =
                    L10n.text(
                        "No Golden tests in this package."
                    )
            } else if
                result.passed
                    == result.total
            {
                goldenTestMessage =
                    L10n.format(
                        "%ld/%ld Golden tests passed.",
                        result.passed,
                        result.total
                    )
            } else {
                goldenTestMessage =
                    L10n.format(
                        "%ld/%ld Golden tests passed; failed checks: %@.",
                        result.passed,
                        result.total,
                        result.issueCodes
                            .joined(
                                separator: ", "
                            )
                    )
            }
        } catch {
            goldenTestMessage =
                error.localizedDescription
        }
    }

    private func review(
        _ package:
            CommunitySkillPackage
    ) -> ImportReviewDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.format(
            "Install %@ %@?",
            package.definition.name,
            package.definition.version
        )
        let required = package.profile.contextRequest.required
            .map(\.title)
            .joined(separator: ", ")
        let optional = package.profile.contextRequest.optional
            .map(\.title)
            .joined(separator: ", ")
        let purpose = package.agentPackage?.metadata.description
            ?? package.definition.localizedSummary
        let upgradeLines = upgradeReviewLines(for: package)
        alert.informativeText =
            """
            \(L10n.text("Purpose")): \(purpose)
            \(L10n.text("Author")): \(package.definition.author)
            \(L10n.text("Required")): \(required.isEmpty ? L10n.text("None") : required)
            \(L10n.text("Optional")): \(optional.isEmpty ? L10n.text("None") : optional)
            \(L10n.text("Output")): \(package.definition.output.format.localizedLabel) / \(package.definition.output.delivery.localizedLabel) / \(package.definition.output.risk.localizedLabel)
            \(L10n.text("Compatibility")): \(package.compatibility.level.rawValue) / \(package.compatibility.runtimeStatus.rawValue)
            \(upgradeLines)

            \(L10n.text("Scripts and vendor extensions are preserved in quarantine but never exposed to the model or executed. Tool-dependent Skills can be installed for inspection but cannot be enabled."))
            """

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.frame = NSRect(
            x: 0,
            y: 0,
            width: 480,
            height: 190
        )
        let transcriptField = NSTextField()
        let selectionField = NSTextField()
        let styleField = NSTextField()
        let terminologyField = NSTextField()
        func addInput(
            title: String,
            placeholder: String,
            field: NSTextField
        ) {
            let label = NSTextField(labelWithString: L10n.text(title))
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            field.placeholderString = L10n.text(placeholder)
            field.frame.size.width = 480
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(label)
            stack.addArrangedSubview(field)
        }
        addInput(
            title: "Test input",
            placeholder: "Type a temporary sample to transform",
            field: transcriptField
        )
        addInput(
            title: "Simulated selection (optional)",
            placeholder: "Text this Skill may rewrite or answer",
            field: selectionField
        )
        addInput(
            title: "Simulated style (optional)",
            placeholder: "For example: concise and friendly",
            field: styleField
        )
        addInput(
            title: "Simulated terminology (optional)",
            placeholder: "Comma-separated terms",
            field: terminologyField
        )
        alert.accessoryView = stack
        alert.addButton(
            withTitle:
                L10n.text("Test Run")
        )
        alert.addButton(
            withTitle:
                L10n.text("Install without Test")
        )
        alert.addButton(
            withTitle:
                L10n.text("Cancel")
        )
        NSApplication.shared.activate(
            ignoringOtherApps: true
        )
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .test(
                ImportTestInput(
                    transcript: transcriptField.stringValue,
                    selection: selectionField.stringValue,
                    style: styleField.stringValue,
                    terminology: terminologyField.stringValue
                )
            )
        case .alertSecondButtonReturn:
            return .install
        default:
            return .cancel
        }
    }

    private func confirmInstallAfterTest(
        package: CommunitySkillPackage,
        result: SkillTestRunResult
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = result.validation.isValid
            ? .informational
            : .warning
        alert.messageText = result.validation.isValid
            ? L10n.text("Test passed. Install this Skill?")
            : L10n.text(
                "The test has Validator issues. Install for inspection anyway?"
            )
        let issues = result.validation.issues
            .map { $0.code.rawValue }
            .joined(separator: ", ")
        alert.informativeText = [
            L10n.format(
                "Skill: %@ %@",
                package.definition.localizedName,
                package.definition.version
            ),
            result.wasEdited
                ? L10n.text("You edited the Provider result in Preview.")
                : L10n.text("You reviewed the Provider result in Preview."),
            issues.isEmpty
                ? L10n.text("Validator passed")
                : L10n.format("Validator failed: %@", issues),
        ].joined(separator: "\n")
        alert.addButton(withTitle: L10n.text("Install"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func upgradeReviewLines(
        for package: CommunitySkillPackage
    ) -> String {
        guard let previous = activePackages.first(where: {
            $0.definition.id == package.definition.id
        }) else {
            return L10n.text(
                "New installation. No existing version will be replaced."
            )
        }
        let previousRequested = Set(
            previous.profile.contextRequest.required
                + previous.profile.contextRequest.optional
        )
        let newRequired = package.profile.contextRequest.required
            .filter { !previousRequested.contains($0) }
            .map(\.title)
        var lines = [
            L10n.format(
                "Update review: %@ → %@. The current version remains available for rollback.",
                previous.definition.version,
                package.definition.version
            ),
        ]
        if !newRequired.isEmpty {
            lines.append(
                L10n.format(
                    "New required Context: %@. VibeCompose will ask again before use.",
                    newRequired.joined(separator: ", ")
                )
            )
        }
        if previous.profile.output != package.profile.output {
            lines.append(
                L10n.text(
                    "Output format, delivery, or risk changed; review the new policy above."
                )
            )
        }
        if previous.contentSHA256 != package.contentSHA256 {
            lines.append(
                L10n.text(
                    "Instructions or packaged resources changed. Technical details remain available in Advanced Inspector."
                )
            )
        }
        return lines.joined(separator: "\n")
    }

    private func resetExpandedContextPermissions(
        previous: CommunitySkillPackage?,
        installed: CommunitySkillPackage
    ) {
        let previousRequested = Set(
            (previous?.profile.contextRequest.required ?? [])
                + (previous?.profile.contextRequest.optional ?? [])
        )
        let expanded = Set(
            installed.profile.contextRequest.required
                + installed.profile.contextRequest.optional
        ).subtracting(previousRequested)
        for source in expanded {
            guard let capability = permissionCapability(for: source) else {
                continue
            }
            config.context.setScope(
                .askEveryTime,
                skillID: installed.definition.id,
                capability: capability
            )
        }
    }

    private func permissionCapability(
        for source: ContextSourceKind
    ) -> SkillCapability? {
        switch source {
        case .voice, .activeApp, .terminology,
             .openFile, .workspace, .editorDiagnostics,
             .terminalSession, .browserPage:
            return nil
        case .selection:
            return .selection
        case .styleCapsule:
            return .styleCapsule
        case .focusedParagraph:
            return .focusedParagraph
        case .conversationWindow:
            return .conversationWindow
        case .clipboard:
            return .clipboard
        }
    }

    private func uninstall(
        skillID: String,
        version: String
    ) {
        do {
            try store.uninstall(
                skillID: skillID,
                version: version
            )
            refresh()
            let remaining =
                versions(for: skillID)
            if
                let newest =
                    remaining.first
            {
                config.communitySkills
                    .setActiveVersion(
                        newest.definition
                            .version,
                        for: skillID
                    )
            }
            message = L10n.format(
                "Uninstalled %@ %@.",
                skillID,
                version
            )
            messageIsError = false
        } catch {
            message =
                error.localizedDescription
            messageIsError = true
        }
    }

    private func forkPackage(
        _ package: CommunitySkillPackage
    ) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = L10n.text("Fork as Standard Skill")
        panel.prompt = L10n.text("Export")
        panel.nameFieldStringValue = "\(package.definition.id.split(separator: ".").last ?? "skill")-fork"
        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }
        let creator = SkillCreator(fileManager: .default)
        let draft: SkillCreatorDraft
        if let agentPackage = package.agentPackage {
            draft = creator.fork(
                package: agentPackage,
                name: destination.lastPathComponent
            )
        } else {
            draft = SkillCreatorDraft(
                name: destination.lastPathComponent,
                description: "Fork of \(package.definition.name)",
                instructions: package.definition.promptInstruction,
                license: nil,
                version: "1.0.0",
                author: "Local Creator",
                profile: package.profile,
                references: [:],
                assets: [:],
                goldenCasesJSONL: nil
            )
        }
        do {
            _ = try creator.export(draft, to: destination)
            message = L10n.format(
                "Exported standard Skill to %@.",
                destination.lastPathComponent
            )
            messageIsError = false
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func refresh() {
        guard localAssetAccessEnabled
        else {
            inventory =
                CommunitySkillInventory(
                    packages: [],
                    rejected: []
                )
            return
        }
        inventory =
            store.loadInventory(
                config:
                    config.communitySkills
            )
        if selectedPackageID == nil {
            selectedPackageID =
                activePackages.first?.id
        }
    }

    private func toggleFavorite(
        _ package: CommunitySkillPackage
    ) {
        let id = package.installation.id
        let wasFavorite = config.skillEcosystem
            .favoriteInstallationIDs
            .contains(id)
        config.skillEcosystem.favoriteInstallationIDs.removeAll { $0 == id }
        if !wasFavorite {
            config.skillEcosystem.favoriteInstallationIDs.append(id)
        }
    }

}
