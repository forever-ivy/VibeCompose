import AppKit

@MainActor
protocol StatusMenuUpdating: AnyObject {
    func update(state: StatusMenuVisualState, detail: String)
}

@MainActor
final class StatusMenuController: NSObject, StatusMenuUpdating {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stateItem = NSMenuItem(title: L10n.text("State: idle"), action: nil, keyEquivalent: "")
    private let detailItem = NSMenuItem(title: L10n.text("Ready"), action: nil, keyEquivalent: "")
    private let openHistoryHandler: () -> Void
    private let openQuickAddHandler: () -> Void
    private let openTerminologyHandler: () -> Void
    private let openSettingsHandler: () -> Void
    private let quitHandler: () -> Void

    init(
        openHistoryHandler: @escaping () -> Void,
        openQuickAddHandler: @escaping () -> Void,
        openTerminologyHandler: @escaping () -> Void,
        openSettingsHandler: @escaping () -> Void,
        quitHandler: @escaping () -> Void
    ) {
        self.openHistoryHandler = openHistoryHandler
        self.openQuickAddHandler = openQuickAddHandler
        self.openTerminologyHandler = openTerminologyHandler
        self.openSettingsHandler = openSettingsHandler
        self.quitHandler = quitHandler
        super.init()
        configureMenu()
        update(state: .ready, detail: L10n.text("Ready. Press F5 to dictate"))
    }

    func update(state: StatusMenuVisualState, detail: String) {
        if let button = statusItem.button {
            button.title = ""
            button.image = OpenWhisperStatusIconRenderer.image(for: state)
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(L10n.format("OpenWhisper %@", state.stateDescription))
            button.toolTip = L10n.format("OpenWhisper: %@", state.stateDescription)
        }

        stateItem.title = L10n.format("State: %@", state.stateDescription)
        detailItem.title = L10n.text(detail)
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
    private func quitApp() {
        quitHandler()
    }
}
