import AppKit
import SwiftUI

@MainActor
final class SkillSwitcherWindowController: NSWindowController {
    init(
        snapshot: SkillMenuSnapshot,
        onAction: @escaping (SkillMenuAction) -> Void,
        onOpenLibrary: @escaping () -> Void
    ) {
        let root = SkillSwitcherView(
            snapshot: snapshot,
            onAction: onAction,
            onOpenLibrary: onOpenLibrary
        )
        .applyingOpenWhisperBrandTint()
        .applyingAccessibilityDisplayOptionsOverride(
            .currentVisualAcceptance
        )
        let hosting = NSHostingController(rootView: root)
        let panel = SkillSwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.identifier = NSUserInterfaceItemIdentifier("OpenWhisper.SkillSwitcherPanel")
        panel.tabbingMode = .disallowed
        panel.contentViewController = hosting
        let window = panel
        AccessibilityDisplayOptionsOverride.currentVisualAcceptance
            .applyAppearance(to: window)
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        centerOnActiveScreen()
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    func writeSnapshot(to url: URL) throws {
        try ProductSurfaceSnapshot.write(window: window, to: url)
    }

    private func centerOnActiveScreen() {
        guard let window else { return }
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2 + visibleFrame.height * 0.08
        )
        window.setFrameOrigin(origin)
    }
}

private final class SkillSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown,
           modifiers.isEmpty,
           event.keyCode == 53
        {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct SkillSwitcherView: View {
    let snapshot: SkillMenuSnapshot
    let onAction: (SkillMenuAction) -> Void
    let onOpenLibrary: () -> Void

    @State private var searchText = ""
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var normalizedQuery: String {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
    }

    private var searchResults: [SkillMenuEntry] {
        SkillMenuSearch.results(
            in: snapshot.installed,
            matching: normalizedQuery
        )
    }

    var body: some View {
        if #available(macOS 26, *) {
            VStack(spacing: 0) {
                searchBar
                Divider()
                    .background(Color(nsColor: OpenWhisperPalette.mist).opacity(0.09))
                skillList
                Divider()
                    .background(Color(nsColor: OpenWhisperPalette.mist).opacity(0.09))
                footer
            }
            .frame(width: 640, height: 520)
            .colorScheme(.dark)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: OpenWhisperMetrics.radiusXXL, style: .continuous)
            )
            .shadow(color: Color.black.opacity(0.38), radius: 48, x: 0, y: 20)
            .scaleEffect(appeared ? 1.0 : (reduceMotion ? 1.0 : 0.96), anchor: .top)
            .animation(OpenWhisperMotion.panelSpring, value: appeared)
            .onAppear { appeared = true }
        } else {
            ZStack {
                // Dark glass background
                VisualEffectBlur()
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    Divider()
                        .background(Color(nsColor: OpenWhisperPalette.mist).opacity(0.09))
                    skillList
                    Divider()
                        .background(Color(nsColor: OpenWhisperPalette.mist).opacity(0.09))
                    footer
                }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: OpenWhisperMetrics.radiusXXL, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OpenWhisperMetrics.radiusXXL, style: .continuous)
                    .stroke(Color(nsColor: OpenWhisperPalette.mist).opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 48, x: 0, y: 20)
            .frame(width: 640, height: 520)
            .scaleEffect(appeared ? 1.0 : (reduceMotion ? 1.0 : 0.96), anchor: .top)
            .animation(OpenWhisperMotion.panelSpring, value: appeared)
            .onAppear { appeared = true }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(nsColor: OpenWhisperPalette.mistMuted))
            TextField(
                L10n.text("Search Skills…"),
                text: $searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Color(nsColor: OpenWhisperPalette.mist))
            .tint(Color(nsColor: OpenWhisperPalette.brandBlue))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(nsColor: OpenWhisperPalette.mistMuted).opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Skill list

    private var skillList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if normalizedQuery.isEmpty {
                    currentSection
                    skillSection(title: L10n.text("Favorites"), entries: snapshot.favorites)
                    skillSection(title: L10n.text("Recent"), entries: snapshot.recent)
                    skillSection(title: L10n.text("Installed"), entries: snapshot.installed)
                } else if searchResults.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Color(nsColor: OpenWhisperPalette.mistMuted).opacity(0.4))
                        Text(L10n.text("No matching Skills"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(nsColor: OpenWhisperPalette.mistMuted).opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                } else {
                    skillSection(title: L10n.text("Results"), entries: searchResults)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Current section

    private var currentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader(L10n.text("Current"))
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(nsColor: OpenWhisperPalette.success).opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(nsColor: OpenWhisperPalette.success))
                }
                Text(snapshot.current.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: OpenWhisperPalette.mist))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(nsColor: OpenWhisperPalette.brandBlue).opacity(0.12),
                in: RoundedRectangle(cornerRadius: OpenWhisperMetrics.radiusL, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OpenWhisperMetrics.radiusL, style: .continuous)
                    .stroke(Color(nsColor: OpenWhisperPalette.brandBlue).opacity(0.22), lineWidth: 1)
            )
        }
        .padding(.bottom, 8)
    }

    // MARK: - Skill section

    @ViewBuilder
    private func skillSection(title: String, entries: [SkillMenuEntry]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionHeader(title)
                ForEach(entries) { entry in
                    skillRow(entry)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .textCase(.uppercase)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color(nsColor: OpenWhisperPalette.mistMuted).opacity(0.45))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }

    private func skillRow(_ entry: SkillMenuEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        entry.requiresSelection
                            ? Color(nsColor: OpenWhisperPalette.amber).opacity(0.14)
                            : Color(nsColor: OpenWhisperPalette.brandBlue).opacity(0.14)
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: entry.requiresSelection ? "selection.pin.in.out" : "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        entry.requiresSelection
                            ? Color(nsColor: OpenWhisperPalette.amber)
                            : Color(nsColor: OpenWhisperPalette.brandBlue)
                    )
            }
            Text(entry.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: OpenWhisperPalette.mist))
            Spacer(minLength: 8)
            Menu {
                if let bundleIdentifier = snapshot.currentApplicationBundleIdentifier {
                    Button(
                        L10n.format("Default for %@", snapshot.currentApplicationName ?? "")
                    ) {
                        onAction(.setApplicationDefault(
                            installationID: entry.installationID,
                            appName: snapshot.currentApplicationName,
                            bundleIdentifier: bundleIdentifier
                        ))
                    }
                }
                Button(L10n.text("Set as Global Default")) {
                    onAction(.setGlobalDefault(entry.installationID))
                }
                Button(
                    snapshot.favorites.contains { $0.installationID == entry.installationID }
                        ? L10n.text("Remove from Favorites")
                        : L10n.text("Add to Favorites")
                ) {
                    onAction(.toggleFavorite(entry.installationID))
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: OpenWhisperPalette.mistMuted).opacity(0.5))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            Button(L10n.text("Use")) {
                onAction(.useNext(entry.installationID))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(nsColor: OpenWhisperPalette.brandBlue))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Color(nsColor: OpenWhisperPalette.brandBlue).opacity(0.14),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(Color.white.opacity(0.001)) // hit-test
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(L10n.format("%ld installed", snapshot.installed.count))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color(nsColor: OpenWhisperPalette.mistMuted).opacity(0.45))
            Spacer()
            Button(L10n.text("Skill Library…")) {
                onOpenLibrary()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(nsColor: OpenWhisperPalette.mistMuted).opacity(0.6))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Visual effect background

private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.appearance = NSAppearance(named: .darkAqua)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(
            srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 0.94
        ).cgColor
        view.layer?.cornerRadius = OpenWhisperMetrics.radiusXXL
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
