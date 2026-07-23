import AppKit
import SwiftUI

@MainActor
final class MicrophonePermissionWindowController: NSWindowController, NSWindowDelegate {
    private var completions: [(Bool) -> Void] = []

    init() {
        let view = MicrophonePermissionView(
            onContinue: {},
            onCancel: {}
        )
        let hostingController = NSHostingController(
            rootView:
                view.applyingVibeWhisperBrandTint()
                .applyingAccessibilityDisplayOptionsOverride(
                    .currentVisualAcceptance
                )
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("Enable Microphone Access")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentMinSize = NSSize(width: 520, height: 180)
        window.contentMaxSize = NSSize(width: 520, height: 180)
        window.center()
        window.level = .normal
        window.contentViewController = hostingController
        AccessibilityDisplayOptionsOverride.currentVisualAcceptance
            .applyAppearance(to: window)

        super.init(window: window)

        hostingController.rootView =
            MicrophonePermissionView(
                onContinue: { [weak self] in
                    self?.finish(with: true)
                },
                onCancel: { [weak self] in
                    self?.finish(with: false)
                }
            )
            .applyingVibeWhisperBrandTint()
            .applyingAccessibilityDisplayOptionsOverride(
                .currentVisualAcceptance
            )
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() async -> Bool {
        await withCheckedContinuation { continuation in
            completions.append { decision in
                continuation.resume(returning: decision)
            }
            if completions.count == 1 {
                show()
            }
        }
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        finish(with: false)
    }

    private func finish(with decision: Bool) {
        guard !completions.isEmpty else {
            return
        }

        let completions = self.completions
        self.completions.removeAll()
        window?.orderOut(nil)
        completions.forEach { completion in
            completion(decision)
        }
    }
}

private struct MicrophonePermissionView: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                VibeWhisperIconWell(
                    systemName: "mic.fill",
                    size: 44,
                    symbolSize: 18
                )
                Text(L10n.text("Allow microphone access"))
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.3)
                    .accessibilityHint(
                        L10n.text(
                            "VibeWhisper needs microphone access before it can record your first dictation."
                        )
                    )
            }

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button(L10n.text("Cancel"), action: onCancel)
                    .buttonStyle(VibeWhisperSecondaryButtonStyle())
                Button(L10n.text("Continue"), action: onContinue)
                    .buttonStyle(VibeWhisperPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520, height: 180, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
