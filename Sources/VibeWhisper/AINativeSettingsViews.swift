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
                accent: VibeWhisperPalette.brandBlue
            )
        case StyleCapsuleRegistry.teamChatID:
            return WritingStylePresentation(
                symbolName: "bubble.left.and.bubble.right.fill",
                accent: VibeWhisperPalette.brandSpectrumCyan
            )
        case StyleCapsuleRegistry.technicalWritingID:
            return WritingStylePresentation(
                symbolName: "chevron.left.forwardslash.chevron.right",
                accent: VibeWhisperPalette.brandSpectrumViolet
            )
        case StyleCapsuleRegistry.englishBusinessID:
            return WritingStylePresentation(
                symbolName: "globe.europe.africa.fill",
                accent: VibeWhisperPalette.brandSpectrumSky
            )
        case StyleCapsuleRegistry.personalCasualID:
            return WritingStylePresentation(
                symbolName: "face.smiling.fill",
                accent: VibeWhisperPalette.brandSpectrumCoral
            )
        default:
            return WritingStylePresentation(
                symbolName: "paintbrush.pointed.fill",
                accent: VibeWhisperPalette.brandSpectrumAmber
            )
        }
    }
}

struct StyleCapsuleLibraryView: View {
    @Binding var config: AppConfig
    let registry: SkillRegistry
    let store: StyleCapsuleStore
    let localAssetAccessEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VibeWhisperPaneHeader(
                title: L10n.text("Writing Styles")
            ) {
                Toggle(
                    L10n.text("Enabled"),
                    isOn: $config.styleCapsules.enabled
                )
                .toggleStyle(.switch)
            }

            StyleCapsuleSettingsView(
                config: $config,
                registry: registry,
                store: store,
                localAssetAccessEnabled: localAssetAccessEnabled,
                showsSectionTitle: false,
                showsEnabledToggle: false
            )
            .padding(.horizontal, VibeWhisperMetrics.space20)
            .padding(.bottom, VibeWhisperMetrics.space24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StyleCapsuleSettingsView: View {
    @Binding var config: AppConfig
    let registry: SkillRegistry
    let store: StyleCapsuleStore
    let localAssetAccessEnabled: Bool
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
    @State private var showsSkillAssignments = false

    private let galleryColumns = [
        GridItem(.adaptive(minimum: 148, maximum: 200), spacing: VibeWhisperMetrics.space12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VibeWhisperMetrics.space20) {
                if showsSectionTitle || showsEnabledToggle {
                    HStack {
                        if showsSectionTitle {
                            Text(L10n.text("Writing Styles"))
                                .font(VibeWhisperTypography.title2())
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
                }

                defaultStrip
                    .disabled(!config.styleCapsules.enabled)

                gallerySection
                    .opacity(config.styleCapsules.enabled ? 1 : 0.48)
                    .allowsHitTesting(config.styleCapsules.enabled)

                if selectedID != nil || isComposingNew {
                    detailHero
                        .opacity(config.styleCapsules.enabled ? 1 : 0.48)
                        .allowsHitTesting(config.styleCapsules.enabled)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if let message {
                    Text(message)
                        .font(VibeWhisperTypography.body(.medium))
                        .foregroundStyle(
                            messageIsError
                                ? Color(nsColor: VibeWhisperPalette.error)
                                : .secondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, VibeWhisperMetrics.space12)
            .animation(VibeWhisperMotion.standardSpring, value: selectedID)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            reload()
            if selectedID == nil, let first = capsules.first {
                select(first)
            }
        }
    }

    // MARK: Default strip

    private var defaultStrip: some View {
        VStack(alignment: .leading, spacing: VibeWhisperMetrics.space14) {
            HStack(alignment: .center, spacing: VibeWhisperMetrics.space12) {
                VibeWhisperIconWell(
                    systemName: "star.circle.fill",
                    size: VibeWhisperMetrics.iconWellSizeLarge,
                    symbolSize: 18,
                    tint: Color(nsColor: VibeWhisperPalette.brandBlue),
                    fillOpacity: 0.14
                )
                Text(L10n.text("Default Style"))
                    .font(VibeWhisperTypography.title2())
                Spacer(minLength: 0)
                if !styleAwareSkills.isEmpty {
                    Button {
                        withAnimation(VibeWhisperMotion.snappySpring) {
                            showsSkillAssignments.toggle()
                        }
                    } label: {
                        Label(
                            L10n.text("By Skill"),
                            systemImage: showsSkillAssignments
                                ? "chevron.up"
                                : "chevron.down"
                        )
                        .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: VibeWhisperMetrics.space10) {
                    defaultChip(
                        id: nil,
                        title: L10n.text("None"),
                        symbol: "circle.slash",
                        accent: VibeWhisperPalette.mistMuted
                    )
                    ForEach(capsules) { capsule in
                        let presentation = WritingStylePresentation.forCapsule(capsule)
                        defaultChip(
                            id: capsule.id,
                            title: L10n.text(capsule.name),
                            symbol: presentation.symbolName,
                            accent: presentation.accent
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            if showsSkillAssignments, !styleAwareSkills.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(styleAwareSkills) { skill in
                        SettingsRow(title: skill.localizedName) {
                            Picker(
                                skill.localizedName,
                                selection: Binding<String?>(
                                    get: {
                                        config.styleCapsules
                                            .assignedCapsuleID(for: skill.id)
                                    },
                                    set: { value in
                                        config.styleCapsules
                                            .setCapsuleID(value, for: skill.id)
                                    }
                                )
                            ) {
                                Text(L10n.text("Use Default"))
                                    .tag(String?.none)
                                ForEach(capsules) { capsule in
                                    Text(L10n.text(capsule.name))
                                        .tag(Optional(capsule.id))
                                }
                            }
                            .labelsHidden()
                            .frame(width: GeneralSettingsChrome.controlClusterWidth)
                        }
                    }
                }
                .padding(.top, VibeWhisperMetrics.space4)
            }
        }
        .padding(VibeWhisperMetrics.space18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusXXL,
                style: .continuous
            )
            .fill(Color(nsColor: VibeWhisperPalette.elevatedSurface))
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusXXL,
                style: .continuous
            )
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private func defaultChip(
        id: String?,
        title: String,
        symbol: String,
        accent: NSColor
    ) -> some View {
        let isDefault = config.styleCapsules.defaultCapsuleID == id
        let tint = Color(nsColor: accent)
        return Button {
            config.styleCapsules.defaultCapsuleID = id
        } label: {
            HStack(spacing: VibeWhisperMetrics.space8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isDefault ? .white : tint)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle()
                            .fill(isDefault ? tint : tint.opacity(0.14))
                    }
                Text(title)
                    .font(VibeWhisperTypography.body(.semibold))
                    .foregroundStyle(isDefault ? .white : .primary)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(isDefault ? tint : Color(nsColor: VibeWhisperPalette.insetSurface))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        isDefault ? Color.clear : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: isDefault ? tint.opacity(0.28) : .clear,
                radius: 8,
                x: 0,
                y: 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isDefault ? .isSelected : [])
        .accessibilityLabel("\(L10n.text("Default Style")): \(title)")
    }

    // MARK: Gallery

    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: VibeWhisperMetrics.space14) {
            HStack(alignment: .center, spacing: VibeWhisperMetrics.space10) {
                Text(L10n.text("Library"))
                    .font(VibeWhisperTypography.title2())
                Spacer(minLength: 0)
                Button {
                    withAnimation(VibeWhisperMotion.standardSpring) {
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

            LazyVGrid(columns: galleryColumns, spacing: VibeWhisperMetrics.space12) {
                ForEach(capsules) { capsule in
                    styleCard(capsule)
                }
                if isComposingNew {
                    composingCard
                }
            }
        }
    }

    private func styleCard(_ capsule: StyleCapsule) -> some View {
        let isSelected = selectedID == capsule.id && !isComposingNew
        let isDefault = config.styleCapsules.defaultCapsuleID == capsule.id
        let presentation = WritingStylePresentation.forCapsule(capsule)
        let accent = Color(nsColor: presentation.accent)

        return Button {
            withAnimation(VibeWhisperMotion.snappySpring) {
                select(capsule)
            }
        } label: {
            VStack(alignment: .leading, spacing: VibeWhisperMetrics.space12) {
                HStack(alignment: .top, spacing: VibeWhisperMetrics.space8) {
                    VibeWhisperIconWell(
                        systemName: presentation.symbolName,
                        size: 44,
                        symbolSize: 18,
                        tint: accent,
                        fillOpacity: isSelected ? 0.20 : 0.12
                    )
                    Spacer(minLength: 0)
                    if isDefault {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(accent)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accent)
                            .symbolRenderingMode(.hierarchical)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(capsule.name))
                        .font(VibeWhisperTypography.title2())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        capsule.isBuiltIn
                            ? L10n.text("Built-in")
                            : L10n.text("Custom")
                    )
                    .font(VibeWhisperTypography.body(.medium))
                    .foregroundStyle(accent.opacity(0.95))
                    .lineLimit(1)
                }
            }
            .padding(VibeWhisperMetrics.space16)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background {
                RoundedRectangle(
                    cornerRadius: VibeWhisperMetrics.radiusXXL,
                    style: .continuous
                )
                .fill(Color(nsColor: VibeWhisperPalette.elevatedSurface))
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: VibeWhisperMetrics.radiusXXL,
                    style: .continuous
                )
                .strokeBorder(
                    isSelected ? accent.opacity(0.90) : Color.primary.opacity(0.06),
                    lineWidth: isSelected ? 2 : 1
                )
            }
            .shadow(
                color: isSelected
                    ? accent.opacity(0.18)
                    : Color.black.opacity(0.04),
                radius: isSelected ? 14 : 6,
                x: 0,
                y: isSelected ? 6 : 2
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: VibeWhisperMetrics.radiusXXL,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(
            "\(L10n.text(capsule.name)). \(capsule.isBuiltIn ? L10n.text("Built-in") : L10n.text("Custom"))"
        )
    }

    private var composingCard: some View {
        let accent = Color(nsColor: VibeWhisperPalette.brandSpectrumAmber)
        return VStack(alignment: .leading, spacing: VibeWhisperMetrics.space12) {
            HStack {
                VibeWhisperIconWell(
                    systemName: "plus.circle.fill",
                    size: 44,
                    symbolSize: 20,
                    tint: accent,
                    fillOpacity: 0.18
                )
                Spacer(minLength: 0)
                Image(systemName: "pencil.line")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Text(L10n.text("New"))
                .font(VibeWhisperTypography.title2())
                .foregroundStyle(.primary)
            Text(L10n.text("Custom"))
                .font(VibeWhisperTypography.body(.medium))
                .foregroundStyle(accent)
        }
        .padding(VibeWhisperMetrics.space16)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background {
            RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusXXL,
                style: .continuous
            )
            .fill(Color(nsColor: VibeWhisperPalette.elevatedSurface))
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusXXL,
                style: .continuous
            )
            .strokeBorder(accent.opacity(0.90), lineWidth: 2)
        }
        .shadow(color: accent.opacity(0.16), radius: 12, x: 0, y: 5)
    }

    // MARK: Detail hero

    private var detailHero: some View {
        let presentation: WritingStylePresentation = {
            if let selectedCapsule {
                return WritingStylePresentation.forCapsule(selectedCapsule)
            }
            return WritingStylePresentation(
                symbolName: "paintbrush.pointed.fill",
                accent: VibeWhisperPalette.brandSpectrumAmber
            )
        }()
        let accent = Color(nsColor: presentation.accent)
        let isBuiltIn = selectedCapsule?.isBuiltIn == true

        return VStack(alignment: .leading, spacing: VibeWhisperMetrics.space18) {
            HStack(alignment: .top, spacing: VibeWhisperMetrics.space16) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 20,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.22),
                                accent.opacity(0.08),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    Image(systemName: presentation.symbolName)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(accent)
                        .symbolRenderingMode(.hierarchical)
                }
                .shadow(color: accent.opacity(0.22), radius: 12, x: 0, y: 4)

                VStack(alignment: .leading, spacing: VibeWhisperMetrics.space8) {
                    HStack(spacing: VibeWhisperMetrics.space8) {
                        if isBuiltIn {
                            VibeWhisperStatusChip(
                                text: L10n.text("Built-in"),
                                kind: .accent
                            )
                        } else {
                            VibeWhisperStatusChip(
                                text: L10n.text("Custom"),
                                kind: .warning
                            )
                        }
                        if let selectedCapsule,
                           config.styleCapsules.defaultCapsuleID == selectedCapsule.id
                        {
                            VibeWhisperStatusChip(
                                text: L10n.text("Default Style"),
                                kind: .success
                            )
                        }
                    }

                    if isBuiltIn {
                        Text(editingName)
                            .font(VibeWhisperTypography.display())
                            .tracking(-0.4)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        TextField(
                            L10n.text("Name"),
                            text: $editingName
                        )
                        .textFieldStyle(.plain)
                        .font(VibeWhisperTypography.display())
                        .tracking(-0.4)
                    }
                }

                Spacer(minLength: 0)
            }

            // Summary as quote-like visual block
            VStack(alignment: .leading, spacing: VibeWhisperMetrics.space10) {
                HStack(spacing: VibeWhisperMetrics.space8) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(L10n.text("Summary"))
                        .font(VibeWhisperTypography.body(.semibold))
                        .foregroundStyle(.secondary)
                }

                if isBuiltIn {
                    Text(editingSummary)
                        .font(VibeWhisperTypography.body())
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextEditor(text: $editingSummary)
                        .font(VibeWhisperTypography.body())
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110, maxHeight: 160)
                        .accessibilityLabel(L10n.text("Summary"))
                }
            }
            .padding(VibeWhisperMetrics.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: VibeWhisperMetrics.radiusXL,
                    style: .continuous
                )
                .fill(accent.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: VibeWhisperMetrics.radiusXL,
                    style: .continuous
                )
                .strokeBorder(accent.opacity(0.16), lineWidth: 1)
            }

            // Example
            VStack(alignment: .leading, spacing: VibeWhisperMetrics.space8) {
                HStack(spacing: VibeWhisperMetrics.space8) {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(L10n.text("Example"))
                        .font(VibeWhisperTypography.body(.semibold))
                        .foregroundStyle(.secondary)
                }
                if isBuiltIn {
                    Text(
                        approvedExample.isEmpty
                            ? "—"
                            : approvedExample
                    )
                    .font(VibeWhisperTypography.body())
                    .foregroundStyle(approvedExample.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(
                        L10n.text("Example"),
                        text: $approvedExample
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(VibeWhisperTypography.body())
                }
            }

            if !isBuiltIn {
                DisclosureGroup(isExpanded: $showsSamples) {
                    VStack(alignment: .leading, spacing: VibeWhisperMetrics.space10) {
                        TextEditor(text: $sourceSamples)
                            .font(VibeWhisperTypography.body())
                            .scrollContentBackground(.hidden)
                            .padding(VibeWhisperMetrics.space10)
                            .frame(minHeight: 88)
                            .background {
                                RoundedRectangle(
                                    cornerRadius: VibeWhisperMetrics.radiusM,
                                    style: .continuous
                                )
                                .fill(Color(nsColor: .textBackgroundColor))
                            }
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: VibeWhisperMetrics.radiusM,
                                    style: .continuous
                                )
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            }
                            .accessibilityLabel(L10n.text("Samples"))

                        Button(L10n.text("Generate")) {
                            analyzeSamples()
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            sourceSamples
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    }
                    .padding(.top, VibeWhisperMetrics.space10)
                } label: {
                    Label(L10n.text("Samples"), systemImage: "doc.text.magnifyingglass")
                        .font(VibeWhisperTypography.body(.semibold))
                }
            }

            HStack(spacing: VibeWhisperMetrics.space10) {
                if !isBuiltIn {
                    Button(L10n.text("Save")) {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(accent)
                    .disabled(!canSave)
                }

                Button(L10n.text("Export…")) {
                    exportSelected()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(selectedCapsule == nil || !localAssetAccessEnabled)

                if let selectedCapsule, !selectedCapsule.isBuiltIn {
                    Button(L10n.text("Delete"), role: .destructive) {
                        deleteSelected()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Spacer(minLength: 0)

                if let selectedCapsule,
                   config.styleCapsules.defaultCapsuleID != selectedCapsule.id
                {
                    Button {
                        config.styleCapsules.defaultCapsuleID = selectedCapsule.id
                    } label: {
                        Label(L10n.text("Default Style"), systemImage: "star")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
        .padding(VibeWhisperMetrics.space20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusXXL,
                style: .continuous
            )
            .fill(Color(nsColor: VibeWhisperPalette.elevatedSurface))
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusXXL,
                style: .continuous
            )
            .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 6)
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
        editingSummary = capsule.summary
        approvedExample = capsule.examples.first ?? ""
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

struct TerminologyPackSettingsView:
    View
{
    @Binding var config: AppConfig

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(
                    L10n.text(
                        "Domain Packs"
                    )
                )
                .font(
                    .system(
                        size: 12,
                        weight: .semibold
                    )
                )
            }

            ForEach(
                TerminologyPackRegistry
                    .builtIn
            ) { pack in
                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    HStack {
                        Toggle(
                            pack.localizedName,
                            isOn: Binding(
                                get: {
                                    config
                                        .terminologyPacks
                                        .isEnabled(
                                            pack.id
                                        )
                                },
                                set: {
                                    enabled in
                                    config
                                        .terminologyPacks
                                        .setEnabled(
                                            enabled,
                                            packID:
                                                pack.id
                                        )
                                }
                            )
                        )
                        .font(
                            .system(
                                size: 11,
                                weight:
                                    .semibold
                            )
                        )
                        Spacer()
                        Text(pack.risk.localizedLabel)
                        .font(
                            .system(
                                size: 9,
                                weight:
                                    .semibold
                            )
                        )
                        .foregroundStyle(
                            pack.risk == .high
                                ? .orange
                                : .secondary
                        )
                        Text(
                            L10n.format(
                                "%ld terms",
                                pack.entries
                                    .count
                            )
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    let conflicts =
                        TerminologyPackResolver()
                            .conflicts(
                                personalEntries:
                                    config
                                        .transcription
                                        .terminology
                                        .entries,
                                pack: pack
                            )
                    if !conflicts.isEmpty {
                        DisclosureGroup(
                            L10n.format(
                                "%ld conflicts — personal entries win",
                                conflicts.count
                            )
                        ) {
                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                ForEach(
                                    conflicts
                                ) { conflict in
                                    Text(
                                        "• \(conflict.term)"
                                    )
                                    .font(
                                        .system(
                                            size: 10
                                        )
                                    )
                                }
                            }
                            .padding(.top, 4)
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    }

                    if pack.risk == .high {
                        Label(
                            L10n.text(
                                "High-risk terminology always enters Preview and requires professional review."
                            ),
                            systemImage:
                                "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
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
            "Import VibeWhisper Skill"
        )
        panel.message = L10n.text(
            "Choose a standard Agent Skills directory containing SKILL.md, or a legacy .vibewhisperskill v1 directory. Every file is scanned before it is copied into VibeWhisper's private Skills directory."
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
                    "New required Context: %@. VibeWhisper will ask again before use.",
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
