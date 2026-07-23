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
    /// Capsule confirmation for non-dictation actions (e.g. Skill selection).
    func showConfirmation(title: String)
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

    func showConfirmation(title: String) {
        _ = title
    }
}

enum OverlaySnapshotError: LocalizedError {
    case missingContentView
    case bitmapUnavailable
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingContentView:
            return "The VibeWhisper HUD has no content view to capture."
        case .bitmapUnavailable:
            return "The VibeWhisper HUD could not create a bitmap snapshot."
        case .pngEncodingFailed:
            return "The VibeWhisper HUD could not encode its snapshot as PNG."
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

    @MainActor
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
                waveformBaseOpacity: 1
            )
        }

        // Dark glass needs higher glyph opacity so the waveform and timer stay
        // crisp against the translucent material; light mode stays calmer.
        let isDark = NSApp.effectiveAppearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua
        return OverlayAccessibilityAppearance(
            backgroundBorderWidth: 1,
            backgroundBorderAlpha: isDark ? 0.14 : 0.08,
            // Elapsed time is primary status during recording — match the skill
            // title at full label opacity. Dimmed secondary labels wash out on
            // both light and dark Liquid Glass.
            timerOpacity: 1,
            cancelControlOpacity: isDark ? 0.92 : 0.78,
            retryControlOpacity: isDark ? 0.94 : 0.84,
            waveformBaseOpacity: isDark ? 0.94 : 0.82
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
    // nonisolated(unsafe): only touched on MainActor; read in deinit for teardown.
    nonisolated(unsafe) private var processingTimer: Timer?
    private var processingFrameIndex = 0
    /// Absolute media-time origin for continuous processing pulse motion.
    private var processingAnimationOrigin: CFTimeInterval = 0
    private var displayedLevels: [CGFloat]
    private var currentState: OverlayVisualState
    private var hotkeyDisplayName = HotkeyBinding.f5.displayName
    private var skillPresentation:
        SkillRuntimePresentation?
    private var alwaysReduceMotion = false
    private var hudPlacement: HUDPlacement = .top
    private var accessibilityAppearance: OverlayAccessibilityAppearance
    private var presentationGeneration = OverlayPresentationGeneration()
    private var escapeHotkeyMonitor: HotkeyMonitor?
    private var activeAccentColor: NSColor?
    /// Token for `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`.
    /// Block-based `addObserver` retains the closure; we must remove it on teardown.
    /// nonisolated(unsafe): only mutated on MainActor; read in deinit for teardown.
    nonisolated(unsafe) private var accessibilityDisplayOptionsObserver: NSObjectProtocol?
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

    isolated deinit {
        if let accessibilityDisplayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                accessibilityDisplayOptionsObserver
            )
        }
        processingTimer?.invalidate()
        hideTask?.cancel()
    }

    func updateHotkeyBinding(_ binding: HotkeyBinding) {
        hotkeyDisplayName = binding.displayName
        // Recording never surfaces the hotkey; only processing/error labels
        // still consult it, so refresh when those states are visible.
        guard panel.isVisible else { return }
        switch currentState {
        case .recording:
            break
        case .processing, .success, .error, .retryableError:
            let title = displayLabel(for: currentState)
            titleLabel.stringValue = title
            titleLabel.isHidden = title.isEmpty
            textStack.isHidden = title.isEmpty
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
        let placementChanged =
            hudPlacement != config.hudPlacement
        alwaysReduceMotion = config.alwaysReduceMotion
        hudPlacement = config.hudPlacement
        updateAccessibilityAppearance()
        if placementChanged, panel.isVisible {
            positionPanel(size: panelSize(for: currentState))
        }
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
        // Continuous media-time phase keeps multi-frequency organic motion alive
        // between level samples so the glyph never freezes into a static envelope.
        displayedLevels = WaveformNormalizer.smoothedLevels(
            previous: displayedLevels,
            targetLevel: level,
            barCount: style.waveformBarCount,
            phase: CACurrentMediaTime()
        )
        apply(state: .recording(levels: displayedLevels, elapsedText: elapsedText))
        present()
    }

    func showProcessing() {
        processingFrameIndex = 0
        processingAnimationOrigin = CACurrentMediaTime()
        displayedLevels = WaveformNormalizer.processingPulseLevels(
            time: 0,
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
        case .confirmation:
            1.4
        }
        scheduleHide(
            afterSeconds: displayDuration
        )
    }

    func showConfirmation(title: String) {
        let trimmed = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return }
        stopProcessingAnimation()
        apply(state: .success(.confirmation(title: trimmed)))
        present()
        scheduleHide(afterSeconds: 1.4)
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

        let title = displayLabel(for: state)
        titleLabel.stringValue = title
        titleLabel.isHidden = title.isEmpty
        textStack.isHidden = title.isEmpty
        trailingTimerLabel.stringValue = state.trailingText ?? ""
        trailingTimerLabel.isHidden = state.trailingText == nil
        trailingAccessoryStack.isHidden = !state.showsCancelControl && !state.showsRetryControl && state.trailingText == nil
        updateSessionControls(for: state)

        switch state {
        case .recording(let levels, _):
            displayedLevels = levels
            // Recording: warm brand-blue waveform so live audio is obvious.
            waveformView.isHidden = false
            waveformView.update(levels: levels)
            waveformView.update(
                accentColor: VibeWhisperPalette.hudRecordingAccent
            )
            leadingBadgeView.isHidden = true
            iconView.isHidden = true
            setAccentRing(VibeWhisperPalette.hudRecordingAccent)
        case .processing:
            // Processing: warmer amber pulse, distinct from live recording blue.
            waveformView.isHidden = false
            waveformView.update(levels: displayedLevels)
            waveformView.update(
                accentColor: VibeWhisperPalette.hudProcessingAccent
            )
            leadingBadgeView.isHidden = true
            iconView.isHidden = true
            setAccentRing(VibeWhisperPalette.hudProcessingAccent)
        case .success(let kind):
            waveformView.isHidden = true
            waveformView.update(accentColor: nil)
            switch kind {
            case .inserted, .pasteSent, .confirmation:
                // Green check reads as success for every delivered path;
                // clipboard-only stays amber so the outcome remains distinct.
                configureBadge(
                    symbolName: "checkmark",
                    tintColor: VibeWhisperPalette.success
                )
            case .copied:
                configureBadge(
                    symbolName: "doc.on.clipboard.fill",
                    tintColor: VibeWhisperPalette.amber
                )
            }
        case .error, .retryableError:
            waveformView.isHidden = true
            waveformView.update(accentColor: nil)
            configureBadge(
                symbolName: "exclamationmark",
                tintColor: VibeWhisperPalette.error
            )
        }

        announce(state)
    }

    private func configureBadge(
        symbolName: String,
        tintColor: NSColor
    ) {
        leadingBadgeView.isHidden = false
        // Softer fill sits on glass without fighting the material.
        leadingBadgeView.layer?.backgroundColor =
            tintColor.withAlphaComponent(0.14).cgColor
        leadingBadgeView.layer?.borderColor =
            tintColor.withAlphaComponent(0.32).cgColor

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
            waveformView.update(levels: displayedLevels, animated: false)
            return
        }

        // ~30 fps continuous time sampling — high enough for smooth travel,
        // low enough that CALayer height springs own the visual interpolation.
        processingAnimationOrigin = CACurrentMediaTime()
        processingTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 30.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processingFrameIndex += 1
                let elapsed = max(
                    0,
                    CACurrentMediaTime() - self.processingAnimationOrigin
                )
                self.displayedLevels = WaveformNormalizer.processingPulseLevels(
                    time: elapsed,
                    barCount: self.style.waveformBarCount
                )
                if case .processing = self.currentState {
                    self.waveformView.update(levels: self.displayedLevels)
                }
            }
        }
        // Tolerate a bit of scheduling jitter so the run loop stays calm.
        processingTimer?.tolerance = 1.0 / 120.0
    }

    private func stopProcessingAnimation() {
        processingTimer?.invalidate()
        processingTimer = nil
    }

    private func present() {
        if panel.alphaValue == 0 || !panel.isVisible {
            // Float-in from slightly above/below the rest frame so the capsule
            // reads as descending onto the desktop (macOS floating chrome feel),
            // not as a hard opacity flash.
            let restFrame = panel.frame
            let floatOffset: CGFloat = 8
            let entryFrame: NSRect
            switch hudPlacement {
            case .top:
                entryFrame = restFrame.offsetBy(dx: 0, dy: floatOffset)
            case .bottom:
                entryFrame = restFrame.offsetBy(dx: 0, dy: -floatOffset)
            }
            panel.setFrame(entryFrame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            if resolvedAccessibilityDisplayOptions()
                .reduceMotion
            {
                panel.setFrame(restFrame, display: false)
                panel.alphaValue = 1
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                // Spring-like ease: short response, slight overshoot damping via
                // allowsImplicitAnimation + easeOut (no CASpringAnimation on
                // NSPanel frame without a custom layer host).
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.2, 0.9, 0.25, 1.0
                )
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
                panel.animator().setFrame(restFrame, display: true)
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
            let restFrame = self.panel.frame
            let floatOffset: CGFloat = 6
            let exitFrame: NSRect
            switch self.hudPlacement {
            case .top:
                exitFrame = restFrame.offsetBy(dx: 0, dy: floatOffset)
            case .bottom:
                exitFrame = restFrame.offsetBy(dx: 0, dy: -floatOffset)
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.4, 0.0, 0.6, 1.0
                )
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 0
                panel.animator().setFrame(exitFrame, display: true)
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
        // Status tile sized for the taller capsule / larger leading glyph.
        leadingBadgeView.layer?.cornerRadius = 7
        leadingBadgeView.layer?.cornerCurve = .continuous
        leadingBadgeView.layer?.borderWidth = 1
        leadingBadgeView.isHidden = true

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.isHidden = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = VibeWhisperPalette.hudText
        titleLabel.lineBreakMode = .byClipping
        // Prefer growing the pill over truncating short status words
        // ("已完成" / "错误" / "Done"). Recording skill names still fit via
        // the larger recording width budget.
        titleLabel.setContentCompressionResistancePriority(
            .required,
            for: .horizontal
        )
        titleLabel.setContentHuggingPriority(
            .defaultHigh,
            for: .horizontal
        )

        trailingTimerLabel.translatesAutoresizingMaskIntoConstraints = false
        // Same size / weight as the skill title — only tabular digits differ so
        // "代码提示词" and "00:06" feel like one type system.
        trailingTimerLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: style.timerFontSize,
            weight: .semibold
        )
        trailingTimerLabel.textColor = VibeWhisperPalette.hudText
        trailingTimerLabel.alignment = .right
        trailingTimerLabel.isHidden = true

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 1
        textStack.alignment = .leading
        textStack.addArrangedSubview(titleLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: L10n.text("Cancel dictation")
        )
        closeButton.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = VibeWhisperPalette.hudTextMuted.withAlphaComponent(0.86)
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
        retryButton.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        retryButton.imagePosition = .imageOnly
        retryButton.contentTintColor = VibeWhisperPalette.hudTextMuted.withAlphaComponent(0.88)
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
            leadingBadgeView.widthAnchor.constraint(equalToConstant: 22),
            leadingBadgeView.heightAnchor.constraint(equalToConstant: 22),

            iconView.centerXAnchor.constraint(equalTo: leadingBadgeView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: leadingBadgeView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13),

            textStack.leadingAnchor.constraint(equalTo: leadingContainer.trailingAnchor, constant: style.textGap),
            // When trailing chrome is hidden the title may reach the trailing pad.
            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: hudContentView.trailingAnchor,
                constant: -style.contentPaddingH
            ),
            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAccessoryStack.leadingAnchor,
                constant: -style.textGap
            ),
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
        let title = displayLabel(for: state)
        let titleWidth = measuredTitleWidth(title)
        return style.size(for: state, titleWidth: titleWidth)
    }

    private func measuredTitleWidth(_ title: String) -> CGFloat {
        guard !title.isEmpty else { return 0 }
        let font = titleLabel.font
            ?? NSFont.systemFont(ofSize: 12, weight: .semibold)
        return ceil(
            (title as NSString).size(withAttributes: [.font: font]).width
        )
    }

    private func observeAccessibilityDisplayOptions() {
        if let accessibilityDisplayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                accessibilityDisplayOptionsObserver
            )
        }
        accessibilityDisplayOptionsObserver =
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
                color: VibeWhisperPalette.hudText.withAlphaComponent(
                    accessibilityAppearance.backgroundBorderAlpha
                )
            )
        }
        titleLabel.textColor = VibeWhisperPalette.hudText
        // Same primary fill as the skill title — one type system across the HUD.
        trailingTimerLabel.textColor = VibeWhisperPalette.hudText
            .withAlphaComponent(accessibilityAppearance.timerOpacity)
        closeButton.contentTintColor = VibeWhisperPalette.hudTextMuted.withAlphaComponent(
            accessibilityAppearance.cancelControlOpacity
        )
        retryButton.contentTintColor = VibeWhisperPalette.hudTextMuted.withAlphaComponent(
            accessibilityAppearance.retryControlOpacity
        )
        waveformView.update(baseOpacity: accessibilityAppearance.waveformBaseOpacity)
        waveformView.update(reduceMotion: options.reduceMotion)
    }

    private func announce(_ state: OverlayVisualState) {
        let title = displayLabel(for: state)
        let announcement: String
        if let supplementaryText = state.supplementaryText, !supplementaryText.isEmpty {
            let head = title.isEmpty
                ? L10n.text("Error")
                : title
            announcement = "\(head). " + supplementaryText
        } else if title.isEmpty {
            // Recording with no skill still needs a VoiceOver cue.
            announcement = L10n.text("Recording")
        } else {
            announcement = title
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
        switch state {
        case .recording:
            // Skill name only — never the hotkey hint.
            return skillPresentation?.displayName ?? ""
        case .processing, .success, .error, .retryableError:
            // No skill prefix on processing / terminal states.
            return state.label(hotkeyDisplayName: hotkeyDisplayName)
        }
    }

    private func positionPanel(size: NSSize) {
        let screen = activeScreen() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let newFrame = Self.panelFrame(
            for: size,
            in: visibleFrame,
            edgeInset: style.topInset,
            placement: hudPlacement
        )
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
            // Width morph between states — slightly springier than linear ease
            // so the glass capsule feels like liquid chrome, not a resize box.
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.22, 0.9, 0.28, 1.0
            )
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    static func panelFrame(
        for size: NSSize,
        in visibleFrame: NSRect,
        edgeInset: CGFloat,
        placement: HUDPlacement = .top
    ) -> NSRect {
        let fittedSize = NSSize(
            width: min(size.width, visibleFrame.width),
            height: min(size.height, visibleFrame.height)
        )
        let y: CGFloat
        switch placement {
        case .top:
            y = max(
                visibleFrame.minY,
                visibleFrame.maxY - edgeInset - fittedSize.height
            )
        case .bottom:
            y = min(
                visibleFrame.maxY - fittedSize.height,
                visibleFrame.minY + edgeInset
            )
        }
        let origin = NSPoint(
            x: visibleFrame.midX - (fittedSize.width / 2),
            y: y
        )
        return NSRect(origin: origin, size: fittedSize)
    }

    /// Back-compat for tests / callers that still pass `topInset`.
    static func panelFrame(
        for size: NSSize,
        in visibleFrame: NSRect,
        topInset: CGFloat
    ) -> NSRect {
        panelFrame(
            for: size,
            in: visibleFrame,
            edgeInset: topInset,
            placement: .top
        )
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
        let surface = panel.contentView as? OverlayHUDSurfaceView
        return OverlayDebugSnapshot(
            usesLiquidGlassMaterial:
                surface?.usesLiquidGlassMaterial
                    ?? VibeWhisperFloatingChrome.usesSystemLiquidGlass,
            usesNativeAppKitHUDMaterial: surface != nil,
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
            accessibilityAppearance: accessibilityAppearance,
            visibleTitle: titleLabel.stringValue,
            isTitleHidden: titleLabel.isHidden,
            waveformAccent: waveformView.debugAccentKind
        )
    }

}

struct OverlayDebugSnapshot: Sendable, Equatable {
    enum WaveformAccentKind: Sendable, Equatable {
        case none
        case recording
        case processing
    }

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
    let visibleTitle: String
    let isTitleHidden: Bool
    let waveformAccent: WaveformAccentKind
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

/// Floating dictation HUD shell, aligned with Apple's AppKit Liquid Glass sample:
/// on macOS 26 a bare `NSGlassEffectView` fills the panel edge-to-edge (glass
/// owns its optical edge + adaptive elevation). Pre-26 falls back to
/// `NSVisualEffectView.Material.hudWindow` with a soft silhouette shadow plate.
@MainActor
private final class OverlayHUDSurfaceView:
    NSView,
    OverlayInteractiveSurface
{
    private let cornerRadius: CGFloat
    private let usesLiquidGlass: Bool
    /// Pre-26 only: hosts the soft elevation plate. Nil under Liquid Glass.
    private let shadowView: NSView?
    /// Classic material host (macOS 13–25). Nil when Liquid Glass is active.
    private let materialView: NSVisualEffectView?
    var interactiveViewsProvider: (() -> [NSView])?

    init(
        cornerRadius: CGFloat,
        chromeInset: CGFloat,
        contentView: NSView
    ) {
        self.cornerRadius = cornerRadius

        contentView.translatesAutoresizingMaskIntoConstraints = false

        if #available(macOS 26, *) {
            // Official sample pattern: glass is the surface. No painted shadow
            // plate, no inset, no manual hairline — Liquid Glass lenses the
            // desktop behind the capsule and draws its own edge.
            let glass = NSGlassEffectView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            // Neutral shell — state accents live on glyphs/badges, never tint
            // the glass (Apple: "tint only primary actions").
            glass.tintColor = nil
            glass.contentView = contentView

            self.materialView = nil
            self.shadowView = nil
            self.usesLiquidGlass = true
            super.init(frame: .zero)

            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            addSubview(glass)
            NSLayoutConstraint.activate(Self.pin(glass, to: self))
            return
        }

        // Pre-26: hudWindow material + soft elevation plate so the pill still
        // reads as floating chrome without Liquid Glass.
        let material = NSVisualEffectView()
        material.translatesAutoresizingMaskIntoConstraints = false
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = cornerRadius
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        material.addSubview(contentView)
        NSLayoutConstraint.activate(Self.pin(contentView, to: material))

        let elevation = NSView()
        elevation.translatesAutoresizingMaskIntoConstraints = false
        elevation.wantsLayer = true
        elevation.layer?.cornerRadius = cornerRadius
        elevation.layer?.cornerCurve = .continuous
        elevation.layer?.shadowColor = NSColor.black.cgColor
        elevation.layer?.shadowOpacity =
            VibeWhisperFloatingChrome.capsuleShadowOpacity
        elevation.layer?.shadowRadius =
            VibeWhisperFloatingChrome.capsuleShadowRadius
        elevation.layer?.shadowOffset = CGSize(
            width: 0,
            height: VibeWhisperFloatingChrome.capsuleShadowOffsetY
        )
        elevation.layer?.masksToBounds = false
        elevation.layer?.backgroundColor = NSColor.clear.cgColor

        self.materialView = material
        self.shadowView = elevation
        self.usesLiquidGlass = false
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(elevation)
        addSubview(material)
        NSLayoutConstraint.activate(
            Self.pin(material, to: elevation) + [
                elevation.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: chromeInset
                ),
                elevation.trailingAnchor.constraint(
                    equalTo: trailingAnchor,
                    constant: -chromeInset
                ),
                elevation.topAnchor.constraint(
                    equalTo: topAnchor,
                    constant: chromeInset
                ),
                elevation.bottomAnchor.constraint(
                    equalTo: bottomAnchor,
                    constant: -chromeInset
                ),
            ]
        )
        updateClassicAdaptiveFill()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var usesLiquidGlassMaterial: Bool { usesLiquidGlass }

    override func layout() {
        super.layout()
        guard let shadowView else { return }
        shadowView.layer?.shadowPath = CGPath(
            roundedRect: shadowView.bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if !usesLiquidGlass {
            updateClassicAdaptiveFill()
        }
    }

    func updateChrome(width: CGFloat, color: NSColor) {
        // Liquid Glass owns its edge; only classic material takes a manual hairline.
        guard !usesLiquidGlass, let materialView else { return }
        materialView.layer?.borderWidth = width
        materialView.layer?.borderColor = color.cgColor
    }

    /// Light adaptive fill so the classic material stays legible without
    /// fighting the blur. Never applied under Liquid Glass.
    private func updateClassicAdaptiveFill() {
        guard !usesLiquidGlass else { return }
        shadowView?.layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(0.55)
            .cgColor
        materialView?.layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(0.08)
            .cgColor
    }

    private static func pin(
        _ child: NSView,
        to parent: NSView
    ) -> [NSLayoutConstraint] {
        [
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ]
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
    private var barLayers: [CALayer] = []
    /// Cached bar geometry so we can spring-animate height without re-layout noise.
    private var barWidth: CGFloat = 2
    private var contentOriginX: CGFloat = 0
    private var prefersReducedMotion = false

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
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        // Disable implicit NSView animations on the host layer; bars own motion.
        layer?.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "sublayers": NSNull(),
        ]
        rebuildBarLayersIfNeeded(count: style.waveformBarCount)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var debugAccentKind: OverlayDebugSnapshot.WaveformAccentKind {
        guard let accentColor else { return .none }
        // Named dynamic colors resolve per appearance; compare resolved sRGB.
        let resolved = accentColor.usingColorSpace(.sRGB) ?? accentColor
        let recording = VibeWhisperPalette.hudRecordingAccent
            .usingColorSpace(.sRGB)
            ?? VibeWhisperPalette.hudRecordingAccent
        let processing = VibeWhisperPalette.hudProcessingAccent
            .usingColorSpace(.sRGB)
            ?? VibeWhisperPalette.hudProcessingAccent
        if abs(resolved.redComponent - recording.redComponent) < 0.04,
           abs(resolved.greenComponent - recording.greenComponent) < 0.04,
           abs(resolved.blueComponent - recording.blueComponent) < 0.04
        {
            return .recording
        }
        if abs(resolved.redComponent - processing.redComponent) < 0.04,
           abs(resolved.greenComponent - processing.greenComponent) < 0.04,
           abs(resolved.blueComponent - processing.blueComponent) < 0.04
        {
            return .processing
        }
        return .none
    }

    func update(levels: [CGFloat], animated: Bool = true) {
        let trimmed = Array(levels.prefix(style.waveformBarCount))
        if trimmed.count == style.waveformBarCount {
            self.levels = trimmed
        } else {
            self.levels = trimmed + Array(
                repeating: WaveformNormalizer.minimumVisibleLevel,
                count: max(0, style.waveformBarCount - trimmed.count)
            )
        }
        applyBarPresentation(animated: animated && !prefersReducedMotion)
    }

    func update(baseOpacity: CGFloat) {
        self.baseOpacity = baseOpacity
        applyBarPresentation(animated: false)
    }

    func update(accentColor: NSColor?) {
        self.accentColor = accentColor
        applyBarPresentation(animated: false)
    }

    func update(reduceMotion: Bool) {
        prefersReducedMotion = reduceMotion
    }

    override func layout() {
        super.layout()
        rebuildGeometry()
        applyBarPresentation(animated: false)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        for bar in barLayers {
            bar.contentsScale = scale
        }
    }

    private func rebuildBarLayersIfNeeded(count: Int) {
        guard barLayers.count != count else { return }
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers.removeAll(keepingCapacity: true)
        let host = layer ?? {
            wantsLayer = true
            return layer!
        }()
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        for _ in 0..<count {
            let bar = CALayer()
            bar.contentsScale = scale
            // Disable implicit layout animations; height/opacity are driven
            // explicitly with a spring-like timing curve.
            bar.actions = [
                "bounds": NSNull(),
                "position": NSNull(),
                "backgroundColor": NSNull(),
                "opacity": NSNull(),
                "cornerRadius": NSNull(),
            ]
            host.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    private func rebuildGeometry() {
        rebuildBarLayersIfNeeded(count: style.waveformBarCount)
        let count = max(1, style.waveformBarCount)
        let totalSpacing = style.waveformBarSpacing * CGFloat(max(0, count - 1))
        let availableWidth = max(0, bounds.width - totalSpacing)
        let rawBarWidth = availableWidth / CGFloat(count)
        // Flat Liquid Glass bars — thin rounded rods.
        barWidth = max(1.75, min(2.4, rawBarWidth))
        let contentWidth = (barWidth * CGFloat(count)) + totalSpacing
        contentOriginX = bounds.midX - (contentWidth / 2)
    }

    private func applyBarPresentation(animated: Bool) {
        guard bounds.width > 0.5, bounds.height > 0.5 else { return }
        rebuildGeometry()

        let activeLevels = levels.isEmpty
            ? Array(
                repeating: WaveformNormalizer.minimumVisibleLevel,
                count: style.waveformBarCount
            )
            : levels
        let fill = accentColor ?? VibeWhisperPalette.hudText
        let resolvedFill = fill.usingColorSpace(.sRGB) ?? fill
        // Critically-damped spring-like ease: short response, no overshoot —
        // Apple voice-meter feel rather than bouncy game juice.
        let spring = CAMediaTimingFunction(controlPoints: 0.22, 0.9, 0.28, 1.0)
        let duration: CFTimeInterval = animated ? 0.12 : 0

        for (index, bar) in barLayers.enumerated() {
            let level: CGFloat
            if activeLevels.indices.contains(index) {
                level = activeLevels[index]
            } else {
                level = WaveformNormalizer.minimumVisibleLevel
            }
            let barHeight = max(
                style.waveformMinimumBarHeight,
                bounds.height * level
            )
            let x = contentOriginX
                + CGFloat(index) * (barWidth + style.waveformBarSpacing)
            let frame = CGRect(
                x: x,
                y: bounds.midY - (barHeight / 2),
                width: barWidth,
                height: barHeight
            )
            let opacity = Float(
                min(1, baseOpacity * (0.50 + level * 0.50))
            )

            if animated, duration > 0 {
                // Animate from the live presentation value so mid-flight
                // retargets never jump (Apple interruptibility principle).
                let fromBounds = bar.presentation()?.bounds ?? bar.bounds
                let fromPosition = bar.presentation()?.position ?? bar.position
                let fromOpacity = bar.presentation()?.opacity ?? bar.opacity

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                bar.bounds = CGRect(
                    origin: .zero,
                    size: frame.size
                )
                bar.position = CGPoint(x: frame.midX, y: frame.midY)
                bar.cornerRadius = barWidth / 2
                bar.backgroundColor = resolvedFill.cgColor
                bar.opacity = opacity
                CATransaction.commit()

                let boundsAnim = CABasicAnimation(keyPath: "bounds")
                boundsAnim.fromValue = NSValue(rect: fromBounds)
                boundsAnim.toValue = NSValue(
                    rect: CGRect(origin: .zero, size: frame.size)
                )
                boundsAnim.duration = duration
                boundsAnim.timingFunction = spring
                boundsAnim.fillMode = .both
                boundsAnim.isRemovedOnCompletion = true

                let positionAnim = CABasicAnimation(keyPath: "position")
                positionAnim.fromValue = NSValue(
                    point: fromPosition
                )
                positionAnim.toValue = NSValue(
                    point: CGPoint(x: frame.midX, y: frame.midY)
                )
                positionAnim.duration = duration
                positionAnim.timingFunction = spring
                positionAnim.fillMode = .both
                positionAnim.isRemovedOnCompletion = true

                let opacityAnim = CABasicAnimation(keyPath: "opacity")
                opacityAnim.fromValue = fromOpacity
                opacityAnim.toValue = opacity
                opacityAnim.duration = duration
                opacityAnim.timingFunction = spring
                opacityAnim.fillMode = .both
                opacityAnim.isRemovedOnCompletion = true

                bar.add(boundsAnim, forKey: "vibewhisper.waveform.bounds")
                bar.add(positionAnim, forKey: "vibewhisper.waveform.position")
                bar.add(opacityAnim, forKey: "vibewhisper.waveform.opacity")
            } else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                bar.removeAllAnimations()
                bar.bounds = CGRect(origin: .zero, size: frame.size)
                bar.position = CGPoint(x: frame.midX, y: frame.midY)
                bar.cornerRadius = barWidth / 2
                bar.backgroundColor = resolvedFill.cgColor
                bar.opacity = opacity
                CATransaction.commit()
            }
        }
    }
}
