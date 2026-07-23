import AppKit

@MainActor
protocol StatusMenuUpdating: AnyObject {
    func update(state: StatusMenuVisualState, detail: String)
    func updateDictationHotkey(_ binding: HotkeyBinding)
    func updateSkillSwitcherHotkey(_ binding: HotkeyBinding?)
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
    func setUndoLastInsertionAvailable(_ available: Bool)
    func setUndoLastInsertionHandler(
        _ handler: @escaping () -> Void
    )
    func updateSkillMenu(_ snapshot: SkillMenuSnapshot)
    func setSkillMenuActionHandler(
        _ handler: @escaping (SkillMenuAction) -> Void
    )
    func setRefreshSkillMenuHandler(
        _ handler: @escaping () -> Void
    )
    func setOpenSkillLibraryHandler(
        _ handler: @escaping () -> Void
    )
    func setOpenSkillSwitcherHandler(
        _ handler: @escaping () -> Void
    )
    func setSoftwareUpdateAvailable(_ available: Bool)
    func reloadLocalization()
}

extension StatusMenuUpdating {
    func updateDictationHotkey(_ binding: HotkeyBinding) {
        _ = binding
    }

    func updateSkillSwitcherHotkey(_ binding: HotkeyBinding?) {
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

    func setUndoLastInsertionAvailable(_ available: Bool) {
        _ = available
    }

    func setUndoLastInsertionHandler(
        _ handler: @escaping () -> Void
    ) {
        _ = handler
    }

    func updateSkillMenu(_ snapshot: SkillMenuSnapshot) {
        _ = snapshot
    }

    func setSkillMenuActionHandler(
        _ handler: @escaping (SkillMenuAction) -> Void
    ) {
        _ = handler
    }

    func setRefreshSkillMenuHandler(
        _ handler: @escaping () -> Void
    ) {
        _ = handler
    }

    func setOpenSkillLibraryHandler(
        _ handler: @escaping () -> Void
    ) {
        _ = handler
    }

    func setOpenSkillSwitcherHandler(
        _ handler: @escaping () -> Void
    ) {
        _ = handler
    }

    func setSoftwareUpdateAvailable(_ available: Bool) {
        _ = available
    }

    func reloadLocalization() {}
}

@MainActor
final class StatusMenuController: NSObject, StatusMenuUpdating, NSMenuDelegate {
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
    private let undoLastInsertionItem = NSMenuItem(
        title: L10n.text("Undo Last Verified Insertion"),
        action: #selector(undoLastInsertion),
        keyEquivalent: ""
    )
    private let skillItem = NSMenuItem(
        title: L10n.text("Current Skill"),
        action: nil,
        keyEquivalent: ""
    )
    private var toggleDictationHandler: () -> Void
    private var retryDictationHandler: () -> Void
    private var undoLastInsertionHandler: () -> Void = {}
    private var skillMenuActionHandler:
        (SkillMenuAction) -> Void = { _ in }
    private var refreshSkillMenuHandler: () -> Void = {}
    private var openSkillLibraryHandler: () -> Void = {}
    private var openSkillSwitcherHandler: () -> Void = {}
    private var skillMenuSnapshot: SkillMenuSnapshot?
    private var dictationHotkey = HotkeyBinding.f5
    private var skillSwitcherHotkey: HotkeyBinding?
    private var currentState:
        StatusMenuVisualState = .ready
    private var manualDictationAvailable = false
    private var undoLastInsertionAvailable = false
    private var softwareUpdateAvailable = false
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
            button.image = VibeWhisperStatusIconRenderer.image(for: state)
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(L10n.format("VibeWhisper %@", state.stateDescription))
            button.toolTip = L10n.format("VibeWhisper: %@", state.stateDescription)
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

    func updateSkillSwitcherHotkey(_ binding: HotkeyBinding?) {
        skillSwitcherHotkey = binding
        refreshSkillMenu()
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

    func setUndoLastInsertionAvailable(_ available: Bool) {
        undoLastInsertionAvailable = available
        undoLastInsertionItem.isEnabled = available
    }

    func setUndoLastInsertionHandler(
        _ handler: @escaping () -> Void
    ) {
        undoLastInsertionHandler = handler
    }

    func updateSkillMenu(_ snapshot: SkillMenuSnapshot) {
        skillMenuSnapshot = snapshot
        refreshSkillMenu()
    }

    func setSkillMenuActionHandler(
        _ handler: @escaping (SkillMenuAction) -> Void
    ) {
        skillMenuActionHandler = handler
    }

    func setRefreshSkillMenuHandler(
        _ handler: @escaping () -> Void
    ) {
        refreshSkillMenuHandler = handler
    }

    func setOpenSkillLibraryHandler(
        _ handler: @escaping () -> Void
    ) {
        openSkillLibraryHandler = handler
    }

    func setOpenSkillSwitcherHandler(
        _ handler: @escaping () -> Void
    ) {
        openSkillSwitcherHandler = handler
    }

    func setSoftwareUpdateAvailable(_ available: Bool) {
        softwareUpdateAvailable = available
        configureMenu()
    }

    func reloadLocalization() {
        stateItem.title = L10n.format(
            "State: %@",
            currentState.stateDescription
        )
        detailItem.title = L10n.format(
            "Ready. Press %@ to dictate",
            dictationHotkey.displayName
        )
        retryDictationItem.title = L10n.text(
            "Retry last dictation"
        )
        retryDictationItem.setAccessibilityLabel(
            L10n.text("Retry last dictation")
        )
        undoLastInsertionItem.title = L10n.text(
            "Undo Last Verified Insertion"
        )
        undoLastInsertionItem.setAccessibilityLabel(
            undoLastInsertionItem.title
        )
        configureMenu()
        refreshSkillMenu()
        refreshDictationItem()
        if let button = statusItem.button {
            button.setAccessibilityLabel(
                L10n.format(
                    "VibeWhisper %@",
                    currentState.stateDescription
                )
            )
            button.toolTip = L10n.format(
                "VibeWhisper: %@",
                currentState.stateDescription
            )
        }
    }

    private func configureMenu() {
        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        // The persistent items above can only belong to one NSMenu at a time.
        // Language changes rebuild the localized menu, so detach every item
        // before inserting those instances again. Creating a second menu while
        // the status item still owns the first one raises an AppKit exception.
        let menu = statusItem.menu ?? NSMenu()
        menu.removeAllItems()
        menu.delegate = self
        menu.addItem(stateItem)
        menu.addItem(detailItem)
        menu.addItem(skillItem)
        dictationItem.target = self
        menu.addItem(dictationItem)
        retryDictationItem.target = self
        retryDictationItem.isEnabled = false
        retryDictationItem.setAccessibilityLabel(
            L10n.text("Retry last dictation")
        )
        menu.addItem(retryDictationItem)
        undoLastInsertionItem.target = self
        undoLastInsertionItem.isEnabled =
            undoLastInsertionAvailable
        undoLastInsertionItem.setAccessibilityLabel(
            L10n.text("Undo Last Verified Insertion")
        )
        menu.addItem(undoLastInsertionItem)
        menu.addItem(.separator())

        let skillLibraryItem = NSMenuItem(
            title: L10n.text("Skill Library…"),
            action: #selector(openSkillLibrary),
            keyEquivalent: ""
        )
        skillLibraryItem.target = self
        menu.addItem(skillLibraryItem)

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

        if softwareUpdateAvailable {
            let updateItem = NSMenuItem(
                title: L10n.text("Check for Updates…"),
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
            updateItem.target = self
            menu.addItem(updateItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.text("Quit VibeWhisper"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshSkillMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        refreshSkillMenuHandler()
    }

    private func refreshSkillMenu() {
        guard let snapshot = skillMenuSnapshot else {
            skillItem.title = L10n.text("Current Skill")
            skillItem.submenu = nil
            skillItem.isEnabled = false
            return
        }
        skillItem.isEnabled = true
        skillItem.title = L10n.format(
            "Current Skill: %@ · %@",
            snapshot.current.displayName,
            snapshot.resolutionLabel
        )
        skillItem.setAccessibilityLabel(skillItem.title)
        let submenu = NSMenu()

        let current = NSMenuItem(
            title: L10n.format(
                "%@ · %@",
                snapshot.current.displayName,
                snapshot.current.sourceLabel
            ),
            action: nil,
            keyEquivalent: ""
        )
        current.state = .on
        submenu.addItem(current)

        let openSwitcher = NSMenuItem(
            title: skillSwitcherHotkey.map {
                L10n.format(
                    "Search and Choose… — %@",
                    $0.displayName
                )
            } ?? L10n.text("Search and Choose…"),
            action: #selector(openSkillSwitcher),
            keyEquivalent: ""
        )
        openSwitcher.target = self
        submenu.addItem(openSwitcher)

        // Favorites and next-use override are retired from the product chrome.
        addSkillSection(
            title: L10n.text("Recent"),
            entries: snapshot.recent,
            snapshot: snapshot,
            to: submenu
        )
        addSkillSection(
            title: L10n.text("Installed"),
            entries: snapshot.installed,
            snapshot: snapshot,
            to: submenu
        )
        skillItem.submenu = submenu
    }

    private func addSkillSection(
        title: String,
        entries: [SkillMenuEntry],
        snapshot: SkillMenuSnapshot,
        to menu: NSMenu
    ) {
        guard !entries.isEmpty else { return }
        menu.addItem(.separator())
        let header = NSMenuItem(
            title: title,
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        for entry in entries {
            let marker = entry.requiresSelection
                ? L10n.text(" · needs selection")
                : ""
            let item = NSMenuItem(
                title: entry.displayName + marker,
                action: nil,
                keyEquivalent: ""
            )
            item.toolTip = entry.summary
            item.representedObject = entry.installationID.uuidString
            item.submenu = actionsMenu(
                for: entry,
                snapshot: snapshot
            )
            menu.addItem(item)
        }
    }

    private func actionsMenu(
        for entry: SkillMenuEntry,
        snapshot: SkillMenuSnapshot
    ) -> NSMenu {
        let menu = NSMenu()
        if snapshot.currentApplicationName != nil {
            menu.addItem(actionItem(
                title: L10n.format(
                    "Default for %@",
                    snapshot.currentApplicationName ?? ""
                ),
                selector: #selector(setApplicationDefault(_:)),
                installationID: entry.installationID
            ))
        }
        menu.addItem(actionItem(
            title: L10n.text("Set as Global Default"),
            selector: #selector(setGlobalDefault(_:)),
            installationID: entry.installationID
        ))
        return menu
    }

    private func actionItem(
        title: String,
        selector: Selector,
        installationID: UUID
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: selector,
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = installationID.uuidString
        return item
    }

    private func installationID(
        from sender: NSMenuItem
    ) -> UUID? {
        (sender.representedObject as? String)
            .flatMap(UUID.init(uuidString:))
    }

    @objc private func setApplicationDefault(_ sender: NSMenuItem) {
        guard
            let id = installationID(from: sender),
            let snapshot = skillMenuSnapshot,
            let bundleIdentifier =
                snapshot.currentApplicationBundleIdentifier
        else { return }
        skillMenuActionHandler(
            .setApplicationDefault(
                installationID: id,
                appName: snapshot.currentApplicationName,
                bundleIdentifier: bundleIdentifier
            )
        )
    }

    @objc private func setGlobalDefault(_ sender: NSMenuItem) {
        guard let id = installationID(from: sender) else { return }
        skillMenuActionHandler(.setGlobalDefault(id))
    }

    @objc
    private func toggleDictation() {
        toggleDictationHandler()
    }

    @objc
    private func retryDictation() {
        retryDictationHandler()
    }

    @objc
    private func undoLastInsertion() {
        undoLastInsertionHandler()
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
    private func openSkillLibrary() {
        openSkillLibraryHandler()
    }

    @objc
    private func openSkillSwitcher() {
        openSkillSwitcherHandler()
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
