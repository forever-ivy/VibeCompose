import AppKit
import AVFoundation
import ApplicationServices
import SwiftUI

enum PreferencesSnapshotError: LocalizedError {
    case missingContentView
    case bitmapUnavailable
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingContentView:
            return "The VibeCompose Settings window has no content view to capture."
        case .bitmapUnavailable:
            return "The VibeCompose Settings window could not create a bitmap snapshot."
        case .pngEncodingFailed:
            return "The VibeCompose Settings window could not encode its snapshot as PNG."
        }
    }
}

/// Main-actor bridge so NotificationCenter can deliver a full AppConfig into
/// SwiftUI without encoding it in userInfo.
@MainActor
final class PreferencesLiveConfigBridge {
    static let shared = PreferencesLiveConfigBridge()
    private(set) var latest: AppConfig?
    private(set) var forceReplace = false

    func publish(
        _ config: AppConfig,
        forceReplace: Bool = false
    ) {
        latest = config
        self.forceReplace = forceReplace
    }

    func consume() -> (AppConfig, Bool)? {
        guard let value = latest else {
            return nil
        }
        let force = forceReplace
        latest = nil
        forceReplace = false
        return (value, force)
    }
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    private var sidebarArrowKeyMonitor: Any?

    init(
        config: AppConfig,
        authManager: ChatGPTAuthManager,
        onSave: @escaping (AppConfig) -> Result<Void, any Error>,
        onImportTerminologyDictionary: @escaping (AppConfig, URL) -> Result<AppConfig, any Error>,
        onLoadRecentHistory: @escaping @Sendable () async -> [TranscriptionHistoryRecord],
        onLoadRecoveryHistory: @escaping @Sendable () async -> [RecoveryRecord],
        onResolveRecoveryAudioURL: @escaping (RecoveryRecord) -> Result<URL, any Error>,
        onRetryRecoveryRecord: @escaping (RecoveryRecord) -> Void,
        onRequestMicrophoneAccess: @escaping @MainActor @Sendable () async -> Result<Void, any Error>,
        onOpenConfigFolder: @escaping () -> Void,
        onExportSupportDiagnostics: @escaping (URL) -> Result<URL, any Error>,
        onExportProductMetrics: @escaping (URL) -> Result<URL, any Error>,
        providerCapabilityPolicy: any ProviderCapabilityChecking,
        recoveryCredentialStore: any OpenAICompatibleCredentialPersisting,
        textPolishUsageDirectoryURL: URL? = ProductIdentity
            .applicationSupportURL(
                homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
            ),
        softwareUpdateSnapshot: SoftwareUpdateSnapshot,
        onCheckForUpdates: @escaping () -> Result<Void, SoftwareUpdateError>,
        onSetAutomaticallyChecksForUpdates: @escaping (Bool) -> Result<SoftwareUpdateSnapshot, SoftwareUpdateError>,
        onDeleteAllData: @escaping () -> Result<AppConfig, any Error>,
        onOpenOnboarding: @escaping () -> Void,
        onOpenSkillLibrary: @escaping () -> Void,
        onOpenTerminology: @escaping () -> Void,
        onLoadFullTranscriptionHistory: @escaping @Sendable () async -> [TranscriptionHistoryRecord] = { [] },
        onLoadFullRecoveryHistory: @escaping @Sendable () async -> [RecoveryRecord] = { [] },
        onCanUndoTranscriptionRecord: @escaping (UUID) -> Bool = { _ in false },
        onUndoTranscriptionRecord: @escaping (UUID) async -> SafeUndoOutcome = { _ in .unavailable },
        onDeleteTranscriptionRecord: @escaping (UUID) -> Result<Void, any Error> = { _ in .success(()) },
        onDeleteRecoveryRecord: @escaping (UUID) -> Result<Void, any Error> = { _ in .success(()) },
        onRunSkillTest: @escaping (SkillTestRunRequest) async -> Result<SkillTestRunResult, any Error> = { _ in
            .failure(SkillTestRunError.appBusy)
        },
        onVoiceSampleAction: @escaping (SkillVoiceSampleAction) async -> Result<SkillVoiceSampleResult, any Error> = { _ in
            .failure(SkillTestRunError.appBusy)
        },
        onHotkeyCaptureChanged:
            @escaping (Bool) -> Void = { _ in },
        onPreviewVisualFeedback:
            @escaping (
                VisualFeedbackPreview,
                VisualFeedbackConfig
            ) -> Void = { _, _ in },
        skillPackageStore:
            SkillPackageStore = .init(),
        styleCapsuleStore:
            StyleCapsuleStore = .init(),
        localAssetAccessEnabled:
            Bool = true,
        focusPane: SettingsPane? = nil,
        skillLibraryInitialSection:
            SkillLibrarySection = .discover
    ) {
        let view = PreferencesView(
            initialConfig: config,
            authManager: authManager,
            onSave: onSave,
            onImportTerminologyDictionary: onImportTerminologyDictionary,
            onLoadRecentHistory: onLoadRecentHistory,
            onLoadRecoveryHistory: onLoadRecoveryHistory,
            onResolveRecoveryAudioURL: onResolveRecoveryAudioURL,
            onRetryRecoveryRecord: onRetryRecoveryRecord,
            onRequestMicrophoneAccess: onRequestMicrophoneAccess,
            onOpenConfigFolder: onOpenConfigFolder,
            onExportSupportDiagnostics: onExportSupportDiagnostics,
            onExportProductMetrics: onExportProductMetrics,
            providerCapabilityPolicy: providerCapabilityPolicy,
            recoveryCredentialStore: recoveryCredentialStore,
            textPolishUsageDirectoryURL: textPolishUsageDirectoryURL,
            softwareUpdateSnapshot: softwareUpdateSnapshot,
            onCheckForUpdates: onCheckForUpdates,
            onSetAutomaticallyChecksForUpdates: onSetAutomaticallyChecksForUpdates,
            onDeleteAllData: onDeleteAllData,
            onOpenOnboarding: onOpenOnboarding,
            onOpenSkillLibrary:
                onOpenSkillLibrary,
            onOpenTerminology:
                onOpenTerminology,
            onLoadFullTranscriptionHistory:
                onLoadFullTranscriptionHistory,
            onLoadFullRecoveryHistory:
                onLoadFullRecoveryHistory,
            onCanUndoTranscriptionRecord:
                onCanUndoTranscriptionRecord,
            onUndoTranscriptionRecord:
                onUndoTranscriptionRecord,
            onDeleteTranscriptionRecord:
                onDeleteTranscriptionRecord,
            onDeleteRecoveryRecord:
                onDeleteRecoveryRecord,
            onRunSkillTest: onRunSkillTest,
            onVoiceSampleAction: onVoiceSampleAction,
            onHotkeyCaptureChanged:
                onHotkeyCaptureChanged,
            onPreviewVisualFeedback:
                onPreviewVisualFeedback,
            skillPackageStore:
                skillPackageStore,
            styleCapsuleStore:
                styleCapsuleStore,
            localAssetAccessEnabled:
                localAssetAccessEnabled,
            focusPane: focusPane,
            skillLibraryInitialSection:
                skillLibraryInitialSection
        )
        .applyingAccessibilityDisplayOptionsOverride(
            .currentVisualAcceptance
        )
        let hostingController = NSHostingController(rootView: view)
        // Keep the hosting plate fully transparent so Liquid Glass corners are
        // not backfilled by a rectangular NSView layer (the source of the
        // light square nubs at the floating sidebar corners).
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        if #available(macOS 11, *) {
            hostingController.view.layerContentsRedrawPolicy = .onSetNeedsDisplay
        }

        let window = CommandClosingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
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
        window.title = ProductIdentity.name
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // Empty unified toolbar reserves the system titlebar strip and keeps
        // traffic lights in the standard slot so the floating glass sidebar
        // can extend under them (Music / App Store treatment).
        window.toolbarStyle = .unified
        window.hasShadow = true
        // Transparent content so the floating glass rail's continuous corners
        // are not backfilled by a solid window plate.
        window.isOpaque = false
        window.backgroundColor = .clear
        // The Settings shell never enters full screen (its fixed sidebar
        // layout is not designed for it), so the zoom control stays disabled.
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.formUnion([.managed, .fullScreenDisallowsTiling])
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        let settingsToolbar = NSToolbar(
            identifier: "VibeCompose.SettingsToolbar"
        )
        settingsToolbar.displayMode = .iconOnly
        settingsToolbar.allowsUserCustomization = false
        settingsToolbar.autosavesConfiguration = false
        settingsToolbar.showsBaselineSeparator = false
        window.toolbar = settingsToolbar
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("VibeCompose.SettingsWindow")
        window.minSize = NSSize(width: 900, height: 620)
        window.tabbingMode = .disallowed
        let restoredFrame = window.setFrameUsingName(SettingsWindowStateStore.frameAutosaveName)
        window.setFrameAutosaveName(SettingsWindowStateStore.frameAutosaveName)
        if !restoredFrame {
            window.center()
        }
        window.contentViewController = hostingController
        AccessibilityDisplayOptionsOverride.currentVisualAcceptance
            .applyAppearance(to: window)

        super.init(window: window)

        // Keep traffic lights in the system leading slot (Apple HIG). Never
        // re-center them over the rail — that pushes them mid/right and
        // accumulates on every show. Re-assert after first layout in case a
        // prior session left the titlebar container shifted.
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            Self.restoreSystemTrafficLightPlacement(in: window)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsWindowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )

        sidebarArrowKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard let self else {
                return event
            }
            return handleSidebarArrowKey(event)
        }
    }

    isolated deinit {
        if let sidebarArrowKeyMonitor {
            NSEvent.removeMonitor(sidebarArrowKeyMonitor)
        }
        NotificationCenter.default.removeObserver(self)
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
            Self.restoreSystemTrafficLightPlacement(in: window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc
    private func settingsWindowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Self.restoreSystemTrafficLightPlacement(in: window)
    }

    /// Pins the titlebar container to the system leading edge so close /
    /// miniaturize / zoom stay in their standard HIG slot (≈19pt from the
    /// window leading edge, 14×14, ~9pt gaps). Music / App Store float the
    /// glass rail *under* these widgets — they never center the widgets on
    /// the rail. Uses absolute origin so repeated calls never accumulate.
    private static func restoreSystemTrafficLightPlacement(in window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let titlebarContainer = closeButton.superview?.superview
        else {
            return
        }
        // Absolute reset — previous builds used `+= delta` which walked the
        // lights toward the trailing edge on every show / layout pass.
        if abs(titlebarContainer.frame.origin.x) > 0.5 {
            var frame = titlebarContainer.frame
            frame.origin.x = 0
            titlebarContainer.frame = frame
        }
        // Keep the three system widgets enabled/visible in standard order.
        // Zoom stays disabled (fixed-layout Settings shell) but remains in slot.
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }

    func navigate(
        to pane: SettingsPane,
        skillLibrarySection: SkillLibrarySection? = nil
    ) {
        if let skillLibrarySection {
            SettingsWindowStateStore().saveSkillLibrarySection(
                skillLibrarySection
            )
        }
        var userInfo: [String: String] = [
            "pane": pane.rawValue,
        ]
        if let skillLibrarySection {
            userInfo["skillLibrarySection"] =
                skillLibrarySection.rawValue
        }
        NotificationCenter.default.post(
            name: .vibeComposeNavigateSettingsPane,
            object: nil,
            userInfo: userInfo
        )
        show()
    }

    /// Push a coordinator-side config commit into the open Settings draft.
    /// Uses 3-way merge so dirty local fields are not clobbered unless
    /// `forceReplace` (e.g. delete-all) replaces the draft entirely.
    func applyLiveConfig(
        _ live: AppConfig,
        forceReplace: Bool = false
    ) {
        PreferencesLiveConfigBridge.shared.publish(
            live,
            forceReplace: forceReplace
        )
        NotificationCenter.default.post(
            name: .vibeComposeLiveConfigDidChange,
            object: nil
        )
    }

    /// The custom sidebar rows (unlike the previous stock `List`) do not come
    /// with built-in arrow-key navigation, so the window reproduces the native
    /// source-list behavior here: Up/Down moves the sidebar selection unless a
    /// text editor, control, or collection view owns the key event.
    private func handleSidebarArrowKey(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else {
            return event
        }
        guard event.keyCode == 126 || event.keyCode == 125 else {
            return event
        }
        let modifiers = event.modifierFlags.intersection(
            .deviceIndependentFlagsMask
        )
        guard modifiers.isDisjoint(with: [.command, .option, .control]) else {
            return event
        }
        if let responder = window.firstResponder, responder !== window {
            let responderOwnsArrows =
                responder is NSTextView
                || responder is NSControl
                || responder is NSCollectionView
            if responderOwnsArrows {
                return event
            }
        }

        // Walk the visible product panes in sidebar order. Filtering by the
        // live search field lives in PreferencesView; arrow navigation still
        // covers the full visible catalog so focus never stalls on an empty
        // filtered set mid-type.
        let orderedPanes = SettingsSidebarGroup.allCases
            .flatMap(\.panes)
            .filter { SettingsPane.visiblePanes.contains($0) }
        guard !orderedPanes.isEmpty else {
            return event
        }
        let currentPane = SettingsWindowStateStore()
            .initialPane(focusedPane: nil)
        let currentIndex =
            orderedPanes.firstIndex(of: currentPane) ?? 0
        let nextIndex =
            event.keyCode == 126
            ? max(0, currentIndex - 1)
            : min(orderedPanes.count - 1, currentIndex + 1)
        guard nextIndex != currentIndex else {
            return nil
        }
        NotificationCenter.default.post(
            name: .vibeComposeNavigateSettingsPane,
            object: nil,
            userInfo: ["pane": orderedPanes[nextIndex].rawValue]
        )
        return nil
    }

    func writeSnapshot(to url: URL) throws {
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.displayIfNeeded()
        try ProductSurfaceSnapshot.write(window: window, to: url)
    }

    func resizeForSnapshot(_ size: SettingsSnapshotSize) {
        window?.setContentSize(
            NSSize(width: CGFloat(size.width), height: CGFloat(size.height))
        )
        window?.center()
    }
}

private final class CommandClosingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isCommandW = event.type == .keyDown
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "w"

        if isCommandW {
            close()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
