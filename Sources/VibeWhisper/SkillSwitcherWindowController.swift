import AppKit
import SwiftUI

// MARK: - Layout constants (Spotlight-scale floating palette)

private enum SkillSwitcherLayout {
    static let width: CGFloat = 600
    static let height: CGFloat = 480
    static let frameAutosaveName = "VibeWhisper.SkillSwitcherPanel"
    /// Upper bias relative to vertical center (Spotlight sits high on screen).
    static let defaultVerticalBias: CGFloat = 0.14
    static let rowHeight: CGFloat = 40
    static let iconSize: CGFloat = 30
}

// MARK: - Session (selection + keyboard, MainActor)

/// Owns list selection and search state so the window controller's local key
/// monitor can move/commit without bridging through NSViewRepresentable.
@MainActor
private final class SkillSwitcherSession: ObservableObject {
    let snapshot: SkillMenuSnapshot
    let onAction: (SkillMenuAction) -> Void
    let onOpenLibrary: () -> Void
    let onDismiss: (() -> Void)?

    @Published var searchText = ""
    @Published var selectedID: UUID?
    @Published var hoveredID: UUID?

    init(
        snapshot: SkillMenuSnapshot,
        onAction: @escaping (SkillMenuAction) -> Void,
        onOpenLibrary: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onAction = onAction
        self.onOpenLibrary = onOpenLibrary
        self.onDismiss = onDismiss
        ensureSelection()
    }

    private var normalizedQuery: String {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
    }

    var isSearching: Bool {
        !normalizedQuery.isEmpty
    }

    var searchResults: [SkillMenuEntry] {
        SkillMenuSearch.results(
            in: snapshot.installed,
            matching: normalizedQuery
        )
    }

    /// Browse sections with first-seen dedupe (Recent → Installed).
    /// Favorites were removed from the product surface.
    var browseSections: [SkillSwitcherSection] {
        var seen = Set<UUID>()
        func unique(_ entries: [SkillMenuEntry]) -> [SkillMenuEntry] {
            entries.filter { seen.insert($0.installationID).inserted }
        }
        return [
            SkillSwitcherSection(
                id: "recent",
                title: L10n.text("Recent"),
                entries: unique(snapshot.recent)
            ),
            SkillSwitcherSection(
                id: "installed",
                title: L10n.text("Installed"),
                entries: unique(snapshot.installed)
            ),
        ]
        .filter { !$0.entries.isEmpty }
    }

    var visibleSections: [SkillSwitcherSection] {
        if isSearching {
            if searchResults.isEmpty { return [] }
            return [
                SkillSwitcherSection(
                    id: "results",
                    title: L10n.text("Results"),
                    entries: searchResults
                ),
            ]
        }
        return browseSections
    }

    var flattenedEntries: [SkillMenuEntry] {
        visibleSections.flatMap(\.entries)
    }

    func ensureSelection() {
        let entries = flattenedEntries
        guard !entries.isEmpty else {
            selectedID = nil
            return
        }
        if let selectedID,
           entries.contains(where: { $0.installationID == selectedID })
        {
            return
        }
        selectedID = entries[0].installationID
    }

    func moveSelection(delta: Int) {
        let entries = flattenedEntries
        guard !entries.isEmpty else { return }
        let currentIndex = entries.firstIndex {
            $0.installationID == selectedID
        } ?? (delta > 0 ? -1 : 0)
        let next = min(
            max(currentIndex + delta, 0),
            entries.count - 1
        )
        selectedID = entries[next].installationID
    }

    /// Primary commit: next recording only (does not change global default).
    func commitNextRun() {
        guard let selectedID else { return }
        onAction(.useNext(selectedID))
    }

    /// Secondary commit: persist as the global default Skill.
    func commitGlobalDefault() {
        guard let selectedID else { return }
        onAction(.setGlobalDefault(selectedID))
    }

    func useNext(_ entry: SkillMenuEntry) {
        selectedID = entry.installationID
        onAction(.useNext(entry.installationID))
    }

    func useGlobalDefault(_ entry: SkillMenuEntry) {
        selectedID = entry.installationID
        onAction(.setGlobalDefault(entry.installationID))
    }
}

// MARK: - Section model

private struct SkillSwitcherSection: Identifiable {
    let id: String
    let title: String
    let entries: [SkillMenuEntry]
}

// MARK: - Window controller

@MainActor
final class SkillSwitcherWindowController: NSWindowController {
    /// Whether `setFrameUsingName` found a previously saved frame.
    private var restoredSavedFrame = false
    private var keyMonitor: Any?
    private let session: SkillSwitcherSession
    private var didInvokeDismiss = false
    /// Host app frontmost before this panel activated VibeWhisper. Restored on
    /// dismiss so AppKit does not fall through to Settings as the next key window.
    private var priorExternalFrontmost: LaunchAppContext?
    /// Set when the user explicitly leaves the switcher for Settings (library).
    private var suppressFrontmostRestore = false

    init(
        snapshot: SkillMenuSnapshot,
        onAction: @escaping (SkillMenuAction) -> Void,
        onOpenLibrary: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        let session = SkillSwitcherSession(
            snapshot: snapshot,
            onAction: onAction,
            onOpenLibrary: onOpenLibrary,
            onDismiss: onDismiss
        )
        self.session = session
        let root = SkillSwitcherView(session: session)
            .applyingVibeWhisperBrandTint()
            .applyingAccessibilityDisplayOptionsOverride(
                .currentVisualAcceptance
            )
        let hosting = NSHostingController(rootView: root)
        let panel = SkillSwitcherPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SkillSwitcherLayout.width,
                height: SkillSwitcherLayout.height
            ),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        // SwiftUI chrome owns elevation; a window shadow would double-cast.
        panel.hasShadow = false
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.identifier = NSUserInterfaceItemIdentifier(
            SkillSwitcherLayout.frameAutosaveName
        )
        panel.tabbingMode = .disallowed
        panel.contentViewController = hosting
        // Match the continuous glass radius on the AppKit host so the
        // square NSView bounds never show past the SwiftUI corner.
        let corner = VibeWhisperFloatingChrome.panelCornerRadius
        hosting.view.wantsLayer = true
        hosting.view.layer?.cornerRadius = corner
        hosting.view.layer?.cornerCurve = .continuous
        hosting.view.layer?.masksToBounds = true
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = corner
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.masksToBounds = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        let window = panel
        AccessibilityDisplayOptionsOverride.currentVisualAcceptance
            .applyAppearance(to: window)
        super.init(window: window)
        // Fixed size — restore only origin so layout upgrades don't stretch.
        panel.setContentSize(
            NSSize(
                width: SkillSwitcherLayout.width,
                height: SkillSwitcherLayout.height
            )
        )
        restoredSavedFrame = panel.setFrameUsingName(
            SkillSwitcherLayout.frameAutosaveName
        )
        panel.setFrameAutosaveName(SkillSwitcherLayout.frameAutosaveName)
        // Re-assert Spotlight size after frame restore (name may expand size).
        var restored = panel.frame
        restored.size = NSSize(
            width: SkillSwitcherLayout.width,
            height: SkillSwitcherLayout.height
        )
        panel.setFrame(restored, display: false)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event)
        }
    }

    isolated deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        // Capture before activate so dismiss can return focus to the host app
        // instead of promoting a still-open Settings window.
        if priorExternalFrontmost == nil {
            priorExternalFrontmost =
                LaunchAppContext.externalFrontmostForTransientRestore()
        }
        suppressFrontmostRestore = false
        placeOnScreen()
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        // Claim key status so Esc / ↑↓ work immediately without a click.
        // Borderless panels sometimes order front without becoming key if
        // another app window still holds first responder.
        window.makeFirstResponder(window.contentView)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = VibeWhisperMotion.panelAppear
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    /// Call before close when the user intentionally navigates into Settings
    /// (Skill Library footer) so focus is not yanked back to another app.
    func prepareForExplicitSettingsNavigation() {
        suppressFrontmostRestore = true
    }

    func writeSnapshot(to url: URL) throws {
        try ProductSurfaceSnapshot.write(window: window, to: url)
    }

    /// Ensures the optional dismiss callback fires exactly once when the panel
    /// leaves the screen (Esc, click-away close, or explicit `close()`).
    override func close() {
        notifyDismissed()
        super.close()
    }

    fileprivate func notifyDismissed() {
        guard !didInvokeDismiss else { return }
        didInvokeDismiss = true
        // Restore the pre-panel host *before* onDismiss so re-skill Preview
        // (which may re-activate us) still sees the correct prior context, and
        // so Settings is not left as the accidental key window after Esc/pick.
        if !suppressFrontmostRestore {
            LaunchAppContext.restoreFrontmostIfNeeded(priorExternalFrontmost)
        }
        priorExternalFrontmost = nil
        session.onDismiss?()
    }

    /// Prefer autosaved origin when it still intersects a screen; otherwise
    /// upper-center under the cursor. Always force Spotlight panel size.
    private func placeOnScreen() {
        guard let window else { return }
        let size = NSSize(
            width: SkillSwitcherLayout.width,
            height: SkillSwitcherLayout.height
        )
        let candidateOrigin: NSPoint
        if restoredSavedFrame,
           screenIntersecting(
            NSRect(origin: window.frame.origin, size: size)
           ) != nil
        {
            candidateOrigin = window.frame.origin
        } else {
            candidateOrigin = defaultOrigin(for: size)
        }
        let clamped = clampedOrigin(candidateOrigin, size: size)
        window.setFrame(
            NSRect(origin: clamped, size: size),
            display: false
        )
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        return NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
                + visible.height * SkillSwitcherLayout.defaultVerticalBias
        )
    }

    private func clampedOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        let screen = screenContaining(origin)
            ?? screenIntersecting(NSRect(origin: origin, size: size))
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let minX = visible.minX
        let maxX = max(visible.minX, visible.maxX - size.width)
        let minY = visible.minY
        let maxY = max(visible.minY, visible.maxY - size.height)
        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.contains(point) }
    }

    private func screenIntersecting(_ rect: NSRect) -> NSScreen? {
        NSScreen.screens.first {
            $0.visibleFrame.intersection(rect).width > 8
                && $0.visibleFrame.intersection(rect).height > 8
        }
    }

    /// ↑/↓ move selection, ↩ = next-run, ⌘↩ = global default, Esc dismisses —
    /// even while the search field is first responder (Spotlight behavior).
    /// Esc is also handled here (not only in `performKeyEquivalent`) so it
    /// works before the user has clicked into the panel.
    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard let window else { return event }
        // Accept keys when this panel is key, even if AppKit still tags the
        // previous window on the event right after order-front.
        let isForThisPanel =
            event.window === window || window.isKeyWindow
        guard isForThisPanel else {
            return event
        }
        let modifiers = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )

        switch event.keyCode {
        case 53: // escape
            guard modifiers.isDisjoint(with: [.command, .option, .control, .shift])
            else { return event }
            window.close()
            return nil
        case 125: // down arrow
            guard modifiers.isDisjoint(with: [.command, .option, .control, .shift])
            else { return event }
            session.moveSelection(delta: 1)
            return nil
        case 126: // up arrow
            guard modifiers.isDisjoint(with: [.command, .option, .control, .shift])
            else { return event }
            session.moveSelection(delta: -1)
            return nil
        case 36, 76: // return / keypad enter
            // ⌘↩ → permanent global default; bare ↩ → next recording only.
            if modifiers.contains(.command),
               modifiers.isDisjoint(with: [.option, .control, .shift])
            {
                session.commitGlobalDefault()
                return nil
            }
            if modifiers.isDisjoint(with: [.command, .option, .control, .shift]) {
                session.commitNextRun()
                return nil
            }
            return event
        default:
            return event
        }
    }
}

// MARK: - Panel

/// Borderless floating panel: key for search focus, draggable by glass
/// background, Esc dismisses.
private final class SkillSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
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

    /// Text fields swallow Esc as `cancelOperation:`; still dismiss the panel.
    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func close() {
        saveFrame(usingName: SkillSwitcherLayout.frameAutosaveName)
        // Notify the window controller so re-skill abort can reopen Preview.
        if let controller = windowController as? SkillSwitcherWindowController {
            controller.notifyDismissed()
        }
        super.close()
    }
}

// MARK: - View

private struct SkillSwitcherView: View {
    @ObservedObject var session: SkillSwitcherSession

    @State private var appeared = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            softDivider
            skillList
            softDivider
            footer
        }
        .frame(
            width: SkillSwitcherLayout.width,
            height: SkillSwitcherLayout.height
        )
        .openWhisperFloatingGlass(
            cornerRadius: VibeWhisperFloatingChrome.panelCornerRadius
        )
        // Final clip: hosting NSView layers can still sample outside the
        // glass shape without an explicit continuous mask at the leaf.
        .clipShape(
            RoundedRectangle(
                cornerRadius: VibeWhisperFloatingChrome.panelCornerRadius,
                style: .continuous
            )
        )
        // Spotlight-like materialize: tiny scale + opacity, no bounce.
        .scaleEffect(
            appeared
                ? 1.0
                : (reduceMotion ? 1.0 : VibeWhisperMotion.panelEntranceScale),
            anchor: .center
        )
        .opacity(appeared ? 1.0 : (reduceMotion ? 1.0 : 0.0))
        .animation(VibeWhisperMotion.panelSpring, value: appeared)
        .onAppear {
            appeared = true
            session.ensureSelection()
            isSearchFocused = true
        }
        .onChange(of: session.searchText) { _ in
            session.ensureSelection()
        }
    }

    private var softDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 0.5)
    }

    // MARK: - Search (Spotlight-style)

    private var searchHeader: some View {
        HStack(spacing: VibeWhisperMetrics.space12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(
                    Color(nsColor: VibeWhisperPalette.floatingSecondaryText)
                )
                .accessibilityHidden(true)
            TextField(
                L10n.text("Search Skills…"),
                text: $session.searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(
                Color(nsColor: VibeWhisperPalette.floatingPrimaryText)
            )
            .tint(Color(nsColor: VibeWhisperPalette.brandBlue))
            .focused($isSearchFocused)
            .accessibilityLabel(L10n.text("Search Skills…"))
            if !session.searchText.isEmpty {
                Button {
                    session.searchText = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            Color(
                                nsColor: VibeWhisperPalette.floatingSecondaryText
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("Clear search"))
            }
        }
        .padding(.horizontal, VibeWhisperMetrics.space20)
        .padding(.vertical, VibeWhisperMetrics.space16)
    }

    // MARK: - List

    private var skillList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !session.isSearching {
                        currentChip
                            .padding(.bottom, VibeWhisperMetrics.space6)
                    }

                    if session.isSearching, session.searchResults.isEmpty {
                        emptySearchState
                    } else {
                        ForEach(session.visibleSections) { section in
                            sectionHeader(section.title)
                            ForEach(section.entries) { entry in
                                skillRow(entry)
                                    .id(entry.installationID)
                            }
                        }
                    }
                }
                .padding(.horizontal, VibeWhisperMetrics.space10)
                .padding(.vertical, VibeWhisperMetrics.space6)
            }
            .onChange(of: session.selectedID) { newValue in
                guard let newValue else { return }
                // Instant scroll — avoid springy list chase while arrowing.
                proxy.scrollTo(newValue, anchor: .center)
            }
        }
    }

    /// Compact current-skill chip (not a fat card; not arrow-key selectable).
    private var currentChip: some View {
        HStack(spacing: VibeWhisperMetrics.space10) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: VibeWhisperPalette.success).opacity(0.22))
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(nsColor: VibeWhisperPalette.success))
            }
            Text(L10n.text("Current"))
                .font(VibeWhisperTypography.caption(.semibold))
                .foregroundStyle(
                    Color(nsColor: VibeWhisperPalette.floatingSecondaryText)
                )
            Text(session.snapshot.current.displayName)
                .font(VibeWhisperTypography.body(.semibold))
                .foregroundStyle(
                    Color(nsColor: VibeWhisperPalette.floatingPrimaryText)
                )
                .lineLimit(1)
            Text("·")
                .foregroundStyle(
                    Color(nsColor: VibeWhisperPalette.floatingSecondaryText)
                )
            Text(session.snapshot.resolutionLabel)
                .font(VibeWhisperTypography.caption())
                .foregroundStyle(
                    Color(nsColor: VibeWhisperPalette.floatingSecondaryText)
                )
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VibeWhisperMetrics.space12)
        .padding(.vertical, VibeWhisperMetrics.space8)
        .background(
            Color(nsColor: VibeWhisperPalette.floatingContentSurfaceQuiet),
            in: RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusM,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.format(
                "Current Skill: %@ · %@",
                session.snapshot.current.displayName,
                session.snapshot.resolutionLabel
            )
        )
        .padding(.top, VibeWhisperMetrics.space4)
    }

    private var emptySearchState: some View {
        VStack(spacing: VibeWhisperMetrics.space10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L10n.text("No matching Skills"))
                .font(VibeWhisperTypography.body(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .textCase(.uppercase)
            .font(VibeWhisperTypography.micro(.semibold))
            .tracking(0.6)
            .foregroundStyle(
                Color(nsColor: VibeWhisperPalette.floatingSecondaryText)
            )
            .padding(.horizontal, VibeWhisperMetrics.space12)
            .padding(.top, VibeWhisperMetrics.space10)
            .padding(.bottom, VibeWhisperMetrics.space4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Row

    private func skillRow(_ entry: SkillMenuEntry) -> some View {
        let isSelected = session.selectedID == entry.installationID
        let isHovered = session.hoveredID == entry.installationID
        let isQueuedNext =
            session.snapshot.nextRunInstallationID == entry.installationID
        let isGlobalDefault =
            session.snapshot.resolutionSource == .globalDefault
            && session.snapshot.current.installationID == entry.installationID

        return Button {
            // Click / ↩ primary path: next recording only.
            session.useNext(entry)
        } label: {
            HStack(spacing: VibeWhisperMetrics.space12) {
                iconWell(for: entry, isSelected: isSelected)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.displayName)
                        .font(
                            VibeWhisperTypography.body(
                                isSelected ? .semibold : .medium
                            )
                        )
                        .foregroundStyle(
                            isSelected
                                ? Color(
                                    nsColor: VibeWhisperPalette
                                        .skillSwitcherSelectionForeground
                                )
                                : Color(
                                    nsColor: VibeWhisperPalette
                                        .floatingPrimaryText
                                )
                        )
                        .lineLimit(1)
                    if isSelected, !entry.summary.isEmpty {
                        Text(entry.summary)
                            .font(VibeWhisperTypography.caption())
                            .foregroundStyle(
                                Color(
                                    nsColor: VibeWhisperPalette
                                        .skillSwitcherSelectionForegroundSecondary
                                )
                            )
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: VibeWhisperMetrics.space8)
                if isQueuedNext {
                    Text(L10n.text("Next"))
                        .font(VibeWhisperTypography.micro(.semibold))
                        .foregroundStyle(
                            isSelected
                                ? Color(
                                    nsColor: VibeWhisperPalette
                                        .skillSwitcherSelectionForegroundSecondary
                                )
                                : Color(nsColor: VibeWhisperPalette.brandBlue)
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (isSelected
                                ? Color.white.opacity(0.18)
                                : Color(nsColor: VibeWhisperPalette.brandBlue)
                                    .opacity(0.12)),
                            in: Capsule(style: .continuous)
                        )
                        .accessibilityHidden(true)
                } else if isGlobalDefault {
                    Text(L10n.text("Default"))
                        .font(VibeWhisperTypography.micro(.semibold))
                        .foregroundStyle(
                            isSelected
                                ? Color(
                                    nsColor: VibeWhisperPalette
                                        .skillSwitcherSelectionForegroundSecondary
                                )
                                : Color(
                                    nsColor: VibeWhisperPalette
                                        .floatingSecondaryText
                                )
                        )
                        .accessibilityHidden(true)
                }
                if isSelected {
                    Text("↩")
                        .font(VibeWhisperTypography.caption(.medium))
                        .foregroundStyle(
                            Color(
                                nsColor: VibeWhisperPalette
                                    .skillSwitcherSelectionForegroundSecondary
                            )
                        )
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, VibeWhisperMetrics.space10)
            .padding(.vertical, 7)
            .frame(
                maxWidth: .infinity,
                minHeight: SkillSwitcherLayout.rowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(
                    cornerRadius: VibeWhisperMetrics.radiusM,
                    style: .continuous
                )
                .fill(selectionFill(isSelected: isSelected, isHovered: isHovered))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.text("Use for Next Recording")) {
                session.useNext(entry)
            }
            Button(L10n.text("Set as Global Default")) {
                session.useGlobalDefault(entry)
            }
        }
        .onHover { hovering in
            if hovering {
                session.hoveredID = entry.installationID
            } else if session.hoveredID == entry.installationID {
                session.hoveredID = nil
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.displayName)
        .accessibilityHint(
            L10n.text(
                "Return uses this Skill for the next recording. Command-Return sets it as the global default."
            )
        )
        .accessibilityAddTraits(
            isSelected ? [.isSelected, .isButton] : .isButton
        )
    }

    private func iconWell(
        for entry: SkillMenuEntry,
        isSelected: Bool
    ) -> some View {
        let accent: NSColor =
            entry.requiresSelection
            ? VibeWhisperPalette.amber
            : VibeWhisperPalette.brandBlue
        let wellFill: Color =
            isSelected
            ? Color.white.opacity(0.22)
            : Color(nsColor: accent).opacity(0.14)
        let glyphColor: Color =
            isSelected
            ? Color(
                nsColor: VibeWhisperPalette.skillSwitcherSelectionForeground
            )
            : Color(nsColor: accent)

        return ZStack {
            RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusS,
                style: .continuous
            )
            .fill(wellFill)
            .frame(
                width: SkillSwitcherLayout.iconSize,
                height: SkillSwitcherLayout.iconSize
            )
            Image(
                systemName: entry.requiresSelection
                    ? "selection.pin.in.out"
                    : "wand.and.stars"
            )
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(glyphColor)
        }
        .accessibilityHidden(true)
    }

    private func selectionFill(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            // Solid brand blue so white selection text stays WCAG-legible on
            // both light and dark Liquid Glass shells (system selectedContent
            // still pairs with primary/secondary semantic colors that do not
            // flip on custom glass).
            Color(
                nsColor: VibeWhisperPalette.skillSwitcherSelectionBackground
            )
        } else if isHovered {
            Color(nsColor: VibeWhisperPalette.floatingContentSurfaceQuiet)
        } else {
            Color.clear
        }
    }


    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: VibeWhisperMetrics.space12) {
            Text(
                L10n.format(
                    "%ld installed",
                    session.snapshot.installed.count
                )
            )
            .font(VibeWhisperTypography.caption())
            .foregroundStyle(
                Color(nsColor: VibeWhisperPalette.floatingSecondaryText)
            )
            Spacer(minLength: 0)
            footerHint(
                keys: "↩",
                label: L10n.text("Next recording")
            )
            footerHint(
                keys: "⌘↩",
                label: L10n.text("Global default")
            )
        }
        .padding(.horizontal, VibeWhisperMetrics.space20)
        .padding(.vertical, VibeWhisperMetrics.space10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            L10n.text(
                "Return uses this Skill for the next recording. Command-Return sets it as the global default."
            )
        )
    }

    private func footerHint(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    Color(nsColor: VibeWhisperPalette.floatingPrimaryText)
                )
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Color(nsColor: VibeWhisperPalette.floatingContentSurfaceQuiet),
                    in: RoundedRectangle(
                        cornerRadius: 4,
                        style: .continuous
                    )
                )
            Text(label)
                .font(VibeWhisperTypography.caption())
                .foregroundStyle(
                    Color(nsColor: VibeWhisperPalette.floatingSecondaryText)
                )
        }
    }
}
