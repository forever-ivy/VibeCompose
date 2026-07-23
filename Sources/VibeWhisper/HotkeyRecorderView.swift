import AppKit
import Carbon
import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    let binding: HotkeyBinding
    let onCandidate:
        @MainActor (HotkeyBinding) -> Void
    let onCaptureChanged:
        @MainActor (Bool) -> Void

    func makeNSView(
        context: Context
    ) -> HotkeyRecorderButton {
        let button = HotkeyRecorderButton()
        button.onCandidate = onCandidate
        button.onCaptureChanged = onCaptureChanged
        button.binding = binding
        return button
    }

    func updateNSView(
        _ nsView: HotkeyRecorderButton,
        context: Context
    ) {
        nsView.onCandidate = onCandidate
        nsView.onCaptureChanged = onCaptureChanged
        if !nsView.isCapturing {
            nsView.binding = binding
        }
    }
}

@MainActor
final class HotkeyRecorderButton: NSButton {
    var binding: HotkeyBinding = .f5 {
        didSet {
            updateTitle()
        }
    }
    var onCandidate:
        (@MainActor (HotkeyBinding) -> Void)?
    var onCaptureChanged:
        (@MainActor (Bool) -> Void)?
    private(set) var isCapturing = false

    override var acceptsFirstResponder: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        // Prefer the SwiftUI frame from settings forms (aligned control cluster).
        NSSize(width: GeneralSettingsChrome.recorderWidth, height: GeneralSettingsChrome.controlHeight)
    }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginCapture)
        focusRingType = .default
        font = .monospacedSystemFont(
            ofSize: 12,
            weight: .medium
        )
        setAccessibilityRole(.button)
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        guard !event.isARepeat else {
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            finishCapture()
            return
        }

        let candidate = HotkeyBinding.from(event: event)
        finishCapture()
        onCandidate?(candidate)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, isCapturing {
            finishCapture()
        }
        return resigned
    }

    @objc
    private func beginCapture() {
        guard !isCapturing else {
            return
        }
        isCapturing = true
        updateTitle()
        window?.makeFirstResponder(self)
        onCaptureChanged?(true)
    }

    private func finishCapture() {
        guard isCapturing else {
            return
        }
        isCapturing = false
        updateTitle()
        onCaptureChanged?(false)
    }

    private func updateTitle() {
        if isCapturing {
            title = L10n.text(
                "Press a shortcut… Esc cancels"
            )
            setAccessibilityLabel(
                L10n.text(
                    "Recording a new dictation shortcut"
                )
            )
            setAccessibilityHelp(
                L10n.text(
                    "Press the shortcut to use, or press Esc to cancel."
                )
            )
        } else {
            title = binding.displayName
            setAccessibilityLabel(
                L10n.format(
                    "Dictation shortcut: %@",
                    binding.displayName
                )
            )
            setAccessibilityHelp(
                L10n.text(
                    "Click to record a new global dictation shortcut."
                )
            )
        }
    }
}
