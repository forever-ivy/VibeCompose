import AppKit
import SwiftUI

enum TerminologyQuickAddError: LocalizedError, Equatable {
    case invalidOriginal
    case replacementRequired
    case duplicate

    var errorDescription: String? {
        switch self {
        case .invalidOriginal:
            return L10n.text("Enter a term or wrong-text value with no more than 240 characters.")
        case .replacementRequired:
            return L10n.text("Corrections require replacement text with no more than 240 characters.")
        case .duplicate:
            return L10n.text("An entry for the same term or wrong text already exists.")
        }
    }
}

struct TerminologyQuickAddDraft: Equatable {
    var type: TerminologyEntryType = .term
    var original = ""
    var replacement = ""
    var aliases = ""

    func makeEntry(
        existing: [TerminologyEntry],
        now: Date = Date()
    ) throws -> TerminologyEntry {
        let normalizedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOriginal.isEmpty, normalizedOriginal.count <= 240 else {
            throw TerminologyQuickAddError.invalidOriginal
        }

        let normalizedReplacement = replacement
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if type == .correction {
            guard !normalizedReplacement.isEmpty, normalizedReplacement.count <= 240 else {
                throw TerminologyQuickAddError.replacementRequired
            }
        }

        var seenAliases = Set<String>()
        let normalizedAliases = aliases
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { alias in
                guard !alias.isEmpty, alias.count <= 240 else {
                    return false
                }
                let key = alias.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                return seenAliases.insert(key).inserted
            }

        let entry = TerminologyEntry(
            type: type,
            original: normalizedOriginal,
            replacement: type == .correction ? normalizedReplacement : nil,
            aliases: normalizedAliases,
            isEnabled: true,
            source: "user",
            usageCount: 0,
            createdAt: ISO8601DateFormatter().string(from: now)
        )
        guard !existing.contains(where: {
            TerminologyLibrary.identityKey(for: $0)
                == TerminologyLibrary.identityKey(for: entry)
        }) else {
            throw TerminologyQuickAddError.duplicate
        }

        return entry
    }
}

@MainActor
final class TerminologyQuickAddWindowController: NSWindowController, NSWindowDelegate {
    /// Host app frontmost before Quick Add activated VibeCompose.
    private var priorExternalFrontmost: LaunchAppContext?
    private var didRestoreFrontmost = false

    init(
        existingEntries: [TerminologyEntry],
        onSave: @escaping (TerminologyEntry) -> Result<Void, any Error>
    ) {
        weak var weakWindow: NSWindow?
        let view = TerminologyQuickAddView(
            existingEntries: existingEntries,
            onSave: onSave,
            onClose: {
                weakWindow?.close()
            }
        )
        .applyingVibeComposeBrandTint()
        .applyingAccessibilityDisplayOptionsOverride(
            .currentVisualAcceptance
        )
        let hostingController = NSHostingController(rootView: view)
        // Borderless floating panel wearing the shared floating-glass chrome
        // (Liquid Glass on macOS 26), matching the Skill Switcher shell —
        // the titled utility-window frame predates the visual system.
        let window = TerminologyQuickAddPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 390),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        weakWindow = window
        window.title = L10n.text("Quick Add Terminology")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("VibeCompose.TerminologyQuickAdd")
        window.level = .floating
        window.isFloatingPanel = true
        window.backgroundColor = .clear
        // SwiftUI chrome owns elevation; a window shadow would double-cast.
        window.hasShadow = false
        window.isOpaque = false
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.tabbingMode = .disallowed
        window.contentViewController = hostingController
        // Match the continuous glass radius on the AppKit host so the square
        // NSView bounds never show past the SwiftUI corner.
        let corner = VibeComposeFloatingChrome.panelCornerRadius
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = corner
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = corner
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.masksToBounds = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        AccessibilityDisplayOptionsOverride.currentVisualAcceptance
            .applyAppearance(to: window)
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else {
            return
        }
        if priorExternalFrontmost == nil {
            priorExternalFrontmost =
                LaunchAppContext.externalFrontmostForTransientRestore()
        }
        didRestoreFrontmost = false
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        restorePriorFrontmostIfNeeded()
    }

    override func close() {
        restorePriorFrontmostIfNeeded()
        super.close()
    }

    private func restorePriorFrontmostIfNeeded() {
        guard !didRestoreFrontmost else { return }
        didRestoreFrontmost = true
        LaunchAppContext.restoreFrontmostIfNeeded(priorExternalFrontmost)
        priorExternalFrontmost = nil
    }

    func writeSnapshot(to url: URL) throws {
        try ProductSurfaceSnapshot.write(window: window, to: url)
    }
}

// MARK: - Panel

/// Borderless floating panel: key so the text fields take focus, draggable by
/// the glass background, Esc dismisses (deferring to IME composition first).
private final class TerminologyQuickAddPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if TransientPanelKeyRouting.inputMethodHasMarkedText(in: self) {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        if event.type == .keyDown,
           modifiers.isEmpty,
           event.keyCode == 53
        {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Text fields swallow Esc as `cancelOperation:`. Dismiss only when the IME
    /// is not composing — otherwise Esc must clear marked text first.
    override func cancelOperation(_ sender: Any?) {
        guard TransientPanelKeyRouting.shouldDismissOnCancelOperation(
            hasMarkedText: TransientPanelKeyRouting.inputMethodHasMarkedText(
                in: self
            )
        ) else {
            return
        }
        close()
    }
}

private struct TerminologyQuickAddView: View {
    @State private var draft = TerminologyQuickAddDraft()
    @State private var message: String?

    let existingEntries: [TerminologyEntry]
    let onSave: (TerminologyEntry) -> Result<Void, any Error>
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                VibeComposeIconWell(
                    systemName: "text.book.closed",
                    size: 40,
                    symbolSize: 16
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("Quick Add Terminology"))
                        .font(VibeComposeTypography.title())
                }
            }

            Form {
                Picker(L10n.text("Type"), selection: $draft.type) {
                    Text(L10n.text("Term")).tag(TerminologyEntryType.term)
                    Text(L10n.text("Correction")).tag(TerminologyEntryType.correction)
                }
                .pickerStyle(.segmented)

                TextField(
                    L10n.text(draft.type == .correction ? "Wrong text" : "Term"),
                    text: $draft.original
                )
                .textFieldStyle(.roundedBorder)

                if draft.type == .correction {
                    TextField(L10n.text("Correct text"), text: $draft.replacement)
                        .textFieldStyle(.roundedBorder)
                }

                TextField(
                    L10n.text("Also match"),
                    text: $draft.aliases,
                    prompt: Text(L10n.text("e.g. vibecompose, vibe compose"))
                )
                .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            // Rows keep their solid cards; the scroll background yields to the
            // floating-glass shell (grouped content never nests its own glass).
            .scrollContentBackground(.hidden)

            if let message {
                Text(message)
                    .font(VibeComposeTypography.caption())
                    .foregroundStyle(Color(nsColor: VibeComposePalette.error))
            }

            HStack {
                Spacer()
                Button(L10n.text("Cancel"), action: onClose)
                    .buttonStyle(VibeComposeSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("Add Entry"), action: save)
                    .buttonStyle(VibeComposePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 390)
        // Shared floating-glass shell: Liquid Glass on macOS 26, hudWindow
        // material earlier, solid plate under Reduce Transparency.
        .vibeComposeFloatingGlass(
            cornerRadius: VibeComposeFloatingChrome.panelCornerRadius
        )
        // Final clip: hosting NSView layers can still sample outside the
        // glass shape without an explicit continuous mask at the leaf.
        .clipShape(
            RoundedRectangle(
                cornerRadius: VibeComposeFloatingChrome.panelCornerRadius,
                style: .continuous
            )
        )
    }

    private func save() {
        do {
            let entry = try draft.makeEntry(existing: existingEntries)
            switch onSave(entry) {
            case .success:
                onClose()
            case .failure(let error):
                message = error.localizedDescription
                NSSound.beep()
            }
        } catch {
            message = error.localizedDescription
            NSSound.beep()
        }
    }
}
