import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum BlueSignalFrameState:
    Sendable,
    Equatable
{
    case recording
    case processing
    case success
    case copied
    case error

    var tint: NSColor {
        switch self {
        case .recording, .processing:
            return OpenWhisperPalette.signalBlue
        case .success:
            return OpenWhisperPalette.success
        case .copied:
            return OpenWhisperPalette.amber
        case .error:
            return OpenWhisperPalette.error
        }
    }

    var speed: CGFloat {
        switch self {
        case .recording:
            return 0.0028
        case .processing:
            return 0.006
        case .success, .copied, .error:
            return 0
        }
    }
}

struct BlueSignalFrameDebugSnapshot:
    Sendable,
    Equatable
{
    let isVisible: Bool
    let animationIsActive: Bool
    let targetFrame: CGRect
    let state: BlueSignalFrameState
    let level: CGFloat
}

@MainActor
final class BlueSignalFrameController:
    OverlaySnapshotCapturing
{
    private let accessibilityDisplayOptionsProvider:
        @MainActor () -> AccessibilityDisplayOptions
    private let panel: NSPanel
    private let signalView = BlueSignalFrameView()
    private var timer: Timer?
    private var frozenTargetFrame = CGRect.zero
    private var config = VisualFeedbackConfig()
    private var state: BlueSignalFrameState =
        .processing
    private var level: CGFloat = 0

    init(
        accessibilityDisplayOptionsProvider:
            @escaping @MainActor ()
                -> AccessibilityDisplayOptions
    ) {
        self.accessibilityDisplayOptionsProvider =
            accessibilityDisplayOptionsProvider
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [
                .borderless,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        signalView.translatesAutoresizingMaskIntoConstraints =
            false
        panel.contentView = signalView
    }

    func show(
        state: BlueSignalFrameState,
        level: CGFloat,
        config: VisualFeedbackConfig
    ) {
        self.state = state
        self.level = min(1, max(0, level))
        self.config = config

        if !panel.isVisible || frozenTargetFrame.isEmpty {
            frozenTargetFrame = resolveTargetFrame(
                config.frameTarget
            )
        }
        panel.setFrame(frozenTargetFrame, display: true)
        signalView.update(
            state: state,
            level: self.level,
            intensity: config.intensity,
            increaseContrast:
                accessibilityDisplayOptionsProvider()
                    .increaseContrast
        )
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        updateAnimation()
    }

    func updateRecordingLevel(_ level: CGFloat) {
        self.level = min(1, max(0, level))
        signalView.updateLevel(self.level)
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
        frozenTargetFrame = .zero
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
            let bitmap =
                contentView.bitmapImageRepForCachingDisplay(
                    in: bounds
                )
        else {
            throw OverlaySnapshotError.bitmapUnavailable
        }
        contentView.cacheDisplay(
            in: bounds,
            to: bitmap
        )
        guard
            let png = bitmap.representation(
                using: .png,
                properties: [:]
            )
        else {
            throw OverlaySnapshotError.pngEncodingFailed
        }
        try png.write(to: url, options: [.atomic])
    }

    private func updateAnimation() {
        timer?.invalidate()
        timer = nil
        guard
            state.speed > 0,
            !accessibilityDisplayOptionsProvider()
                .reduceMotion,
            !config.alwaysReduceMotion
        else {
            signalView.setStaticPhase()
            return
        }

        timer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 30.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.signalView.advance(
                    by:
                        self.state.speed
                        * CGFloat(
                            self.config.intensity
                                .amplitudeScale
                        )
                )
            }
        }
    }

    private func resolveTargetFrame(
        _ target: BlueSignalFrameTarget
    ) -> CGRect {
        switch target {
        case .activeDisplay:
            return activeScreenFrame()
        case .focusedWindow:
            return focusedWindowFrame()
                ?? activeScreenFrame()
        }
    }

    private func activeScreenFrame() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(mouseLocation)
        }) ?? NSScreen.main
        return (screen?.frame
            ?? CGRect(
                x: 0,
                y: 0,
                width: 1440,
                height: 900
            )).insetBy(dx: 2, dy: 2)
    }

    private func focusedWindowFrame() -> CGRect? {
        guard
            AccessibilityPermission.isTrusted()
        else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedApplication: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedApplicationAttribute
                    as CFString,
                &focusedApplication
            ) == .success,
            let focusedApplication
        else {
            return nil
        }

        var focusedWindow: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                unsafeBitCast(
                    focusedApplication,
                    to: AXUIElement.self
                ),
                kAXFocusedWindowAttribute as CFString,
                &focusedWindow
            ) == .success,
            let focusedWindow
        else {
            return nil
        }

        let window = unsafeBitCast(
            focusedWindow,
            to: AXUIElement.self
        )
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                window,
                kAXPositionAttribute as CFString,
                &positionValue
            ) == .success,
            AXUIElementCopyAttributeValue(
                window,
                kAXSizeAttribute as CFString,
                &sizeValue
            ) == .success,
            let positionValue,
            let sizeValue
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(
                unsafeBitCast(
                    positionValue,
                    to: AXValue.self
                ),
                .cgPoint,
                &position
            ),
            AXValueGetValue(
                unsafeBitCast(
                    sizeValue,
                    to: AXValue.self
                ),
                .cgSize,
                &size
            ),
            size.width >= 120,
            size.height >= 80
        else {
            return nil
        }

        let desktopTop = NSScreen.screens
            .map(\.frame.maxY)
            .max() ?? 0
        return CGRect(
            x: position.x - 2,
            y:
                desktopTop - position.y
                - size.height - 2,
            width: size.width + 4,
            height: size.height + 4
        )
    }

    var debugSnapshot:
        BlueSignalFrameDebugSnapshot
    {
        BlueSignalFrameDebugSnapshot(
            isVisible: panel.isVisible,
            animationIsActive: timer?.isValid == true,
            targetFrame: frozenTargetFrame,
            state: state,
            level: level
        )
    }
}

@MainActor
private final class BlueSignalFrameView: NSView {
    private var state:
        BlueSignalFrameState = .processing
    private var level: CGFloat = 0
    private var phase: CGFloat = 0.18
    private var intensity:
        VisualFeedbackIntensity = .standard
    private var increaseContrast = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        state: BlueSignalFrameState,
        level: CGFloat,
        intensity: VisualFeedbackIntensity,
        increaseContrast: Bool
    ) {
        self.state = state
        self.level = level
        self.intensity = intensity
        self.increaseContrast = increaseContrast
        needsDisplay = true
    }

    func updateLevel(_ level: CGFloat) {
        self.level = level
        needsDisplay = true
    }

    func advance(by delta: CGFloat) {
        phase = (phase + delta)
            .truncatingRemainder(dividingBy: 1)
        needsDisplay = true
    }

    func setStaticPhase() {
        phase = 0.18
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 8, bounds.height > 8 else {
            return
        }

        let intensityScale = CGFloat(
            intensity.amplitudeScale
        )
        let inset: CGFloat = increaseContrast ? 2 : 2.5
        let lineWidth =
            (increaseContrast ? 1.75 : 1.15)
            * intensityScale
        let borderRect = bounds.insetBy(
            dx: inset,
            dy: inset
        )
        let basePath = NSBezierPath(
            roundedRect: borderRect,
            xRadius: 14,
            yRadius: 14
        )
        basePath.lineWidth = lineWidth
        state.tint.withAlphaComponent(
            increaseContrast ? 0.34 : 0.2
        ).setStroke()
        basePath.stroke()

        let voiceBoost =
            state == .recording
                ? min(0.15, level * 0.15)
                : 0.08
        let highlightAlpha = min(
            1,
            (increaseContrast ? 0.92 : 0.76)
                + voiceBoost
        )
        let highlightWidth =
            min(2.2, lineWidth + 0.72)
        let segmentFraction: CGFloat =
            state.speed == 0 ? 0.18 : 0.09
        drawHighlight(
            in: borderRect,
            phase: phase,
            fraction: segmentFraction,
            lineWidth: highlightWidth,
            color:
                state.tint.withAlphaComponent(
                    highlightAlpha
                )
        )
    }

    private func drawHighlight(
        in rect: CGRect,
        phase: CGFloat,
        fraction: CGFloat,
        lineWidth: CGFloat,
        color: NSColor
    ) {
        let perimeter =
            2 * (rect.width + rect.height)
        guard perimeter > 0 else {
            return
        }
        let start = phase * perimeter
        let length = max(40, fraction * perimeter)
        let samples = max(
            12,
            Int(length / 8)
        )
        let path = NSBezierPath()
        var previousDistance: CGFloat?
        for index in 0...samples {
            let distance =
                (start
                    + (
                        CGFloat(index)
                        / CGFloat(samples)
                    ) * length)
                .truncatingRemainder(
                    dividingBy: perimeter
                )
            let point = point(
                on: rect,
                distance: distance
            )
            if index == 0
                || (
                    previousDistance != nil
                        && distance
                            < previousDistance!
                )
            {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
            previousDistance = distance
        }
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func point(
        on rect: CGRect,
        distance: CGFloat
    ) -> CGPoint {
        var remaining = distance
        if remaining <= rect.width {
            return CGPoint(
                x: rect.minX + remaining,
                y: rect.maxY
            )
        }
        remaining -= rect.width
        if remaining <= rect.height {
            return CGPoint(
                x: rect.maxX,
                y: rect.maxY - remaining
            )
        }
        remaining -= rect.height
        if remaining <= rect.width {
            return CGPoint(
                x: rect.maxX - remaining,
                y: rect.minY
            )
        }
        remaining -= rect.width
        return CGPoint(
            x: rect.minX,
            y: rect.minY + min(
                remaining,
                rect.height
            )
        )
    }
}
