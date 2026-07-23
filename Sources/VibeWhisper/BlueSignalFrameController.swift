import AppKit
import ApplicationServices
import CoreGraphics
import CoreImage
import Foundation
import QuartzCore

/// Semantic state for the Agent Activity Indicator. The historical type name is
/// retained as a source-compatibility boundary for existing tests and scripts.
enum BlueSignalFrameState: String,
    Codable,
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

}

typealias AIActivityGlowState = BlueSignalFrameState

enum AIActivityGlowMotion:
    Sendable,
    Equatable
{
    case breathe
    case settle
}

struct AIActivityGlowLayerStyle:
    Sendable,
    Equatable
{
    let lineWidthMultiplier: CGFloat
    let blurRadius: CGFloat
    let opacity: Float
}

struct AIActivityGlowBreathingStyle:
    Sendable,
    Equatable
{
    let animatedLayerCount: Int
    let halfCycleDuration: CFTimeInterval
    let minimumOpacityMultiplier: Float
    let colorShiftFraction: CGFloat
}

/// One-shot pulse played when the glow settles into a result state: a soft
/// scale bloom plus an opacity swell that eases back out, like the confirmation
/// ripple macOS 26 plays on its floating controls.
struct AIActivityGlowSettleStyle:
    Sendable,
    Equatable
{
    let peakOpacity: Float
    let scalePeak: CGFloat
    let scaleDuration: CFTimeInterval
    let opacitySwellDuration: CFTimeInterval

    static let standard = AIActivityGlowSettleStyle(
        peakOpacity: 1,
        scalePeak: 1.02,
        scaleDuration: 0.46,
        opacitySwellDuration: 0.5
    )
}

struct AIActivityGlowTransition:
    Sendable,
    Equatable
{
    let duration: CFTimeInterval
    let controlPoint1: CGPoint
    let controlPoint2: CGPoint
}

enum AIActivityGlowTransitionProfile {
    static let paletteCrossfadeDuration: CFTimeInterval = 0.35
    static let appearance = AIActivityGlowTransition(
        duration: 0.32,
        controlPoint1: CGPoint(x: 0.22, y: 1),
        controlPoint2: CGPoint(x: 0.36, y: 1)
    )
    static let disappearance = AIActivityGlowTransition(
        duration: 0.28,
        controlPoint1: CGPoint(x: 0.4, y: 0),
        controlPoint2: CGPoint(x: 0.6, y: 1)
    )
}

struct AIActivityGlowVisualProfile:
    Sendable,
    Equatable
{
    let segmentCount: Int
    let baseLineWidth: CGFloat
    let layerStyles: [AIActivityGlowLayerStyle]
    let breathing: AIActivityGlowBreathingStyle?
    let settle: AIActivityGlowSettleStyle?
    let edgeInset: CGFloat
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let motion: AIActivityGlowMotion

    static func resolve(
        state: AIActivityGlowState,
        intensity: VisualFeedbackIntensity,
        target: BlueSignalFrameTarget,
        increaseContrast: Bool
    ) -> Self {
        let baseLineWidth: CGFloat = switch intensity {
        case .subtle:
            14
        case .standard:
            20
        case .expressive:
            26
        }
        let blurScale: CGFloat = switch intensity {
        case .subtle:
            0.82
        case .standard:
            1
        case .expressive:
            1.18
        }
        let contrastBoost: Float = increaseContrast ? 0.1 : 0
        let layerStyles = [
            AIActivityGlowLayerStyle(
                lineWidthMultiplier: 1,
                blurRadius: 20 * blurScale,
                opacity: min(1, 0.22 + contrastBoost)
            ),
            AIActivityGlowLayerStyle(
                lineWidthMultiplier: 0.58,
                blurRadius: 12 * blurScale,
                opacity: min(1, 0.42 + contrastBoost)
            ),
            AIActivityGlowLayerStyle(
                lineWidthMultiplier: 0.24,
                blurRadius: 4 * blurScale,
                opacity: min(1, 0.82 + contrastBoost)
            ),
            AIActivityGlowLayerStyle(
                lineWidthMultiplier: 0.12,
                blurRadius: 0,
                opacity: min(1, 1 + contrastBoost * 0.5)
            ),
        ]
        let outerBloomReach = baseLineWidth
            * layerStyles[0].lineWidthMultiplier / 2
            + layerStyles[0].blurRadius
        let edgeInset: CGFloat = target == .focusedWindow
            ? ceil(outerBloomReach + 6)
            : 1.5
        let topCornerRadius: CGFloat = target == .focusedWindow ? 17 : 18
        let bottomCornerRadius: CGFloat = 0

        switch state {
        case .recording:
            return Self(
                segmentCount: 32,
                baseLineWidth: baseLineWidth,
                layerStyles: layerStyles,
                breathing: AIActivityGlowBreathingStyle(
                    animatedLayerCount: 2,
                    halfCycleDuration: 1.6,
                    minimumOpacityMultiplier: 0.76,
                    colorShiftFraction: 0.14
                ),
                settle: nil,
                edgeInset: edgeInset,
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                motion: .breathe
            )
        case .processing:
            return Self(
                segmentCount: 32,
                baseLineWidth: baseLineWidth,
                layerStyles: layerStyles,
                breathing: AIActivityGlowBreathingStyle(
                    animatedLayerCount: 3,
                    halfCycleDuration: 0.95,
                    minimumOpacityMultiplier: 0.58,
                    colorShiftFraction: 0.22
                ),
                settle: nil,
                edgeInset: edgeInset,
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                motion: .breathe
            )
        case .success, .copied, .error:
            return Self(
                segmentCount: 32,
                baseLineWidth: baseLineWidth,
                layerStyles: layerStyles,
                breathing: nil,
                settle: .standard,
                edgeInset: edgeInset,
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                motion: .settle
            )
        }
    }
}

struct BlueSignalFrameDebugSnapshot:
    Sendable,
    Equatable
{
    let isVisible: Bool
    let panelIsVisible: Bool
    let animationIsActive: Bool
    let targetFrame: CGRect
    let state: BlueSignalFrameState
    let level: CGFloat
    let animationKeys: [String]
    let glowOpacity: Float
    let ambientBreathingLayerCount: Int
}

@MainActor
final class BlueSignalFrameController:
    OverlaySnapshotCapturing
{
    private let accessibilityDisplayOptionsProvider:
        @MainActor () -> AccessibilityDisplayOptions
    private let panel: NSPanel
    private let signalView = AIActivityGlowView()
    private var frozenTargetFrame = CGRect.zero
    private var config = VisualFeedbackConfig()
    private var state: BlueSignalFrameState = .processing
    private var level: CGFloat = 0
    private var transitionGeneration = 0
    private var logicallyVisible = false

    init(
        accessibilityDisplayOptionsProvider:
            @escaping @MainActor () -> AccessibilityDisplayOptions
    ) {
        self.accessibilityDisplayOptionsProvider = accessibilityDisplayOptionsProvider
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
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
        signalView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = signalView
    }

    func show(
        state: BlueSignalFrameState,
        level: CGFloat,
        config: VisualFeedbackConfig,
        retarget: Bool = false
    ) {
        let wasLogicallyVisible = logicallyVisible
        let wasPanelVisible = panel.isVisible
        transitionGeneration &+= 1
        logicallyVisible = true
        self.state = state
        self.level = min(1, max(0, level))
        self.config = config
        let options = accessibilityDisplayOptionsProvider()

        if retarget || !wasLogicallyVisible || frozenTargetFrame.isEmpty {
            frozenTargetFrame = resolveTargetFrame(
                config.frameTarget,
                intensity: config.intensity,
                increaseContrast: options.increaseContrast
            )
        }
        panel.setFrame(frozenTargetFrame, display: true)
        signalView.update(
            state: state,
            level: self.level,
            intensity: config.intensity,
            target: config.frameTarget,
            reduceMotion: options.reduceMotion || config.alwaysReduceMotion,
            increaseContrast: options.increaseContrast
        )

        if !wasPanelVisible {
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        if !wasLogicallyVisible || !wasPanelVisible {
            animatePanelAlpha(
                to: 1,
                transition: AIActivityGlowTransitionProfile.appearance
            )
        } else {
            // State-to-state transitions must never inherit a pending fade-out.
            // In particular, stopping a recording keeps the same panel visible
            // while the glow changes from recording to processing.
            panel.alphaValue = 1
        }
    }

    func updateRecordingLevel(_ level: CGFloat) {
        self.level = min(1, max(0, level))
        signalView.updateLevel(self.level)
    }

    func hide() {
        transitionGeneration &+= 1
        let generation = transitionGeneration
        logicallyVisible = false
        signalView.resetPresentation()
        frozenTargetFrame = .zero

        guard panel.isVisible else {
            panel.alphaValue = 0
            return
        }

        animatePanelAlpha(
            to: 0,
            transition: AIActivityGlowTransitionProfile.disappearance
        ) { [weak self] in
            guard let self,
                  self.transitionGeneration == generation,
                  !self.logicallyVisible
            else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 0
        }
    }

    private func animatePanelAlpha(
        to targetAlpha: CGFloat,
        transition: AIActivityGlowTransition,
        completion: (@MainActor () -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = transition.duration
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: Float(transition.controlPoint1.x),
                Float(transition.controlPoint1.y),
                Float(transition.controlPoint2.x),
                Float(transition.controlPoint2.y)
            )
            panel.animator().alphaValue = targetAlpha
        } completionHandler: {
            Task { @MainActor in
                completion?()
            }
        }
    }

    func writeSnapshot(to url: URL) throws {
        guard let contentView = panel.contentView else {
            throw OverlaySnapshotError.missingContentView
        }
        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()
        let bounds = contentView.bounds
        guard bounds.width > 0,
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

    private func resolveTargetFrame(
        _ target: BlueSignalFrameTarget,
        intensity: VisualFeedbackIntensity,
        increaseContrast: Bool
    ) -> CGRect {
        switch target {
        case .activeDisplay:
            return activeScreenFrame()
        case .focusedWindow:
            let profile = AIActivityGlowVisualProfile.resolve(
                state: state,
                intensity: intensity,
                target: target,
                increaseContrast: increaseContrast
            )
            return focusedWindowFrame(expansion: profile.edgeInset)
                ?? activeScreenFrame()
        }
    }

    /// Display targeting uses an inner glow so the ambient layer is never
    /// clipped by the screen or a neighboring display.
    private func activeScreenFrame() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(mouseLocation)
        }) ?? NSScreen.main
        return screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Focused-window targeting expands the non-activating panel around the AX
    /// window; the visible core remains aligned to the original window edge.
    private func focusedWindowFrame(expansion: CGFloat) -> CGRect? {
        guard AccessibilityPermission.isTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApplication: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApplication
        ) == .success,
        let focusedApplication else { return nil }

        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            unsafeBitCast(focusedApplication, to: AXUIElement.self),
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success,
        let focusedWindow else { return nil }

        let window = unsafeBitCast(focusedWindow, to: AXUIElement.self)
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
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
        let sizeValue else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(
            unsafeBitCast(positionValue, to: AXValue.self),
            .cgPoint,
            &position
        ),
        AXValueGetValue(
            unsafeBitCast(sizeValue, to: AXValue.self),
            .cgSize,
            &size
        ),
        size.width >= 120,
        size.height >= 80 else { return nil }

        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGRect(
            x: position.x - expansion,
            y: desktopTop - position.y - size.height - expansion,
            width: size.width + expansion * 2,
            height: size.height + expansion * 2
        )
    }

    var debugSnapshot: BlueSignalFrameDebugSnapshot {
        BlueSignalFrameDebugSnapshot(
            isVisible: logicallyVisible,
            panelIsVisible: panel.isVisible,
            animationIsActive: signalView.animationIsActive,
            targetFrame: frozenTargetFrame,
            state: state,
            level: level,
            animationKeys: signalView.activeAnimationKeys,
            glowOpacity: signalView.glowOpacity,
            ambientBreathingLayerCount:
                signalView.ambientBreathingLayerCount
        )
    }
}

typealias AIActivityGlowController = BlueSignalFrameController

@MainActor
private final class AIActivityGlowView: NSView {
    private let ringLayer = CALayer()
    private var segmentLayers: [[CAShapeLayer]] = []
    private var state: BlueSignalFrameState = .processing
    private var level: CGFloat = 0
    private var intensity: VisualFeedbackIntensity = .standard
    private var target: BlueSignalFrameTarget = .activeDisplay
    private var reduceMotion = false
    private var increaseContrast = false
    private var hasRenderedState = false
    private var profile = AIActivityGlowVisualProfile.resolve(
        state: .processing,
        intensity: .standard,
        target: .activeDisplay,
        increaseContrast: false
    )

    private var animatedLayers: [CALayer] {
        var layers: [CALayer] = [ringLayer]
        layers.append(contentsOf: segmentLayers.flatMap { $0 })
        return layers
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        ringLayer.masksToBounds = false
        ringLayer.opacity = 1
        layer?.addSublayer(ringLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    func update(
        state: BlueSignalFrameState,
        level: CGFloat,
        intensity: VisualFeedbackIntensity,
        target: BlueSignalFrameTarget,
        reduceMotion: Bool,
        increaseContrast: Bool
    ) {
        let previousState = self.state
        let previousPalette = palette
        self.state = state
        self.level = min(1, max(0, level))
        self.intensity = intensity
        self.target = target
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        profile = AIActivityGlowVisualProfile.resolve(
            state: state,
            intensity: intensity,
            target: target,
            increaseContrast: increaseContrast
        )

        rebuildSegmentLayers()
        updateGeometry()
        updateColors()
        let shouldCrossfadePalette = hasRenderedState
            && previousState != state
            && !reduceMotion
        configureAnimations(
            colorBreathingDelay: shouldCrossfadePalette
                ? AIActivityGlowTransitionProfile.paletteCrossfadeDuration
                : 0
        )
        if shouldCrossfadePalette {
            addPaletteTransition(from: previousPalette)
        }
        updateLevel(self.level)
        hasRenderedState = true
    }

    func updateLevel(_ level: CGFloat) {
        self.level = min(1, max(0, level))
    }

    func stopAnimations() {
        ringLayer.removeAllAnimations()
        for segmentLayer in segmentLayers.flatMap({ $0 }) {
            segmentLayer.removeAllAnimations()
        }
    }

    func resetPresentation() {
        stopAnimations()
        hasRenderedState = false
    }

    var animationIsActive: Bool {
        animatedLayers.contains {
            !($0.animationKeys() ?? []).isEmpty
        }
    }

    var activeAnimationKeys: [String] {
        Array(Set(animatedLayers.flatMap { $0.animationKeys() ?? [] }))
            .sorted()
    }

    var glowOpacity: Float {
        ringLayer.opacity
    }

    var ambientBreathingLayerCount: Int {
        guard activeAnimationKeys.contains(
            "openwhisper.edgeGlow.ambientBreathing"
        ) else { return 0 }
        return profile.breathing?.animatedLayerCount ?? 0
    }

    // EdgeGlow's MIT-licensed four-layer neon stack is adapted here from
    // GlowWindow.swift at commit d39d0471a25af97d8de077591f69f938efa8bea8.
    // OpenWhisper supplies its own lifecycle, palettes, accessibility behavior,
    // target freezing, and dictation-state choreography around that renderer.
    private func rebuildSegmentLayers() {
        stopAnimations()
        ringLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        segmentLayers.removeAll(keepingCapacity: true)

        for segmentIndex in 0..<profile.segmentCount {
            var layersForSegment: [CAShapeLayer] = []
            for style in profile.layerStyles {
                let shapeLayer = CAShapeLayer()
                shapeLayer.fillColor = nil
                shapeLayer.lineCap = .butt
                shapeLayer.lineJoin = .miter
                shapeLayer.miterLimit = 4
                shapeLayer.opacity = style.opacity
                let overlap: CGFloat = 0.0008
                shapeLayer.strokeStart = max(
                    0,
                    CGFloat(segmentIndex) / CGFloat(profile.segmentCount)
                        - overlap
                )
                shapeLayer.strokeEnd = min(
                    1,
                    CGFloat(segmentIndex + 1) / CGFloat(profile.segmentCount)
                        + overlap
                )

                if style.blurRadius > 0,
                   let blur = CIFilter(name: "CIGaussianBlur")
                {
                    blur.setValue(style.blurRadius, forKey: "inputRadius")
                    shapeLayer.filters = [blur]
                    shapeLayer.contentsScale = 0.5
                } else {
                    shapeLayer.contentsScale = NSScreen.main?
                        .backingScaleFactor ?? 2
                }

                ringLayer.addSublayer(shapeLayer)
                layersForSegment.append(shapeLayer)
            }
            segmentLayers.append(layersForSegment)
        }
    }

    private func updateGeometry() {
        guard bounds.width > 12, bounds.height > 12 else { return }
        let rect = bounds.insetBy(
            dx: profile.edgeInset,
            dy: profile.edgeInset
        )
        let path = asymmetricEdgePath(
            rect: rect,
            topCornerRadius: profile.topCornerRadius,
            bottomCornerRadius: profile.bottomCornerRadius
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.frame = bounds
        for layersForSegment in segmentLayers {
            for (styleIndex, shapeLayer) in layersForSegment.enumerated() {
                guard profile.layerStyles.indices.contains(styleIndex) else {
                    continue
                }
                let style = profile.layerStyles[styleIndex]
                shapeLayer.frame = bounds
                shapeLayer.path = path
                shapeLayer.lineWidth = max(
                    1,
                    profile.baseLineWidth * style.lineWidthMultiplier
                )
            }
        }
        CATransaction.commit()
    }

    private func asymmetricEdgePath(
        rect: CGRect,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat
    ) -> CGPath {
        let maximumRadius = max(0, min(rect.width, rect.height) / 2)
        let topRadius = min(max(0, topCornerRadius), maximumRadius)
        let bottomRadius = min(max(0, bottomCornerRadius), maximumRadius)
        let path = CGMutablePath()

        path.move(to: CGPoint(x: rect.minX + bottomRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - bottomRadius, y: rect.minY))
        if bottomRadius > 0 {
            path.addArc(
                center: CGPoint(
                    x: rect.maxX - bottomRadius,
                    y: rect.minY + bottomRadius
                ),
                radius: bottomRadius,
                startAngle: -.pi / 2,
                endAngle: 0,
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - topRadius))
        if topRadius > 0 {
            path.addArc(
                center: CGPoint(
                    x: rect.maxX - topRadius,
                    y: rect.maxY - topRadius
                ),
                radius: topRadius,
                startAngle: 0,
                endAngle: .pi / 2,
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY))
        if topRadius > 0 {
            path.addArc(
                center: CGPoint(
                    x: rect.minX + topRadius,
                    y: rect.maxY - topRadius
                ),
                radius: topRadius,
                startAngle: .pi / 2,
                endAngle: .pi,
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bottomRadius))
        if bottomRadius > 0 {
            path.addArc(
                center: CGPoint(
                    x: rect.minX + bottomRadius,
                    y: rect.minY + bottomRadius
                ),
                radius: bottomRadius,
                startAngle: .pi,
                endAngle: .pi * 1.5,
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }

    private func updateColors() {
        let colors = palette
        guard !colors.isEmpty else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (segmentIndex, layersForSegment) in segmentLayers.enumerated() {
            let baseColor = interpolatedPaletteColor(
                segmentIndex: segmentIndex,
                colors: colors
            )
            for (styleIndex, shapeLayer) in layersForSegment.enumerated() {
                let whiteMix: CGFloat = switch styleIndex {
                case 2:
                    0.14
                case 3:
                    0.44
                default:
                    0
                }
                let color = baseColor.blended(
                    withFraction: whiteMix,
                    of: .white
                ) ?? baseColor
                shapeLayer.strokeColor = color.cgColor
                if profile.layerStyles.indices.contains(styleIndex) {
                    shapeLayer.opacity = profile.layerStyles[styleIndex].opacity
                }
            }
        }
        ringLayer.opacity = 1
        CATransaction.commit()
    }

    private func interpolatedPaletteColor(
        segmentIndex: Int,
        colors: [NSColor]
    ) -> NSColor {
        guard colors.count > 1 else { return colors[0] }
        let progress = CGFloat(segmentIndex)
            / CGFloat(max(1, profile.segmentCount))
        let scaledIndex = progress * CGFloat(colors.count - 1)
        let lowerIndex = min(
            colors.count - 2,
            max(0, Int(floor(scaledIndex)))
        )
        let fraction = scaledIndex - CGFloat(lowerIndex)
        return colors[lowerIndex].blended(
            withFraction: fraction,
            of: colors[lowerIndex + 1]
        ) ?? colors[lowerIndex]
    }

    private func configureAnimations(
        colorBreathingDelay: CFTimeInterval
    ) {
        for animatedLayer in animatedLayers {
            animatedLayer.removeAllAnimations()
        }
        guard !reduceMotion else { return }

        switch profile.motion {
        case .breathe:
            addAmbientBreathing(
                colorAnimationDelay: colorBreathingDelay
            )
        case .settle:
            addSettleTransition()
        }
    }

    private func addAmbientBreathing(
        colorAnimationDelay: CFTimeInterval
    ) {
        guard let breathing = profile.breathing else { return }
        let animatedLayerCount = min(
            breathing.animatedLayerCount,
            profile.layerStyles.count
        )

        for layersForSegment in segmentLayers {
            for styleIndex in 0..<animatedLayerCount {
                guard layersForSegment.indices.contains(styleIndex) else {
                    continue
                }
                let shapeLayer = layersForSegment[styleIndex]
                let style = profile.layerStyles[styleIndex]
                let breathe = CABasicAnimation(keyPath: "opacity")
                breathe.fromValue = style.opacity
                breathe.toValue = style.opacity
                    * breathing.minimumOpacityMultiplier
                breathe.duration = breathing.halfCycleDuration
                breathe.autoreverses = true
                breathe.repeatCount = .infinity
                breathe.timingFunction = CAMediaTimingFunction(
                    name: .easeInEaseOut
                )
                shapeLayer.add(
                    breathe,
                    forKey: "openwhisper.edgeGlow.ambientBreathing"
                )

                guard let strokeColor = shapeLayer.strokeColor,
                      let baseColor = NSColor(cgColor: strokeColor),
                      let shiftedColor = baseColor.blended(
                          withFraction: breathing.colorShiftFraction,
                          of: ambientBreathingTint
                      )
                else { continue }
                let colorBreathing = CABasicAnimation(keyPath: "strokeColor")
                colorBreathing.fromValue = strokeColor
                colorBreathing.toValue = shiftedColor.cgColor
                colorBreathing.duration = breathing.halfCycleDuration
                colorBreathing.autoreverses = true
                colorBreathing.repeatCount = .infinity
                if colorAnimationDelay > 0 {
                    colorBreathing.beginTime = shapeLayer.convertTime(
                        CACurrentMediaTime(),
                        from: nil
                    ) + colorAnimationDelay
                }
                colorBreathing.timingFunction = CAMediaTimingFunction(
                    name: .easeInEaseOut
                )
                shapeLayer.add(
                    colorBreathing,
                    forKey: "openwhisper.edgeGlow.ambientColorBreathing"
                )
            }
        }
    }

    private func addPaletteTransition(from colors: [NSColor]) {
        guard !colors.isEmpty else { return }

        for (segmentIndex, layersForSegment) in segmentLayers.enumerated() {
            let previousBaseColor = interpolatedPaletteColor(
                segmentIndex: segmentIndex,
                colors: colors
            )
            for (styleIndex, shapeLayer) in layersForSegment.enumerated() {
                let whiteMix: CGFloat = switch styleIndex {
                case 2:
                    0.14
                case 3:
                    0.44
                default:
                    0
                }
                let previousColor = previousBaseColor.blended(
                    withFraction: whiteMix,
                    of: .white
                ) ?? previousBaseColor
                guard let targetColor = shapeLayer.strokeColor else {
                    continue
                }

                let transition = CABasicAnimation(keyPath: "strokeColor")
                transition.fromValue = previousColor.cgColor
                transition.toValue = targetColor
                transition.duration = AIActivityGlowTransitionProfile
                    .paletteCrossfadeDuration
                transition.timingFunction = CAMediaTimingFunction(
                    name: .easeInEaseOut
                )
                shapeLayer.add(
                    transition,
                    forKey: "openwhisper.edgeGlow.paletteCrossfade"
                )
            }
        }
    }

    private var ambientBreathingTint: NSColor {
        switch state {
        case .recording:
            return NSColor(
                srgbRed: 0.1,
                green: 0.82,
                blue: 1,
                alpha: 1
            )
        case .processing:
            return NSColor(
                srgbRed: 0.62,
                green: 0.42,
                blue: 1,
                alpha: 1
            )
        case .success:
            return NSColor(
                srgbRed: 0.45,
                green: 1,
                blue: 0.78,
                alpha: 1
            )
        case .copied:
            return NSColor(
                srgbRed: 1,
                green: 0.86,
                blue: 0.42,
                alpha: 1
            )
        case .error:
            return NSColor(
                srgbRed: 1,
                green: 0.34,
                blue: 0.5,
                alpha: 1
            )
        }
    }

    private func addSettleTransition() {
        guard let settle = profile.settle else { return }

        let scaleBloom = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleBloom.values = [1.0, settle.scalePeak, 1.0]
        scaleBloom.keyTimes = [0, 0.38, 1]
        scaleBloom.duration = settle.scaleDuration
        scaleBloom.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(
                controlPoints: 0.3, 0, 0.4, 1
            ),
        ]
        ringLayer.add(
            scaleBloom,
            forKey: "openwhisper.edgeGlow.settleScaleBloom"
        )

        let swell = CAKeyframeAnimation(keyPath: "opacity")
        swell.values = [0.9, settle.peakOpacity, settle.peakOpacity]
        swell.keyTimes = [0, 0.28, 1]
        swell.duration = settle.opacitySwellDuration
        swell.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        ringLayer.add(
            swell,
            forKey: "openwhisper.edgeGlow.settle"
        )
    }

    private var palette: [NSColor] {
        switch state {
        case .recording:
            // Cool cyan-to-azure spectrum: calm and unmistakably "listening".
            return [
                NSColor(srgbRed: 0.05, green: 0.62, blue: 0.98, alpha: 1),
                NSColor(srgbRed: 0.07, green: 0.78, blue: 0.98, alpha: 1),
                NSColor(srgbRed: 0.05, green: 0.88, blue: 0.9, alpha: 1),
                NSColor(srgbRed: 0.16, green: 0.66, blue: 1, alpha: 1),
                NSColor(srgbRed: 0.08, green: 0.5, blue: 1, alpha: 1),
                NSColor(srgbRed: 0.05, green: 0.62, blue: 0.98, alpha: 1),
            ]
        case .processing:
            // Violet-to-indigo: the AI "thinking" hue, distinct from recording.
            return [
                NSColor(srgbRed: 0.48, green: 0.34, blue: 1, alpha: 1),
                NSColor(srgbRed: 0.62, green: 0.38, blue: 1, alpha: 1),
                NSColor(srgbRed: 0.44, green: 0.42, blue: 1, alpha: 1),
                NSColor(srgbRed: 0.34, green: 0.5, blue: 1, alpha: 1),
                NSColor(srgbRed: 0.56, green: 0.3, blue: 0.98, alpha: 1),
                NSColor(srgbRed: 0.48, green: 0.34, blue: 1, alpha: 1),
            ]
        case .success:
            // Mint to soft green.
            return [
                OpenWhisperPalette.success,
                NSColor(srgbRed: 0.24, green: 0.92, blue: 0.62, alpha: 1),
                NSColor(srgbRed: 0.5, green: 0.96, blue: 0.7, alpha: 1),
                NSColor(srgbRed: 0.3, green: 0.86, blue: 0.56, alpha: 1),
                OpenWhisperPalette.success,
            ]
        case .copied:
            // Warm amber-to-gold, clearly warmer than success.
            return [
                OpenWhisperPalette.amber,
                NSColor(srgbRed: 1, green: 0.82, blue: 0.3, alpha: 1),
                NSColor(srgbRed: 1, green: 0.66, blue: 0.18, alpha: 1),
                NSColor(srgbRed: 1, green: 0.76, blue: 0.24, alpha: 1),
                OpenWhisperPalette.amber,
            ]
        case .error:
            // Rose to coral, avoiding a harsh traffic-light red.
            return [
                OpenWhisperPalette.error,
                NSColor(srgbRed: 1, green: 0.3, blue: 0.42, alpha: 1),
                NSColor(srgbRed: 1, green: 0.44, blue: 0.38, alpha: 1),
                NSColor(srgbRed: 0.98, green: 0.34, blue: 0.5, alpha: 1),
                OpenWhisperPalette.error,
            ]
        }
    }
}
