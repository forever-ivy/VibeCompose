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
        let view = TerminologyManagerView(
            initialConfig: config,
            onSave: onSave
        )
        .applyingVibeWhisperBrandTint()
        .applyingAccessibilityDisplayOptionsOverride(
            .currentVisualAcceptance
        )
        let hostingController = NSHostingController(rootView: view)
        let window = TerminologyCommandClosingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("VibeWhisper Terminology")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("VibeWhisper.TerminologyWindow")
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.minSize = NSSize(width: 760, height: 500)
        window.tabbingMode = .disallowed
        let restored = window.setFrameUsingName("VibeWhisper.TerminologyWindow")
        window.setFrameAutosaveName("VibeWhisper.TerminologyWindow")
        if !restored {
            window.center()
        }
        window.contentViewController = hostingController
        AccessibilityDisplayOptionsOverride.currentVisualAcceptance
            .applyAppearance(to: window)

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else {
            return
        }
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
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

private struct TerminologyToolbarView: View {
    @Binding var query: String
    @Binding var isEnabled: Bool
    @Binding var filter: TerminologyManagerFilter
    @Binding var sort: TerminologyManagerSort
    /// Embedded mode moves the enable toggle and Add button into the pane
    /// header, so the secondary row only carries search and filtering.
    var showsControls: Bool = true
    let canExport: Bool
    let onAdd: () -> Void
    let onImport: () -> Void
    let onExport: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularLayout
            compactLayout
        }
        .controlSize(.small)
        .openWhisperToolbar()
    }

    private var regularLayout: some View {
        VStack(spacing: VibeWhisperMetrics.space10) {
            HStack(spacing: VibeWhisperMetrics.space12) {
                searchField
                    .frame(minWidth: 190, maxWidth: .infinity)
                if showsControls {
                    enabledToggle
                    addButton
                }
            }

            HStack(spacing: VibeWhisperMetrics.space10) {
                filterPicker
                Spacer(minLength: 0)
                sortMenu
                importExportMenu
            }
        }
    }

    private var compactLayout: some View {
        VStack(spacing: VibeWhisperMetrics.space10) {
            searchField
                .frame(maxWidth: .infinity)
            if showsControls {
                HStack(spacing: VibeWhisperMetrics.space10) {
                    enabledToggle
                    Spacer(minLength: 0)
                    addButton
                }
            }
            HStack(spacing: VibeWhisperMetrics.space10) {
                filterPicker
                    .frame(maxWidth: .infinity)
                sortMenu
                importExportMenu
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                L10n.text("Search"),
                text: $query,
                prompt: Text(L10n.text("Search"))
            )
            .textFieldStyle(.plain)
        }
        .openWhisperSearchField()
    }

    private var enabledToggle: some View {
        Toggle(L10n.text("Enabled"), isOn: $isEnabled)
            .toggleStyle(.switch)
            .fixedSize()
    }

    /// Primary filter as App Store-style segmented control.
    private var filterPicker: some View {
        Picker(L10n.text("Filter"), selection: $filter) {
            ForEach(TerminologyManagerFilter.allCases) { filter in
                Text(L10n.text(filter.rawValue)).tag(filter)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
    }

    /// Sort collapses into a menu so the toolbar never truncates at min width.
    private var sortMenu: some View {
        Menu {
            Picker(L10n.text("Sort"), selection: $sort) {
                ForEach(TerminologyManagerSort.allCases) { sort in
                    Text(L10n.text(sort.rawValue)).tag(sort)
                }
            }
        } label: {
            Label(L10n.text(sort.rawValue), systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.text("Sort"))
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Label(L10n.text("Add"), systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
    }

    private var importExportMenu: some View {
        Menu {
            Button(L10n.text("Import…"), action: onImport)
            Button(L10n.text("Export…"), action: onExport)
                .disabled(!canExport)
        } label: {
            Label(
                L10n.text("Import / Export"),
                systemImage: "square.and.arrow.up"
            )
        }
        .help(L10n.text("Import / Export"))
    }
}

struct TerminologyManagerView: View {
    @State private var config: AppConfig
    @State private var query = ""
    @State private var filter: TerminologyManagerFilter = .all
    @State private var sort: TerminologyManagerSort = .alphabetical
    @State private var filteredEntries: [TerminologyEntry]
    @State private var selectedEntryID: UUID?
    @State private var draft: TerminologyEditorDraft?
    @State private var pendingImport: TerminologyImportPreview?
    @State private var pendingDeletionID: UUID?
    @State private var message: String?
    @State private var messageIsError = false

    let onSave: (AppConfig) -> Result<Void, any Error>
    let isEmbedded: Bool

    init(
        initialConfig: AppConfig,
        isEmbedded: Bool = false,
        onSave: @escaping (AppConfig) -> Result<Void, any Error>
    ) {
        _config = State(initialValue: initialConfig)
        _filteredEntries = State(
            initialValue: Self.makeFilteredEntries(
                entries: initialConfig.transcription.terminology.entries,
                query: "",
                filter: .all,
                sort: .alphabetical
            )
        )
        self.isEmbedded = isEmbedded
        self.onSave = onSave
    }

    private var terminologyEnabledBinding: Binding<Bool> {
        Binding(
            get: { config.transcription.terminology.enabled },
            set: { value in
                setTerminologyEnabled(value)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if isEmbedded {
                VibeWhisperPaneHeader(title: L10n.text("Terminology")) {
                    Toggle(
                        L10n.text("Enabled"),
                        isOn: terminologyEnabledBinding
                    )
                    .toggleStyle(.switch)
                    .fixedSize()
                    addEntryButton
                        .controlSize(.large)
                }
            }
            toolbar
            Divider().opacity(0.45)

            HStack(spacing: 0) {
                entryList
                    .frame(width: 320)
                Divider().opacity(0.45)
                editorDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
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
        .onChange(of: config.transcription.terminology.entries) { _ in
            refreshFilteredEntries()
        }
        .onChange(of: query) { _ in
            refreshFilteredEntries()
        }
        .onChange(of: filter) { _ in
            refreshFilteredEntries()
        }
        .onChange(of: sort) { _ in
            refreshFilteredEntries()
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
        TerminologyToolbarView(
            query: $query,
            isEnabled: terminologyEnabledBinding,
            filter: $filter,
            sort: $sort,
            showsControls: !isEmbedded,
            canExport: !config.transcription.terminology.entries.isEmpty,
            onAdd: addEntry,
            onImport: chooseImport,
            onExport: exportDictionary
        )
    }

    private func addEntry() {
        selectedEntryID = nil
        draft = .empty
    }

    private var addEntryButton: some View {
        Button(action: addEntry) {
            Label(L10n.text("Add"), systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
    }

    private var entryList: some View {
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
        .listStyle(.inset)
        .listRowSeparator(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !filteredEntries.isEmpty {
                Text(listCountLabel)
                    .font(VibeWhisperTypography.caption())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
        }
        .overlay {
            if filteredEntries.isEmpty {
                VibeWhisperEmptyState(
                    systemImage: "text.book.closed",
                    title: L10n.text("No matching terminology"),
                    detail: L10n.text(
                        "Add a term, import a dictionary, or change the search and filters."
                    )
                )
            }
        }
    }

    private var listCountLabel: String {
        let matching = filteredEntries.count
        let total = config.transcription.terminology.entries.count
        if matching == total {
            return L10n.format("%ld entries", total)
        }
        return L10n.format("%ld of %ld", matching, total)
    }

    private func entryRow(_ entry: TerminologyEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(
                systemName: entry.type == .correction
                    ? "arrow.left.arrow.right"
                    : "textformat"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(nsColor: VibeWhisperPalette.brandBlue))
            .frame(width: 32, height: 32)
            .background(
                Color(nsColor: VibeWhisperPalette.brandBlue).opacity(0.09),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(
                    entry.type == .correction
                        ? "\(entry.original) → \(entry.replacement ?? "")"
                        : entry.original
                )
                .font(VibeWhisperTypography.callout(.semibold))
                .lineLimit(1)

                Text(entryRowSubtitle(entry))
                    .font(VibeWhisperTypography.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !entry.isEnabled {
                Text(L10n.text("Off"))
                    .font(VibeWhisperTypography.micro(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel(L10n.text("disabled"))
            }
        }
        .padding(.vertical, 6)
        .opacity(entry.isEnabled ? 1 : 0.65)
        .accessibilityElement(children: .combine)
    }

    private func entryRowSubtitle(_ entry: TerminologyEntry) -> String {
        var parts = [
            L10n.text(entry.type == .correction ? "Correction" : "Term"),
        ]
        if !entry.aliases.isEmpty {
            parts.append(L10n.format("%ld other spellings", entry.aliases.count))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var editorDetail: some View {
        // Use a snapshot of draft rather than Binding($draft).
        // Binding($draft) relies on BindingOperations.ForceUnwrapping internally,
        // which crashes when the SwiftUI attribute graph updates the binding
        // on a layout pass after draft has been set to nil by onChange.
        // Passing a stable value snapshot + explicit callbacks avoids the race.
        if let currentDraft = draft {
            TerminologyEditorDetailView(
                draft: currentDraft,
                message: message,
                messageIsError: messageIsError,
                canSave: canSave,
                onDraftChange: { draft = $0 },
                onCancel: {
                    selectedEntryID = nil
                    draft = nil
                },
                onSave: { saveDraft($0) },
                onRequestDelete: { pendingDeletionID = $0 }
            )
        } else {
            VibeWhisperEmptyState(
                systemImage: "text.book.closed",
                title: L10n.text("Select an entry"),
                detail: L10n.text("Or add a new term or correction.")
            )
        }
    }

    private func refreshFilteredEntries() {
        filteredEntries = Self.makeFilteredEntries(
            entries: config.transcription.terminology.entries,
            query: query,
            filter: filter,
            sort: sort
        )
    }

    private static func makeFilteredEntries(
        entries: [TerminologyEntry],
        query: String,
        filter: TerminologyManagerFilter,
        sort: TerminologyManagerSort
    ) -> [TerminologyEntry] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        let filtered = entries
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
        panel.nameFieldStringValue = "VibeWhisper-Terminology.csv"
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
                        .foregroundStyle(Color(nsColor: VibeWhisperPalette.brandBlue))
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

// MARK: - Isolated editor detail view

/// Separate View struct so its @State-based rendering is isolated from the parent's
/// optional `draft` state. Avoids the BindingOperations.ForceUnwrapping crash that
/// occurs when `Binding($draft)` is used directly and the attribute graph tries to
/// update the binding on a layout pass after `draft` has been set to nil.
private struct TerminologyEditorDetailView: View {
    var draft: TerminologyEditorDraft
    var message: String?
    var messageIsError: Bool
    var canSave: (TerminologyEditorDraft) -> Bool
    var onDraftChange: (TerminologyEditorDraft) -> Void
    var onCancel: () -> Void
    var onSave: (TerminologyEditorDraft) -> Void
    var onRequestDelete: (UUID?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.text(draft.id == nil ? "New Entry" : "Edit Entry"))
                        .font(VibeWhisperTypography.title())
                        .tracking(-0.18)

                    VStack(alignment: .leading, spacing: 16) {
                        editorField(title: "Type") {
                            Picker(
                                L10n.text("Type"),
                                selection: Binding(
                                    get: { draft.type },
                                    set: { var d = draft; d.type = $0; onDraftChange(d) }
                                )
                            ) {
                                Text(L10n.text("Term")).tag(TerminologyEntryType.term)
                                Text(L10n.text("Correction")).tag(
                                    TerminologyEntryType.correction
                                )
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        editorField(
                            title: draft.type == .correction ? "Wrong text" : "Term"
                        ) {
                            TextField(
                                L10n.text(
                                    draft.type == .correction ? "Wrong text" : "Term"
                                ),
                                text: Binding(
                                    get: { draft.original },
                                    set: { var d = draft; d.original = $0; onDraftChange(d) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }

                        if draft.type == .correction {
                            editorField(title: "Correct text") {
                                TextField(
                                    L10n.text("Correct text"),
                                    text: Binding(
                                        get: { draft.replacement },
                                        set: {
                                            var d = draft
                                            d.replacement = $0
                                            onDraftChange(d)
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)
                            }
                        }

                        editorField(title: "Also match") {
                            TextField(
                                L10n.text("Also match"),
                                text: Binding(
                                    get: { draft.aliases },
                                    set: { var d = draft; d.aliases = $0; onDraftChange(d) }
                                ),
                                prompt: Text(L10n.text("e.g. vibewhisper, vibe whisper"))
                            )
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text(L10n.text("Enabled"))
                                .font(VibeWhisperTypography.body())
                            Spacer(minLength: 12)
                            Toggle(
                                L10n.text("Enabled"),
                                isOn: Binding(
                                    get: { draft.isEnabled },
                                    set: {
                                        var d = draft
                                        d.isEnabled = $0
                                        onDraftChange(d)
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                    }
                    .openWhisperInset(padding: 16)

                    if let message {
                        Text(message)
                            .font(VibeWhisperTypography.caption())
                            .foregroundStyle(
                                messageIsError
                                    ? Color(nsColor: VibeWhisperPalette.error)
                                    : Color.secondary
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(28)
                .frame(maxWidth: 620, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            Divider().opacity(0.45)

            // Match History / Settings footers: destructive left, actions right.
            HStack(spacing: 10) {
                if draft.id != nil {
                    Button(role: .destructive) {
                        onRequestDelete(draft.id)
                    } label: {
                        Label(L10n.text("Delete"), systemImage: "trash")
                    }
                    .buttonStyle(VibeWhisperSecondaryButtonStyle())
                }
                Spacer(minLength: 12)
                Button(L10n.text("Cancel"), action: onCancel)
                    .buttonStyle(VibeWhisperSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("Save")) {
                    onSave(draft)
                }
                .buttonStyle(VibeWhisperPrimaryButtonStyle())
                .disabled(!canSave(draft))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }

    private func editorField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title))
                .font(VibeWhisperTypography.micro(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)
            content()
        }
    }
}
