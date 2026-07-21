import AppKit
import CoreGraphics
import Foundation
import QuartzCore

enum OverlayCancelSource: String, Sendable, Equatable {
    case escapeKey = "escape-key"
    case inlineClose = "inline-close"
}

@MainActor
protocol OverlayControlling: AnyObject {
    var onCancel: (@MainActor (OverlayCancelSource) -> Void)? { get set }
    var onRetry: (@MainActor () -> Void)? { get set }

    func updateHotkeyBinding(_ binding: HotkeyBinding)
    func updateSkillPresentation(
        _ presentation: SkillRuntimePresentation?
    )
    func updateVisualFeedbackConfiguration(
        _ config: VisualFeedbackConfig
    )
    func showRecording(elapsedText: String)
    func updateRecording(level: CGFloat, elapsedText: String)
    func showProcessing()
    func showResult(text: String, outcome: InjectionOutcome)
    func showError(_ message: String)
    func showRetryableError(_ message: String)
    func hide()
}

extension OverlayControlling {
    func updateHotkeyBinding(_ binding: HotkeyBinding) {
        _ = binding
    }

    func updateSkillPresentation(
        _ presentation: SkillRuntimePresentation?
    ) {
        _ = presentation
    }

    func updateVisualFeedbackConfiguration(
        _ config: VisualFeedbackConfig
    ) {
        _ = config
    }
}

enum OverlaySnapshotError: LocalizedError {
    case missingContentView
    case bitmapUnavailable
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingContentView:
            return "The OpenWhisper HUD has no content view to capture."
        case .bitmapUnavailable:
            return "The OpenWhisper HUD could not create a bitmap snapshot."
        case .pngEncodingFailed:
            return "The OpenWhisper HUD could not encode its snapshot as PNG."
        }
    }
}

@MainActor
protocol OverlaySnapshotCapturing: AnyObject {
    func writeSnapshot(to url: URL) throws
}

struct OverlayPresentationGeneration: Sendable, Equatable {
    private(set) var value: UInt64 = 0

    @discardableResult
    mutating func beginPresentation() -> UInt64 {
        value &+= 1
        return value
    }

    func isCurrent(_ candidate: UInt64) -> Bool {
        candidate == value
    }
}

struct OverlayAccessibilityAppearance: Sendable, Equatable {
    let backgroundBorderWidth: CGFloat
    let backgroundBorderAlpha: CGFloat
    let timerOpacity: CGFloat
    let cancelControlOpacity: CGFloat
    let retryControlOpacity: CGFloat
    let waveformBaseOpacity: CGFloat

    static func resolve(
        options: AccessibilityDisplayOptions,
        style: OverlayStylePreset
    ) -> OverlayAccessibilityAppearance {
        if options.increaseContrast {
            return OverlayAccessibilityAppearance(
                backgroundBorderWidth: 1.5,
                backgroundBorderAlpha: 0.34,
                timerOpacity: 1,
                cancelControlOpacity: 1,
                retryControlOpacity: 1,
                waveformBaseOpacity: 0.86
            )
        }

        return OverlayAccessibilityAppearance(
            backgroundBorderWidth: 1,
            backgroundBorderAlpha: 0.08,
            timerOpacity: style.timerOpacity,
            cancelControlOpacity: 0.78,
            retryControlOpacity: 0.84,
            waveformBaseOpacity: 0.68
        )
    }
}

@MainActor
final class OverlayController: OverlayControlling, OverlaySnapshotCapturing {
    private let style = OverlayStylePreset.dictationHUD
    private let accessibilityDisplayOptionsProvider: @MainActor () -> AccessibilityDisplayOptions
    private let panel: NSPanel
    private let backgroundView: NSView
    private let hudContentView: NSView
    private let leadingContainer = NSView()
    private let leadingBadgeView = NSView()
    private let waveformView: OverlayWaveformView
    private let iconView = NSImageView()
    private let closeButton = OverlayHitTargetButton()
    private let retryButton = OverlayHitTargetButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let trailingTimerLabel = NSTextField(labelWithString: "")
    private let textStack = NSStackView()
    private let trailingAccessoryStack = NSStackView()
    private var hideTask: Task<Void, Never>?
    private var processingTimer: Timer?
    private var processingFrameIndex = 0
    private var displayedLevels: [CGFloat]
    private var currentState: OverlayVisualState
    private var hotkeyDisplayName = HotkeyBinding.f5.displayName
    private var skillPresentation:
        SkillRuntimePresentation?
    private var alwaysReduceMotion = false
    private var accessibilityAppearance: OverlayAccessibilityAppearance
    private var presentationGeneration = OverlayPresentationGeneration()
    private var escapeHotkeyMonitor: HotkeyMonitor?
    private var activeAccentColor: NSColor?
    var onCancel: (@MainActor (OverlayCancelSource) -> Void)?
    var onRetry: (@MainActor () -> Void)?

    init(
        onCancel: (@MainActor (OverlayCancelSource) -> Void)? = nil,
        onRetry: (@MainActor () -> Void)? = nil,
        accessibilityDisplayOptionsProvider: @escaping @MainActor () -> AccessibilityDisplayOptions = {
            AccessibilityDisplayOptionsOverride
                .current
        }
    ) {
        self.accessibilityDisplayOptionsProvider = accessibilityDisplayOptionsProvider
        let surface = makeOverlaySurface(
            cornerRadius: OverlayStylePreset.dictationHUD.cornerRadius,
            chromeInset: OverlayStylePreset.dictationHUD.chromeInset
        )
        backgroundView = surface.rootView
        hudContentView = surface.contentView
        displayedLevels = Array(
            repeating: WaveformNormalizer.minimumVisibleLevel,
            count: style.waveformBarCount
        )
        currentState = .processing
        accessibilityAppearance = OverlayAccessibilityAppearance.resolve(
            options: Self.resolvedAccessibilityDisplayOptions(
                provider: accessibilityDisplayOptionsProvider,
                alwaysReduceMotion: false
            ),
            style: style
        )
        waveformView = OverlayWaveformView(
            levels: displayedLevels,
            style: style,
            baseOpacity: accessibilityAppearance.waveformBaseOpacity
        )
        panel = NSPanel(
            contentRect: NSRect(
                origin: .zero,
                size: style.size(for: .processing)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        // The inset material surface draws its own rounded shadow. A window
        // shadow would follow the transparent rectangular panel instead.
        panel.hasShadow = false
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false
        self.onCancel = onCancel
        self.onRetry = onRetry

        configureViews()
        observeAccessibilityDisplayOptions()
    }

    func updateHotkeyBinding(_ binding: HotkeyBinding) {
        hotkeyDisplayName = binding.displayName
        if case .recording = currentState, panel.isVisible {
            titleLabel.stringValue = currentState.label(
                hotkeyDisplayName: hotkeyDisplayName
            )
        }
    }

    func updateSkillPresentation(
        _ presentation: SkillRuntimePresentation?
    ) {
        skillPresentation = presentation
        guard panel.isVisible else { return }
        apply(state: currentState)
    }

    func updateVisualFeedbackConfiguration(
        _ config: VisualFeedbackConfig
    ) {
        let reduceMotionChanged =
            alwaysReduceMotion != config.alwaysReduceMotion
        alwaysReduceMotion = config.alwaysReduceMotion
        updateAccessibilityAppearance()
        if reduceMotionChanged,
           case .processing = currentState,
           panel.isVisible
        {
            startProcessingAnimation()
        }
    }

    func showRecording(elapsedText: String) {
        stopProcessingAnimation()
        displayedLevels = Array(
            repeating: WaveformNormalizer.minimumVisibleLevel,
            count: style.waveformBarCount
        )
        apply(state: .recording(levels: displayedLevels, elapsedText: elapsedText))
        present()
    }

    func updateRecording(level: CGFloat, elapsedText: String) {
        stopProcessingAnimation()
        displayedLevels = WaveformNormalizer.smoothedLevels(
            previous: displayedLevels,
            targetLevel: level,
            barCount: style.waveformBarCount
        )
        apply(state: .recording(levels: displayedLevels, elapsedText: elapsedText))
        present()
    }

    func showProcessing() {
        processingFrameIndex = 0
        displayedLevels = WaveformNormalizer.processingPulseLevels(
            frame: processingFrameIndex,
            barCount: style.waveformBarCount
        )
        apply(state: .processing)
        present()
        startProcessingAnimation()
    }

    func showResult(text: String, outcome: InjectionOutcome) {
        _ = text
        stopProcessingAnimation()

        let successKind: OverlaySuccessKind
        switch outcome {
        case .insertedAndVerified:
            successKind = .inserted
        case .pasteDispatchedClipboardRetained:
            successKind = .pasteSent
        case .copiedToClipboard:
            successKind = .copied
        }

        apply(state: .success(successKind))
        present()
        let displayDuration: Double = switch successKind {
        case .inserted:
            0.9
        case .pasteSent:
            1.5
        case .copied:
            2
        }
        scheduleHide(
            afterSeconds: displayDuration
        )
    }

    func showError(_ message: String) {
        stopProcessingAnimation()
        apply(state: .error(message))
        present()
        scheduleHide(afterSeconds: style.errorAutoHideDelay ?? 2.0)
    }

    func showRetryableError(_ message: String) {
        stopProcessingAnimation()
        apply(state: .retryableError(message))
        present()
    }

    func hide() {
        presentationGeneration.beginPresentation()
        hideTask?.cancel()
        stopProcessingAnimation()
        hideSessionControls()
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    func writeSnapshot(to url: URL) throws {
        guard let contentView = panel.contentView else {
            throw OverlaySnapshotError.missingContentView
        }

        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()
        let bounds = contentView.bounds
        guard
            bounds.width > 0,
            bounds.height > 0,
            let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds)
        else {
            throw OverlaySnapshotError.bitmapUnavailable
        }

        contentView.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw OverlaySnapshotError.pngEncodingFailed
        }
        try png.write(to: url, options: [.atomic])
    }

    private func apply(state: OverlayVisualState) {
        presentationGeneration.beginPresentation()
        hideTask?.cancel()
        currentState = state
        positionPanel(size: panelSize(for: state))
        updateAccessibilityAppearance()

        titleLabel.stringValue = displayLabel(for: state)
        trailingTimerLabel.stringValue = state.trailingText ?? ""
        trailingTimerLabel.isHidden = state.trailingText == nil
        trailingAccessoryStack.isHidden = !state.showsCancelControl && !state.showsRetryControl && state.trailingText == nil
        updateSessionControls(for: state)

        switch state {
        case .recording(let levels, _):
            displayedLevels = levels
            // Recording keeps the shell neutral and lets the voice glyph lead.
            waveformView.isHidden = false
            waveformView.update(levels: levels)
            waveformView.update(accentColor: nil)
            leadingBadgeView.isHidden = true
            iconView.isHidden = true
            setAccentRing(nil)
        case .processing:
            waveformView.isHidden = false
            waveformView.update(levels: displayedLevels)
            waveformView.update(
                accentColor: OpenWhisperPalette.hudProcessingAccent
            )
            leadingBadgeView.isHidden = true
            iconView.isHidden = true
            setAccentRing(OpenWhisperPalette.hudProcessingAccent)
        case .success(let kind):
            waveformView.isHidden = true
            switch kind {
            case .inserted:
                configureBadge(
                    symbolName: "checkmark",
                    tintColor: OpenWhisperPalette.success
                )
            case .pasteSent:
                configureBadge(
                    symbolName: "arrow.right",
                    tintColor: OpenWhisperPalette.brandBlue
                )
            case .copied:
                configureBadge(
                    symbolName: "doc.on.clipboard.fill",
                    tintColor: OpenWhisperPalette.amber
                )
            }
        case .error, .retryableError:
            waveformView.isHidden = true
            configureBadge(
                symbolName: "exclamationmark",
                tintColor: OpenWhisperPalette.error
            )
        }

        announce(state)
    }

    private func configureBadge(
        symbolName: String,
        tintColor: NSColor
    ) {
        leadingBadgeView.isHidden = false
        leadingBadgeView.layer?.backgroundColor =
            tintColor.withAlphaComponent(0.20).cgColor
        leadingBadgeView.layer?.borderColor =
            tintColor.withAlphaComponent(0.45).cgColor

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            iconView.image = image
            iconView.contentTintColor = tintColor
        } else {
            iconView.image = nil
        }

        iconView.isHidden = false
        setAccentRing(tintColor)
    }

    /// Keep the shell neutral. State belongs to the content glyph rather than
    /// an attention-heavy outline around the whole HUD.
    private func setAccentRing(_ color: NSColor?) {
        activeAccentColor = color
    }

    private func startProcessingAnimation() {
        stopProcessingAnimation()

        if resolvedAccessibilityDisplayOptions()
            .reduceMotion
        {
            displayedLevels = WaveformNormalizer.reducedMotionProcessingLevels(
                barCount: style.waveformBarCount
            )
            waveformView.update(levels: displayedLevels)
            return
        }

        processingTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processingFrameIndex += 1
                self.displayedLevels = WaveformNormalizer.processingPulseLevels(
                    frame: self.processingFrameIndex,
                    barCount: self.style.waveformBarCount
                )
                if case .processing = self.currentState {
                    self.waveformView.update(levels: self.displayedLevels)
                }
            }
        }
    }

    private func stopProcessingAnimation() {
        processingTimer?.invalidate()
        processingTimer = nil
    }

    private func present() {
        if panel.alphaValue == 0 || !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            if resolvedAccessibilityDisplayOptions()
                .reduceMotion
            {
                panel.alphaValue = 1
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    private func scheduleHide(afterSeconds: Double) {
        hideTask?.cancel()
        let scheduledGeneration = presentationGeneration.value
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(afterSeconds * 1_000_000_000))
            guard
                !Task.isCancelled,
                self.presentationGeneration.isCurrent(scheduledGeneration)
            else {
                return
            }
            if self.resolvedAccessibilityDisplayOptions()
                .reduceMotion
            {
                self.hide()
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    guard self.presentationGeneration.isCurrent(scheduledGeneration) else {
                        return
                    }
                    self.hide()
                }
            })
        }
    }

    private func configureViews() {
        (backgroundView as? any OverlayInteractiveSurface)?
            .interactiveViewsProvider = { [weak self] in
            guard let self else {
                return []
            }
            return [self.closeButton, self.retryButton]
        }
        // Keep the complete adaptive AppKit surface as the window content view.
        panel.contentView = backgroundView

        leadingContainer.translatesAutoresizingMaskIntoConstraints = false
        leadingContainer.wantsLayer = false

        leadingBadgeView.translatesAutoresizingMaskIntoConstraints = false
        leadingBadgeView.wantsLayer = true
        // A compact continuous rounded square reads like a native status tile.
        leadingBadgeView.layer?.cornerRadius = 9
        leadingBadgeView.layer?.cornerCurve = .continuous
        leadingBadgeView.layer?.borderWidth = 1
        leadingBadgeView.isHidden = true

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = .init(pointSize: 15, weight: .bold)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.isHidden = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = OpenWhisperPalette.hudText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        trailingTimerLabel.translatesAutoresizingMaskIntoConstraints = false
        trailingTimerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: style.timerFontSize, weight: .semibold)
        trailingTimerLabel.textColor = OpenWhisperPalette.hudTextMuted.withAlphaComponent(style.timerOpacity)
        trailingTimerLabel.alignment = .right
        trailingTimerLabel.isHidden = true

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.addArrangedSubview(titleLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: L10n.text("Cancel dictation")
        )
        closeButton.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = OpenWhisperPalette.hudTextMuted.withAlphaComponent(0.78)
        closeButton.toolTip = L10n.text("Cancel and discard this recording (Esc)")
        closeButton.setAccessibilityLabel(L10n.text("Cancel dictation"))
        closeButton.setAccessibilityHelp(L10n.text("Cancel and discard this recording (Esc)"))
        closeButton.target = self
        closeButton.action = #selector(handleCancelControlPressed)
        closeButton.setButtonType(.momentaryChange)
        closeButton.focusRingType = .none
        closeButton.isHidden = true

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isBordered = false
        retryButton.bezelStyle = .regularSquare
        retryButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: L10n.text("Retry transcription")
        )
        retryButton.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        retryButton.imagePosition = .imageOnly
        retryButton.contentTintColor = OpenWhisperPalette.hudTextMuted.withAlphaComponent(0.84)
        retryButton.target = self
        retryButton.action = #selector(handleRetryControlPressed)
        retryButton.setButtonType(.momentaryChange)
        retryButton.focusRingType = .none
        retryButton.isHidden = true
        retryButton.toolTip = L10n.text("Retry transcription")
        retryButton.setAccessibilityLabel(L10n.text("Retry transcription"))

        trailingAccessoryStack.translatesAutoresizingMaskIntoConstraints = false
        trailingAccessoryStack.orientation = .horizontal
        trailingAccessoryStack.spacing = style.inlineControlGap
        trailingAccessoryStack.alignment = .centerY
        trailingAccessoryStack.addArrangedSubview(trailingTimerLabel)
        trailingAccessoryStack.addArrangedSubview(retryButton)
        trailingAccessoryStack.addArrangedSubview(closeButton)

        hudContentView.addSubview(leadingContainer)
        hudContentView.addSubview(textStack)
        hudContentView.addSubview(trailingAccessoryStack)
        leadingContainer.addSubview(waveformView)
        leadingContainer.addSubview(leadingBadgeView)
        leadingContainer.addSubview(iconView)

        NSLayoutConstraint.activate([
            leadingContainer.leadingAnchor.constraint(equalTo: hudContentView.leadingAnchor, constant: style.contentPaddingH),
            leadingContainer.centerYAnchor.constraint(equalTo: hudContentView.centerYAnchor),
            leadingContainer.widthAnchor.constraint(equalToConstant: style.leadingVisualWidth),
            leadingContainer.heightAnchor.constraint(equalToConstant: style.leadingVisualHeight),

            waveformView.leadingAnchor.constraint(equalTo: leadingContainer.leadingAnchor),
            waveformView.trailingAnchor.constraint(equalTo: leadingContainer.trailingAnchor),
            waveformView.topAnchor.constraint(equalTo: leadingContainer.topAnchor),
            waveformView.bottomAnchor.constraint(equalTo: leadingContainer.bottomAnchor),

            leadingBadgeView.centerXAnchor.constraint(equalTo: leadingContainer.centerXAnchor),
            leadingBadgeView.centerYAnchor.constraint(equalTo: leadingContainer.centerYAnchor),
            leadingBadgeView.widthAnchor.constraint(equalToConstant: 30),
            leadingBadgeView.heightAnchor.constraint(equalToConstant: 30),

            iconView.centerXAnchor.constraint(equalTo: leadingBadgeView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: leadingBadgeView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: leadingContainer.trailingAnchor, constant: style.textGap),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAccessoryStack.leadingAnchor, constant: -style.textGap),
            textStack.centerYAnchor.constraint(equalTo: hudContentView.centerYAnchor),

            trailingAccessoryStack.trailingAnchor.constraint(equalTo: hudContentView.trailingAnchor, constant: -style.contentPaddingH),
            trailingAccessoryStack.centerYAnchor.constraint(equalTo: hudContentView.centerYAnchor),
            trailingTimerLabel.widthAnchor.constraint(equalToConstant: style.timerWidth),
            retryButton.widthAnchor.constraint(equalToConstant: style.inlineCancelControlSize),
            retryButton.heightAnchor.constraint(equalToConstant: style.inlineCancelControlSize),
            closeButton.widthAnchor.constraint(equalToConstant: style.inlineCancelControlSize),
            closeButton.heightAnchor.constraint(equalToConstant: style.inlineCancelControlSize),
        ])
    }

    private func panelSize(for state: OverlayVisualState) -> NSSize {
        style.size(for: state)
    }

    private func observeAccessibilityDisplayOptions() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.updateAccessibilityAppearance()
                if case .processing = self.currentState {
                    self.startProcessingAnimation()
                }
            }
        }
    }

    private func updateAccessibilityAppearance() {
        let options = resolvedAccessibilityDisplayOptions()
        accessibilityAppearance = OverlayAccessibilityAppearance.resolve(
            options: options,
            style: style
        )
        // Preserve the system material while strengthening its semantic edge
        // when Increase Contrast is enabled.
        setAccentRing(activeAccentColor)
        if let surfaceView = backgroundView as? OverlayHUDSurfaceView {
            surfaceView.updateChrome(
                width: accessibilityAppearance.backgroundBorderWidth,
                color: OpenWhisperPalette.hudText.withAlphaComponent(
                    accessibilityAppearance.backgroundBorderAlpha
                )
            )
        }
        titleLabel.textColor = OpenWhisperPalette.hudText
        trailingTimerLabel.textColor = OpenWhisperPalette.hudTextMuted.withAlphaComponent(
            accessibilityAppearance.timerOpacity
        )
        closeButton.contentTintColor = OpenWhisperPalette.hudTextMuted.withAlphaComponent(
            accessibilityAppearance.cancelControlOpacity
        )
        retryButton.contentTintColor = OpenWhisperPalette.hudTextMuted.withAlphaComponent(
            accessibilityAppearance.retryControlOpacity
        )
        waveformView.update(baseOpacity: accessibilityAppearance.waveformBaseOpacity)
    }

    private func announce(_ state: OverlayVisualState) {
        let announcement: String
        if let supplementaryText = state.supplementaryText, !supplementaryText.isEmpty {
            announcement =
                "\(displayLabel(for: state)). "
                + supplementaryText
        } else {
            announcement = displayLabel(for: state)
        }

        backgroundView.setAccessibilityElement(true)
        backgroundView.setAccessibilityRole(.group)
        backgroundView.setAccessibilityLabel(announcement)
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func displayLabel(
        for state: OverlayVisualState
    ) -> String {
        let base = state.label(
            hotkeyDisplayName: hotkeyDisplayName
        )
        guard let skillPresentation else {
            return base
        }
        switch state {
        case .recording, .processing:
            return L10n.format(
                "%@ · %@",
                skillPresentation.displayName,
                base
            )
        case .success, .error, .retryableError:
            return base
        }
    }

    private func positionPanel(size: NSSize) {
        let screen = activeScreen() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let newFrame = Self.panelFrame(for: size, in: visibleFrame, topInset: style.topInset)
        animateToFrame(newFrame)
    }

    private func animateToFrame(_ newFrame: NSRect) {
        guard panel.isVisible else {
            panel.setFrame(newFrame, display: false)
            return
        }
        guard !resolvedAccessibilityDisplayOptions().reduceMotion else {
            panel.setFrame(newFrame, display: false)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    static func panelFrame(
        for size: NSSize,
        in visibleFrame: NSRect,
        topInset: CGFloat
    ) -> NSRect {
        let fittedSize = NSSize(
            width: min(size.width, visibleFrame.width),
            height: min(size.height, visibleFrame.height)
        )
        let origin = NSPoint(
            x: visibleFrame.midX - (fittedSize.width / 2),
            y: max(
                visibleFrame.minY,
                visibleFrame.maxY
                    - topInset
                    - fittedSize.height
            )
        )
        return NSRect(origin: origin, size: fittedSize)
    }

    private func resolvedAccessibilityDisplayOptions()
        -> AccessibilityDisplayOptions
    {
        Self.resolvedAccessibilityDisplayOptions(
            provider: accessibilityDisplayOptionsProvider,
            alwaysReduceMotion: alwaysReduceMotion
        )
    }

    private static func resolvedAccessibilityDisplayOptions(
        provider:
            @MainActor () -> AccessibilityDisplayOptions,
        alwaysReduceMotion: Bool
    ) -> AccessibilityDisplayOptions {
        let options = provider()
        return AccessibilityDisplayOptions(
            reduceMotion:
                options.reduceMotion
                    || alwaysReduceMotion,
            increaseContrast:
                options.increaseContrast
        )
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    }

    private func updateSessionControls(for state: OverlayVisualState) {
        if state.showsCancelControl {
            closeButton.isHidden = false
            activateEscapeHotkeyIfNeeded()
        } else {
            escapeHotkeyMonitor = nil
            closeButton.isHidden = true
        }
        retryButton.isHidden = !state.showsRetryControl
    }

    private func activateEscapeHotkeyIfNeeded() {
        guard escapeHotkeyMonitor == nil else { return }
        escapeHotkeyMonitor = try? HotkeyMonitor(keyCode: 53) { [weak self] in
            Task { @MainActor [weak self] in
                self?.onCancel?(.escapeKey)
            }
        }
    }

    private func hideSessionControls() {
        escapeHotkeyMonitor = nil
        closeButton.isHidden = true
        retryButton.isHidden = true
    }

    @objc
    private func handleCancelControlPressed() {
        onCancel?(.inlineClose)
    }

    @objc
    private func handleRetryControlPressed() {
        onRetry?()
    }

    @discardableResult
    func debugSimulateCancelControlClick() -> Bool {
        guard !closeButton.isHidden else {
            return false
        }

        let centerInRoot = backgroundView.convert(
            NSPoint(x: closeButton.bounds.midX, y: closeButton.bounds.midY),
            from: closeButton
        )
        guard let hitView = backgroundView.hitTest(centerInRoot) as? NSControl else {
            return false
        }

        hitView.performClick(nil)
        return true
    }

    @discardableResult
    func debugSimulateRetryControlClick() -> Bool {
        guard !retryButton.isHidden else {
            return false
        }

        let centerInRoot = backgroundView.convert(
            NSPoint(x: retryButton.bounds.midX, y: retryButton.bounds.midY),
            from: retryButton
        )
        guard let hitView = backgroundView.hitTest(centerInRoot) as? NSControl else {
            return false
        }

        hitView.performClick(nil)
        return true
    }

    var debugSnapshot: OverlayDebugSnapshot {
        OverlayDebugSnapshot(
            usesLiquidGlassMaterial: false,
            usesNativeAppKitHUDMaterial:
                panel.contentView is OverlayHUDSurfaceView,
            usesIntegratedSessionControl: closeButton.superview === trailingAccessoryStack,
            hasDetachedClosePanel: false,
            panelIgnoresMouseEvents: panel.ignoresMouseEvents,
            isCancelControlVisible: !closeButton.isHidden,
            isRetryControlVisible: !retryButton.isHidden,
            isTimerVisible: !trailingTimerLabel.isHidden,
            presentationGeneration: presentationGeneration.value,
            panelIsVisible: panel.isVisible,
            processingAnimationIsActive: processingTimer?.isValid == true,
            displayedLevels: displayedLevels,
            accessibilityAppearance: accessibilityAppearance
        )
    }

}

struct OverlayDebugSnapshot: Sendable, Equatable {
    let usesLiquidGlassMaterial: Bool
    let usesNativeAppKitHUDMaterial: Bool
    let usesIntegratedSessionControl: Bool
    let hasDetachedClosePanel: Bool
    let panelIgnoresMouseEvents: Bool
    let isCancelControlVisible: Bool
    let isRetryControlVisible: Bool
    let isTimerVisible: Bool
    let presentationGeneration: UInt64
    let panelIsVisible: Bool
    let processingAnimationIsActive: Bool
    let displayedLevels: [CGFloat]
    let accessibilityAppearance: OverlayAccessibilityAppearance
}

private struct OverlaySurfaceComponents {
    let rootView: NSView
    let contentView: NSView
}

@MainActor
private protocol OverlayInteractiveSurface: AnyObject {
    var interactiveViewsProvider: (() -> [NSView])? { get set }
}

@MainActor
private func makeOverlaySurface(
    cornerRadius: CGFloat,
    chromeInset: CGFloat
) -> OverlaySurfaceComponents {
    let contentView = NSView()
    contentView.wantsLayer = false
    let surfaceView = OverlayHUDSurfaceView(
        cornerRadius: cornerRadius,
        chromeInset: chromeInset,
        contentView: contentView
    )
    return OverlaySurfaceComponents(
        rootView: surfaceView,
        contentView: contentView
    )
}

@MainActor
private func interactiveHitTest(
    _ point: NSPoint,
    in rootView: NSView,
    provider: (() -> [NSView])?
) -> NSView? {
    guard let interactiveViews = provider?() else {
        return nil
    }

    for view in interactiveViews.reversed()
        where !view.isHidden && view.alphaValue > 0
    {
        let pointInView = view.convert(point, from: rootView)
        if let hitView = view.hitTest(pointInView) {
            return hitView
        }
    }

    return nil
}

@MainActor
private final class OverlayHUDSurfaceView:
    NSView,
    OverlayInteractiveSurface
{
    private let chromeInset: CGFloat
    private let cornerRadius: CGFloat
    private let shadowView = NSView()
    private let materialView = NSVisualEffectView()
    var interactiveViewsProvider: (() -> [NSView])?

    init(
        cornerRadius: CGFloat,
        chromeInset: CGFloat,
        contentView: NSView
    ) {
        self.cornerRadius = cornerRadius
        self.chromeInset = chromeInset
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.wantsLayer = true
        shadowView.layer?.cornerRadius = cornerRadius
        shadowView.layer?.cornerCurve = .continuous
        shadowView.layer?.shadowColor = NSColor.black.cgColor
        shadowView.layer?.shadowOpacity = 0.22
        shadowView.layer?.shadowRadius = 14
        shadowView.layer?.shadowOffset = CGSize(width: 0, height: -3)
        shadowView.layer?.masksToBounds = false

        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.material = .popover
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = cornerRadius
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true

        addSubview(shadowView)
        addSubview(materialView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(contentView)
        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: chromeInset
            ),
            shadowView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -chromeInset
            ),
            shadowView.topAnchor.constraint(
                equalTo: topAnchor,
                constant: chromeInset
            ),
            shadowView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -chromeInset
            ),

            materialView.leadingAnchor.constraint(
                equalTo: shadowView.leadingAnchor
            ),
            materialView.trailingAnchor.constraint(
                equalTo: shadowView.trailingAnchor
            ),
            materialView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            materialView.bottomAnchor.constraint(
                equalTo: shadowView.bottomAnchor
            ),

            contentView.leadingAnchor.constraint(
                equalTo: materialView.leadingAnchor
            ),
            contentView.trailingAnchor.constraint(
                equalTo: materialView.trailingAnchor
            ),
            contentView.topAnchor.constraint(equalTo: materialView.topAnchor),
            contentView.bottomAnchor.constraint(
                equalTo: materialView.bottomAnchor
            ),
        ])
        updateAdaptiveChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        shadowView.layer?.shadowPath = CGPath(
            roundedRect: shadowView.bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAdaptiveChrome()
    }

    func updateChrome(width: CGFloat, color: NSColor) {
        materialView.layer?.borderWidth = width
        materialView.layer?.borderColor = color.cgColor
    }

    private func updateAdaptiveChrome() {
        let base = NSColor.windowBackgroundColor
            .withAlphaComponent(0.94)
        shadowView.layer?.backgroundColor = base.cgColor
        materialView.layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(0.16)
            .cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        interactiveHitTest(
            point,
            in: self,
            provider: interactiveViewsProvider
        )
    }
}

private final class OverlayHitTargetButton: NSButton {
    private let hitTargetPadding: CGFloat = 6

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitBounds = bounds.insetBy(dx: -hitTargetPadding, dy: -hitTargetPadding)
        return hitBounds.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
private final class OverlayWaveformView: NSView {
    private var levels: [CGFloat]
    private let style: OverlayStylePreset
    private var baseOpacity: CGFloat
    private var accentColor: NSColor?

    init(
        levels: [CGFloat],
        style: OverlayStylePreset,
        baseOpacity: CGFloat
    ) {
        self.levels = levels
        self.style = style
        self.baseOpacity = baseOpacity
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(levels: [CGFloat]) {
        let trimmed = Array(levels.prefix(style.waveformBarCount))
        if trimmed.count == style.waveformBarCount {
            self.levels = trimmed
        } else {
            self.levels = trimmed + Array(
                repeating: WaveformNormalizer.minimumVisibleLevel,
                count: max(0, style.waveformBarCount - trimmed.count)
            )
        }
        needsDisplay = true
    }

    func update(baseOpacity: CGFloat) {
        self.baseOpacity = baseOpacity
        needsDisplay = true
    }

    func update(accentColor: NSColor?) {
        self.accentColor = accentColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let activeLevels = levels.isEmpty
            ? Array(repeating: WaveformNormalizer.minimumVisibleLevel, count: style.waveformBarCount)
            : levels

        let totalSpacing = style.waveformBarSpacing * CGFloat(max(0, activeLevels.count - 1))
        let availableWidth = bounds.width - totalSpacing
        let rawBarWidth = availableWidth / CGFloat(max(1, activeLevels.count))
        let barWidth = max(2, min(3.5, floor(rawBarWidth)))
        let contentWidth = (barWidth * CGFloat(activeLevels.count)) + totalSpacing
        var x = bounds.midX - (contentWidth / 2)
        for level in activeLevels {
            let barHeight = max(style.waveformMinimumBarHeight, bounds.height * level)
            let barRect = CGRect(
                x: x,
                y: bounds.midY - (barHeight / 2),
                width: barWidth,
                height: barHeight
            )

            let barColor: NSColor
            if let accentColor {
                // State-tinted glyph (processing): keep the bars luminous and
                // let level drive brightness so the pulse stays readable.
                let lift = 0.18 + (level * 0.34)
                barColor = accentColor
                    .blended(withFraction: lift, of: .white)?
                    .withAlphaComponent(min(1, baseOpacity + 0.18))
                    ?? accentColor
            } else {
                barColor = OpenWhisperPalette.hudText
                    .withAlphaComponent(baseOpacity)
            }

            barColor.setFill()
            NSBezierPath(
                roundedRect: barRect,
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).fill()

            x += barWidth + style.waveformBarSpacing
        }
    }
}
