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
            return VibeComposePalette.signalBlue
        case .success:
            return VibeComposePalette.success
        case .copied:
            return VibeComposePalette.amber
        case .error:
            return VibeComposePalette.error
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
/// scale bloom plus a gentle opacity swell, closer to a system confirmation
/// than a neon flash.
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
        scalePeak: 1.01,
        scaleDuration: 0.4,
        opacitySwellDuration: 0.42
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
    static let paletteCrossfadeDuration: CFTimeInterval = 0.38

    /// Soft panel fade-in. Slightly longer than the ring reveal so the chrome
    /// never pops ahead of the light.
    static let appearance = AIActivityGlowTransition(
        duration: 0.48,
        controlPoint1: CGPoint(x: 0.16, y: 1),
        controlPoint2: CGPoint(x: 0.3, y: 1)
    )

    /// Gentle ease-out — light dissolves before the panel is ordered out.
    static let disappearance = AIActivityGlowTransition(
        duration: 0.36,
        controlPoint1: CGPoint(x: 0.36, y: 0),
        controlPoint2: CGPoint(x: 0.68, y: 1)
    )

    /// Ring reveal choreography (scale + opacity bloom). Runs on the glow
    /// layer itself so the edge feels like light arriving, not a window fade.
    static let revealDuration: CFTimeInterval = 0.52
    static let revealScaleFrom: CGFloat = 0.978
    static let revealScalePeak: CGFloat = 1.006
    static let revealLayerStagger: CFTimeInterval = 0.055

    /// Ring exit — slight bloom-out as opacity falls.
    static let exitDuration: CFTimeInterval = 0.34
    static let exitScalePeak: CGFloat = 1.012
}

/// Hardware / window chrome that shapes the glow path so the light hugs the
/// real bezel: rounded MacBook displays, notch / Dynamic Island cutouts, flat
/// external monitors, and focused windows.
struct DisplayChromeGeometry: Sendable, Equatable {
    /// Soft inset from the panel edge so bloom isn't clipped.
    var edgeInset: CGFloat
    var topLeadingRadius: CGFloat
    var topTrailingRadius: CGFloat
    var bottomLeadingRadius: CGFloat
    var bottomTrailingRadius: CGFloat
    /// Top-center camera housing / Dynamic Island. Coordinates are relative to
    /// the full panel bounds (not the inset rect).
    var topCutout: TopCutout?

    struct TopCutout: Sendable, Equatable {
        /// Horizontal center of the cutout in panel coordinates.
        var centerX: CGFloat
        var width: CGFloat
        var height: CGFloat
        /// Fillet on the cutout's lower corners (where light wraps the housing).
        var cornerRadius: CGFloat
    }

    /// Uniform rounded rect — focused windows and unknown displays.
    static func uniform(
        edgeInset: CGFloat,
        cornerRadius: CGFloat
    ) -> Self {
        Self(
            edgeInset: edgeInset,
            topLeadingRadius: cornerRadius,
            topTrailingRadius: cornerRadius,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topCutout: nil
        )
    }

    /// Fallback when no live `NSScreen` is available (tests / headless).
    static func fallbackDisplay(edgeInset: CGFloat) -> Self {
        Self(
            edgeInset: edgeInset,
            topLeadingRadius: 0,
            topTrailingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topCutout: nil
        )
    }

    static func forFocusedWindow(
        bloomReach: CGFloat,
        windowSize: CGSize = CGSize(width: 800, height: 600),
        isFullscreen: Bool = false
    ) -> Self {
        // Fullscreen apps are effectively the display — square edge, no fake
        // window radius. Ordinary windows use a modest continuous radius that
        // scales gently with size so small panels don't look over-rounded.
        if isFullscreen {
            let edgeInset = max(2.5, min(6, bloomReach * 0.08 + 2))
            return .fallbackDisplay(edgeInset: edgeInset)
        }
        let edgeInset = ceil(bloomReach + 6)
        let shortSide = min(windowSize.width, windowSize.height)
        let radius = min(16, max(10, shortSide * 0.018))
        return .uniform(edgeInset: edgeInset, cornerRadius: radius)
    }

    /// Resolve bezel geometry for the active display: flat external monitors
    /// stay square; notched MacBooks get rounded corners and a top cutout that
    /// tracks the camera housing / Dynamic Island.
    @MainActor
    static func forScreen(
        _ screen: NSScreen,
        bloomReach: CGFloat
    ) -> Self {
        // Keep bloom fully inside the panel so neighbouring displays don't clip.
        let edgeInset = max(2.5, min(6, bloomReach * 0.08 + 2))
        let frame = screen.frame
        let hasNotch = detectsTopCutout(on: screen)

        // Liquid Retina corners on notched MacBooks; flat panels stay sharp.
        // Radius scales gently with display size so 13" and 16" both read right.
        let corner: CGFloat
        if hasNotch {
            corner = min(28, max(18, frame.height * 0.016))
        } else {
            // A few modern external displays have a soft radius; prefer 0 for
            // classic rectangles so the light sits flush on the bezel.
            corner = 0
        }

        let cutout = topCutout(on: screen, panelFrame: frame)

        return Self(
            edgeInset: edgeInset,
            topLeadingRadius: corner,
            topTrailingRadius: corner,
            bottomLeadingRadius: corner,
            bottomTrailingRadius: corner,
            topCutout: cutout
        )
    }

    /// True when the display exposes a split top auxiliary region (notch /
    /// Dynamic Island camera housing).
    @MainActor
    static func detectsTopCutout(on screen: NSScreen) -> Bool {
        topCutoutMetrics(on: screen) != nil
    }

    @MainActor
    static func topCutout(
        on screen: NSScreen,
        panelFrame: CGRect
    ) -> TopCutout? {
        guard let metrics = topCutoutMetrics(on: screen) else { return nil }
        // Convert from global screen coords to panel-local (panel origin is
        // screen.frame.origin in AppKit space).
        let localCenterX = metrics.centerX - panelFrame.minX
        return TopCutout(
            centerX: localCenterX,
            width: metrics.width,
            height: metrics.height,
            cornerRadius: metrics.cornerRadius
        )
    }

    private struct CutoutMetrics {
        var centerX: CGFloat
        var width: CGFloat
        var height: CGFloat
        var cornerRadius: CGFloat
    }

    @MainActor
    private static func topCutoutMetrics(
        on screen: NSScreen
    ) -> CutoutMetrics? {
        // auxiliaryTopLeft/Right describe the unobscured menu-bar regions on
        // either side of the camera housing (macOS 12+). On flat displays
        // these are nil or degenerate.
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              left.width > 1,
              right.width > 1,
              right.minX > left.maxX
        else { return nil }

        let gap = right.minX - left.maxX
        // Real notch / island gaps are well above a hairline separator.
        guard gap >= 80 else { return nil }

        let frame = screen.frame
        // Housing depth: from the top of the display down to the bottom of the
        // auxiliary menu-bar strips (typically ~32–38 pt on MacBook Pro).
        let auxiliaryBottom = min(left.minY, right.minY)
        let rawHeight = frame.maxY - auxiliaryBottom
        let height = min(max(rawHeight, 28), 48)

        // Slightly wider than the raw gap so the stroke wraps the black housing
        // instead of sitting inside the camera pill.
        let width = min(frame.width * 0.42, gap + 10)
        let centerX = (left.maxX + right.minX) / 2
        let cornerRadius = min(14, max(8, height * 0.38))

        return CutoutMetrics(
            centerX: centerX,
            width: width,
            height: height,
            cornerRadius: cornerRadius
        )
    }
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
    let chrome: DisplayChromeGeometry
    let motion: AIActivityGlowMotion

    var edgeInset: CGFloat { chrome.edgeInset }
    var topCornerRadius: CGFloat {
        max(chrome.topLeadingRadius, chrome.topTrailingRadius)
    }
    var bottomCornerRadius: CGFloat {
        max(chrome.bottomLeadingRadius, chrome.bottomTrailingRadius)
    }

    static func resolve(
        state: AIActivityGlowState,
        intensity: VisualFeedbackIntensity,
        target: BlueSignalFrameTarget,
        increaseContrast: Bool,
        chrome: DisplayChromeGeometry? = nil,
        isDarkAppearance: Bool = true
    ) -> Self {
        // System-light language, refined: slightly softer bloom, clearer
        // recording↔processing hue split, calmer breath. Dark desktops favor
        // luminosity; light desktops favor density (resolved below + in view).
        let baseLineWidth: CGFloat = switch intensity {
        case .subtle:
            9
        case .standard:
            13
        case .expressive:
            17
        }
        let blurScale: CGFloat = switch intensity {
        case .subtle:
            0.92
        case .standard:
            1
        case .expressive:
            1.1
        }
        let intensityScale: Float = switch intensity {
        case .subtle:
            0.8
        case .standard:
            1
        case .expressive:
            1.28
        }
        // Light wallpapers wash out edge light — raise density. Dark desktops
        // already contrast well, so stay softer and more luminous.
        let appearanceDensity: Float = isDarkAppearance ? 1 : 1.28
        let contrastBoost: Float = increaseContrast
            ? (isDarkAppearance ? 0.1 : 0.12)
            : 0
        let outerBase: Float = isDarkAppearance ? 0.18 : 0.24
        let innerBase: Float = isDarkAppearance ? 0.44 : 0.56
        let outerBlur: CGFloat = (isDarkAppearance ? 30 : 26) * blurScale
        let innerBlur: CGFloat = (isDarkAppearance ? 10 : 8) * blurScale

        let layerStyles = [
            // Outer soft bloom — the main "system light" read.
            AIActivityGlowLayerStyle(
                lineWidthMultiplier: 1,
                blurRadius: outerBlur,
                opacity: min(
                    1,
                    (outerBase + contrastBoost * 0.5)
                        * intensityScale
                        * appearanceDensity
                )
            ),
            // Soft inner core — still blurred; never a hard hairline.
            AIActivityGlowLayerStyle(
                lineWidthMultiplier: 0.4,
                blurRadius: innerBlur,
                opacity: min(
                    1,
                    (innerBase + contrastBoost)
                        * intensityScale
                        * appearanceDensity
                )
            ),
        ]
        let outerBloomReach = baseLineWidth
            * layerStyles[0].lineWidthMultiplier / 2
            + layerStyles[0].blurRadius
        let resolvedChrome = chrome ?? {
            switch target {
            case .focusedWindow:
                return DisplayChromeGeometry.forFocusedWindow(
                    bloomReach: outerBloomReach
                )
            case .activeDisplay:
                return DisplayChromeGeometry.fallbackDisplay(
                    edgeInset: 2.5
                )
            }
        }()
        // Soft multi-stop gradient around the bezel — enough segments for a
        // refined continuous hue drift, not a neon ribbon.
        let segmentCount = 20

        switch state {
        case .recording:
            return Self(
                segmentCount: segmentCount,
                baseLineWidth: baseLineWidth,
                layerStyles: layerStyles,
                breathing: AIActivityGlowBreathingStyle(
                    animatedLayerCount: 1,
                    halfCycleDuration: 2.4,
                    minimumOpacityMultiplier: isDarkAppearance ? 0.9 : 0.92,
                    // Same-family micro brighten only.
                    colorShiftFraction: isDarkAppearance ? 0.05 : 0.035
                ),
                settle: nil,
                chrome: resolvedChrome,
                motion: .breathe
            )
        case .processing:
            return Self(
                segmentCount: segmentCount,
                baseLineWidth: baseLineWidth,
                layerStyles: layerStyles,
                breathing: AIActivityGlowBreathingStyle(
                    animatedLayerCount: 2,
                    halfCycleDuration: 1.7,
                    minimumOpacityMultiplier: isDarkAppearance ? 0.86 : 0.89,
                    colorShiftFraction: isDarkAppearance ? 0.07 : 0.05
                ),
                settle: nil,
                chrome: resolvedChrome,
                motion: .breathe
            )
        case .success, .copied, .error:
            return Self(
                segmentCount: segmentCount,
                baseLineWidth: baseLineWidth,
                layerStyles: layerStyles,
                breathing: nil,
                settle: .standard,
                chrome: resolvedChrome,
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

/// Live AX + CGWindow resolution for the frontmost user window.
struct FocusedWindowGeometry: Sendable, Equatable {
    /// AppKit-space frame of the window content (before bloom expansion).
    var contentFrame: CGRect
    var isFullscreen: Bool
    /// True when Geometry came from CGWindowList rather than AX attributes.
    var usedScreenFallback: Bool
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
    private var retargetTimer: Timer?
    private var lastFocusedGeometry: FocusedWindowGeometry?
    /// Skip microscopic moves so the ring doesn't jitter on 1-pt AX noise.
    private let retargetThreshold: CGFloat = 2.5
    private let retargetInterval: TimeInterval = 0.12

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
        let reduceMotion =
            options.reduceMotion || config.alwaysReduceMotion
        let isFirstAppearance =
            !wasLogicallyVisible || !wasPanelVisible

        if retarget || !wasLogicallyVisible || frozenTargetFrame.isEmpty {
            applyTargetLayout(
                force: true,
                intensity: config.intensity,
                increaseContrast: options.increaseContrast,
                animateGeometry: false
            )
        } else if config.frameTarget == .focusedWindow {
            // Keep hugging the live window even across state transitions.
            applyTargetLayout(
                force: false,
                intensity: config.intensity,
                increaseContrast: options.increaseContrast,
                animateGeometry: !reduceMotion
            )
        }

        let chrome = resolveChrome(
            target: config.frameTarget,
            intensity: config.intensity,
            increaseContrast: options.increaseContrast,
            focusedGeometry: lastFocusedGeometry
        )
        signalView.update(
            state: state,
            level: self.level,
            intensity: config.intensity,
            target: config.frameTarget,
            chrome: chrome,
            reduceMotion: reduceMotion,
            increaseContrast: options.increaseContrast,
            playReveal: isFirstAppearance
        )

        if isFirstAppearance {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            animatePanelAlpha(
                to: 1,
                transition: AIActivityGlowTransitionProfile.appearance
            )
        } else {
            // State-to-state transitions must never inherit a pending fade-out.
            // In particular, stopping a recording keeps the same panel visible
            // while the glow changes from recording to processing.
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }

        updateRetargetTimer()
    }

    func updateRecordingLevel(_ level: CGFloat) {
        self.level = min(1, max(0, level))
        signalView.updateLevel(self.level)
    }

    func hide() {
        transitionGeneration &+= 1
        let generation = transitionGeneration
        logicallyVisible = false
        frozenTargetFrame = .zero
        lastFocusedGeometry = nil
        stopRetargetTimer()
        let options = accessibilityDisplayOptionsProvider()
        let reduceMotion =
            options.reduceMotion || config.alwaysReduceMotion

        guard panel.isVisible else {
            signalView.resetPresentation()
            panel.alphaValue = 0
            return
        }

        // Soft ring exit first, then dissolve the panel chrome so the light
        // never hard-cuts mid-fade.
        signalView.playDisappearance(reduceMotion: reduceMotion)
        animatePanelAlpha(
            to: 0,
            transition: AIActivityGlowTransitionProfile.disappearance
        ) { [weak self] in
            guard let self,
                  self.transitionGeneration == generation,
                  !self.logicallyVisible
            else { return }
            self.signalView.resetPresentation()
            self.panel.orderOut(nil)
            self.panel.alphaValue = 0
        }
    }

    private func updateRetargetTimer() {
        stopRetargetTimer()
        guard logicallyVisible,
              config.frameTarget == .focusedWindow
        else { return }

        let timer = Timer(
            timeInterval: retargetInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retargetIfNeeded()
            }
        }
        timer.tolerance = retargetInterval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        retargetTimer = timer
    }

    private func stopRetargetTimer() {
        retargetTimer?.invalidate()
        retargetTimer = nil
    }

    private func retargetIfNeeded() {
        guard logicallyVisible,
              config.frameTarget == .focusedWindow
        else {
            stopRetargetTimer()
            return
        }
        let options = accessibilityDisplayOptionsProvider()
        let reduceMotion =
            options.reduceMotion || config.alwaysReduceMotion
        applyTargetLayout(
            force: false,
            intensity: config.intensity,
            increaseContrast: options.increaseContrast,
            animateGeometry: !reduceMotion
        )
    }

    /// Resolve the panel frame + chrome from the live target. When
    /// `force` is false, only applies if the content moved more than the
    /// retarget threshold (avoids 1-pt AX jitter).
    private func applyTargetLayout(
        force: Bool,
        intensity: VisualFeedbackIntensity,
        increaseContrast: Bool,
        animateGeometry: Bool
    ) {
        let reach = bloomReach(
            intensity: intensity,
            increaseContrast: increaseContrast
        )
        let resolved = resolveTarget(
            config.frameTarget,
            bloomReach: reach
        )
        lastFocusedGeometry = resolved.focusedGeometry

        let nextFrame = resolved.panelFrame
        if !force,
           !frozenTargetFrame.isEmpty,
           abs(nextFrame.minX - frozenTargetFrame.minX) < retargetThreshold,
           abs(nextFrame.minY - frozenTargetFrame.minY) < retargetThreshold,
           abs(nextFrame.width - frozenTargetFrame.width) < retargetThreshold,
           abs(nextFrame.height - frozenTargetFrame.height) < retargetThreshold
        {
            return
        }

        frozenTargetFrame = nextFrame
        if animateGeometry, panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeInEaseOut
                )
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(nextFrame, display: true)
            }
        } else {
            panel.setFrame(nextFrame, display: true)
        }

        let chrome = resolveChrome(
            target: config.frameTarget,
            intensity: intensity,
            increaseContrast: increaseContrast,
            focusedGeometry: resolved.focusedGeometry
        )
        // Geometry-only chrome refresh — don't restart reveal/breathing.
        signalView.updateChrome(chrome)
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

    private struct ResolvedTarget {
        var panelFrame: CGRect
        var focusedGeometry: FocusedWindowGeometry?
    }

    private func resolveTarget(
        _ target: BlueSignalFrameTarget,
        bloomReach: CGFloat
    ) -> ResolvedTarget {
        switch target {
        case .activeDisplay:
            let frame = activeScreen()?.frame
                ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            return ResolvedTarget(panelFrame: frame, focusedGeometry: nil)
        case .focusedWindow:
            if let geometry = resolveFocusedWindowGeometry() {
                let expansion = ceil(bloomReach + 6)
                let panelFrame = geometry.contentFrame.insetBy(
                    dx: -expansion,
                    dy: -expansion
                )
                return ResolvedTarget(
                    panelFrame: panelFrame,
                    focusedGeometry: geometry
                )
            }
            // Accessibility missing / no readable window → fall back to
            // the active display so the user still gets ambient light.
            let frame = activeScreen()?.frame
                ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            return ResolvedTarget(panelFrame: frame, focusedGeometry: nil)
        }
    }

    private func bloomReach(
        intensity: VisualFeedbackIntensity,
        increaseContrast: Bool
    ) -> CGFloat {
        // Mirror the outer layer in AIActivityGlowVisualProfile.resolve
        // (dark appearance is the wider-bloom case used for canvas reserve).
        let baseLineWidth: CGFloat = switch intensity {
        case .subtle: 9
        case .standard: 13
        case .expressive: 17
        }
        let blurScale: CGFloat = switch intensity {
        case .subtle: 0.92
        case .standard: 1
        case .expressive: 1.1
        }
        return baseLineWidth / 2 + 30 * blurScale
    }

    private func resolveChrome(
        target: BlueSignalFrameTarget,
        intensity: VisualFeedbackIntensity,
        increaseContrast: Bool,
        focusedGeometry: FocusedWindowGeometry?
    ) -> DisplayChromeGeometry {
        let reach = bloomReach(
            intensity: intensity,
            increaseContrast: increaseContrast
        )
        switch target {
        case .focusedWindow:
            if let geometry = focusedGeometry {
                return DisplayChromeGeometry.forFocusedWindow(
                    bloomReach: reach,
                    windowSize: geometry.contentFrame.size,
                    isFullscreen: geometry.isFullscreen
                )
            }
            // Fell back to the display while still in focused-window mode.
            if let screen = activeScreen() {
                return DisplayChromeGeometry.forScreen(
                    screen,
                    bloomReach: reach
                )
            }
            return DisplayChromeGeometry.fallbackDisplay(edgeInset: 2.5)
        case .activeDisplay:
            if let screen = activeScreen() {
                return DisplayChromeGeometry.forScreen(
                    screen,
                    bloomReach: reach
                )
            }
            return DisplayChromeGeometry.fallbackDisplay(edgeInset: 2.5)
        }
    }

    /// Display targeting uses an inner glow so the ambient layer is never
    /// clipped by the screen or a neighboring display.
    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: {
            $0.frame.contains(mouseLocation)
        }) ?? NSScreen.main
    }

    /// Resolve the frontmost user window in AppKit coordinates.
    /// Prefers AX position/size; falls back to CGWindowList when AX is sparse
    /// (Electron, some games). Never targets VibeCompose's own windows.
    private func resolveFocusedWindowGeometry() -> FocusedWindowGeometry? {
        guard AccessibilityPermission.isTrusted() else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApplication: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApplication
        ) == .success,
        let focusedApplication,
        CFGetTypeID(focusedApplication) == AXUIElementGetTypeID()
        else { return nil }

        let appElement = unsafeDowncast(
            focusedApplication as AnyObject,
            to: AXUIElement.self
        )
        var pid: pid_t = 0
        if AXUIElementGetPid(appElement, &pid) == .success, pid == ownPID {
            // Never wrap our own settings / preview / HUD panels.
            return nil
        }

        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success,
        let focusedWindow,
        CFGetTypeID(focusedWindow) == AXUIElementGetTypeID()
        else {
            // No focused window on the front app — try CGWindowList for the
            // frontmost on-screen layer owned by that pid.
            return cgWindowGeometry(forPID: pid > 0 ? pid : nil)
        }

        let window = unsafeDowncast(
            focusedWindow as AnyObject,
            to: AXUIElement.self
        )

        if let axFrame = axWindowFrame(window) {
            let fullscreen = axIsFullscreen(window)
                || isApproximatelyFullscreen(axFrame)
            return FocusedWindowGeometry(
                contentFrame: axFrame,
                isFullscreen: fullscreen,
                usedScreenFallback: false
            )
        }

        // AX window without position/size — CGWindowList by pid.
        return cgWindowGeometry(forPID: pid > 0 ? pid : nil)
    }

    private func axWindowFrame(_ window: AXUIElement) -> CGRect? {
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
        let sizeValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(
            unsafeDowncast(positionValue as AnyObject, to: AXValue.self),
            .cgPoint,
            &position
        ),
        AXValueGetValue(
            unsafeDowncast(sizeValue as AnyObject, to: AXValue.self),
            .cgSize,
            &size
        ),
        size.width >= 80,
        size.height >= 60 else { return nil }

        // AX is top-left origin in a global desktop space; AppKit is bottom-left.
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGRect(
            x: position.x,
            y: desktopTop - position.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func axIsFullscreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            "AXFullScreen" as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == CFBooleanGetTypeID()
        else { return false }
        return CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self))
    }

    private func isApproximatelyFullscreen(_ frame: CGRect) -> Bool {
        let screen = NSScreen.screens.first(where: {
            $0.frame.intersects(frame)
        }) ?? NSScreen.main
        guard let screen else { return false }
        let coverage = (frame.width * frame.height)
            / max(1, screen.frame.width * screen.frame.height)
        return coverage >= 0.92
    }

    /// Frontmost on-screen window for a process (or overall if pid is nil),
    /// excluding VibeCompose itself, menu bar extras, and tiny UI chips.
    private func cgWindowGeometry(forPID pid: pid_t?) -> FocusedWindowGeometry? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options = CGWindowListOption(
            arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements
        )
        guard let infoList = CGWindowListCopyWindowInfo(
            options,
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? 0

        for info in infoList {
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            if ownerPID == ownPID { continue }
            if let pid, ownerPID != pid { continue }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            // Normal app windows live on layer 0.
            guard layer == 0 else { continue }

            let alpha = info[kCGWindowAlpha as String] as? CGFloat ?? 1
            guard alpha > 0.05 else { continue }

            guard let boundsRaw = info[kCGWindowBounds as String],
                  let boundsDict = boundsRaw as? [String: Any],
                  let x = cgFloat(boundsDict["X"]),
                  let y = cgFloat(boundsDict["Y"]),
                  let w = cgFloat(boundsDict["Width"]),
                  let h = cgFloat(boundsDict["Height"]),
                  w >= 80,
                  h >= 60
            else { continue }

            // CGWindow bounds are top-left origin.
            let frame = CGRect(
                x: x,
                y: desktopTop - y - h,
                width: w,
                height: h
            )
            return FocusedWindowGeometry(
                contentFrame: frame,
                isFullscreen: isApproximatelyFullscreen(frame),
                usedScreenFallback: true
            )
        }
        return nil
    }

    private func cgFloat(_ value: Any?) -> CGFloat? {
        switch value {
        case let number as NSNumber:
            return CGFloat(truncating: number)
        case let double as Double:
            return CGFloat(double)
        case let float as CGFloat:
            return float
        case let int as Int:
            return CGFloat(int)
        default:
            return nil
        }
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
    private var chrome = DisplayChromeGeometry.fallbackDisplay(edgeInset: 2.5)
    private var reduceMotion = false
    private var increaseContrast = false
    private var isDarkAppearance = true
    private var hasRenderedState = false
    private var profile = AIActivityGlowVisualProfile.resolve(
        state: .processing,
        intensity: .standard,
        target: .activeDisplay,
        increaseContrast: false,
        isDarkAppearance: true
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
        chrome: DisplayChromeGeometry,
        reduceMotion: Bool,
        increaseContrast: Bool,
        playReveal: Bool = false
    ) {
        let previousState = self.state
        let previousPalette = palette
        self.state = state
        self.level = min(1, max(0, level))
        self.intensity = intensity
        self.target = target
        self.chrome = chrome
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        self.isDarkAppearance = Self.resolveIsDarkAppearance()
        profile = AIActivityGlowVisualProfile.resolve(
            state: state,
            intensity: intensity,
            target: target,
            increaseContrast: increaseContrast,
            chrome: chrome,
            isDarkAppearance: isDarkAppearance
        )

        rebuildSegmentLayers()
        updateGeometry()
        updateColors()

        if playReveal {
            // Fresh appearance: soft scale+opacity bloom, then settle into
            // the continuous breathing (or settle) profile.
            configureReveal(thenContinuous: true)
        } else {
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
        }
        updateLevel(self.level)
        hasRenderedState = true
    }

    /// Geometry-only refresh when the panel frame moves without a state change.
    /// Skips rebuild when chrome is unchanged so continuous breathing keeps
    /// running while the focused window is dragged.
    func updateChrome(_ chrome: DisplayChromeGeometry) {
        if chrome == self.chrome {
            updateGeometry()
            return
        }
        self.chrome = chrome
        profile = AIActivityGlowVisualProfile.resolve(
            state: state,
            intensity: intensity,
            target: target,
            increaseContrast: increaseContrast,
            chrome: chrome,
            isDarkAppearance: isDarkAppearance
        )
        updateGeometry()
    }

    /// Track the system appearance at the moment the glow is drawn so light
    /// and dark desktops get distinct density and hue.
    private static func resolveIsDarkAppearance() -> Bool {
        let appearance = NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.transform = CATransform3DIdentity
        ringLayer.opacity = 1
        for layersForSegment in segmentLayers {
            for (styleIndex, shapeLayer) in layersForSegment.enumerated() {
                if profile.layerStyles.indices.contains(styleIndex) {
                    shapeLayer.opacity = profile.layerStyles[styleIndex].opacity
                }
            }
        }
        CATransaction.commit()
        hasRenderedState = false
    }

    /// Soft exit bloom: the light eases out slightly larger as it dissolves.
    func playDisappearance(reduceMotion: Bool) {
        stopAnimations()
        guard !reduceMotion else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ringLayer.opacity = 0
            CATransaction.commit()
            return
        }

        let duration = AIActivityGlowTransitionProfile.exitDuration
        let timing = CAMediaTimingFunction(controlPoints: 0.36, 0, 0.68, 1)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = AIActivityGlowTransitionProfile.exitScalePeak
        scale.duration = duration
        scale.timingFunction = timing
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = false

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = ringLayer.presentation()?.opacity ?? ringLayer.opacity
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = timing
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false

        ringLayer.add(scale, forKey: "vibecompose.edgeGlow.exitScale")
        ringLayer.add(fade, forKey: "vibecompose.edgeGlow.exitFade")
        ringLayer.opacity = 0
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
            "vibecompose.edgeGlow.ambientBreathing"
        ) else { return 0 }
        return profile.breathing?.animatedLayerCount ?? 0
    }

    // EdgeGlow's MIT-licensed multi-layer stroke+blur stack is adapted here
    // from GlowWindow.swift at commit d39d0471a25af97d8de077591f69f938efa8bea8.
    // VibeCompose retunes it toward system ambient light (soft bloom, monochrome
    // palettes) and supplies its own lifecycle, accessibility, target freezing,
    // and dictation-state choreography.
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
        let inset = profile.chrome.edgeInset
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = bezelEdgePath(rect: rect, chrome: profile.chrome)

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

    /// Continuous stroke that hugs the display bezel. On notched MacBooks the
    /// top edge drops around the camera housing / Dynamic Island; on flat
    /// external monitors it is a simple (optionally rounded) rectangle.
    private func bezelEdgePath(
        rect: CGRect,
        chrome: DisplayChromeGeometry
    ) -> CGPath {
        let maxR = max(0, min(rect.width, rect.height) / 2)
        let tl = min(max(0, chrome.topLeadingRadius), maxR)
        let tr = min(max(0, chrome.topTrailingRadius), maxR)
        let br = min(max(0, chrome.bottomTrailingRadius), maxR)
        let bl = min(max(0, chrome.bottomLeadingRadius), maxR)

        let path = CGMutablePath()

        // Start mid-bottom so the first join isn't on a cutout corner.
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - br, y: rect.minY))
        if br > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - br, y: rect.minY + br),
                radius: br,
                startAngle: -.pi / 2,
                endAngle: 0,
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tr))
        if tr > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - tr, y: rect.maxY - tr),
                radius: tr,
                startAngle: 0,
                endAngle: .pi / 2,
                clockwise: false
            )
        }

        // Top edge — optionally wrap the camera housing / Dynamic Island.
        // Cutout metrics are panel-local; convert to the inset rect space by
        // clamping against the inset top edge.
        if let cutout = chrome.topCutout,
           cutout.width > 8,
           cutout.height > 4
        {
            let halfWidth = cutout.width / 2
            let cutCenter = min(
                rect.maxX - tr - 4,
                max(rect.minX + tl + 4, cutout.centerX)
            )
            let cutLeft = max(rect.minX + tl + 4, cutCenter - halfWidth)
            let cutRight = min(rect.maxX - tr - 4, cutCenter + halfWidth)
            // Depth into the display from the top bezel.
            let depth = min(
                max(cutout.height - chrome.edgeInset, 10),
                rect.height * 0.08
            )
            let cutBottom = rect.maxY - depth
            let cutWidth = cutRight - cutLeft
            let fillet = min(
                cutout.cornerRadius,
                cutWidth / 2,
                depth
            )

            // Right top → right of cutout.
            path.addLine(to: CGPoint(x: cutRight, y: rect.maxY))
            // Down the right wall of the housing.
            path.addLine(to: CGPoint(x: cutRight, y: cutBottom + fillet))
            if fillet > 0 {
                path.addArc(
                    center: CGPoint(
                        x: cutRight - fillet,
                        y: cutBottom + fillet
                    ),
                    radius: fillet,
                    startAngle: 0,
                    endAngle: -.pi / 2,
                    clockwise: true
                )
            }
            // Across the underside of the housing.
            path.addLine(to: CGPoint(x: cutLeft + fillet, y: cutBottom))
            if fillet > 0 {
                path.addArc(
                    center: CGPoint(
                        x: cutLeft + fillet,
                        y: cutBottom + fillet
                    ),
                    radius: fillet,
                    startAngle: -.pi / 2,
                    endAngle: -.pi,
                    clockwise: true
                )
            }
            // Up the left wall back to the top bezel.
            path.addLine(to: CGPoint(x: cutLeft, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + tl, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: rect.minX + tl, y: rect.maxY))
        }

        if tl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + tl, y: rect.maxY - tl),
                radius: tl,
                startAngle: .pi / 2,
                endAngle: .pi,
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bl))
        if bl > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bl, y: rect.minY + bl),
                radius: bl,
                startAngle: .pi,
                endAngle: .pi * 1.5,
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
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
                // Soft core gets a hair of white so the inner band reads as
                // light. Dark mode can take a bit more lift; light mode stays
                // more saturated so the edge doesn't wash out on white walls.
                let whiteMix: CGFloat
                if styleIndex == 1 {
                    whiteMix = isDarkAppearance ? 0.12 : 0.04
                } else {
                    whiteMix = isDarkAppearance ? 0.04 : 0
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
        // segmentCount is typically 1 for system light; keep multi-stop
        // interpolation for any residual multi-segment profiles.
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
        // Clear any residual reveal/exit transform so continuous motion starts
        // from a settled pose.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.transform = CATransform3DIdentity
        ringLayer.opacity = 1
        CATransaction.commit()

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

    /// System-light arrival: the ring blooms in from a slightly smaller,
    /// transparent pose, outer bloom leading, soft core lagging a beat —
    /// then continuous breathing / settle starts mid-reveal so the handoff
    /// feels seamless rather than "animation A, then animation B".
    private func configureReveal(thenContinuous: Bool) {
        for animatedLayer in animatedLayers {
            animatedLayer.removeAllAnimations()
        }

        guard !reduceMotion else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ringLayer.transform = CATransform3DIdentity
            ringLayer.opacity = 1
            for layersForSegment in segmentLayers {
                for (styleIndex, shapeLayer) in layersForSegment.enumerated() {
                    if profile.layerStyles.indices.contains(styleIndex) {
                        shapeLayer.opacity =
                            profile.layerStyles[styleIndex].opacity
                    }
                }
            }
            CATransaction.commit()
            if thenContinuous {
                configureAnimations(colorBreathingDelay: 0)
            }
            return
        }

        let duration = AIActivityGlowTransitionProfile.revealDuration
        let stagger = AIActivityGlowTransitionProfile.revealLayerStagger
        // Ease-out with a whisper of overshoot in the scale channel.
        let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        let softEase = CAMediaTimingFunction(controlPoints: 0.22, 0.9, 0.28, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.transform = CATransform3DIdentity
        ringLayer.opacity = 1
        CATransaction.commit()

        // Ring: scale 0.978 → 1.006 → 1.0, opacity 0 → 1.
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [
            AIActivityGlowTransitionProfile.revealScaleFrom,
            AIActivityGlowTransitionProfile.revealScalePeak,
            1.0,
        ]
        scale.keyTimes = [0, 0.62, 1]
        scale.duration = duration
        scale.timingFunctions = [easeOut, softEase]
        scale.fillMode = .both
        scale.isRemovedOnCompletion = true

        let ringFade = CAKeyframeAnimation(keyPath: "opacity")
        ringFade.values = [0, 1, 1]
        ringFade.keyTimes = [0, 0.55, 1]
        ringFade.duration = duration
        ringFade.timingFunctions = [easeOut, softEase]
        ringFade.fillMode = .both
        ringFade.isRemovedOnCompletion = true

        ringLayer.add(scale, forKey: "vibecompose.edgeGlow.revealScale")
        ringLayer.add(ringFade, forKey: "vibecompose.edgeGlow.revealFade")

        // Per-layer opacity: outer bloom leads, soft core follows.
        for layersForSegment in segmentLayers {
            for (styleIndex, shapeLayer) in layersForSegment.enumerated() {
                guard profile.layerStyles.indices.contains(styleIndex) else {
                    continue
                }
                let targetOpacity = profile.layerStyles[styleIndex].opacity
                let delay = stagger * CFTimeInterval(styleIndex)

                let layerFade = CABasicAnimation(keyPath: "opacity")
                layerFade.fromValue = 0
                layerFade.toValue = targetOpacity
                layerFade.duration = max(0.22, duration - delay * 0.55)
                layerFade.beginTime = shapeLayer.convertTime(
                    CACurrentMediaTime(),
                    from: nil
                ) + delay
                layerFade.timingFunction = easeOut
                layerFade.fillMode = .backwards
                layerFade.isRemovedOnCompletion = true

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                shapeLayer.opacity = targetOpacity
                CATransaction.commit()

                shapeLayer.add(
                    layerFade,
                    forKey: "vibecompose.edgeGlow.revealLayer"
                )
            }
        }

        guard thenContinuous else { return }

        // Continuous motion starts after the bulk of the reveal so the first
        // breath rides the settled light rather than fighting the arrival.
        let handoff = duration * 0.68
        switch profile.motion {
        case .breathe:
            addAmbientBreathing(
                colorAnimationDelay: handoff,
                motionBeginDelay: handoff
            )
        case .settle:
            addSettleTransition(beginDelay: handoff)
        }
    }

    private func addAmbientBreathing(
        colorAnimationDelay: CFTimeInterval,
        motionBeginDelay: CFTimeInterval = 0
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
                if motionBeginDelay > 0 {
                    breathe.beginTime = shapeLayer.convertTime(
                        CACurrentMediaTime(),
                        from: nil
                    ) + motionBeginDelay
                    // Hold the settled opacity until the first breath starts.
                    breathe.fillMode = .backwards
                }
                shapeLayer.add(
                    breathe,
                    forKey: "vibecompose.edgeGlow.ambientBreathing"
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
                let colorDelay = max(colorAnimationDelay, motionBeginDelay)
                if colorDelay > 0 {
                    colorBreathing.beginTime = shapeLayer.convertTime(
                        CACurrentMediaTime(),
                        from: nil
                    ) + colorDelay
                    colorBreathing.fillMode = .backwards
                }
                colorBreathing.timingFunction = CAMediaTimingFunction(
                    name: .easeInEaseOut
                )
                shapeLayer.add(
                    colorBreathing,
                    forKey: "vibecompose.edgeGlow.ambientColorBreathing"
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
                let whiteMix: CGFloat
                if styleIndex == 1 {
                    whiteMix = isDarkAppearance ? 0.12 : 0.04
                } else {
                    whiteMix = isDarkAppearance ? 0.04 : 0
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
                    forKey: "vibecompose.edgeGlow.paletteCrossfade"
                )
            }
        }
    }

    private var ambientBreathingTint: NSColor {
        // Same-family micro brighten — recording lifts toward cool sky,
        // processing toward soft periwinkle so the two states keep distinct breath.
        switch state {
        case .recording:
            if isDarkAppearance {
                return NSColor(
                    srgbRed: 0.58,
                    green: 0.9,
                    blue: 1,
                    alpha: 1
                )
            }
            return NSColor(
                srgbRed: 0.22,
                green: 0.6,
                blue: 0.98,
                alpha: 1
            )
        case .processing:
            // Warm amber lift — same family as the processing palette.
            if isDarkAppearance {
                return NSColor(
                    srgbRed: 1,
                    green: 0.9,
                    blue: 0.62,
                    alpha: 1
                )
            }
            return NSColor(
                srgbRed: 0.92,
                green: 0.62,
                blue: 0.14,
                alpha: 1
            )
        case .success:
            if isDarkAppearance {
                return NSColor(
                    srgbRed: 0.72,
                    green: 1,
                    blue: 0.88,
                    alpha: 1
                )
            }
            return NSColor(
                srgbRed: 0.18,
                green: 0.72,
                blue: 0.48,
                alpha: 1
            )
        case .copied:
            if isDarkAppearance {
                return NSColor(
                    srgbRed: 1,
                    green: 0.92,
                    blue: 0.7,
                    alpha: 1
                )
            }
            return NSColor(
                srgbRed: 0.92,
                green: 0.62,
                blue: 0.12,
                alpha: 1
            )
        case .error:
            if isDarkAppearance {
                return NSColor(
                    srgbRed: 1,
                    green: 0.72,
                    blue: 0.78,
                    alpha: 1
                )
            }
            return NSColor(
                srgbRed: 0.92,
                green: 0.28,
                blue: 0.34,
                alpha: 1
            )
        }
    }

    private func addSettleTransition(beginDelay: CFTimeInterval = 0) {
        guard let settle = profile.settle else { return }

        let scaleBloom = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleBloom.values = [1.0, settle.scalePeak, 1.0]
        scaleBloom.keyTimes = [0, 0.4, 1]
        scaleBloom.duration = settle.scaleDuration
        scaleBloom.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(
                controlPoints: 0.3, 0, 0.4, 1
            ),
        ]
        if beginDelay > 0 {
            scaleBloom.beginTime = ringLayer.convertTime(
                CACurrentMediaTime(),
                from: nil
            ) + beginDelay
            scaleBloom.fillMode = .backwards
        }
        ringLayer.add(
            scaleBloom,
            forKey: "vibecompose.edgeGlow.settleScaleBloom"
        )

        // Soft confirmation swell — peak then ease back slightly so the
        // terminal state doesn't "flash" like a neon hit.
        let swell = CAKeyframeAnimation(keyPath: "opacity")
        swell.values = [0.92, settle.peakOpacity, 0.96]
        swell.keyTimes = [0, 0.32, 1]
        swell.duration = settle.opacitySwellDuration
        swell.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        if beginDelay > 0 {
            swell.beginTime = ringLayer.convertTime(
                CACurrentMediaTime(),
                from: nil
            ) + beginDelay
            swell.fillMode = .backwards
        }
        ringLayer.add(
            swell,
            forKey: "vibecompose.edgeGlow.settle"
        )
    }

    private var palette: [NSColor] {
        // Multi-stop monochrome families: recording is cool sky-cyan
        // (listening), processing is warm amber (thinking). Cold↔warm split
        // reads at a glance and matches the Status Bar processing accent.
        if isDarkAppearance {
            return darkPalette
        }
        return lightPalette
    }

    private var darkPalette: [NSColor] {
        switch state {
        case .recording:
            // Cool sky cyan — clear "listening", luminous but not electric.
            return [
                NSColor(srgbRed: 0.22, green: 0.66, blue: 1.00, alpha: 1),
                NSColor(srgbRed: 0.34, green: 0.80, blue: 1.00, alpha: 1),
                NSColor(srgbRed: 0.42, green: 0.88, blue: 0.98, alpha: 1),
                NSColor(srgbRed: 0.26, green: 0.72, blue: 1.00, alpha: 1),
            ]
        case .processing:
            // Warm amber — refined "thinking", cold↔warm opposite of sky-cyan.
            return [
                NSColor(srgbRed: 1.00, green: 0.72, blue: 0.28, alpha: 1),
                NSColor(srgbRed: 1.00, green: 0.82, blue: 0.40, alpha: 1),
                NSColor(srgbRed: 1.00, green: 0.76, blue: 0.34, alpha: 1),
                NSColor(srgbRed: 0.98, green: 0.68, blue: 0.24, alpha: 1),
            ]
        case .success:
            // Soft mint — calm confirmation.
            return [
                NSColor(srgbRed: 0.32, green: 0.90, blue: 0.68, alpha: 1),
                NSColor(srgbRed: 0.42, green: 0.95, blue: 0.76, alpha: 1),
                NSColor(srgbRed: 0.36, green: 0.92, blue: 0.70, alpha: 1),
            ]
        case .copied:
            // Champagne gold — warmer than success, never orange-neon.
            return [
                NSColor(srgbRed: 1.00, green: 0.84, blue: 0.44, alpha: 1),
                NSColor(srgbRed: 1.00, green: 0.90, blue: 0.56, alpha: 1),
                NSColor(srgbRed: 0.98, green: 0.80, blue: 0.38, alpha: 1),
            ]
        case .error:
            // Soft rose — clear without traffic-light red.
            return [
                NSColor(srgbRed: 1.00, green: 0.50, blue: 0.56, alpha: 1),
                NSColor(srgbRed: 1.00, green: 0.60, blue: 0.64, alpha: 1),
                NSColor(srgbRed: 0.98, green: 0.46, blue: 0.52, alpha: 1),
            ]
        }
    }

    private var lightPalette: [NSColor] {
        switch state {
        case .recording:
            // Deeper sky blue — holds against pale wallpapers.
            return [
                NSColor(srgbRed: 0.10, green: 0.48, blue: 0.94, alpha: 1),
                NSColor(srgbRed: 0.14, green: 0.56, blue: 0.98, alpha: 1),
                NSColor(srgbRed: 0.12, green: 0.52, blue: 0.92, alpha: 1),
                VibeComposePalette.signalBlue,
            ]
        case .processing:
            // Deeper amber — holds on pale wallpapers, still soft not neon.
            return [
                NSColor(srgbRed: 0.90, green: 0.54, blue: 0.08, alpha: 1),
                NSColor(srgbRed: 0.96, green: 0.62, blue: 0.14, alpha: 1),
                NSColor(srgbRed: 0.92, green: 0.58, blue: 0.10, alpha: 1),
                NSColor(srgbRed: 0.86, green: 0.50, blue: 0.06, alpha: 1),
            ]
        case .success:
            return [
                NSColor(srgbRed: 0.14, green: 0.68, blue: 0.46, alpha: 1),
                NSColor(srgbRed: 0.18, green: 0.74, blue: 0.52, alpha: 1),
                NSColor(srgbRed: 0.16, green: 0.70, blue: 0.48, alpha: 1),
            ]
        case .copied:
            return [
                NSColor(srgbRed: 0.86, green: 0.60, blue: 0.12, alpha: 1),
                NSColor(srgbRed: 0.92, green: 0.68, blue: 0.18, alpha: 1),
                NSColor(srgbRed: 0.84, green: 0.56, blue: 0.10, alpha: 1),
            ]
        case .error:
            return [
                NSColor(srgbRed: 0.88, green: 0.28, blue: 0.34, alpha: 1),
                NSColor(srgbRed: 0.94, green: 0.36, blue: 0.40, alpha: 1),
                NSColor(srgbRed: 0.86, green: 0.26, blue: 0.32, alpha: 1),
            ]
        }
    }
}
