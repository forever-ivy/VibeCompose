import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StyleCapsuleSettingsView:
    View
{
    @Binding var config: AppConfig
    let registry: SkillRegistry
    let store: StyleCapsuleStore
    let localAssetAccessEnabled: Bool

    @State private var capsules:
        [StyleCapsule] =
            StyleCapsuleRegistry.builtIn
    @State private var selectedID: String?
    @State private var editingName = ""
    @State private var editingSummary = ""
    @State private var approvedExample = ""
    @State private var sourceSamples = ""
    @State private var message: String?
    @State private var messageIsError =
        false

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        L10n.text(
                            "Style Capsules"
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
                Toggle(
                    L10n.text("Enabled"),
                    isOn:
                        $config.styleCapsules
                            .enabled
                )
                .toggleStyle(.switch)
            }

            LabeledContent(
                L10n.text(
                    "Default Capsule"
                )
            ) {
                Picker(
                    L10n.text(
                        "Default Capsule"
                    ),
                    selection:
                        $config.styleCapsules
                            .defaultCapsuleID
                ) {
                    Text(
                        L10n.text("None")
                    )
                    .tag(String?.none)
                    ForEach(capsules) {
                        capsule in
                        Text(
                            L10n.text(
                                capsule.name
                            )
                        )
                        .tag(
                            Optional(capsule.id)
                        )
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }
            .disabled(
                !config.styleCapsules
                    .enabled
            )

            if !styleAwareSkills.isEmpty {
                DisclosureGroup(
                    L10n.text(
                        "Per-Skill Style"
                    )
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(
                            styleAwareSkills
                        ) { skill in
                            HStack {
                                Text(
                                    skill.localizedName
                                )
                                .font(
                                    .system(
                                        size: 11,
                                        weight:
                                            .medium
                                    )
                                )
                                Spacer()
                                Picker(
                                    skill.localizedName,
                                    selection:
                                        Binding<
                                            String?
                                        >(
                                            get: {
                                                config
                                                    .styleCapsules
                                                    .assignedCapsuleID(
                                                        for:
                                                            skill.id
                                                    )
                                            },
                                            set: {
                                                value in
                                                config
                                                    .styleCapsules
                                                    .setCapsuleID(
                                                        value,
                                                        for:
                                                            skill.id
                                                    )
                                            }
                                        )
                                ) {
                                    Text(
                                        L10n.text(
                                            "Use Default"
                                        )
                                    )
                                    .tag(String?.none)
                                    ForEach(
                                        capsules
                                    ) { capsule in
                                        Text(
                                            L10n.text(
                                                capsule
                                                    .name
                                            )
                                        )
                                        .tag(
                                            Optional(
                                                capsule
                                                    .id
                                            )
                                        )
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 210)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .disabled(
                    !config.styleCapsules
                        .enabled
                )
            }

            Divider()

            HStack(
                alignment: .top,
                spacing: 12
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    HStack {
                        Text(
                            L10n.text(
                                "Capsule Library"
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
                        Button(
                            L10n.text("New")
                        ) {
                            beginNew()
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            !localAssetAccessEnabled
                        )
                    }

                    ScrollView {
                        LazyVStack(
                            spacing: 5
                        ) {
                            ForEach(
                                capsules
                            ) { capsule in
                                Button {
                                    select(capsule)
                                } label: {
                                    HStack {
                                        VStack(
                                            alignment:
                                                .leading,
                                            spacing: 2
                                        ) {
                                            Text(
                                                L10n.text(
                                                    capsule
                                                        .name
                                                )
                                            )
                                            .font(
                                                .system(
                                                    size:
                                                        11,
                                                    weight:
                                                        .medium
                                                )
                                            )
                                            Text(
                                                capsule
                                                    .isBuiltIn
                                                ? L10n
                                                    .text(
                                                        "Built-in"
                                                    )
                                                : L10n
                                                    .text(
                                                        "Custom"
                                                    )
                                            )
                                            .font(
                                                .system(
                                                    size:
                                                        9
                                                )
                                            )
                                            .foregroundStyle(
                                                .secondary
                                            )
                                        }
                                        Spacer()
                                        if
                                            selectedID
                                                == capsule
                                                    .id
                                        {
                                            Image(
                                                systemName:
                                                    "checkmark"
                                            )
                                        }
                                    }
                                    .padding(7)
                                    .background(
                                        selectedID
                                            == capsule
                                                .id
                                        ? Color
                                            .accentColor
                                            .opacity(
                                                0.12
                                            )
                                        : Color(
                                            nsColor:
                                                .textBackgroundColor
                                        )
                                    )
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius:
                                                7
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(
                        width: 180,
                        height: 220
                    )
                }

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    TextField(
                        L10n.text(
                            "Capsule name"
                        ),
                        text: $editingName
                    )
                    .textFieldStyle(
                        .roundedBorder
                    )
                    .disabled(
                        selectedCapsule?
                            .isBuiltIn == true
                    )

                    Text(
                        L10n.text(
                            "Readable style summary"
                        )
                    )
                    .font(
                        .system(
                            size: 10,
                            weight: .medium
                        )
                    )
                    TextEditor(
                        text: $editingSummary
                    )
                    .font(.system(size: 11))
                    .accessibilityLabel(
                        L10n.text(
                            "Readable style summary"
                        )
                    )
                    .frame(
                        minHeight: 82,
                        maxHeight: 110
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: 6
                        )
                        .stroke(
                            Color.secondary
                                .opacity(0.22)
                        )
                    )
                    .disabled(
                        selectedCapsule?
                            .isBuiltIn == true
                    )

                    TextField(
                        L10n.text(
                            "Optional approved example"
                        ),
                        text:
                            $approvedExample
                    )
                    .textFieldStyle(
                        .roundedBorder
                    )
                    .disabled(
                        selectedCapsule?
                            .isBuiltIn == true
                    )

                    DisclosureGroup(
                        L10n.text(
                            "Analyze My Samples Locally"
                        )
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: 6
                        ) {
                            TextEditor(
                                text:
                                    $sourceSamples
                            )
                            .font(
                                .system(
                                    size: 11
                                )
                            )
                            .frame(
                                minHeight: 72
                            )
                            .accessibilityLabel(
                                L10n.text(
                                    "Style source samples"
                                )
                            )
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius:
                                        6
                                )
                                .stroke(
                                    Color
                                        .secondary
                                        .opacity(
                                            0.22
                                        )
                                )
                            )
                            Text(
                                L10n.text(
                                    "Analysis runs on this Mac. After the summary is generated, the source samples are cleared and are not saved."
                                )
                            )
                            .font(
                                .system(
                                    size: 10
                                )
                            )
                            .foregroundStyle(
                                .secondary
                            )
                            Button(
                                L10n.text(
                                    "Generate Summary"
                                )
                            ) {
                                analyzeSamples()
                            }
                            .buttonStyle(
                                .bordered
                            )
                            .disabled(
                                sourceSamples
                                    .trimmingCharacters(
                                        in:
                                            .whitespacesAndNewlines
                                    )
                                    .isEmpty
                                    || selectedCapsule?
                                        .isBuiltIn
                                        == true
                            )
                        }
                        .padding(.top, 6)
                    }

                    HStack {
                        Button(
                            L10n.text("Save")
                        ) {
                            save()
                        }
                        .buttonStyle(
                            .borderedProminent
                        )
                        .disabled(!canSave)

                        Button(
                            L10n.text("Export…")
                        ) {
                            exportSelected()
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            selectedCapsule == nil
                                || !localAssetAccessEnabled
                        )

                        if
                            let selectedCapsule,
                            !selectedCapsule
                                .isBuiltIn
                        {
                            Button(
                                L10n.text(
                                    "Delete"
                                ),
                                role: .destructive
                            ) {
                                deleteSelected()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .topLeading
                )
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
            reload()
            if selectedID == nil,
               let first = capsules.first
            {
                select(first)
            }
        }
    }

    private var selectedCapsule:
        StyleCapsule?
    {
        capsules.first {
            $0.id == selectedID
        }
    }

    private var styleAwareSkills:
        [SkillDefinition]
    {
        registry.orderedDefinitions
            .filter {
                $0.allCapabilities
                    .contains(
                        .styleCapsule
                    )
            }
    }

    private var canSave: Bool {
        localAssetAccessEnabled
            && selectedCapsule?
                .isBuiltIn != true
            && !editingName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            && !editingSummary
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
    }

    private func reload() {
        guard localAssetAccessEnabled
        else {
            capsules =
                StyleCapsuleRegistry.builtIn
            return
        }
        do {
            capsules = try store.loadAll()
            message = nil
            messageIsError = false
        } catch {
            capsules =
                StyleCapsuleRegistry.builtIn
            message =
                error.localizedDescription
            messageIsError = true
        }
    }

    private func select(
        _ capsule: StyleCapsule
    ) {
        selectedID = capsule.id
        editingName =
            L10n.text(capsule.name)
        editingSummary =
            capsule.summary
        approvedExample =
            capsule.examples.first
            ?? ""
        sourceSamples = ""
    }

    private func beginNew() {
        selectedID = nil
        editingName = ""
        editingSummary = ""
        approvedExample = ""
        sourceSamples = ""
        message = L10n.text(
            "Paste only text you own or are authorized to use."
        )
        messageIsError = false
    }

    private func analyzeSamples() {
        let summary =
            StyleCapsuleAnalyzer
                .summarize(
                    samples:
                        sourceSamples
                )
        guard !summary.isEmpty else {
            return
        }
        editingSummary = summary
        sourceSamples = ""
        message = L10n.text(
            "Style summary generated locally. Source samples were cleared and not saved."
        )
        messageIsError = false
    }

    private func save() {
        let now =
            ISO8601DateFormatter()
                .string(from: Date())
        let existing =
            selectedCapsule
        let id =
            existing?.id
            ?? "user.\(UUID().uuidString.lowercased())"
        let capsule = StyleCapsule(
            id: id,
            name: editingName,
            summary: editingSummary,
            examples:
                approvedExample
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ).isEmpty
                ? []
                : [approvedExample],
            createdAt:
                existing?.createdAt
                ?? now,
            updatedAt: now,
            isBuiltIn: false
        )
        do {
            try store.save(capsule)
            reload()
            if
                let refreshed =
                    capsules.first(
                        where: {
                            $0.id
                                == capsule.id
                        }
                    )
            {
                select(refreshed)
            }
            message = L10n.text(
                "Style Capsule saved locally."
            )
            messageIsError = false
        } catch {
            message =
                error.localizedDescription
            messageIsError = true
        }
    }

    private func deleteSelected() {
        guard
            let selectedCapsule,
            !selectedCapsule.isBuiltIn
        else {
            return
        }
        do {
            try store.delete(
                id: selectedCapsule.id
            )
            if
                config.styleCapsules
                    .defaultCapsuleID
                    == selectedCapsule.id
            {
                config.styleCapsules
                    .defaultCapsuleID = nil
            }
            config.styleCapsules
                .skillAssignments
                .removeAll {
                    $0.capsuleID
                        == selectedCapsule.id
                }
            reload()
            if let first = capsules.first {
                select(first)
            } else {
                beginNew()
            }
            message = L10n.text(
                "Style Capsule deleted."
            )
            messageIsError = false
        } catch {
            message =
                error.localizedDescription
            messageIsError = true
        }
    }

    private func exportSelected() {
        guard let selectedCapsule else {
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            selectedCapsule.id + ".json"
        panel.title = L10n.text(
            "Export Style Capsule"
        )
        panel.prompt = L10n.text("Export")
        guard
            panel.runModal() == .OK,
            let url = panel.url
        else {
            return
        }
        do {
            try store.export(
                selectedCapsule,
                to: url
            )
            message = L10n.format(
                "Exported %@.",
                url.lastPathComponent
            )
            messageIsError = false
        } catch {
            message =
                error.localizedDescription
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
            "Import OpenWhisper Skill"
        )
        panel.message = L10n.text(
            "Choose a standard Agent Skills directory containing SKILL.md, or a legacy .openwhisperskill v1 directory. Every file is scanned before it is copied into OpenWhisper's private Skills directory."
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
                    "New required Context: %@. OpenWhisper will ask again before use.",
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
