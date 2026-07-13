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
                    Text(
                        L10n.text(
                            "A Capsule is an editable writing-style description, never a fact source. OpenWhisper does not scan mail, messages, or documents to create one."
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
                Text(
                    L10n.text(
                        "Domain Packs add deterministic spelling guidance. Personal corrections win over Skill terms, personal terms, and Domain Packs."
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
                        Text(
                            L10n.text(
                                pack.risk
                                    .rawValue
                                    .capitalized
                            )
                        )
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
    @Binding var config: AppConfig
    @Binding var inventory:
        CommunitySkillInventory
    let store: SkillPackageStore
    let localAssetAccessEnabled: Bool

    @State private var selectedPackageID:
        String?
    @State private var message: String?
    @State private var messageIsError =
        false
    @State private var goldenTestMessage:
        String?

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
                            "Local Community Skills"
                        )
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold
                        )
                    )
                    Text(
                        L10n.text(
                            "Community Skill v1 is declarative only: no Swift, JavaScript, Python, Shell, dynamic libraries, processes, custom network requests, Keychain access, or external actions."
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
                )
            }

            if activePackages.isEmpty {
                Text(
                    L10n.text(
                        "No community Skills installed. Built-in Skills remain available."
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(
                        activePackages
                    ) { package in
                        communitySkillRow(
                            package
                        )
                    }
                }
            }

            if let selectedPackage {
                DisclosureGroup(
                    L10n.text(
                        "Skill Inspector"
                    ),
                    isExpanded: .constant(true)
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

    private var selectedPackage:
        CommunitySkillPackage?
    {
        if let selectedPackageID {
            return inventory.packages
                .first {
                    $0.id
                        == selectedPackageID
                }
        }
        return activePackages.first
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
        HStack(spacing: 9) {
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
            .frame(width: 105)

            Button(
                L10n.text("Inspect")
            ) {
                selectedPackageID =
                    package.id
            }
            .buttonStyle(.bordered)

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
    private func inspector(
        _ package:
            CommunitySkillPackage
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 6
        ) {
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
            Text(
                L10n.text(
                    "Runtime order: fixed OpenWhisper safety shell → output contract → untrusted Skill prompt → optional Style Capsule → terminology → authorized context → transcript. The package cannot move ahead of the safety shell."
                )
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

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
            "Choose a local .openwhisperskill directory. OpenWhisper validates every file before copying it into its private Skills directory."
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
            guard
                review(inspected)
            else {
                return
            }
            let installed =
                try store.install(
                    from: url
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
                    true,
                    skillID:
                        installed.definition
                            .id
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
            message =
                error.localizedDescription
            messageIsError = true
            NSSound.beep()
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
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.format(
            "Install %@ %@?",
            package.definition.name,
            package.definition.version
        )
        let capabilities =
            (
                package.definition
                    .requiredCapabilities
                + package.definition
                    .optionalCapabilities
            )
            .map(\.rawValue)
            .joined(separator: ", ")
        alert.informativeText =
            """
            \(L10n.text("Author")): \(package.definition.author)
            \(L10n.text("Permissions")): \(capabilities)
            \(L10n.text("Output")): \(package.definition.output.format.rawValue) / \(package.definition.output.delivery.rawValue) / \(package.definition.output.risk.rawValue)
            \(L10n.text("Files")): \(package.relativeFiles.count)
            SHA-256: \(package.contentSHA256)

            \(L10n.text("This package is declarative and cannot execute code, start processes, read arbitrary files or Keychain, make custom network requests, change providers, bypass sensitive-app policy, or perform external actions."))
            """
        alert.addButton(
            withTitle:
                L10n.text("Install")
        )
        alert.addButton(
            withTitle:
                L10n.text("Cancel")
        )
        NSApplication.shared.activate(
            ignoringOtherApps: true
        )
        return alert.runModal()
            == .alertFirstButtonReturn
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
}
