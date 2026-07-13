import AppKit
import CoreGraphics
import Foundation

enum OverlayCancelSource: String, Sendable, Equatable {
    case escapeKey = "escape-key"
    case inlineClose = "inline-close"
}

@MainActor
protocol OverlayControlling: AnyObject {
    var onCancel: (@MainActor (OverlayCancelSource) -> Void)? { get set }
    var onRetry: (@MainActor () -> Void)? { get set }

    func updateHotkeyBinding(_ binding: HotkeyBinding)
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
    let detailUsesPrimaryText: Bool
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
                detailUsesPrimaryText: true,
                timerOpacity: 1,
                cancelControlOpacity: 1,
                retryControlOpacity: 1,
                waveformBaseOpacity: 0.86
            )
        }

        return OverlayAccessibilityAppearance(
            backgroundBorderWidth: 1,
            backgroundBorderAlpha: 0.08,
            detailUsesPrimaryText: false,
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
    private let panelRootView = OverlayPassthroughView()
    private let backgroundView = NSView()
    private let leadingContainer = NSView()
    private let leadingBadgeView = NSView()
    private let waveformView: OverlayWaveformView
    private let iconView = NSImageView()
    private let closeButton = OverlayHitTargetButton()
    private let retryButton = OverlayHitTargetButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let trailingTimerLabel = NSTextField(labelWithString: "")
    private let textStack = NSStackView()
    private let trailingAccessoryStack = NSStackView()
    private var hideTask: Task<Void, Never>?
    private var processingTimer: Timer?
    private var processingFrameIndex = 0
    private var displayedLevels: [CGFloat]
    private var currentState: OverlayVisualState
    private var hotkeyDisplayName = HotkeyBinding.f5.displayName
    private var alwaysReduceMotion = false
    private var accessibilityAppearance: OverlayAccessibilityAppearance
    private var presentationGeneration = OverlayPresentationGeneration()
    private var escapeHotkeyMonitor: HotkeyMonitor?
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
        panel.hasShadow = true
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

        titleLabel.stringValue = state.label(
            hotkeyDisplayName: hotkeyDisplayName
        )
        detailLabel.stringValue = state.supplementaryText ?? ""
        detailLabel.isHidden = !state.allowsSupplementaryText
        trailingTimerLabel.stringValue = state.trailingText ?? ""
        trailingTimerLabel.isHidden = state.trailingText == nil
        trailingAccessoryStack.isHidden = !state.showsCancelControl && !state.showsRetryControl && state.trailingText == nil
        updateSessionControls(for: state)

        switch state {
        case .recording(let levels, _):
            displayedLevels = levels
            waveformView.isHidden = false
            waveformView.update(levels: levels)
            leadingBadgeView.isHidden = true
            iconView.isHidden = true
        case .processing:
            waveformView.isHidden = false
            waveformView.update(levels: displayedLevels)
            leadingBadgeView.isHidden = true
            iconView.isHidden = true
        case .success(let kind):
            waveformView.isHidden = true
            switch kind {
            case .inserted:
                configureBadge(
                    symbolName: "checkmark",
                    tintColor: OpenWhisperPalette.success,
                    fillColor: OpenWhisperPalette.success.withAlphaComponent(0.14),
                    borderColor: OpenWhisperPalette.success.withAlphaComponent(0.34)
                )
            case .pasteSent:
                configureBadge(
                    symbolName: "arrow.right",
                    tintColor: OpenWhisperPalette.iceBlue,
                    fillColor: OpenWhisperPalette.iceBlue.withAlphaComponent(0.14),
                    borderColor: OpenWhisperPalette.iceBlue.withAlphaComponent(0.34)
                )
            case .copied:
                configureBadge(
                    symbolName: "doc.on.clipboard.fill",
                    tintColor: OpenWhisperPalette.amber,
                    fillColor: OpenWhisperPalette.amber.withAlphaComponent(0.16),
                    borderColor: OpenWhisperPalette.amber.withAlphaComponent(0.38)
                )
            }
        case .error, .retryableError:
            waveformView.isHidden = true
            configureBadge(
                symbolName: "exclamationmark",
                tintColor: OpenWhisperPalette.error,
                fillColor: OpenWhisperPalette.error.withAlphaComponent(0.15),
                borderColor: OpenWhisperPalette.error.withAlphaComponent(0.34)
            )
        }

        announce(state)
    }

    private func configureBadge(
        symbolName: String,
        tintColor: NSColor,
        fillColor: NSColor,
        borderColor: NSColor
    ) {
        leadingBadgeView.isHidden = false
        leadingBadgeView.layer?.backgroundColor = fillColor.cgColor
        leadingBadgeView.layer?.borderColor = borderColor.cgColor

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            iconView.image = image
            iconView.contentTintColor = tintColor
        } else {
            iconView.image = nil
        }

        iconView.isHidden = false
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
                context.duration = 0.14
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
                context.duration = 0.16
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
        panelRootView.translatesAutoresizingMaskIntoConstraints = false
        panelRootView.wantsLayer = false
        panelRootView.interactiveViewsProvider = { [weak self] in
            guard let self else {
                return []
            }
            return [self.closeButton, self.retryButton]
        }
        panel.contentView = panelRootView
        panelRootView.addSubview(backgroundView)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = OpenWhisperPalette.graphite.cgColor
        backgroundView.layer?.cornerRadius = style.cornerRadius
        backgroundView.layer?.borderWidth = 1
        backgroundView.layer?.borderColor = OpenWhisperPalette.mist.withAlphaComponent(0.08).cgColor
        backgroundView.shadow = NSShadow()
        backgroundView.shadow?.shadowBlurRadius = 18
        backgroundView.shadow?.shadowOffset = NSSize(width: 0, height: -2)
        backgroundView.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.35)

        leadingContainer.translatesAutoresizingMaskIntoConstraints = false
        leadingContainer.wantsLayer = false

        leadingBadgeView.translatesAutoresizingMaskIntoConstraints = false
        leadingBadgeView.wantsLayer = true
        leadingBadgeView.layer?.cornerRadius = 14
        leadingBadgeView.layer?.borderWidth = 1
        leadingBadgeView.isHidden = true

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = .init(pointSize: 15, weight: .bold)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.isHidden = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = OpenWhisperPalette.mist
        titleLabel.lineBreakMode = .byTruncatingTail

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 11, weight: .medium)
        detailLabel.textColor = OpenWhisperPalette.mistMuted
        detailLabel.maximumNumberOfLines = 1
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.isHidden = true

        trailingTimerLabel.translatesAutoresizingMaskIntoConstraints = false
        trailingTimerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: style.timerFontSize, weight: .medium)
        trailingTimerLabel.textColor = OpenWhisperPalette.mistMuted.withAlphaComponent(style.timerOpacity)
        trailingTimerLabel.alignment = .right
        trailingTimerLabel.isHidden = true

        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(detailLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: L10n.text("Cancel dictation")
        )
        closeButton.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = OpenWhisperPalette.mistMuted.withAlphaComponent(0.78)
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
        retryButton.contentTintColor = OpenWhisperPalette.mistMuted.withAlphaComponent(0.84)
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

        backgroundView.addSubview(leadingContainer)
        backgroundView.addSubview(textStack)
        backgroundView.addSubview(trailingAccessoryStack)
        leadingContainer.addSubview(waveformView)
        leadingContainer.addSubview(leadingBadgeView)
        leadingContainer.addSubview(iconView)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: panelRootView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: panelRootView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: panelRootView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: panelRootView.bottomAnchor),

            leadingContainer.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: style.contentPaddingH),
            leadingContainer.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            leadingContainer.widthAnchor.constraint(equalToConstant: style.leadingVisualWidth),
            leadingContainer.heightAnchor.constraint(equalToConstant: style.leadingVisualHeight),

            waveformView.leadingAnchor.constraint(equalTo: leadingContainer.leadingAnchor),
            waveformView.trailingAnchor.constraint(equalTo: leadingContainer.trailingAnchor),
            waveformView.topAnchor.constraint(equalTo: leadingContainer.topAnchor),
            waveformView.bottomAnchor.constraint(equalTo: leadingContainer.bottomAnchor),

            leadingBadgeView.centerXAnchor.constraint(equalTo: leadingContainer.centerXAnchor),
            leadingBadgeView.centerYAnchor.constraint(equalTo: leadingContainer.centerYAnchor),
            leadingBadgeView.widthAnchor.constraint(equalToConstant: 48),
            leadingBadgeView.heightAnchor.constraint(equalToConstant: 28),

            iconView.centerXAnchor.constraint(equalTo: leadingBadgeView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: leadingBadgeView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: leadingContainer.trailingAnchor, constant: style.textGap),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAccessoryStack.leadingAnchor, constant: -style.textGap),
            textStack.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),

            trailingAccessoryStack.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -style.contentPaddingH),
            trailingAccessoryStack.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
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
        backgroundView.layer?.borderWidth = accessibilityAppearance.backgroundBorderWidth
        backgroundView.layer?.borderColor = OpenWhisperPalette.mist
            .withAlphaComponent(accessibilityAppearance.backgroundBorderAlpha)
            .cgColor
        titleLabel.textColor = OpenWhisperPalette.mist
        detailLabel.textColor = accessibilityAppearance.detailUsesPrimaryText
            ? OpenWhisperPalette.mist
            : OpenWhisperPalette.mistMuted
        trailingTimerLabel.textColor = OpenWhisperPalette.mistMuted.withAlphaComponent(
            accessibilityAppearance.timerOpacity
        )
        closeButton.contentTintColor = OpenWhisperPalette.mistMuted.withAlphaComponent(
            accessibilityAppearance.cancelControlOpacity
        )
        retryButton.contentTintColor = OpenWhisperPalette.mistMuted.withAlphaComponent(
            accessibilityAppearance.retryControlOpacity
        )
        waveformView.update(baseOpacity: accessibilityAppearance.waveformBaseOpacity)
    }

    private func announce(_ state: OverlayVisualState) {
        let announcement: String
        if let supplementaryText = state.supplementaryText, !supplementaryText.isEmpty {
            announcement =
                "\(state.label(hotkeyDisplayName: hotkeyDisplayName)). "
                + supplementaryText
        } else {
            announcement = state.label(
                hotkeyDisplayName: hotkeyDisplayName
            )
        }

        panelRootView.setAccessibilityElement(true)
        panelRootView.setAccessibilityRole(.group)
        panelRootView.setAccessibilityLabel(announcement)
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func positionPanel(size: NSSize) {
        let screen = activeScreen() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(
            Self.panelFrame(
                for: size,
                in: visibleFrame,
                topInset: style.topInset
            ),
            display: false
        )
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

        let centerInRoot = panelRootView.convert(
            NSPoint(x: closeButton.bounds.midX, y: closeButton.bounds.midY),
            from: closeButton
        )
        guard let hitView = panelRootView.hitTest(centerInRoot) as? NSControl else {
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

        let centerInRoot = panelRootView.convert(
            NSPoint(x: retryButton.bounds.midX, y: retryButton.bounds.midY),
            from: retryButton
        )
        guard let hitView = panelRootView.hitTest(centerInRoot) as? NSControl else {
            return false
        }

        hitView.performClick(nil)
        return true
    }

    var debugSnapshot: OverlayDebugSnapshot {
        OverlayDebugSnapshot(
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

private final class OverlayPassthroughView: NSView {
    var interactiveViewsProvider: (() -> [NSView])?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let interactiveViews = interactiveViewsProvider?() else {
            return nil
        }

        for view in interactiveViews.reversed() where !view.isHidden && view.alphaValue > 0 {
            let pointInView = view.convert(point, from: self)
            if let hitView = view.hitTest(pointInView) {
                return hitView
            }
        }

        return nil
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let activeLevels = levels.isEmpty
            ? Array(repeating: WaveformNormalizer.minimumVisibleLevel, count: style.waveformBarCount)
            : levels

        let totalSpacing = style.waveformBarSpacing * CGFloat(max(0, activeLevels.count - 1))
        let availableWidth = bounds.width - totalSpacing
        let rawBarWidth = availableWidth / CGFloat(max(1, activeLevels.count))
        let barWidth = max(2, min(3, floor(rawBarWidth)))
        let contentWidth = (barWidth * CGFloat(activeLevels.count)) + totalSpacing
        var x = bounds.midX - (contentWidth / 2)
        let center = CGFloat(max(0, activeLevels.count - 1)) / 2

        for (index, level) in activeLevels.enumerated() {
            let barHeight = max(style.waveformMinimumBarHeight, bounds.height * level)
            let barRect = CGRect(
                x: x,
                y: bounds.midY - (barHeight / 2),
                width: barWidth,
                height: barHeight
            )

            let distanceFromCenter = abs(CGFloat(index) - center) / max(1, center)
            let accentMix = (1 - min(1, distanceFromCenter)) * min(1, 0.42 + (level * 0.68))
            let barColor = NSColor.blend(
                from: OpenWhisperPalette.mist.withAlphaComponent(baseOpacity),
                to: OpenWhisperPalette.iceBlue,
                amount: accentMix
            )
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
