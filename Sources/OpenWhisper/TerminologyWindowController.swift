import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum TerminologyManagerFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case terms = "Terms"
    case corrections = "Corrections"
    case disabled = "Disabled"

    var id: String { rawValue }
}

private enum TerminologyManagerSort: String, CaseIterable, Identifiable {
    case alphabetical = "A–Z"
    case type = "Type"
    case newest = "Newest"

    var id: String { rawValue }
}

private struct TerminologyEditorDraft: Equatable {
    let id: UUID?
    var type: TerminologyEntryType
    var original: String
    var replacement: String
    var aliases: String
    var isEnabled: Bool

    init(entry: TerminologyEntry) {
        id = entry.id
        type = entry.type
        original = entry.original
        replacement = entry.replacement ?? ""
        aliases = entry.aliases.joined(separator: ", ")
        isEnabled = entry.isEnabled
    }

    static let empty = TerminologyEditorDraft(
        id: nil,
        type: .term,
        original: "",
        replacement: "",
        aliases: "",
        isEnabled: true
    )

    private init(
        id: UUID?,
        type: TerminologyEntryType,
        original: String,
        replacement: String,
        aliases: String,
        isEnabled: Bool
    ) {
        self.id = id
        self.type = type
        self.original = original
        self.replacement = replacement
        self.aliases = aliases
        self.isEnabled = isEnabled
    }
}

@MainActor
final class TerminologyWindowController: NSWindowController {
    init(
        config: AppConfig,
        onSave: @escaping (AppConfig) -> Result<Void, any Error>
    ) {
        let view = TerminologyManagerView(initialConfig: config, onSave: onSave)
        let hostingController = NSHostingController(rootView: view)
        let window = TerminologyCommandClosingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("OpenWhisper Terminology")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("OpenWhisper.TerminologyWindow")
        window.minSize = NSSize(width: 760, height: 500)
        window.tabbingMode = .disallowed
        let restored = window.setFrameUsingName("OpenWhisper.TerminologyWindow")
        window.setFrameAutosaveName("OpenWhisper.TerminologyWindow")
        if !restored {
            window.center()
        }
        window.contentViewController = hostingController

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func writeSnapshot(to url: URL) throws {
        try ProductSurfaceSnapshot.write(window: window, to: url)
    }
}

private final class TerminologyCommandClosingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandW = event.type == .keyDown
            && modifiers.contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "w"
        if isCommandW {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct TerminologyManagerView: View {
    @State private var config: AppConfig
    @State private var query = ""
    @State private var filter: TerminologyManagerFilter = .all
    @State private var sort: TerminologyManagerSort = .alphabetical
    @State private var selectedEntryID: UUID?
    @State private var draft: TerminologyEditorDraft?
    @State private var pendingImport: TerminologyImportPreview?
    @State private var pendingDeletionID: UUID?
    @State private var message: String?
    @State private var messageIsError = false

    let onSave: (AppConfig) -> Result<Void, any Error>

    init(
        initialConfig: AppConfig,
        onSave: @escaping (AppConfig) -> Result<Void, any Error>
    ) {
        _config = State(initialValue: initialConfig)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            NavigationSplitView {
                entryList
                    .navigationSplitViewColumnWidth(min: 310, ideal: 360, max: 430)
            } detail: {
                editorDetail
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .onChange(of: selectedEntryID) { id in
            guard let id,
                  let entry = config.transcription.terminology.entries.first(where: { $0.id == id })
            else {
                if draft?.id != nil {
                    draft = nil
                }
                return
            }
            draft = TerminologyEditorDraft(entry: entry)
        }
        .sheet(item: $pendingImport) { preview in
            TerminologyImportPreviewView(
                preview: preview,
                onCancel: {
                    pendingImport = nil
                },
                onMerge: {
                    applyImport(preview)
                }
            )
        }
        .alert(
            L10n.text("Delete this terminology entry?"),
            isPresented: Binding(
                get: { pendingDeletionID != nil },
                set: { if !$0 { pendingDeletionID = nil } }
            )
        ) {
            Button(L10n.text("Cancel"), role: .cancel) {
                pendingDeletionID = nil
            }
            Button(L10n.text("Delete"), role: .destructive) {
                deletePendingEntry()
            }
        } message: {
            Text(L10n.text("The entry will stop influencing future dictations."))
        }
    }

    private var toolbar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(L10n.text("Terminology enabled"))
                    .font(.system(size: 12, weight: .medium))
                Toggle(
                    L10n.text("Terminology enabled"),
                    isOn: Binding(
                        get: { config.transcription.terminology.enabled },
                        set: { value in
                            setTerminologyEnabled(value)
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)

                TextField(L10n.text("Search terminology"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, maxWidth: .infinity)

                Button {
                    selectedEntryID = nil
                    draft = .empty
                } label: {
                    Label(L10n.text("Add Entry"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                Picker(L10n.text("Filter"), selection: $filter) {
                    ForEach(TerminologyManagerFilter.allCases) { filter in
                        Text(L10n.text(filter.rawValue)).tag(filter)
                    }
                }
                .frame(width: 160)

                Picker(L10n.text("Sort"), selection: $sort) {
                    ForEach(TerminologyManagerSort.allCases) { sort in
                        Text(L10n.text(sort.rawValue)).tag(sort)
                    }
                }
                .frame(width: 140)

                Spacer()

                Menu {
                    Button(L10n.text("Import Dictionary…"), action: chooseImport)
                    Button(L10n.text("Export Dictionary…"), action: exportDictionary)
                        .disabled(config.transcription.terminology.entries.isEmpty)
                } label: {
                    Label(L10n.text("Import / Export"), systemImage: "square.and.arrow.down")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var entryList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(
                    L10n.format(
                        "%ld matching entries",
                        filteredEntries.count
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Spacer()
                Text(
                    L10n.format(
                        "%ld total entries",
                        config.transcription.terminology.entries.count
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(filteredEntries, selection: $selectedEntryID) { entry in
                entryRow(entry)
                    .tag(entry.id)
                    .contextMenu {
                        Button(L10n.text("Edit")) {
                            selectedEntryID = entry.id
                        }
                        Button(
                            L10n.text(entry.isEnabled ? "Disable" : "Enable")
                        ) {
                            setEnabled(!entry.isEnabled, for: entry.id)
                        }
                        Divider()
                        Button(L10n.text("Delete"), role: .destructive) {
                            pendingDeletionID = entry.id
                        }
                    }
            }
            .listStyle(.sidebar)
            .overlay {
                if filteredEntries.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 27))
                            .foregroundStyle(.secondary)
                        Text(L10n.text("No matching terminology"))
                            .font(.system(size: 14, weight: .semibold))
                        Text(L10n.text("Add a term, import a dictionary, or change the search and filters."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 250)
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: TerminologyEntry) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(
                systemName: entry.type == .correction
                    ? "arrow.left.arrow.right"
                    : "textformat"
            )
            .foregroundStyle(
                entry.type == .correction ? Color.orange : Color.accentColor
            )
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    entry.type == .correction
                        ? "\(entry.original) → \(entry.replacement ?? "")"
                        : entry.original
                )
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

                HStack(spacing: 6) {
                    Text(L10n.text(entry.type == .correction ? "Correction" : "Term"))
                    Text("•")
                    Text(entry.source)
                    if !entry.aliases.isEmpty {
                        Text("•")
                        Text(L10n.format("%ld aliases", entry.aliases.count))
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Image(systemName: entry.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                .foregroundStyle(entry.isEnabled ? .green : .secondary)
                .accessibilityLabel(L10n.text(entry.isEnabled ? "enabled" : "disabled"))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var editorDetail: some View {
        if let draftBinding = Binding($draft) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(
                        L10n.text(
                            draftBinding.wrappedValue.id == nil ? "Add Entry" : "Edit Entry"
                        )
                    )
                    .font(.system(size: 24, weight: .semibold))

                    Form {
                        Picker(
                            L10n.text("Type"),
                            selection: draftBinding.type
                        ) {
                            Text(L10n.text("Term")).tag(TerminologyEntryType.term)
                            Text(L10n.text("Correction")).tag(TerminologyEntryType.correction)
                        }
                        .pickerStyle(.segmented)

                        TextField(
                            L10n.text(
                                draftBinding.wrappedValue.type == .correction
                                    ? "Wrong text"
                                    : "Term"
                            ),
                            text: draftBinding.original
                        )

                        if draftBinding.wrappedValue.type == .correction {
                            TextField(
                                L10n.text("Correct text"),
                                text: draftBinding.replacement
                            )
                        }

                        TextField(
                            L10n.text("Aliases separated by commas"),
                            text: draftBinding.aliases
                        )

                        Toggle(
                            L10n.text("Enabled"),
                            isOn: draftBinding.isEnabled
                        )
                    }
                    .formStyle(.grouped)

                    if let message {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(messageIsError ? .red : .secondary)
                    }

                    HStack {
                        if draftBinding.wrappedValue.id != nil {
                            Button(L10n.text("Delete"), role: .destructive) {
                                pendingDeletionID = draftBinding.wrappedValue.id
                            }
                        }
                        Spacer()
                        Button(L10n.text("Cancel")) {
                            selectedEntryID = nil
                            draft = nil
                        }
                        Button(L10n.text("Save Entry")) {
                            saveDraft(draftBinding.wrappedValue)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave(draftBinding.wrappedValue))
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text(L10n.text("Select or add an entry"))
                    .font(.system(size: 17, weight: .semibold))
                Text(L10n.text("Terms guide recognition. Corrections replace predictable mistakes after transcription."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .padding(30)
        }
    }

    private var filteredEntries: [TerminologyEntry] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let filtered = config.transcription.terminology.entries
            .filter { entry in
                switch filter {
                case .all:
                    return true
                case .terms:
                    return entry.type == .term
                case .corrections:
                    return entry.type == .correction
                case .disabled:
                    return !entry.isEnabled
                }
            }
            .filter { entry in
                guard !normalizedQuery.isEmpty else {
                    return true
                }
                return [
                    entry.original,
                    entry.replacement ?? "",
                    entry.aliases.joined(separator: " "),
                    entry.source,
                ]
                .joined(separator: " ")
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                .contains(normalizedQuery)
            }

        switch sort {
        case .alphabetical:
            return filtered.sorted {
                $0.original.localizedStandardCompare($1.original) == .orderedAscending
            }
        case .type:
            return filtered.sorted {
                if $0.type != $1.type {
                    return $0.type.rawValue < $1.type.rawValue
                }
                return $0.original.localizedStandardCompare($1.original) == .orderedAscending
            }
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = config.transcription.terminology.entries.firstIndex(where: {
            $0.id == id
        }) else {
            return
        }
        let previousConfig = config
        config.transcription.terminology.entries[index].isEnabled = enabled
        if !persist() {
            config = previousConfig
        }
    }

    private func setTerminologyEnabled(_ enabled: Bool) {
        let previousConfig = config
        config.transcription.terminology.enabled = enabled
        if !persist() {
            config = previousConfig
        }
    }

    private func canSave(_ draft: TerminologyEditorDraft) -> Bool {
        let original = draft.original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, original.count <= 240 else {
            return false
        }
        if draft.type == .correction {
            let replacement = draft.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
            return !replacement.isEmpty && replacement.count <= 240
        }
        return true
    }

    private func saveDraft(_ draft: TerminologyEditorDraft) {
        let original = draft.original.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = draft.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = draft.aliases
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 240 }

        let candidate = TerminologyEntry(
            id: draft.id ?? UUID(),
            type: draft.type,
            original: original,
            replacement: draft.type == .correction ? replacement : nil,
            aliases: aliases,
            isEnabled: draft.isEnabled,
            source: draft.id == nil ? "user" : existingEntry(id: draft.id)?.source ?? "user",
            usageCount: existingEntry(id: draft.id)?.usageCount ?? 0,
            createdAt: existingEntry(id: draft.id)?.createdAt
                ?? ISO8601DateFormatter().string(from: Date())
        )

        let duplicate = config.transcription.terminology.entries.first {
            $0.id != candidate.id
                && TerminologyLibrary.key(for: $0) == TerminologyLibrary.key(for: candidate)
        }
        guard duplicate == nil else {
            message = L10n.text("An equivalent terminology entry already exists.")
            messageIsError = true
            return
        }

        let previousConfig = config
        if let index = config.transcription.terminology.entries.firstIndex(where: {
            $0.id == candidate.id
        }) {
            config.transcription.terminology.entries[index] = candidate
        } else {
            config.transcription.terminology.entries.append(candidate)
        }
        config.transcription.terminology.enabled = true

        if persist() {
            selectedEntryID = candidate.id
            self.draft = TerminologyEditorDraft(entry: candidate)
            message = L10n.text("Terminology entry saved.")
            messageIsError = false
        } else {
            config = previousConfig
        }
    }

    private func existingEntry(id: UUID?) -> TerminologyEntry? {
        guard let id else {
            return nil
        }
        return config.transcription.terminology.entries.first { $0.id == id }
    }

    private func deletePendingEntry() {
        guard let id = pendingDeletionID else {
            return
        }
        pendingDeletionID = nil
        let previousConfig = config
        config.transcription.terminology.entries.removeAll { $0.id == id }
        if persist() {
            if selectedEntryID == id {
                selectedEntryID = nil
                draft = nil
            }
            message = L10n.text("Terminology entry deleted.")
            messageIsError = false
        } else {
            config = previousConfig
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]
        panel.message = L10n.text("Choose a plain text or CSV terminology dictionary.")

        guard panel.runModal() == .OK, let fileURL = panel.url else {
            return
        }

        do {
            let result = try TerminologyTextImporter().importEntries(from: fileURL)
            pendingImport = TerminologyLibrary.importPreview(
                existing: config.transcription.terminology.entries,
                result: result
            )
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func applyImport(_ preview: TerminologyImportPreview) {
        let previousConfig = config
        config.transcription.terminology.entries = TerminologyLibrary.merge(
            existing: config.transcription.terminology.entries,
            incoming: preview.result.entries
        )
        config.transcription.terminology.enabled = true
        config.transcription.terminology.lastImportedSource = preview.result.source
        config.transcription.terminology.lastImportedAt = preview.result.importedAt
        if persist() {
            pendingImport = nil
            message = L10n.format(
                "Imported %ld new entries; skipped %ld duplicates and %ld conflicts.",
                preview.newEntries.count,
                preview.duplicateEntries.count,
                preview.conflictingEntries.count
            )
            messageIsError = false
        } else {
            config = previousConfig
        }
    }

    private func exportDictionary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "OpenWhisper-Terminology.csv"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try TerminologyLibrary.csvData(
                entries: config.transcription.terminology.entries
            ).write(to: url, options: [.atomic])
            message = L10n.text("Terminology dictionary exported.")
            messageIsError = false
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    @discardableResult
    private func persist() -> Bool {
        switch onSave(config) {
        case .success:
            return true
        case .failure(let error):
            message = error.localizedDescription
            messageIsError = true
            return false
        }
    }
}

private struct TerminologyImportPreviewView: View {
    let preview: TerminologyImportPreview
    let onCancel: () -> Void
    let onMerge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("Import terminology preview"))
                .font(.system(size: 20, weight: .semibold))
            Text(
                L10n.format(
                    "%ld entries found: %ld new, %ld duplicates, and %ld conflicts.",
                    preview.importedCount,
                    preview.newEntries.count,
                    preview.duplicateEntries.count,
                    preview.conflictingEntries.count
                )
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            List(Array(preview.newEntries.prefix(30))) { entry in
                HStack {
                    Text(L10n.text(entry.type == .correction ? "Correction" : "Term"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            entry.type == .correction ? Color.orange : Color.accentColor
                        )
                        .frame(width: 78, alignment: .leading)
                    Text(
                        entry.type == .correction
                            ? "\(entry.original) → \(entry.replacement ?? "")"
                            : entry.original
                    )
                    .font(.system(size: 12))
                }
            }
            .frame(minHeight: 220)

            if preview.newEntries.count > 30 {
                Text(
                    L10n.format(
                        "Showing the first 30 of %ld new entries.",
                        preview.newEntries.count
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            if !preview.conflictingEntries.isEmpty {
                Label(
                    L10n.text(
                        "Conflicts share the same term or wrong text with an existing entry and will be skipped."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button(L10n.text("Cancel"), action: onCancel)
                Button(L10n.text("Merge New Entries"), action: onMerge)
                    .buttonStyle(.borderedProminent)
                    .disabled(preview.newEntries.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 580, height: 420)
    }
}
