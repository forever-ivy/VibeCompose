import AppKit
import SwiftUI

@MainActor
private final class HistoryAudioPlayer: ObservableObject {
    private var sound: NSSound?
    @Published private(set) var playingRecordID: UUID?

    func play(url: URL, recordID: UUID) {
        stop()
        guard let sound = NSSound(contentsOf: url, byReference: true) else {
            NSSound.beep()
            return
        }
        self.sound = sound
        playingRecordID = recordID
        sound.play()
    }

    func stop() {
        sound?.stop()
        sound = nil
        playingRecordID = nil
    }
}

@MainActor
final class HistoryWindowController: NSWindowController {
    init(
        hotkeyBinding: HotkeyBinding = .f5,
        onLoadTranscriptionHistory: @escaping @Sendable () async -> [TranscriptionHistoryRecord],
        onLoadRecoveryHistory: @escaping @Sendable () async -> [RecoveryRecord],
        onResolveRecoveryAudioURL: @escaping (RecoveryRecord) -> Result<URL, any Error>,
        onRetryRecoveryRecord: @escaping (RecoveryRecord) -> Void,
        onCanUndoTranscriptionRecord: @escaping (UUID) -> Bool,
        onUndoTranscriptionRecord:
            @escaping (UUID) async -> SafeUndoOutcome,
        onDeleteTranscriptionRecord: @escaping (UUID) -> Result<Void, any Error>,
        onDeleteRecoveryRecord: @escaping (UUID) -> Result<Void, any Error>
    ) {
        let view = HistoryWindowView(
            isEmbedded: false,
            hotkeyBinding: hotkeyBinding,
            onLoadTranscriptionHistory: onLoadTranscriptionHistory,
            onLoadRecoveryHistory: onLoadRecoveryHistory,
            onResolveRecoveryAudioURL: onResolveRecoveryAudioURL,
            onRetryRecoveryRecord: onRetryRecoveryRecord,
            onCanUndoTranscriptionRecord:
                onCanUndoTranscriptionRecord,
            onUndoTranscriptionRecord:
                onUndoTranscriptionRecord,
            onDeleteTranscriptionRecord: onDeleteTranscriptionRecord,
            onDeleteRecoveryRecord: onDeleteRecoveryRecord
        )
        .applyingOpenWhisperBrandTint()
        .applyingAccessibilityDisplayOptionsOverride(
            .currentVisualAcceptance
        )
        let hostingController = NSHostingController(rootView: view)
        let window = HistoryCommandClosingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
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
        window.title = L10n.text("OpenWhisper History")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        let historyToolbar = NSToolbar(
            identifier: "OpenWhisper.HistoryToolbar"
        )
        historyToolbar.displayMode = .iconOnly
        historyToolbar.allowsUserCustomization = false
        historyToolbar.autosavesConfiguration = false
        window.toolbar = historyToolbar
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("OpenWhisper.HistoryWindow")
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.minSize = NSSize(width: 760, height: 500)
        window.tabbingMode = .disallowed
        let restored = window.setFrameUsingName("OpenWhisper.HistoryWindow")
        window.setFrameAutosaveName("OpenWhisper.HistoryWindow")
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

private final class HistoryCommandClosingWindow: NSWindow {
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

struct HistoryWindowView: View {
    @State private var transcriptionRecords: [TranscriptionHistoryRecord] = []
    @State private var recoveryRecords: [RecoveryRecord] = []
    @State private var query = ""
    @State private var kindFilter: HistoryKindFilter = .all
    @State private var statusFilter: HistoryStatusFilter = .all
    @State private var dateFilter: HistoryDateFilter = .all
    @State private var selectedEntryID: String?
    @State private var pendingDeletion: HistoryEntry?
    @State private var message: String?
    @State private var messageIsError = false
    @State private var isRefreshing = false
    @StateObject private var audioPlayer = HistoryAudioPlayer()

    let isEmbedded: Bool
    let hotkeyBinding: HotkeyBinding
    let onLoadTranscriptionHistory: @Sendable () async -> [TranscriptionHistoryRecord]
    let onLoadRecoveryHistory: @Sendable () async -> [RecoveryRecord]
    let onResolveRecoveryAudioURL: (RecoveryRecord) -> Result<URL, any Error>
    let onRetryRecoveryRecord: (RecoveryRecord) -> Void
    let onCanUndoTranscriptionRecord: (UUID) -> Bool
    let onUndoTranscriptionRecord:
        (UUID) async -> SafeUndoOutcome
    let onDeleteTranscriptionRecord: (UUID) -> Result<Void, any Error>
    let onDeleteRecoveryRecord: (UUID) -> Result<Void, any Error>

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularLayout
            compactLayout
        }
        .frame(minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .modifier(HistoryChromeModifier(
            isEmbedded: isEmbedded,
            query: $query,
            kindFilter: $kindFilter,
            statusFilter: $statusFilter,
            dateFilter: $dateFilter,
            isRefreshing: isRefreshing,
            onRefresh: { Task { await refresh() } }
        ))
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .alert(
            L10n.text("Delete this history record?"),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button(L10n.text("Cancel"), role: .cancel) {
                pendingDeletion = nil
            }
            Button(L10n.text("Delete"), role: .destructive) {
                deletePendingEntry()
            }
        } message: {
            Text(L10n.text("This removes the local record and any associated recovery audio."))
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 0) {
            historyList
                .frame(width: 320)
            Divider()
            detail
                .frame(minWidth: 420)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760)
    }

    private var compactLayout: some View {
        HStack(spacing: 0) {
            historyList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 280)
            Divider()
            detail
                .frame(minWidth: 260)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var historyList: some View {
        List(filteredEntries, selection: $selectedEntryID) { entry in
            historyRow(entry)
                .tag(entry.id)
        }
        .listStyle(.inset)
        .listRowSeparator(.hidden)
        .overlay {
            if filteredEntries.isEmpty {
                emptyState
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            historyIconWell(for: entry)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.target)
                        .font(OpenWhisperTypography.callout(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(OpenWhisperTypography.micro())
                        .foregroundStyle(.secondary)
                }
                Text(entry.summary)
                    .font(OpenWhisperTypography.caption())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                metadataRow(for: entry)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func historyIconWell(for entry: HistoryEntry) -> some View {
        let symbol: String = entry.kind == .recovery
            ? "waveform.badge.exclamationmark"
            : outcomeSymbol(entry.outcome)
        return Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(nsColor: OpenWhisperPalette.brandBlue))
            .frame(width: 32, height: 32)
            .background(
                Color(nsColor: OpenWhisperPalette.brandBlue).opacity(0.09),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private func metadataRow(for entry: HistoryEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: entry.kind == .recovery ? "waveform" : "text.bubble.fill")
                .font(.system(size: 8, weight: .semibold))
            Text(entry.kind == .recovery
                ? L10n.text("Recovery")
                : TextDeliveryStatus.localizedLabel(for: entry.outcome))
                .font(OpenWhisperTypography.micro(.medium))
        }
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader(entry)
                    Divider().opacity(0.5)
                    if let record = entry.transcriptionRecord {
                        transcriptionDetail(record)
                    } else if let record = entry.recoveryRecord {
                        recoveryDetail(record)
                    }
                    if let message {
                        Text(message)
                            .font(OpenWhisperTypography.caption())
                            .foregroundStyle(
                                messageIsError
                                    ? Color(nsColor: OpenWhisperPalette.error)
                                    : Color.secondary
                            )
                    }
                }
                .padding(28)
                .frame(maxWidth: 620, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            OpenWhisperEmptyState(
                systemImage: "clock.arrow.circlepath",
                title: L10n.text("Select a record"),
                detail: L10n.text("Inspect, copy, retry, reveal, play, or delete local dictation records.")
            )
        }
    }

    private func detailHeader(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.target)
                    .font(OpenWhisperTypography.title())
                    .tracking(-0.18)
                Spacer()
                Button(role: .destructive) {
                    pendingDeletion = entry
                } label: {
                    Label(L10n.text("Delete"), systemImage: "trash")
                }
                .buttonStyle(OpenWhisperSecondaryButtonStyle())
            }
            Text(entry.timestamp.formatted(date: .complete, time: .standard))
                .font(OpenWhisperTypography.callout())
                .foregroundStyle(.secondary)
            OpenWhisperStatusChip(
                text: TextDeliveryStatus.localizedLabel(for: entry.outcome),
                kind: statusChipKind(for: entry.outcome)
            )
        }
    }

    private func statusChipKind(for outcome: String) -> OpenWhisperStatusChip.Kind {
        switch TextDeliveryStatus.kind(for: outcome) {
        case .insertedAndVerified:
            return .success
        case .pasteDispatched:
            return .accent
        case .clipboard:
            return .warning
        case .error:
            return .error
        case .unknown:
            return .neutral
        }
    }

    private func transcriptionDetail(_ record: TranscriptionHistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let skillName = record.skillName {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Skill run"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(skillName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(
                        [
                            record.skillSource.flatMap {
                                SkillResolutionSource(rawValue: $0)?
                                    .localizedLabel
                            },
                            record.skillVersion.map { "v\($0)" },
                            record.skillRevision,
                        ].compactMap { $0 }.joined(separator: " · ")
                    )
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    if !record.skillValidationIssueCodes.isEmpty {
                        Label(
                            L10n.format(
                                "Validator fallback: %@",
                                record.skillValidationIssueCodes
                                    .joined(separator: ", ")
                            ),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    }
                    if let fallback = record.skillFallbackMessage {
                        Text(fallback)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                    if let action = record.skillDeliveryAction {
                        Label(
                            record.skillResultEdited
                                ? L10n.format(
                                    "Edited by you · %@",
                                    localizedDeliveryAction(
                                        action
                                    )
                                )
                                : localizedDeliveryAction(
                                    action
                                ),
                            systemImage:
                                record.skillResultEdited
                                ? "pencil.line"
                                : "arrow.right.circle"
                        )
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    if let receipt = record.skillRunReceipt {
                        let context = receipt.contextDecisions
                            .filter {
                                $0.decisionCode != "not_requested"
                            }
                            .map { decision in
                                "\(decision.source.title):\(decision.decisionCode)"
                            }
                            .joined(separator: " · ")
                        if !context.isEmpty {
                            Label(
                                L10n.format(
                                    "Context: %@",
                                    context
                                ),
                                systemImage: "checkmark.shield"
                            )
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        }
                        Text(
                            L10n.format(
                                "Receipt: %@ · %@",
                                receipt.targetVerification,
                                receipt.finalUserAction
                            )
                        )
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            historyTextSection(title: "Final text", text: record.finalText)

            if let rawText = record.rawText,
               rawText.trimmingCharacters(in: .whitespacesAndNewlines) != record.finalText
            {
                historyTextSection(title: "Original ASR", text: rawText)
            }

            HStack {
                Button {
                    copyText(record.finalText)
                } label: {
                    Label(L10n.text("Copy"), systemImage: "doc.on.doc")
                }
                if let provider = record.textPolishProvider {
                    Text(L10n.format("Polished with %@", provider))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if record.undoState == .available,
                   onCanUndoTranscriptionRecord(record.id)
                {
                    Button {
                        Task { @MainActor in
                            let outcome =
                                await onUndoTranscriptionRecord(
                                    record.id
                                )
                            message = outcome.statusDetail
                            messageIsError = outcome != .restored
                            Task { await refresh() }
                        }
                    } label: {
                        Label(
                            L10n.text("Safe Undo"),
                            systemImage: "arrow.uturn.backward.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                } else if let undoState = record.undoState {
                    Label(
                        localizedUndoState(undoState),
                        systemImage: undoState == .restored
                            ? "checkmark.arrow.trianglehead.counterclockwise"
                            : "arrow.uturn.backward.circle"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func localizedUndoState(
        _ state: HistoryUndoState
    ) -> String {
        switch state {
        case .available:
            return L10n.text("Safe Undo expired")
        case .restored:
            return L10n.text("Insertion safely undone")
        case .originalCopied:
            return L10n.text("Original selected text copied")
        case .unavailable:
            return L10n.text("Safe Undo unavailable")
        }
    }

    private func localizedDeliveryAction(
        _ action: String
    ) -> String {
        switch PreviewAction(rawValue: action) {
        case .replaceSelection:
            return L10n.text("Replaced selection")
        case .pasteToTarget:
            return L10n.text("Pasted to target")
        case .copy:
            return L10n.text("Copied")
        case nil:
            return action
        }
    }

    private func recoveryDetail(_ record: RecoveryRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = record.errorMessage, !error.isEmpty {
                historyTextSection(title: "Failure", text: error, color: .red)
            }
            if let text = record.polishText, !text.isEmpty {
                historyTextSection(title: "AI polish result", text: text)
            }
            if let text = record.asrText, !text.isEmpty {
                historyTextSection(title: "ASR transcript", text: text)
            }

            LabeledContent(
                L10n.text("Audio duration"),
                value: Self.formattedDuration(record.audioDurationMs)
            )

            HStack(spacing: 10) {
                Button {
                    play(record)
                } label: {
                    Label(
                        L10n.text(
                            audioPlayer.playingRecordID == record.id ? "Restart Audio" : "Play Audio"
                        ),
                        systemImage: "play.circle"
                    )
                }
                Button {
                    reveal(record)
                } label: {
                    Label(L10n.text("Reveal in Finder"), systemImage: "folder")
                }
                Button {
                    onRetryRecoveryRecord(record)
                } label: {
                    Label(L10n.text("Retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                if let copyText = record.polishText ?? record.asrText, !copyText.isEmpty {
                    Button {
                        self.copyText(copyText)
                    } label: {
                        Label(L10n.text("Copy"), systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }

    private func historyTextSection(
        title: String,
        text: String,
        color: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title))
                .font(OpenWhisperTypography.micro(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.3)
            Text(text)
                .font(OpenWhisperTypography.body())
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    Color(nsColor: OpenWhisperPalette.insetSurface),
                    in: RoundedRectangle(
                        cornerRadius: OpenWhisperMetrics.radiusM,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: OpenWhisperMetrics.radiusM,
                        style: .continuous
                    )
                    .stroke(
                        Color(nsColor: OpenWhisperPalette.hairline),
                        lineWidth: 0.5
                    )
                }
        }
    }

    private var emptyState: some View {
        OpenWhisperEmptyState(
            systemImage: "text.bubble",
            title: L10n.text("No matching history"),
            detail: L10n.format(
                "Press %@ to create your first dictation, or change the search and filters.",
                hotkeyBinding.displayName
            )
        )
    }

    private var entries: [HistoryEntry] {
        transcriptionRecords.map(HistoryEntry.transcript)
            + recoveryRecords.map(HistoryEntry.recovery)
    }

    private var filteredEntries: [HistoryEntry] {
        HistoryLibrary.filteredEntries(
            transcripts: transcriptionRecords,
            recovery: recoveryRecords,
            query: query,
            kindFilter: kindFilter,
            statusFilter: statusFilter,
            dateFilter: dateFilter
        )
    }

    private var selectedEntry: HistoryEntry? {
        guard let selectedEntryID else {
            return nil
        }
        return entries.first { $0.id == selectedEntryID }
    }

    private func refresh() async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let loadedTranscriptionRecords = await onLoadTranscriptionHistory()
        let loadedRecoveryRecords = await onLoadRecoveryHistory()
        guard !Task.isCancelled else {
            return
        }
        if loadedTranscriptionRecords != transcriptionRecords {
            transcriptionRecords = loadedTranscriptionRecords
        }
        if loadedRecoveryRecords != recoveryRecords {
            recoveryRecords = loadedRecoveryRecords
        }
        if let selectedEntryID, !entries.contains(where: { $0.id == selectedEntryID }) {
            self.selectedEntryID = nil
        }
    }

    private func play(_ record: RecoveryRecord) {
        switch onResolveRecoveryAudioURL(record) {
        case .success(let url):
            audioPlayer.play(url: url, recordID: record.id)
            message = nil
        case .failure(let error):
            message = error.localizedDescription
            messageIsError = true
            NSSound.beep()
        }
    }

    private func reveal(_ record: RecoveryRecord) {
        switch onResolveRecoveryAudioURL(record) {
        case .success(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
            message = nil
        case .failure(let error):
            message = error.localizedDescription
            messageIsError = true
            NSSound.beep()
        }
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        message = L10n.text("Copied to clipboard")
        messageIsError = false
    }

    private func deletePendingEntry() {
        guard let entry = pendingDeletion else {
            return
        }
        pendingDeletion = nil

        let result: Result<Void, any Error>
        if let record = entry.transcriptionRecord {
            result = onDeleteTranscriptionRecord(record.id)
        } else if let record = entry.recoveryRecord {
            result = onDeleteRecoveryRecord(record.id)
        } else {
            return
        }

        switch result {
        case .success:
            selectedEntryID = nil
            message = L10n.text("History record deleted.")
            messageIsError = false
            Task { await refresh() }
        case .failure(let error):
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func outcomeSymbol(_ outcome: String) -> String {
        switch TextDeliveryStatus.kind(for: outcome) {
        case .insertedAndVerified:
            return "checkmark.circle.fill"
        case .pasteDispatched:
            return "arrow.right.circle.fill"
        case .clipboard:
            return "doc.on.clipboard.fill"
        case .error:
            return "exclamationmark.circle.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func outcomeColor(_ outcome: String) -> Color {
        switch TextDeliveryStatus.kind(for: outcome) {
        case .insertedAndVerified:
            return .green
        case .pasteDispatched:
            return .blue
        case .clipboard:
            return .orange
        case .error:
            return .red
        case .unknown:
            return .secondary
        }
    }

    private static func formattedDuration(_ durationMs: Int) -> String {
        let seconds = max(0, durationMs) / 1_000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// Embedded mode renders the pane's controls in an in-content header (Apple's
/// detail-column pattern, same as the Skill Library pane); standalone mode
/// keeps the window toolbar chrome with a native search field.
private struct HistoryChromeModifier: ViewModifier {
    let isEmbedded: Bool
    @Binding var query: String
    @Binding var kindFilter: HistoryKindFilter
    @Binding var statusFilter: HistoryStatusFilter
    @Binding var dateFilter: HistoryDateFilter
    let isRefreshing: Bool
    let onRefresh: () -> Void

    func body(content: Content) -> some View {
        if isEmbedded {
            VStack(spacing: 0) {
                OpenWhisperPaneHeader(title: L10n.text("History")) {
                    headerControls
                }
                Divider().opacity(0.45)
                content
            }
        } else {
            content
                .searchable(
                    text: $query,
                    placement: .toolbar,
                    prompt: Text(L10n.text("Search history"))
                )
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        kindPicker
                    }
                    ToolbarItem {
                        filterMenu
                    }
                    ToolbarItem {
                        refreshButton
                    }
                }
        }
    }

    @ViewBuilder
    private var headerControls: some View {
        searchField
            .frame(width: 220)
        kindMenu
        filterMenu
        refreshButton
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                L10n.text("Search history"),
                text: $query
            )
            .textFieldStyle(.plain)
        }
        .openWhisperSearchField()
    }

    private var kindPicker: some View {
        Picker(L10n.text("Type"), selection: $kindFilter) {
            ForEach(HistoryKindFilter.allCases) { filter in
                Text(L10n.text(filter.rawValue)).tag(filter)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 250)
    }

    private var kindMenu: some View {
        Menu {
            Picker(L10n.text("Type"), selection: $kindFilter) {
                ForEach(HistoryKindFilter.allCases) { filter in
                    Text(L10n.text(filter.rawValue)).tag(filter)
                }
            }
        } label: {
            Label(
                L10n.text(kindFilter.rawValue),
                systemImage: "tray.full"
            )
        }
        .help(L10n.text("Type"))
    }

    private var filterMenu: some View {
        Menu {
            Picker(L10n.text("Status"), selection: $statusFilter) {
                ForEach(HistoryStatusFilter.allCases) { filter in
                    Text(L10n.text(filter.rawValue)).tag(filter)
                }
            }
            Picker(L10n.text("Date"), selection: $dateFilter) {
                ForEach(HistoryDateFilter.allCases) { filter in
                    Text(L10n.text(filter.rawValue)).tag(filter)
                }
            }
        } label: {
            Label(
                activeFilterSummary,
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }
        .help(L10n.text("Filter"))
    }

    private var activeFilterSummary: String {
        let parts: [String] = [
            statusFilter == .all ? nil : L10n.text(statusFilter.rawValue),
            dateFilter == .all ? nil : L10n.text(dateFilter.rawValue),
        ].compactMap { $0 }
        return parts.isEmpty
            ? L10n.text("Filter")
            : parts.joined(separator: " · ")
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(isRefreshing)
        .help(L10n.text("Refresh"))
        .accessibilityLabel(L10n.text("Refresh"))
    }
}
