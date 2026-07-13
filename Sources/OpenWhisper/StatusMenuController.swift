import AppKit

@MainActor
protocol StatusMenuUpdating: AnyObject {
    func update(state: StatusMenuVisualState, detail: String)
    func updateDictationHotkey(_ binding: HotkeyBinding)
    func setManualDictationAvailable(_ available: Bool)
    func setToggleDictationHandler(
        _ handler: @escaping () -> Void
    )
    func setRetryDictationAvailable(
        _ available: Bool
    )
    func setRetryDictationHandler(
        _ handler: @escaping () -> Void
    )
}

extension StatusMenuUpdating {
    func updateDictationHotkey(_ binding: HotkeyBinding) {
        _ = binding
    }

    func setManualDictationAvailable(_ available: Bool) {
        _ = available
    }

    func setToggleDictationHandler(
        _ handler: @escaping () -> Void
    ) {
        _ = handler
    }

    func setRetryDictationAvailable(
        _ available: Bool
    ) {
        _ = available
    }

    func setRetryDictationHandler(
        _ handler: @escaping () -> Void
    ) {
        _ = handler
    }
}

@MainActor
final class StatusMenuController: NSObject, StatusMenuUpdating {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stateItem = NSMenuItem(title: L10n.text("State: idle"), action: nil, keyEquivalent: "")
    private let detailItem = NSMenuItem(title: L10n.text("Ready"), action: nil, keyEquivalent: "")
    private let dictationItem = NSMenuItem(
        title: "",
        action: #selector(toggleDictation),
        keyEquivalent: ""
    )
    private let retryDictationItem = NSMenuItem(
        title: L10n.text("Retry last dictation"),
        action: #selector(retryDictation),
        keyEquivalent: ""
    )
    private var toggleDictationHandler: () -> Void
    private var retryDictationHandler: () -> Void
    private var dictationHotkey = HotkeyBinding.f5
    private var currentState:
        StatusMenuVisualState = .ready
    private var manualDictationAvailable = false
    private let openHistoryHandler: () -> Void
    private let openQuickAddHandler: () -> Void
    private let openTerminologyHandler: () -> Void
    private let openSettingsHandler: () -> Void
    private let checkForUpdatesHandler: () -> Void
    private let quitHandler: () -> Void

    init(
        toggleDictationHandler: @escaping () -> Void = {},
        retryDictationHandler: @escaping () -> Void = {},
        openHistoryHandler: @escaping () -> Void,
        openQuickAddHandler: @escaping () -> Void,
        openTerminologyHandler: @escaping () -> Void,
        openSettingsHandler: @escaping () -> Void,
        checkForUpdatesHandler: @escaping () -> Void,
        quitHandler: @escaping () -> Void
    ) {
        self.toggleDictationHandler = toggleDictationHandler
        self.retryDictationHandler =
            retryDictationHandler
        self.openHistoryHandler = openHistoryHandler
        self.openQuickAddHandler = openQuickAddHandler
        self.openTerminologyHandler = openTerminologyHandler
        self.openSettingsHandler = openSettingsHandler
        self.checkForUpdatesHandler = checkForUpdatesHandler
        self.quitHandler = quitHandler
        super.init()
        configureMenu()
        updateDictationHotkey(.f5)
        update(
            state: .ready,
            detail: L10n.format(
                "Ready. Press %@ to dictate",
                HotkeyBinding.f5.displayName
            )
        )
    }

    func update(state: StatusMenuVisualState, detail: String) {
        currentState = state
        if let button = statusItem.button {
            button.title = ""
            button.image = OpenWhisperStatusIconRenderer.image(for: state)
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(L10n.format("OpenWhisper %@", state.stateDescription))
            button.toolTip = L10n.format("OpenWhisper: %@", state.stateDescription)
        }

        stateItem.title = L10n.format("State: %@", state.stateDescription)
        detailItem.title = L10n.text(detail)
        refreshDictationItem()
    }

    func updateDictationHotkey(_ binding: HotkeyBinding) {
        dictationHotkey = binding
        refreshDictationItem()
        dictationItem.setAccessibilityLabel(
            L10n.format(
                "Start or stop dictation with %@",
                binding.displayName
            )
        )
    }

    func setManualDictationAvailable(_ available: Bool) {
        manualDictationAvailable = available
        refreshDictationItem()
    }

    func setToggleDictationHandler(
        _ handler: @escaping () -> Void
    ) {
        toggleDictationHandler = handler
    }

    func setRetryDictationAvailable(
        _ available: Bool
    ) {
        retryDictationItem.isEnabled = available
    }

    func setRetryDictationHandler(
        _ handler: @escaping () -> Void
    ) {
        retryDictationHandler = handler
    }

    private func configureMenu() {
        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        let menu = NSMenu()
        menu.addItem(stateItem)
        menu.addItem(detailItem)
        dictationItem.target = self
        menu.addItem(dictationItem)
        retryDictationItem.target = self
        retryDictationItem.isEnabled = false
        retryDictationItem.setAccessibilityLabel(
            L10n.text("Retry last dictation")
        )
        menu.addItem(retryDictationItem)
        menu.addItem(.separator())

        let historyItem = NSMenuItem(
            title: L10n.text("History…"),
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        historyItem.target = self
        menu.addItem(historyItem)

        let quickAddItem = NSMenuItem(
            title: L10n.text("Quick Add…"),
            action: #selector(openQuickAdd),
            keyEquivalent: " "
        )
        quickAddItem.keyEquivalentModifierMask = [.control, .option]
        quickAddItem.target = self
        menu.addItem(quickAddItem)

        let terminologyItem = NSMenuItem(
            title: L10n.text("Terminology…"),
            action: #selector(openTerminology),
            keyEquivalent: ""
        )
        terminologyItem.target = self
        menu.addItem(terminologyItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: L10n.text("Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(
            title: L10n.text("Check for Updates…"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.text("Quit OpenWhisper"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc
    private func toggleDictation() {
        toggleDictationHandler()
    }

    @objc
    private func retryDictation() {
        retryDictationHandler()
    }

    private func refreshDictationItem() {
        switch currentState {
        case .recording:
            dictationItem.title = L10n.format(
                "Stop dictation — %@",
                dictationHotkey.displayName
            )
            dictationItem.isEnabled =
                manualDictationAvailable
        case .processing:
            dictationItem.title = L10n.text(
                "Dictation is processing"
            )
            dictationItem.isEnabled = false
        case .ready,
             .setupRequired,
             .error,
             .demo:
            dictationItem.title = L10n.format(
                "Start dictation — %@",
                dictationHotkey.displayName
            )
            dictationItem.isEnabled =
                manualDictationAvailable
        }
    }

    @objc
    private func openHistory() {
        openHistoryHandler()
    }

    @objc
    private func openQuickAdd() {
        openQuickAddHandler()
    }

    @objc
    private func openTerminology() {
        openTerminologyHandler()
    }

    @objc
    private func openSettings() {
        openSettingsHandler()
    }

    @objc
    private func checkForUpdates() {
        checkForUpdatesHandler()
    }

    @objc
    private func quitApp() {
        quitHandler()
    }
}
