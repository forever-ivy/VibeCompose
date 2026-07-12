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

    func showRecording(elapsedText: String)
    func updateRecording(level: CGFloat, elapsedText: String)
    func showProcessing()
    func showResult(text: String, outcome: InjectionOutcome)
    func showError(_ message: String)
    func showRetryableError(_ message: String)
    func hide()
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

@MainActor
final class OverlayController: OverlayControlling, OverlaySnapshotCapturing {
    private let style = OverlayStylePreset.dictationHUD
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
    private var escapeHotkeyMonitor: HotkeyMonitor?
    var onCancel: (@MainActor (OverlayCancelSource) -> Void)?
    var onRetry: (@MainActor () -> Void)?

    init(
        onCancel: (@MainActor (OverlayCancelSource) -> Void)? = nil,
        onRetry: (@MainActor () -> Void)? = nil
    ) {
        displayedLevels = Array(
            repeating: WaveformNormalizer.minimumVisibleLevel,
            count: style.waveformBarCount
        )
        currentState = .processing
        waveformView = OverlayWaveformView(
            levels: displayedLevels,
            style: style
        )
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: style.pillWidth, height: style.pillHeight),
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
        case .pasted:
            successKind = .pasted
        case .copiedToClipboard:
            successKind = .copied
        }

        apply(state: .success(successKind))
        present()
        scheduleHide(afterSeconds: style.successAutoHideDelay ?? 1.2)
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
        hideTask?.cancel()
        currentState = state
        positionPanel(size: panelSize(for: state))

        titleLabel.stringValue = state.label
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
            configureBadge(
                symbolName: kind == .pasted ? "checkmark" : "doc.on.clipboard.fill",
                tintColor: kind == .pasted ? OpenWhisperPalette.success : OpenWhisperPalette.amber,
                fillColor: kind == .pasted ? OpenWhisperPalette.success.withAlphaComponent(0.14) : OpenWhisperPalette.amber.withAlphaComponent(0.16),
                borderColor: kind == .pasted ? OpenWhisperPalette.success.withAlphaComponent(0.34) : OpenWhisperPalette.amber.withAlphaComponent(0.38)
            )
        case .error, .retryableError:
            waveformView.isHidden = true
            configureBadge(
                symbolName: "exclamationmark",
                tintColor: OpenWhisperPalette.error,
                fillColor: OpenWhisperPalette.error.withAlphaComponent(0.15),
                borderColor: OpenWhisperPalette.error.withAlphaComponent(0.34)
            )
        }
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
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func scheduleHide(afterSeconds: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(afterSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
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
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Cancel dictation")
        closeButton.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = OpenWhisperPalette.mistMuted.withAlphaComponent(0.78)
        closeButton.toolTip = "Cancel and discard this recording (Esc)"
        closeButton.target = self
        closeButton.action = #selector(handleCancelControlPressed)
        closeButton.setButtonType(.momentaryChange)
        closeButton.focusRingType = .none
        closeButton.isHidden = true

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isBordered = false
        retryButton.bezelStyle = .regularSquare
        retryButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Retry transcription")
        retryButton.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        retryButton.imagePosition = .imageOnly
        retryButton.contentTintColor = OpenWhisperPalette.mistMuted.withAlphaComponent(0.84)
        retryButton.target = self
        retryButton.action = #selector(handleRetryControlPressed)
        retryButton.setButtonType(.momentaryChange)
        retryButton.focusRingType = .none
        retryButton.isHidden = true

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
        NSSize(width: style.width(for: state), height: style.pillHeight)
    }

    private func positionPanel(size: NSSize) {
        let screen = activeScreen() ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(
            Self.panelFrame(
                for: size,
                in: visibleFrame,
                bottomInset: style.bottomInset
            ),
            display: false
        )
    }

    static func panelFrame(
        for size: NSSize,
        in visibleFrame: NSRect,
        bottomInset: CGFloat
    ) -> NSRect {
        let fittedSize = NSSize(
            width: min(size.width, visibleFrame.width),
            height: min(size.height, visibleFrame.height)
        )
        let origin = NSPoint(
            x: visibleFrame.midX - (fittedSize.width / 2),
            y: min(visibleFrame.maxY - fittedSize.height, visibleFrame.minY + bottomInset)
        )
        return NSRect(origin: origin, size: fittedSize)
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
            isTimerVisible: !trailingTimerLabel.isHidden
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

    init(levels: [CGFloat], style: OverlayStylePreset) {
        self.levels = levels
        self.style = style
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
                from: OpenWhisperPalette.mist.withAlphaComponent(0.68),
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
