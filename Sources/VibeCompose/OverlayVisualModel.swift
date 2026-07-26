import CoreGraphics
import Foundation

struct OverlayStylePreset: Sendable, Equatable {
    /// Default / max recording panel width. On macOS 26 this is the glass
    /// capsule itself; pre-26 it includes the soft-shadow chrome inset.
    let primaryPillWidth: CGFloat
    let primaryPillHeight: CGFloat
    let errorPillWidth: CGFloat
    let errorPillHeight: CGFloat
    let topInset: CGFloat
    /// Outer margin around the material. 0 under Liquid Glass (glass fills the
    /// panel); pre-26 reserves room for the silhouette shadow plate.
    let chromeInset: CGFloat
    let cornerRadius: CGFloat
    let contentPaddingH: CGFloat
    let contentPaddingV: CGFloat
    let leadingVisualWidth: CGFloat
    let leadingVisualHeight: CGFloat
    let textGap: CGFloat
    let waveformBarCount: Int
    let waveformBarSpacing: CGFloat
    let waveformMinimumBarHeight: CGFloat
    let showsTranscriptPreview: Bool
    let recordingAutoHideDelay: TimeInterval?
    let processingAutoHideDelay: TimeInterval?
    let successAutoHideDelay: TimeInterval?
    let errorAutoHideDelay: TimeInterval?
    let inlineCancelControlSize: CGFloat
    let inlineControlGap: CGFloat
    let inlineControlReservedWidth: CGFloat
    let timerWidth: CGFloat
    let timerFontSize: CGFloat
    let timerOpacity: CGFloat

    static let dictationHUD = OverlayStylePreset(
        // macOS 26 official floating glass capsule (NSGlassEffectView):
        // glass fills the panel edge-to-edge — no external shadow chrome, no
        // inset plate. Heights stay constant so state morphs only change width.
        //
        // Visible capsule is always 44pt tall / radius 22 (true capsule). Pre-26
        // adds a 6pt elevation margin around that silhouette so the soft layer
        // shadow has room outside the material without clipping.
        primaryPillWidth: usesLiquidGlassShell ? 272 : 284,
        primaryPillHeight: usesLiquidGlassShell ? 44 : 56,
        errorPillWidth: usesLiquidGlassShell ? 272 : 284,
        errorPillHeight: usesLiquidGlassShell ? 44 : 56,
        // Slightly farther from the menu bar / dock edge so the pill reads as
        // floating chrome rather than docked chrome.
        topInset: 14,
        chromeInset: usesLiquidGlassShell ? 0 : 6,
        cornerRadius: 22,
        contentPaddingH: 14,
        contentPaddingV: 10,
        // Flat Liquid Glass voice glyph — no glow padding needed.
        leadingVisualWidth: 28,
        leadingVisualHeight: 16,
        // Extra air between the bars and the title / timer so the glyph doesn't
        // crowd the monospaced elapsed time.
        textGap: 14,
        waveformBarCount: 5,
        waveformBarSpacing: 2.5,
        waveformMinimumBarHeight: 3,
        showsTranscriptPreview: false,
        recordingAutoHideDelay: nil,
        processingAutoHideDelay: nil,
        successAutoHideDelay: 1.0,
        errorAutoHideDelay: 4.0,
        inlineCancelControlSize: 16,
        inlineControlGap: 6,
        inlineControlReservedWidth: 48,
        timerWidth: 36,
        // Match the skill-title size so timer and title read as one type system.
        // monospacedDigitSystemFont is the only intentional difference.
        timerFontSize: 12,
        // Full primary opacity — elapsed time is status, not muted chrome.
        timerOpacity: 1
    )

    /// Shared shell decision for geometry tokens. Liquid Glass owns its edge, so
    /// the panel and the glass share one rect; classic material needs an outer
    /// chrome inset for the silhouette shadow plate.
    private static var usesLiquidGlassShell: Bool {
        VibeComposeFloatingChrome.usesSystemLiquidGlass
    }

    /// Per-state content-width bounds (visible surface, excluding chrome).
    /// Compact result states hug their short labels; recording expands for
    /// skill names. Mins avoid sparse empty trail, maxes never clip CJK.
    private func contentWidthBounds(
        for state: OverlayVisualState
    ) -> (min: CGFloat, max: CGFloat) {
        switch state {
        case .processing:
            // waveform + short label ("处理中" / "Processing") + cancel.
            return (120, 176)
        case .success(let kind):
            // Delivery outcomes keep a tight "Done" pill; skill confirmation
            // needs room for the selected Skill display name (CJK included).
            switch kind {
            case .inserted, .pasteSent, .copied:
                return (96, 148)
            case .confirmation:
                return (132, primaryPillWidth - chromeInset * 2)
            }
        case .recording:
            // waveform + skill name + timer + cancel.
            return (196, primaryPillWidth - chromeInset * 2)
        case .error, .retryableError:
            // badge + short "错误"/"Error"; retryable adds a trailing control.
            // Keep the min tight so a two-character label doesn't float in a
            // long empty capsule.
            if state.showsRetryControl {
                return (132, 220)
            }
            return (96, 180)
        }
    }

    /// Trailing accessory strip width for the state's timer / retry / cancel.
    /// Only counts pieces that are actually visible for this state so sizing
    /// matches layout (hidden stack children must not inflate the pill).
    func trailingAccessoryWidth(for state: OverlayVisualState) -> CGFloat {
        var pieces: [CGFloat] = []
        if state.trailingText != nil {
            pieces.append(timerWidth)
        }
        if state.showsRetryControl {
            pieces.append(inlineCancelControlSize)
        }
        if state.showsCancelControl {
            pieces.append(inlineCancelControlSize)
        }
        guard !pieces.isEmpty else { return 0 }
        return pieces.reduce(0, +)
            + inlineControlGap * CGFloat(pieces.count - 1)
    }

    /// Fitted panel size. Pass measured title width (0 when the title is hidden).
    func size(
        for state: OverlayVisualState,
        titleWidth: CGFloat = 0
    ) -> CGSize {
        let height: CGFloat
        switch state {
        case .error, .retryableError:
            height = errorPillHeight
        case .recording, .processing, .success:
            height = primaryPillHeight
        }

        let chrome = chromeInset * 2
        let pad = contentPaddingH * 2
        let trailing = trailingAccessoryWidth(for: state)
        // Small slack so CJK glyph metrics / font fallback never clip a hair.
        let resolvedTitle = titleWidth > 0.5 ? titleWidth + 2 : 0
        let hasTitle = resolvedTitle > 0.5

        // leading | gap | [title | gap] | trailing
        var core = pad + leadingVisualWidth
        if hasTitle || trailing > 0 {
            core += textGap
        }
        if hasTitle {
            core += resolvedTitle
            if trailing > 0 {
                core += textGap
            }
        }
        core += trailing

        let bounds = contentWidthBounds(for: state)
        let contentWidth = min(max(core, bounds.min), bounds.max)
        return CGSize(width: contentWidth + chrome, height: height)
    }
}

enum OverlayLeadingVisual: Sendable, Equatable {
    case waveform
    case icon(symbolName: String)
}

enum OverlaySuccessKind: Sendable, Equatable {
    case inserted
    case pasteSent
    case copied
    /// Ephemeral confirmation (Skill Switcher, etc.) — title is the message.
    case confirmation(title: String)

    var label: String {
        switch self {
        case .inserted, .pasteSent, .copied:
            // One calm success word for every delivery path. Insert and paste
            // share a green check; clipboard-only keeps the amber copy badge.
            return L10n.text("Done")
        case .confirmation(let title):
            return title
        }
    }
}

enum OverlayVisualState: Sendable, Equatable {
    case recording(levels: [CGFloat], elapsedText: String)
    case processing
    case success(OverlaySuccessKind)
    case error(String)
    case retryableError(String)

    var label: String {
        label(
            hotkeyDisplayName: HotkeyBinding.f5.displayName
        )
    }

    func label(
        hotkeyDisplayName: String
    ) -> String {
        switch self {
        case .recording:
            // Recording shows the skill name (or nothing) — never the hotkey.
            _ = hotkeyDisplayName
            return ""
        case .processing:
            return L10n.text("Processing")
        case .success(let kind):
            return kind.label
        case .error, .retryableError:
            return L10n.text("Error")
        }
    }

    var leadingVisual: OverlayLeadingVisual {
        switch self {
        case .recording:
            return .waveform
        case .processing:
            return .waveform
        case .success(let kind):
            switch kind {
            case .inserted, .pasteSent, .confirmation:
                return .icon(symbolName: "checkmark.circle.fill")
            case .copied:
                return .icon(symbolName: "doc.on.clipboard.fill")
            }
        case .error, .retryableError:
            return .icon(symbolName: "exclamationmark.triangle.fill")
        }
    }

    var showsCancelControl: Bool {
        switch self {
        case .recording, .processing:
            return true
        case .success, .error, .retryableError:
            return false
        }
    }

    var showsRetryControl: Bool {
        if case .retryableError = self {
            return true
        }
        return false
    }

    var trailingText: String? {
        switch self {
        case .recording(_, let elapsedText):
            return elapsedText
        case .processing, .success, .error, .retryableError:
            return nil
        }
    }

    var supplementaryText: String? {
        let message: String
        switch self {
        case .error(let value), .retryableError(let value):
            message = value
        case .recording, .processing, .success:
            return nil
        }
        return Self.collapseErrorMessage(message)
    }

    private static func collapseErrorMessage(_ message: String) -> String {
        let collapsed = message
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let characterLimit = 70
        guard collapsed.count > characterLimit else {
            return collapsed
        }

        let limitIndex = collapsed.index(collapsed.startIndex, offsetBy: characterLimit)
        let prefix = String(collapsed[..<limitIndex])
        let trimmed = prefix[..<(prefix.lastIndex(of: " ") ?? prefix.endIndex)]
        return String(trimmed) + "…"
    }
}

enum WaveformNormalizer {
    static let minimumVisibleLevel: CGFloat = 0.08
    static let maximumVisibleLevel: CGFloat = 1
    private static let silenceFloor: Float = -160
    /// Fast attack so the glyph snaps with speech onsets (Apple voice-meter feel).
    private static let attackSmoothing: CGFloat = 0.58
    /// Softer release so bars fall with a natural decay instead of locking to the mic.
    private static let releaseSmoothing: CGFloat = 0.26
    /// Continuous-time sample rate used when mapping discrete `frame` ticks.
    private static let processingFrameDuration: TimeInterval = 1.0 / 30.0

    static func normalizedLevel(fromAveragePower averagePower: Float) -> CGFloat {
        if averagePower >= 0 {
            return maximumVisibleLevel
        }
        let clamped = max(silenceFloor, min(0, averagePower))
        let normalized = 1 - CGFloat(abs(clamped) / abs(silenceFloor))
        return min(maximumVisibleLevel, max(minimumVisibleLevel, normalized))
    }

    /// Live recording bars. `phase` is continuous seconds (e.g. `CACurrentMediaTime`)
    /// so multi-frequency organic motion never freezes into a static envelope.
    static func smoothedLevels(
        previous: [CGFloat],
        targetLevel: CGFloat,
        barCount: Int,
        phase: TimeInterval = 0
    ) -> [CGFloat] {
        let seed = Array(previous.prefix(barCount))
        let padded = seed + Array(
            repeating: minimumVisibleLevel,
            count: max(0, barCount - seed.count)
        )
        let target = min(
            maximumVisibleLevel,
            max(minimumVisibleLevel, targetLevel)
        )

        let center = CGFloat(max(0, barCount - 1)) / 2
        let radius = max(center, 1)
        let t = CGFloat(phase)
        // How much of the range above the silence floor is live energy.
        let energy = max(
            0,
            min(1, (target - minimumVisibleLevel) / (1 - minimumVisibleLevel))
        )
        // Quiet input still breathes gently so the glyph never looks frozen.
        let silence = max(0, 1 - energy / 0.28)

        return padded.enumerated().map { index, prior in
            let i = CGFloat(index)
            let distanceFromCenter = abs(i - center) / radius
            // Slightly softer contour so outer bars still carry audible life.
            let contour = pow(max(0, 1 - distanceFromCenter), 1.12)
            let baseWeight = 0.30 + (contour * 0.70)

            // Multi-frequency organic motion — three incommensurate sines keep
            // the 5-bar glyph from reading as a single rigid envelope.
            let waveA = sin(t * 5.4 + i * 1.25) * 0.5 + 0.5
            let waveB = sin(t * 9.6 + i * 2.15 + 0.85) * 0.5 + 0.5
            let waveC = sin(t * 14.8 + i * 0.72 + 1.6) * 0.5 + 0.5
            let organic = waveA * 0.50 + waveB * 0.32 + waveC * 0.18
            // Depth scales with energy: louder speech opens more variation,
            // soft speech keeps a calmer (but still living) shape.
            let depth = 0.16 + energy * 0.48
            let modulation = (organic * 2 - 1) * depth

            // Idle breath — low-frequency rise/fall when the mic is quiet.
            let breath =
                (sin(t * 2.35 + i * 0.9) * 0.5 + 0.5)
                * 0.14
                * silence
                * (0.55 + contour * 0.45)

            let energySpan = target - minimumVisibleLevel
            let shaped =
                minimumVisibleLevel
                + energySpan * baseWeight * (1 + modulation * 0.9)
                + breath
            let weightedTarget = min(
                maximumVisibleLevel,
                max(minimumVisibleLevel, shaped)
            )

            // Asymmetric attack/release — springy rise, tapered fall.
            let factor = weightedTarget > prior
                ? attackSmoothing
                : releaseSmoothing
            let next = prior + ((weightedTarget - prior) * factor)
            return min(
                maximumVisibleLevel,
                max(minimumVisibleLevel, next)
            )
        }
    }

    /// Discrete-frame convenience for tests / legacy call sites. Maps each tick
    /// onto continuous time so the motion stays smooth at any cadence.
    static func processingPulseLevels(frame: Int, barCount: Int) -> [CGFloat] {
        processingPulseLevels(
            time: TimeInterval(max(0, frame)) * processingFrameDuration,
            barCount: barCount
        )
    }

    /// Continuous-time processing pulse: a soft gaussian ridge travels across
    /// the bars with a quieter secondary counter-wave and micro-shimmer, so the
    /// "thinking" glyph has depth instead of a single triangular blip.
    static func processingPulseLevels(
        time: TimeInterval,
        barCount: Int
    ) -> [CGFloat] {
        let center = CGFloat(max(0, barCount - 1)) / 2
        let radius = max(center, 1)
        let t = CGFloat(max(0, time))
        // Full glyph sweep roughly every 1.05s — brisk enough to read as
        // activity, slow enough to feel deliberate rather than frantic.
        let cycleWidth = CGFloat(barCount) + 2.4
        let primarySpeed = cycleWidth / 1.05
        let secondarySpeed = cycleWidth / 1.7
        let primaryPhase = (t * primarySpeed)
            .truncatingRemainder(dividingBy: cycleWidth) - 1.2
        let secondaryPhase = (t * secondarySpeed + cycleWidth * 0.45)
            .truncatingRemainder(dividingBy: cycleWidth) - 1.2

        return (0..<barCount).map { index in
            let i = CGFloat(index)
            let distanceFromCenter = abs(i - center) / radius
            let contour = pow(max(0, 1 - distanceFromCenter), 1.1)

            // Breathing base so idle bars never sit dead-flat between ridges.
            let breath =
                0.5 + 0.5 * sin(t * 2.25 + i * 0.55)
            let envelope =
                minimumVisibleLevel
                + contour * (0.16 + breath * 0.18)

            // Soft primary ridge (gaussian) — Apple-style continuous light.
            let primaryDistance = abs(i - primaryPhase)
            let primarySigma: CGFloat = 1.05
            let primaryRidge = exp(
                -(primaryDistance * primaryDistance)
                    / (2 * primarySigma * primarySigma)
            )

            // Quieter counter-wave for layered depth.
            let secondaryDistance = abs(i - secondaryPhase)
            let secondarySigma: CGFloat = 1.45
            let secondaryRidge = exp(
                -(secondaryDistance * secondaryDistance)
                    / (2 * secondarySigma * secondarySigma)
            ) * 0.38

            // Micro shimmer rides the contour so the peak stays dominant.
            let shimmer =
                (sin(t * 7.6 + i * 1.7) * 0.5 + 0.5)
                * 0.10
                * contour

            let level =
                envelope
                + primaryRidge * 0.78
                + secondaryRidge
                + shimmer
            return min(
                maximumVisibleLevel,
                max(minimumVisibleLevel, level)
            )
        }
    }

    static func reducedMotionProcessingLevels(barCount: Int) -> [CGFloat] {
        let center = CGFloat(max(0, barCount - 1)) / 2
        let radius = max(center, 1)

        return (0..<barCount).map { index in
            let distanceFromCenter = abs(CGFloat(index) - center) / radius
            let contour = pow(max(0, 1 - distanceFromCenter), 1.25)
            return min(
                maximumVisibleLevel,
                max(minimumVisibleLevel, minimumVisibleLevel + (contour * 0.48))
            )
        }
    }
}
