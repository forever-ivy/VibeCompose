import AppKit
import Carbon
import Foundation

struct FeedbackSurfaceDebugSnapshot:
    Codable,
    Sendable,
    Equatable
{
    let mode: VisualFeedbackMode
    let refinedHUDIsVisible: Bool
    let blueSignalFrameIsVisible: Bool
    let escapeCancellationIsActive: Bool
    let blueSignalAnimationIsActive: Bool
}

@MainActor
final class FeedbackSurfaceController:
    OverlayControlling,
    OverlaySnapshotCapturing
{
    typealias EscapeMonitorFactory = @MainActor (
        @escaping @Sendable () -> Void
    ) throws -> AnyObject

    private enum Presentation {
        case recording(
            level: CGFloat,
            elapsedText: String
        )
        case processing
        case result(
            text: String,
            outcome: InjectionOutcome
        )
        case error(String)
        case retryableError(String)

        var permitsCancellation: Bool {
            switch self {
            case .recording, .processing:
                return true
            case .result, .error, .retryableError:
                return false
            }
        }
    }

    private let refinedHUD: OverlayController
    private let blueSignalFrame:
        BlueSignalFrameController
    private var config = VisualFeedbackConfig()
    private var presentation: Presentation?
    private var hideTask: Task<Void, Never>?
    private let escapeMonitorFactory:
        EscapeMonitorFactory
    private var escapeHotkeyMonitor: AnyObject?
    private var hotkeyBinding = HotkeyBinding.f5

    var onCancel:
        (@MainActor (OverlayCancelSource) -> Void)?
    {
        didSet {
            refinedHUD.onCancel = onCancel
        }
    }

    var onRetry: (@MainActor () -> Void)? {
        didSet {
            refinedHUD.onRetry = onRetry
        }
    }

    init(
        accessibilityDisplayOptionsProvider:
            @escaping @MainActor ()
                -> AccessibilityDisplayOptions = {
                    AccessibilityDisplayOptionsOverride
                        .current
                },
        escapeMonitorFactory:
            @escaping EscapeMonitorFactory = {
                onPress in
                try HotkeyMonitor(
                    keyCode: UInt32(kVK_Escape),
                    onPress: onPress
                )
            }
    ) {
        self.escapeMonitorFactory =
            escapeMonitorFactory
        refinedHUD = OverlayController(
            accessibilityDisplayOptionsProvider:
                accessibilityDisplayOptionsProvider
        )
        blueSignalFrame = BlueSignalFrameController(
            accessibilityDisplayOptionsProvider:
                accessibilityDisplayOptionsProvider
        )
    }

    func updateHotkeyBinding(
        _ binding: HotkeyBinding
    ) {
        hotkeyBinding = binding
        refinedHUD.updateHotkeyBinding(binding)
    }

    func updateVisualFeedbackConfiguration(
        _ config: VisualFeedbackConfig
    ) {
        guard self.config != config else {
            return
        }
        self.config = config
        refinedHUD.updateVisualFeedbackConfiguration(
            config
        )
        rerenderCurrentPresentation()
    }

    func showRecording(elapsedText: String) {
        beginPresentation(
            .recording(
                level:
                    WaveformNormalizer
                        .minimumVisibleLevel,
                elapsedText: elapsedText
            )
        )
    }

    func updateRecording(
        level: CGFloat,
        elapsedText: String
    ) {
        let scaledLevel = min(
            1,
            max(
                0,
                level
                    * CGFloat(
                        config.intensity
                            .amplitudeScale
                    )
            )
        )
        presentation = .recording(
            level: scaledLevel,
            elapsedText: elapsedText
        )

        switch config.mode {
        case .refinedHUD:
            refinedHUD.updateRecording(
                level: scaledLevel,
                elapsedText: elapsedText
            )
        case .blueSignalFrame:
            blueSignalFrame.updateRecordingLevel(
                scaledLevel
            )
        case .hidden:
            break
        }
    }

    func showProcessing() {
        beginPresentation(.processing)
    }

    func showResult(
        text: String,
        outcome: InjectionOutcome
    ) {
        beginPresentation(
            .result(
                text: text,
                outcome: outcome
            )
        )
        scheduleHide(
            afterSeconds:
                resultDisplayDuration(for: outcome)
        )
    }

    func showError(_ message: String) {
        beginPresentation(.error(message))
        scheduleHide(afterSeconds: 5)
    }

    func showRetryableError(_ message: String) {
        beginPresentation(
            .retryableError(message)
        )
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        presentation = nil
        deactivateEscapeCancellation()
        refinedHUD.hide()
        blueSignalFrame.hide()
    }

    func writeSnapshot(to url: URL) throws {
        switch config.mode {
        case .refinedHUD:
            try refinedHUD.writeSnapshot(to: url)
        case .blueSignalFrame:
            try blueSignalFrame.writeSnapshot(to: url)
        case .hidden:
            throw OverlaySnapshotError.bitmapUnavailable
        }
    }

    var debugSnapshot:
        FeedbackSurfaceDebugSnapshot
    {
        FeedbackSurfaceDebugSnapshot(
            mode: config.mode,
            refinedHUDIsVisible:
                refinedHUD.debugSnapshot.panelIsVisible,
            blueSignalFrameIsVisible:
                blueSignalFrame.debugSnapshot
                    .isVisible,
            escapeCancellationIsActive:
                escapeHotkeyMonitor != nil
                    || refinedHUD.debugSnapshot
                        .isCancelControlVisible,
            blueSignalAnimationIsActive:
                blueSignalFrame.debugSnapshot
                    .animationIsActive
        )
    }

    private func beginPresentation(
        _ presentation: Presentation
    ) {
        hideTask?.cancel()
        hideTask = nil
        let previousPresentation = self.presentation
        self.presentation = presentation
        render(
            presentation,
            previousPresentation:
                previousPresentation
        )
    }

    private func rerenderCurrentPresentation() {
        refinedHUD.hide()
        blueSignalFrame.hide()
        deactivateEscapeCancellation()
        guard let presentation else {
            return
        }
        render(
            presentation,
            previousPresentation: nil
        )
    }

    private func render(
        _ presentation: Presentation,
        previousPresentation: Presentation?
    ) {
        switch config.mode {
        case .refinedHUD:
            blueSignalFrame.hide()
            deactivateEscapeCancellation()
            renderRefinedHUD(presentation)
        case .blueSignalFrame:
            renderBlueSignalFrame(
                presentation,
                previousPresentation:
                    previousPresentation
            )
        case .hidden:
            refinedHUD.hide()
            blueSignalFrame.hide()
            configureEscapeCancellation(
                for: presentation
            )
            announce(presentation)
        }
    }

    private func renderRefinedHUD(
        _ presentation: Presentation
    ) {
        switch presentation {
        case .recording(
            let level,
            let elapsedText
        ):
            refinedHUD.showRecording(
                elapsedText: elapsedText
            )
            refinedHUD.updateRecording(
                level: level,
                elapsedText: elapsedText
            )
        case .processing:
            refinedHUD.showProcessing()
        case .result(let text, let outcome):
            refinedHUD.showResult(
                text: text,
                outcome: outcome
            )
        case .error(let message):
            refinedHUD.showError(message)
        case .retryableError(let message):
            refinedHUD.showRetryableError(message)
        }
    }

    private func renderBlueSignalFrame(
        _ presentation: Presentation,
        previousPresentation: Presentation?
    ) {
        refinedHUD.hide()
        configureEscapeCancellation(
            for: presentation
        )

        switch presentation {
        case .recording(
            let level,
            _
        ):
            blueSignalFrame.hide()
            blueSignalFrame.show(
                state: .recording,
                level: level,
                config: config
            )
            announce(presentation)
        case .processing:
            if previousPresentation?
                .permitsCancellation != true
            {
                blueSignalFrame.hide()
            }
            blueSignalFrame.show(
                state: .processing,
                level: 0,
                config: config
            )
            announce(presentation)
        case .result(let text, let outcome):
            let frameState:
                BlueSignalFrameState =
                    switch outcome {
                    case .copiedToClipboard:
                        .copied
                    case .insertedAndVerified,
                         .pasteDispatchedClipboardRetained:
                        .success
                    }
            blueSignalFrame.show(
                state: frameState,
                level: 0,
                config: config
            )
            if config.showStatusText {
                refinedHUD.showResult(
                    text: text,
                    outcome: outcome
                )
            } else {
                announce(presentation)
            }
        case .error(let message):
            blueSignalFrame.show(
                state: .error,
                level: 0,
                config: config
            )
            if config.showStatusText {
                refinedHUD.showError(message)
            } else {
                announce(presentation)
            }
        case .retryableError(let message):
            blueSignalFrame.show(
                state: .error,
                level: 0,
                config: config
            )
            if config.showStatusText {
                refinedHUD.showRetryableError(
                    message
                )
            } else {
                announce(presentation)
            }
        }
    }

    private func configureEscapeCancellation(
        for presentation: Presentation
    ) {
        guard presentation.permitsCancellation else {
            deactivateEscapeCancellation()
            return
        }
        guard escapeHotkeyMonitor == nil else {
            return
        }
        escapeHotkeyMonitor = try? escapeMonitorFactory {
            [weak self] in
            Task { @MainActor [weak self] in
                self?.onCancel?(.escapeKey)
            }
        }
    }

    private func deactivateEscapeCancellation() {
        escapeHotkeyMonitor = nil
    }

    private func scheduleHide(
        afterSeconds delay: Double
    ) {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    for: .seconds(delay)
                )
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self?.hide()
        }
    }

    private func resultDisplayDuration(
        for outcome: InjectionOutcome
    ) -> Double {
        switch outcome {
        case .insertedAndVerified:
            return 0.9
        case .pasteDispatchedClipboardRetained:
            return 1.5
        case .copiedToClipboard:
            return 2
        }
    }

    private func announce(
        _ presentation: Presentation
    ) {
        let announcement: String
        switch presentation {
        case .recording:
            announcement = L10n.format(
                "Listening. Press %@ to transcribe.",
                hotkeyBinding.displayName
            )
        case .processing:
            announcement = L10n.text("Processing")
        case .result(_, let outcome):
            switch outcome {
            case .insertedAndVerified:
                announcement = L10n.text("Inserted")
            case .pasteDispatchedClipboardRetained:
                announcement = L10n.text(
                    "Paste sent"
                )
            case .copiedToClipboard:
                announcement = L10n.text("Copied")
            }
        case .error(let message),
             .retryableError(let message):
            announcement =
                L10n.text("Error")
                + ". "
                + message
        }

        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority:
                    NSAccessibilityPriorityLevel
                        .high.rawValue,
            ]
        )
    }
}
