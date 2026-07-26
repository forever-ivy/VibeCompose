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
                view.applyingVibeComposeBrandTint()
                .applyingAccessibilityDisplayOptionsOverride(
                    .currentVisualAcceptance
                )
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("Enable Microphone Access")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentMinSize = NSSize(width: 520, height: 200)
        window.contentMaxSize = NSSize(width: 560, height: 320)
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
            .applyingVibeComposeBrandTint()
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

    private var bodyCopy: String {
        L10n.text(
            "VibeCompose needs microphone access before it can record your first dictation. Click Continue and macOS should show the microphone permission prompt next."
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VibeComposeMetrics.space16) {
            HStack(alignment: .top, spacing: VibeComposeMetrics.space14) {
                VibeComposeIconWell(
                    systemName: "mic.fill",
                    size: 44,
                    symbolSize: 18
                )
                VStack(alignment: .leading, spacing: VibeComposeMetrics.space8) {
                    Text(L10n.text("Allow microphone access"))
                        .font(VibeComposeTypography.title())
                        .tracking(-0.3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(bodyCopy)
                        .font(VibeComposeTypography.body())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: VibeComposeMetrics.space8)

            HStack {
                Spacer()
                Button(L10n.text("Cancel"), action: onCancel)
                    .buttonStyle(VibeComposeSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("Continue"), action: onContinue)
                    .buttonStyle(VibeComposePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(VibeComposeMetrics.space24)
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 560, alignment: .topLeading)
        .frame(minHeight: 200, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
