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
        onLoadTranscriptionHistory: @escaping () -> [TranscriptionHistoryRecord],
        onLoadRecoveryHistory: @escaping () -> [RecoveryRecord],
        onResolveRecoveryAudioURL: @escaping (RecoveryRecord) -> Result<URL, any Error>,
        onRetryRecoveryRecord: @escaping (RecoveryRecord) -> Void,
        onDeleteTranscriptionRecord: @escaping (UUID) -> Result<Void, any Error>,
        onDeleteRecoveryRecord: @escaping (UUID) -> Result<Void, any Error>
    ) {
        let view = HistoryWindowView(
            hotkeyBinding: hotkeyBinding,
            onLoadTranscriptionHistory: onLoadTranscriptionHistory,
            onLoadRecoveryHistory: onLoadRecoveryHistory,
            onResolveRecoveryAudioURL: onResolveRecoveryAudioURL,
            onRetryRecoveryRecord: onRetryRecoveryRecord,
            onDeleteTranscriptionRecord: onDeleteTranscriptionRecord,
            onDeleteRecoveryRecord: onDeleteRecoveryRecord
        )
        .applyingAccessibilityDisplayOptionsOverride(
            .currentVisualAcceptance
        )
        let hostingController = NSHostingController(rootView: view)
        let window = HistoryCommandClosingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("OpenWhisper History")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("OpenWhisper.HistoryWindow")
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
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

private struct HistoryWindowView: View {
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
    @StateObject private var audioPlayer = HistoryAudioPlayer()

    let hotkeyBinding: HotkeyBinding
    let onLoadTranscriptionHistory: () -> [TranscriptionHistoryRecord]
    let onLoadRecoveryHistory: () -> [RecoveryRecord]
    let onResolveRecoveryAudioURL: (RecoveryRecord) -> Result<URL, any Error>
    let onRetryRecoveryRecord: (RecoveryRecord) -> Void
    let onDeleteTranscriptionRecord: (UUID) -> Result<Void, any Error>
    let onDeleteRecoveryRecord: (UUID) -> Result<Void, any Error>

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            NavigationSplitView {
                historyList
                    .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 430)
            } detail: {
                detail
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .onAppear(perform: refresh)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else {
                    return
                }
                refresh()
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

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
            TextField(L10n.text("Search history"), text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 150, maxWidth: .infinity)
            Picker(L10n.text("Type"), selection: $kindFilter) {
                ForEach(HistoryKindFilter.allCases) { filter in
                    Text(L10n.text(filter.rawValue)).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 105)
            Picker(L10n.text("Status"), selection: $statusFilter) {
                ForEach(HistoryStatusFilter.allCases) { filter in
                    Text(L10n.text(filter.rawValue)).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            Picker(L10n.text("Date"), selection: $dateFilter) {
                ForEach(HistoryDateFilter.allCases) { filter in
                    Text(L10n.text(filter.rawValue)).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            Button {
                refresh()
            } label: {
                Label(L10n.text("Refresh"), systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var historyList: some View {
        List(filteredEntries, selection: $selectedEntryID) { entry in
            historyRow(entry)
                .tag(entry.id)
        }
        .listStyle(.sidebar)
        .overlay {
            if filteredEntries.isEmpty {
                emptyState
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(
                systemName: entry.kind == .recovery
                    ? "waveform.badge.exclamationmark"
                    : outcomeSymbol(entry.outcome)
            )
            .foregroundStyle(entry.kind == .recovery ? .orange : outcomeColor(entry.outcome))
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.target)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(entry.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(
                    entry.kind == .recovery
                        ? L10n.text("Recovery")
                        : TextDeliveryStatus.localizedLabel(for: entry.outcome)
                )
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(entry.kind == .recovery ? .orange : outcomeColor(entry.outcome))
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader(entry)
                    Divider()
                    if let record = entry.transcriptionRecord {
                        transcriptionDetail(record)
                    } else if let record = entry.recoveryRecord {
                        recoveryDetail(record)
                    }
                    if let message {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(messageIsError ? .red : .secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text(L10n.text("Select a record"))
                    .font(.system(size: 17, weight: .semibold))
                Text(L10n.text("Inspect, copy, retry, reveal, play, or delete local dictation records."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(30)
        }
    }

    private func detailHeader(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.target)
                    .font(.system(size: 24, weight: .semibold))
                Spacer()
                Button(role: .destructive) {
                    pendingDeletion = entry
                } label: {
                    Label(L10n.text("Delete"), systemImage: "trash")
                }
            }
            Text(entry.timestamp.formatted(date: .complete, time: .standard))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(TextDeliveryStatus.localizedLabel(for: entry.outcome))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(outcomeColor(entry.outcome))
        }
    }

    private func transcriptionDetail(_ record: TranscriptionHistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
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
            }
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
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.text(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(L10n.text("No matching history"))
                .font(.system(size: 15, weight: .semibold))
            Text(
                L10n.format(
                    "Press %@ to create your first dictation, or change the search and filters.",
                    hotkeyBinding.displayName
                )
            )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
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

    private func refresh() {
        transcriptionRecords = onLoadTranscriptionHistory()
        recoveryRecords = onLoadRecoveryHistory()
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
            refresh()
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
