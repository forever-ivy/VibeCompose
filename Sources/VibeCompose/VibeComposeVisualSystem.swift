import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Status menu visual state

enum StatusMenuVisualState: Sendable, Equatable {
    case ready
    case setupRequired
    case recording
    case processing
    case error
    case demo

    var menuLabel: String {
        switch self {
        case .ready:
            return "OW"
        case .setupRequired:
            return "SET"
        case .recording:
            return "REC"
        case .processing:
            return L10n.text("Working")
        case .error:
            return "ERR"
        case .demo:
            return "DMO"
        }
    }

    var stateDescription: String {
        switch self {
        case .ready:
            return L10n.text("Ready")
        case .setupRequired:
            return L10n.text("Setup required")
        case .recording:
            return L10n.text("Recording")
        case .processing:
            return L10n.text("Processing")
        case .error:
            return L10n.text("Error")
        case .demo:
            return L10n.text("Demo")
        }
    }

    var usesTemplateAttention: Bool {
        switch self {
        case .ready:
            return false
        case .setupRequired, .recording, .processing, .error, .demo:
            return true
        }
    }

    fileprivate var barHeights: [CGFloat] {
        switch self {
        case .ready:
            return [0.42, 0.72, 0.56]
        case .setupRequired:
            return [0.4, 0.82, 0.3]
        case .recording:
            return [0.5, 0.96, 0.68]
        case .processing:
            return [0.58, 0.84, 0.74]
        case .error:
            return [0.44, 0.84, 0.24]
        case .demo:
            return [0.48, 0.9, 0.6]
        }
    }
}

// MARK: - Palette

enum VibeComposePalette {
    /// Semantic foregrounds let the system resolve legibility for the current
    /// appearance and accessibility settings above the native AppKit material.
    ///
    /// HUD labels sit on translucent Liquid Glass — system `labelColor` still
    /// reads gray through dark materials. Resolve a hard primary instead so
    /// skill titles and the elapsed timer share one crisp fill.
    static let hudText = NSColor(
        name: "VibeComposeHUDText"
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // Near-white, not pure #FFF — keeps a hair of depth on glass.
            return NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1)
        }
        return NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
    }
    static let hudTextMuted = NSColor.secondaryLabelColor
    /// State accents live in the glyphs and badges. The material shell stays
    /// neutral so the HUD remains calm and legible in every appearance.
    /// Live recording — slightly lifted brand blue so the voice glyph stays
    /// luminous on dark glass without washing out on light glass.
    static let hudRecordingAccent = NSColor(
        name: "VibeComposeHUDRecordingAccent"
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // #4DA3FF — brighter, more saturated against dark materials.
            return NSColor(
                srgbRed: 0.30,
                green: 0.64,
                blue: 1,
                alpha: 1
            )
        }
        return brandBlue
    }
    /// Processing pulse — warmer amber so it never collides with recording blue
    /// or the success green badge that follows.
    static let hudProcessingAccent = NSColor(
        name: "VibeComposeHUDProcessingAccent"
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(
                srgbRed: 1,
                green: 0.78,
                blue: 0.36,
                alpha: 1
            )
        }
        return NSColor(
            srgbRed: 1,
            green: 0.62,
            blue: 0.22,
            alpha: 1
        )
    }
    static let graphite = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 0.90)
    static let graphiteElevated = NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 0.92)
    static let mist = NSColor(srgbRed: 0.96, green: 0.975, blue: 0.99, alpha: 1)
    static let mistMuted = NSColor(srgbRed: 0.78, green: 0.82, blue: 0.88, alpha: 1)
    /// Product-owner approved brand blue sampled from the reference artwork.
    /// #0074FF / RGB 0, 116, 255.
    static let brandBlue = NSColor(
        srgbRed: 0,
        green: 116.0 / 255.0,
        blue: 1,
        alpha: 1
    )
    // MARK: Logo rainbow stops (infinity-knot emblem)
    // Soft spectral family sampled from VibeComposeLogoSource — used for
    // brand-stage accents that need the full knot trail. Keep pastels
    // desaturated so they read as atmosphere, not a pride flag.
    /// Logo cyan / teal stop.
    static let brandSpectrumCyan = NSColor(
        srgbRed: 0.22,
        green: 0.78,
        blue: 0.82,
        alpha: 1
    )
    /// Logo sky blue stop (sits next to brandBlue).
    static let brandSpectrumSky = NSColor(
        srgbRed: 0.30,
        green: 0.58,
        blue: 0.98,
        alpha: 1
    )
    /// Logo violet / indigo stop.
    static let brandSpectrumViolet = NSColor(
        srgbRed: 0.52,
        green: 0.42,
        blue: 0.96,
        alpha: 1
    )
    /// Logo coral / rose stop.
    static let brandSpectrumCoral = NSColor(
        srgbRed: 0.98,
        green: 0.42,
        blue: 0.48,
        alpha: 1
    )
    /// Logo amber / gold stop.
    static let brandSpectrumAmber = NSColor(
        srgbRed: 0.98,
        green: 0.72,
        blue: 0.28,
        alpha: 1
    )

    // MARK: Atmosphere stage (Codex-inspired continuum)
    // Soft blue → periwinkle → lavender field sampled from openai.com/codex
    // hero backdrop / OG art. Used for onboarding right-stage wallpaper —
    // dreamy continuum, not a multi-stop rainbow.
    /// Plate behind the continuum — #EFEEFE lavender mist.
    static let atmospherePlate = NSColor(
        srgbRed: 0xEF / 255.0,
        green: 0xEE / 255.0,
        blue: 0xFE / 255.0,
        alpha: 1
    )
    /// Soft sky periwinkle — #A0B4FA.
    static let atmosphereSky = NSColor(
        srgbRed: 0xA0 / 255.0,
        green: 0xB4 / 255.0,
        blue: 0xFA / 255.0,
        alpha: 1
    )
    /// Mid periwinkle bloom — #969AF0.
    static let atmospherePeriwinkle = NSColor(
        srgbRed: 0x96 / 255.0,
        green: 0x9A / 255.0,
        blue: 0xF0 / 255.0,
        alpha: 1
    )
    /// Cool indigo-violet — #7878DC.
    static let atmosphereIndigo = NSColor(
        srgbRed: 0x78 / 255.0,
        green: 0x78 / 255.0,
        blue: 0xDC / 255.0,
        alpha: 1
    )
    /// Soft lavender highlight — #C8C8F8.
    static let atmosphereLavender = NSColor(
        srgbRed: 0xC8 / 255.0,
        green: 0xC8 / 255.0,
        blue: 0xF8 / 255.0,
        alpha: 1
    )
    /// Deep royal corner weight (floral shadow) — #1840E0.
    static let atmosphereDeep = NSColor(
        srgbRed: 0x18 / 255.0,
        green: 0x40 / 255.0,
        blue: 0xE0 / 255.0,
        alpha: 1
    )
    /// Light appearance selection fill sampled from the same artwork.
    /// #EFEFEF / RGB 239, 239, 239.
    static let sidebarSelectionLightColor = NSColor(
        srgbRed: 239.0 / 255.0,
        green: 239.0 / 255.0,
        blue: 239.0 / 255.0,
        alpha: 1
    )
    static let sidebarSelectionBackground = NSColor(
        name: "VibeComposeSidebarSelectionBackground"
    ) { appearance in
        if appearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.12)
        }
        return sidebarSelectionLightColor
    }
    /// Inactive (window unfocused / selection not emphasized) pill fill —
    /// quieter gray so the blue accent only appears while the shell is key.
    static let sidebarSelectionBackgroundInactive = NSColor(
        name: "VibeComposeSidebarSelectionBackgroundInactive"
    ) { appearance in
        if appearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.08)
        }
        return NSColor(
            srgbRed: 0.90,
            green: 0.90,
            blue: 0.91,
            alpha: 1
        )
    }
    /// Foreground (icon + label) of a selected source-list row while focused.
    static let sidebarSelectionForeground = NSColor(
        name: "VibeComposeSidebarSelectionForeground"
    ) { appearance in
        if appearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua {
            return NSColor(
                srgbRed: 0.42,
                green: 0.70,
                blue: 1,
                alpha: 1
            )
        }
        return brandBlue
    }
    /// Foreground of a selected row when the window / sidebar loses focus —
    /// system-gray primary, matching Finder / System Settings inactive state.
    static let sidebarSelectionForegroundInactive = NSColor(
        name: "VibeComposeSidebarSelectionForegroundInactive"
    ) { appearance in
        if appearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.78)
        }
        return NSColor(
            srgbRed: 0.22,
            green: 0.22,
            blue: 0.24,
            alpha: 1
        )
    }
    static let signalBlue = brandBlue
    static let success = NSColor(srgbRed: 0.32, green: 0.80, blue: 0.58, alpha: 1)
    static let amber = NSColor(srgbRed: 1, green: 0.72, blue: 0.28, alpha: 1)
    static let error = NSColor(srgbRed: 1, green: 0.42, blue: 0.44, alpha: 1)

    /// Skill Switcher selection pill: solid brand blue so white labels stay
    /// legible on Liquid Glass in both light and dark appearances (system
    /// `selectedContentBackgroundColor` still pairs with semantic primary
    /// colors that do not flip on custom glass shells).
    static let skillSwitcherSelectionBackground = brandBlue
    /// Primary label / glyph on a selected switcher row — always white.
    static let skillSwitcherSelectionForeground = NSColor.white
    /// Summary / ↩ glyph on a selected switcher row.
    static let skillSwitcherSelectionForegroundSecondary = NSColor.white
        .withAlphaComponent(0.82)

    /// Semantic system colors keep content surfaces adaptive without trying to
    /// imitate the optical behavior of Liquid Glass.
    static let hairline = NSColor.separatorColor
    static let elevatedSurface = NSColor.controlBackgroundColor
    static let insetSurface = NSColor.textBackgroundColor

    /// Stable body under the Settings floating source-list glass. Pure
    /// `.glassEffect` without a plate freezes as a dark graphite slab after
    /// miniaturize → deminiaturize (and other compositor resets) because the
    /// glass sample buffer is empty. The plate keeps the rail light/adaptive;
    /// glass only supplies the optical edge.
    static let floatingSidebarPlate = NSColor(
        name: "VibeComposeFloatingSidebarPlate"
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 0.92)
        }
        // Cool mist close to windowBackground / Music source-list family.
        return NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 0.94)
    }

    /// Gentle glass tint over the sidebar plate — lighter than reading-panel
    /// tint so the rail stays a navigation surface, not a content plate.
    static let floatingSidebarGlassTint = NSColor(
        name: "VibeComposeFloatingSidebarGlassTint"
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.18, green: 0.19, blue: 0.22, alpha: 0.36)
        }
        return NSColor(srgbRed: 0.98, green: 0.99, blue: 1.0, alpha: 0.32)
    }

    /// Near-opaque plate under reading-panel glass. Wallpaper must not compete
    /// with type — Apple's Spotlight / Applications launcher use a dense body,
    /// not a see-through film. Glass sits on top for the optical edge only.
    static let floatingPanelPlate = NSColor(
        name: "VibeComposeFloatingPanelPlate"
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // Graphite body — high alpha so busy desktops cannot punch through.
            return NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 0.94)
        }
        // Soft paper white / cool mist (Applications launcher family).
        return NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 0.96)
    }

    /// Light glass tint layered on top of the plate for Liquid Glass refraction.
    /// Kept gentle so the plate carries opacity and the glass only adds edge.
    static let floatingPanelGlassTint = NSColor(
        name: "VibeComposeFloatingPanelGlassTint"
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.14, green: 0.15, blue: 0.18, alpha: 0.45)
        }
        return NSColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 0.40)
    }

    /// Primary reading surfaces (Result editor, Comparison) — solid enough that
    /// body text never samples the desktop. Never a second glass layer.
    static let floatingContentSurface = NSColor(
        name: "VibeComposeFloatingContentSurface"
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 0.96)
        }
        return NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.98)
    }

    /// Secondary plates (chips, hover, header buttons) on floating chrome.
    static let floatingContentSurfaceQuiet = NSColor(
        name: "VibeComposeFloatingContentSurfaceQuiet"
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.22, green: 0.23, blue: 0.26, alpha: 0.72)
        }
        return NSColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.06)
    }

    /// Hard primary label for text sitting on floating glass / plate. System
    /// `labelColor` still washes gray through translucent materials.
    static let floatingPrimaryText = NSColor(
        name: "VibeComposeFloatingPrimaryText"
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.96, green: 0.97, blue: 0.98, alpha: 1)
        }
        return NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1)
    }

    /// Secondary label on floating chrome — still crisp, not tertiary wash.
    static let floatingSecondaryText = NSColor(
        name: "VibeComposeFloatingSecondaryText"
    ) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.78, green: 0.80, blue: 0.84, alpha: 1)
        }
        return NSColor(srgbRed: 0.32, green: 0.34, blue: 0.38, alpha: 1)
    }
}

// MARK: - Design tokens

enum VibeComposeMetrics {
    static let space2: CGFloat = 2
    static let space4: CGFloat = 4
    static let space6: CGFloat = 6
    static let space8: CGFloat = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space14: CGFloat = 14
    static let space16: CGFloat = 16
    static let space18: CGFloat = 18
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space28: CGFloat = 28
    static let space32: CGFloat = 32
    static let space40: CGFloat = 40
    static let space48: CGFloat = 48

    static let radiusXS: CGFloat = 6
    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 10
    static let radiusL: CGFloat = 12
    static let radiusXL: CGFloat = 16
    static let radiusXXL: CGFloat = 22
    static let radiusPill: CGFloat = 999

    static let controlHeight: CGFloat = 28
    static let controlHeightLarge: CGFloat = 36
    static let iconWellSize: CGFloat = 32
    static let iconWellSizeLarge: CGFloat = 40
    static let iconWellSizeXL: CGFloat = 48
    static let windowChromePadding: CGFloat = 20
    static let contentMaxWidth: CGFloat = 720
    /// Onboarding / wizard content column — iPad-like reading width.
    static let onboardingContentMaxWidth: CGFloat = 780
}

// MARK: - Motion tokens

enum VibeComposeMotion {
    // MARK: Durations (AppKit / TimeInterval)
    static let hudAppear: TimeInterval = 0.18
    static let hudDismiss: TimeInterval = 0.20
    static let hudSizeMorph: TimeInterval = 0.22
    static let pageTransition: Double = 0.20
    static let quickFade: Double = 0.14
    /// Spotlight-like panel fade — short ease, no bounce.
    static let panelAppear: TimeInterval = 0.16
    static let panelDismiss: TimeInterval = 0.12

    // MARK: Springs (SwiftUI Animation)
    /// Standard spring — settings sidebar navigation, content pane transitions.
    /// Slightly longer response reads more deliberate on macOS R6 glass chrome.
    static var standardSpring: Animation {
        .spring(response: 0.36, dampingFraction: 0.88)
    }
    /// Snappy spring — settings sidebar selection (navigation, not content swap)
    static var snappySpring: Animation {
        .spring(response: 0.26, dampingFraction: 0.88)
    }
    /// Press spring — button active-state scale feedback
    static var pressSpring: Animation {
        .spring(response: 0.18, dampingFraction: 0.72)
    }
    /// Panel spring — floating panel entrance. High damping + short response so
    /// Skill Switcher / Preview feel like Spotlight (opacity + tiny scale), not
    /// a bouncy card.
    static var panelSpring: Animation {
        .spring(response: 0.22, dampingFraction: 0.94)
    }
    /// Ease for in-panel expand/collapse (Comparison, etc.) — no slide.
    static var panelContent: Animation {
        .easeOut(duration: 0.16)
    }
    /// Step spring — onboarding step content transition (interruptible, physical)
    static var stepSpring: Animation {
        .spring(response: 0.38, dampingFraction: 0.90)
    }
    /// Indicator spring — onboarding step circle color/icon morph
    static var indicatorSpring: Animation {
        .spring(response: 0.34, dampingFraction: 0.82)
    }
    /// Soft settle — hero cards, brand mark appear
    static var softSettle: Animation {
        .spring(response: 0.48, dampingFraction: 0.92)
    }
    /// Showcase geometry morph — width, height, radius, color, and shadow move
    /// as one highly damped surface. Retargeting preserves in-flight velocity
    /// without the visible bounce of a general-purpose content spring.
    static var showcaseMorph: Animation {
        .spring(response: 0.40, dampingFraction: 0.94)
    }

    /// Entrance scale for floating panels. Keep very close to 1 so motion reads
    /// as a soft materialize, not a pop.
    static let panelEntranceScale: CGFloat = 0.985
}

enum VibeComposeTypography {
    /// Hero / onboarding step titles — slightly larger for editorial presence.
    /// Uses Dynamic Type text styles so Settings / long-form UI tracks system size.
    static func display(_ weight: Font.Weight = .semibold) -> Font {
        .system(.largeTitle, design: .default).weight(weight)
    }

    static func title(_ weight: Font.Weight = .semibold) -> Font {
        .system(.title2, design: .default).weight(weight)
    }

    static func title2(_ weight: Font.Weight = .semibold) -> Font {
        .system(.title3, design: .default).weight(weight)
    }

    static func headline(_ weight: Font.Weight = .semibold) -> Font {
        .system(.headline, design: .default).weight(weight)
    }

    static func body(_ weight: Font.Weight = .regular) -> Font {
        .system(.body, design: .default).weight(weight)
    }

    static func callout(_ weight: Font.Weight = .regular) -> Font {
        .system(.callout, design: .default).weight(weight)
    }

    static func caption(_ weight: Font.Weight = .regular) -> Font {
        .system(.caption, design: .default).weight(weight)
    }

    static func micro(_ weight: Font.Weight = .medium) -> Font {
        .system(.caption2, design: .default).weight(weight)
    }

    /// App Store editorial eyebrow: tracked-out caption labels
    /// ("OUR FAVOURITES", "EDITORS' CHOICE") used above hero content.
    static func eyebrow(_ weight: Font.Weight = .semibold) -> Font {
        .system(.caption, design: .default).weight(weight)
    }

    /// Monospaced runs (code, timers). `size` remains available for chrome that
    /// must stay pixel-locked (HUD timer digits); prefer the default for forms.
    static func mono(_ size: CGFloat? = nil, weight: Font.Weight = .medium) -> Font {
        if let size {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .system(.caption, design: .monospaced).weight(weight)
    }
}

// MARK: - Brand tint

extension View {
    func applyingVibeComposeBrandTint() -> some View {
        tint(
            Color(nsColor: VibeComposePalette.brandBlue)
        )
    }
}

// MARK: - Floating glass chrome
//
// Liquid Glass is the material of floating / navigation chrome only — never
// grouped form content. HUD, Skill Switcher, and other borderless floaters
// share these tokens so shadow, hairline, and glass style stay one family.

enum VibeComposeFloatingChrome {
    /// Soft elevation under floating glass / material shells.
    static let shadowOpacity: Float = 0.22
    static let shadowRadius: CGFloat = 18
    static let shadowOffsetY: CGFloat = -4
    /// Pre-26 classic material only. Liquid Glass draws its own optical edge
    /// and must not sit on a painted shadow plate (Apple sample uses bare
    /// `NSGlassEffectView` with no manual CALayer elevation).
    static let capsuleShadowOpacity: Float = 0.16
    static let capsuleShadowRadius: CGFloat = 14
    static let capsuleShadowOffsetY: CGFloat = -3
    /// Hairline on pre-26 material fallbacks (glass draws its own edge).
    static let hairlineAlpha: CGFloat = 0.12
    static let increaseContrastHairlineAlpha: CGFloat = 0.34
    static let increaseContrastHairlineWidth: CGFloat = 1.5
    static let standardHairlineWidth: CGFloat = 0.5
    /// Panel shells (Skill Switcher) use a large continuous corner.
    static let panelCornerRadius: CGFloat = VibeComposeMetrics.radiusXXL
    /// Panel elevation (SwiftUI shadow companion when the window has no AppKit shadow).
    /// Slightly tighter than before so the plate feels grounded like Spotlight.
    static let panelShadowOpacity: Double = 0.32
    static let panelShadowRadius: CGFloat = 28
    static let panelShadowY: CGFloat = 12
    /// App Store / Music floating source list: continuous corner concentric
    /// with macOS 26 window chrome. ~20 keeps the rail soft without reading as
    /// a phone-scale capsule.
    static let sidebarCornerRadius: CGFloat = 20
    static let sidebarShadowOpacity: Double = 0.16
    static let sidebarShadowRadius: CGFloat = 22
    static let sidebarShadowY: CGFloat = 8
    /// Pre-26 fallback elevation is slightly stronger so the rounded rail still reads.
    static let sidebarFallbackShadowOpacity: Double = 0.22

    static var usesSystemLiquidGlass: Bool {
        if #available(macOS 26, *) {
            return true
        }
        return false
    }

    /// Shared tint applied to reading-panel Liquid Glass (Skill Switcher, Preview).
    static var panelGlassTintColor: Color {
        Color(nsColor: VibeComposePalette.floatingPanelGlassTint)
    }

    static var panelGlassTintNSColor: NSColor {
        VibeComposePalette.floatingPanelGlassTint
    }

    /// Dense body that blocks wallpaper under the glass optical layer.
    static var panelPlateColor: Color {
        Color(nsColor: VibeComposePalette.floatingPanelPlate)
    }

    static var panelPlateNSColor: NSColor {
        VibeComposePalette.floatingPanelPlate
    }

    static var sidebarPlateColor: Color {
        Color(nsColor: VibeComposePalette.floatingSidebarPlate)
    }

    static var sidebarGlassTintColor: Color {
        Color(nsColor: VibeComposePalette.floatingSidebarGlassTint)
    }
}

/// SwiftUI floating shell: Liquid Glass on macOS 26, refined hudWindow material
/// earlier. Content rows stay solid fills — never nest glass inside this shell.
///
/// Reading panels (Skill Switcher, Preview peers) use a near-opaque plate under
/// regular glass so type stays Spotlight-legible over busy wallpapers. HUD
/// capsules keep the default untinted glass via their own AppKit path.
struct VibeComposeFloatingGlassChrome<S: InsettableShape>: ViewModifier {
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        let increaseContrast = colorSchemeContrast == .increased
        let hairlineAlpha = increaseContrast
            ? VibeComposeFloatingChrome.increaseContrastHairlineAlpha
            : VibeComposeFloatingChrome.hairlineAlpha
        let hairlineWidth = increaseContrast
            ? VibeComposeFloatingChrome.increaseContrastHairlineWidth
            : VibeComposeFloatingChrome.standardHairlineWidth
        // Reduce Transparency: solid elevated plate, no glass/material sample.
        if reduceTransparency {
            content
                .background {
                    shape.fill(Color(nsColor: VibeComposePalette.elevatedSurface))
                }
                .clipShape(shape)
                .overlay {
                    shape.stroke(
                        Color.primary.opacity(hairlineAlpha),
                        lineWidth: hairlineWidth
                    )
                }
                .shadow(
                    color: Color.black.opacity(
                        VibeComposeFloatingChrome.panelShadowOpacity * 0.5
                    ),
                    radius: VibeComposeFloatingChrome.panelShadowRadius * 0.6,
                    x: 0,
                    y: VibeComposeFloatingChrome.panelShadowY * 0.6
                )
        } else if #available(macOS 26, *) {
            // Hosted AppKit windows often leave a rectangular backing layer under
            // Liquid Glass. Clip → composite → glass → clip again so solid fills
            // and the host plate never peek past the continuous corner as square
            // nubs (the classic "white corner" artifact on floating rails).
            //
            // Plate first (opacity), then glass (edge / refraction). Tint is
            // light — the plate does the readability work.
            content
                .background {
                    shape.fill(VibeComposeFloatingChrome.panelPlateColor)
                }
                .clipShape(shape)
                .compositingGroup()
                .glassEffect(
                    .regular.tint(VibeComposeFloatingChrome.panelGlassTintColor),
                    in: shape
                )
                .clipShape(shape)
                .shadow(
                    color: Color.black.opacity(VibeComposeFloatingChrome.panelShadowOpacity),
                    radius: VibeComposeFloatingChrome.panelShadowRadius,
                    x: 0,
                    y: VibeComposeFloatingChrome.panelShadowY
                )
        } else {
            content
                .background {
                    VibeComposeFloatingMaterialBackground(
                        shape: shape,
                        material: .hudWindow,
                        blendingMode: .behindWindow
                    )
                }
                // Near-opaque plate under classic material.
                .background {
                    shape.fill(VibeComposeFloatingChrome.panelPlateColor)
                }
                .clipShape(shape)
                .overlay {
                    shape.stroke(
                        Color.primary.opacity(hairlineAlpha),
                        lineWidth: hairlineWidth
                    )
                }
                .shadow(
                    color: Color.black.opacity(VibeComposeFloatingChrome.panelShadowOpacity + 0.08),
                    radius: VibeComposeFloatingChrome.panelShadowRadius,
                    x: 0,
                    y: VibeComposeFloatingChrome.panelShadowY
                )
        }
    }
}

/// App Store / Music–style floating source list: a rounded Liquid Glass rail that
/// sits *on* the content canvas (navigation layer), not a flush split column.
/// Selection pills and labels stay solid fills — never nest a second glass layer.
struct VibeComposeFloatingSidebarChrome<S: InsettableShape>: ViewModifier {
    let shape: S
    /// Bumped after deminiaturize / key-window restore so Liquid Glass remounts
    /// instead of reusing a stale compositor sample (dark graphite slab).
    var materializationID: Int = 0

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        let increaseContrast = colorSchemeContrast == .increased
        let hairlineAlpha = increaseContrast
            ? VibeComposeFloatingChrome.increaseContrastHairlineAlpha
            : VibeComposeFloatingChrome.hairlineAlpha
        let hairlineWidth = increaseContrast
            ? VibeComposeFloatingChrome.increaseContrastHairlineWidth
            : VibeComposeFloatingChrome.standardHairlineWidth

        // Reduce Transparency: solid elevated plate, no glass/material sample.
        if reduceTransparency {
            content
                .background {
                    shape.fill(Color(nsColor: VibeComposePalette.elevatedSurface))
                }
                .clipShape(shape)
                .overlay {
                    shape.stroke(
                        Color.primary.opacity(hairlineAlpha),
                        lineWidth: hairlineWidth
                    )
                }
                .shadow(
                    color: Color.black.opacity(
                        VibeComposeFloatingChrome.sidebarFallbackShadowOpacity * 0.55
                    ),
                    radius: VibeComposeFloatingChrome.sidebarShadowRadius * 0.6,
                    x: 0,
                    y: VibeComposeFloatingChrome.sidebarShadowY * 0.6
                )
        } else if #available(macOS 26, *) {
            // Plate + glass mirrors the reading-panel shell. A plate-less pure
            // `.glassEffect` looks correct on first open but freezes dark after
            // the window is miniaturized and restored (empty sample buffer).
            // Double-clip + compositingGroup still prevent square nubs at the
            // continuous corners of the NSHostingView plate.
            content
                .background {
                    shape.fill(VibeComposeFloatingChrome.sidebarPlateColor)
                }
                .clipShape(shape)
                .compositingGroup()
                .glassEffect(
                    .regular.tint(VibeComposeFloatingChrome.sidebarGlassTintColor),
                    in: shape
                )
                .clipShape(shape)
                // Remount glass after compositor resets without reloading the
                // whole Settings tree.
                .id("vw-sidebar-glass-\(materializationID)")
                .shadow(
                    color: Color.black.opacity(
                        VibeComposeFloatingChrome.sidebarShadowOpacity
                    ),
                    radius: VibeComposeFloatingChrome.sidebarShadowRadius,
                    x: 0,
                    y: VibeComposeFloatingChrome.sidebarShadowY
                )
        } else {
            content
                .background {
                    VibeComposeFloatingMaterialBackground(
                        shape: shape,
                        material: .sidebar,
                        blendingMode: .withinWindow
                    )
                }
                // Adaptive plate under classic material so deminiaturize cannot
                // leave a dark empty hole either.
                .background {
                    shape.fill(VibeComposeFloatingChrome.sidebarPlateColor)
                }
                .clipShape(shape)
                .overlay {
                    shape.stroke(
                        Color.primary.opacity(hairlineAlpha),
                        lineWidth: hairlineWidth
                    )
                }
                .shadow(
                    color: Color.black.opacity(
                        VibeComposeFloatingChrome.sidebarFallbackShadowOpacity
                    ),
                    radius: VibeComposeFloatingChrome.sidebarShadowRadius,
                    x: 0,
                    y: VibeComposeFloatingChrome.sidebarShadowY
                )
        }
    }
}

/// Pre-26 material backdrop that tracks the system appearance (no forced dark).
private struct VibeComposeFloatingMaterialBackground<S: InsettableShape>: View {
    let shape: S
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    var body: some View {
        VibeComposeMaterialRepresentable(
            material: material,
            blendingMode: blendingMode
        )
        .clipShape(shape)
    }
}

private struct VibeComposeMaterialRepresentable: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Surface modifiers

struct VibeComposeCardChrome: ViewModifier {
    var padding: CGFloat = VibeComposeMetrics.space16
    var cornerRadius: CGFloat = VibeComposeMetrics.radiusL
    var elevated = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    // Content cards remain solid. Liquid Glass belongs to navigation chrome and
    // floating controls, not grouped form content. A hairline + soft shadow
    // gives depth without sampling the desktop (safe for opaque wizard plates).
    func body(content: Content) -> some View {
        let increaseContrast = colorSchemeContrast == .increased
        let hairlineWidth = increaseContrast
            ? VibeComposeFloatingChrome.increaseContrastHairlineWidth
            : VibeComposeFloatingChrome.standardHairlineWidth
        let hairlineOpacity = increaseContrast
            ? VibeComposeFloatingChrome.increaseContrastHairlineAlpha
            : (elevated ? 0.55 : 0.40)
        // Reduce Transparency: keep the plate fully opaque (already solid) and
        // drop the soft elevation shadow so cards don't read as translucent lift.
        let shadowOpacity = reduceTransparency
            ? 0.0
            : (elevated ? 0.06 : 0.03)

        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: VibeComposePalette.elevatedSurface),
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(
                    Color(nsColor: VibeComposePalette.hairline).opacity(hairlineOpacity),
                    lineWidth: hairlineWidth
                )
            }
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: elevated ? 14 : 6,
                x: 0,
                y: elevated ? 5 : 2
            )
    }
}

struct VibeComposeInsetChrome: ViewModifier {
    var padding: CGFloat = VibeComposeMetrics.space12
    var cornerRadius: CGFloat = VibeComposeMetrics.radiusM

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        let increaseContrast = colorSchemeContrast == .increased
        let hairlineWidth = increaseContrast
            ? VibeComposeFloatingChrome.increaseContrastHairlineWidth
            : VibeComposeFloatingChrome.standardHairlineWidth
        let hairlineOpacity = increaseContrast
            ? VibeComposeFloatingChrome.increaseContrastHairlineAlpha
            : 0.7

        content
            .padding(padding)
            .background(
                Color(nsColor: VibeComposePalette.insetSurface),
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(
                    Color(nsColor: VibeComposePalette.hairline).opacity(hairlineOpacity),
                    lineWidth: hairlineWidth
                )
            }
    }
}

struct VibeComposeSearchFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, VibeComposeMetrics.space12)
            .padding(.vertical, VibeComposeMetrics.space6)
            .frame(minHeight: 30)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusL,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusL,
                    style: .continuous
                )
                .stroke(
                    Color(nsColor: .separatorColor),
                    lineWidth: 0.5
                )
            }
    }
}

struct VibeComposeToolbarChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, VibeComposeMetrics.space20)
            .padding(.vertical, VibeComposeMetrics.space12)
            .background(.bar)
    }
}

/// Hides the system keyboard-focus glow on `.focusable()` containers.
/// Product selection chrome (card stroke / fill) remains the only highlight.
struct VibeComposeFocusRingSuppressed: ViewModifier {
    func body(content: Content) -> some View {
        // SwiftUI's default focus effect draws a brand-tinted rectangle around
        // the whole focusable region (the skill grid blue outline). Disable it
        // at the SwiftUI layer, then clear AppKit focusRingType as a backstop.
        Group {
            if #available(macOS 14.0, *) {
                content.focusEffectDisabled(true)
            } else {
                content
            }
        }
        .background(
            VibeComposeFocusRingSuppressor()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        )
    }
}

/// Walks the hosting NSView tree and clears `focusRingType` so arrow-key
/// grids do not draw the default blue outer rectangle when focusEffectDisabled
/// is unavailable or incomplete.
private struct VibeComposeFocusRingSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = FocusRingHostView(frame: .zero)
        view.focusRingType = .none
        DispatchQueue.main.async {
            suppressFocusRings(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.focusRingType = .none
        DispatchQueue.main.async {
            suppressFocusRings(from: nsView)
        }
    }

    private func suppressFocusRings(from view: NSView) {
        var walker: NSView? = view
        while let current = walker {
            current.focusRingType = .none
            walker = current.superview
        }
        // Climb to the nearest NSHostingView / clip view and clear the subtree
        // that owns the keyboard-focusable grid, without walking the whole window.
        if let host = nearestHostingAncestor(from: view) {
            suppressFocusRingsInSubtree(host)
        } else if let host = view.superview {
            suppressFocusRingsInSubtree(host)
        }
    }

    private func nearestHostingAncestor(from view: NSView) -> NSView? {
        var walker: NSView? = view.superview
        while let current = walker {
            let name = String(describing: type(of: current))
            if name.contains("HostingView") || name.contains("NSClipView") {
                return current
            }
            walker = current.superview
        }
        return view.superview
    }

    private func suppressFocusRingsInSubtree(_ root: NSView) {
        root.focusRingType = .none
        for child in root.subviews {
            suppressFocusRingsInSubtree(child)
        }
    }
}

/// Zero-size probe that never draws its own focus ring.
private final class FocusRingHostView: NSView {
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { super.focusRingType = .none }
    }

    override func drawFocusRingMask() {}
    override var focusRingMaskBounds: NSRect { .zero }
}

extension View {
    /// Preferred card chrome API (VibeCompose product name).
    func vibeComposeCard(
        padding: CGFloat = VibeComposeMetrics.space16,
        cornerRadius: CGFloat = VibeComposeMetrics.radiusL,
        elevated: Bool = true
    ) -> some View {
        modifier(
            VibeComposeCardChrome(
                padding: padding,
                cornerRadius: cornerRadius,
                elevated: elevated
            )
        )
    }

    func vibeComposeInset(
        padding: CGFloat = VibeComposeMetrics.space12,
        cornerRadius: CGFloat = VibeComposeMetrics.radiusM
    ) -> some View {
        modifier(
            VibeComposeInsetChrome(
                padding: padding,
                cornerRadius: cornerRadius
            )
        )
    }

    func vibeComposeSearchField() -> some View {
        modifier(VibeComposeSearchFieldChrome())
    }

    /// Suppress the system keyboard-focus glow on focusable containers while
    /// keeping arrow-key / onMoveCommand navigation. Selection chrome is owned
    /// by the product (row/card stroke), not the default blue focus rectangle.
    func vibeComposeSuppressFocusRing() -> some View {
        modifier(VibeComposeFocusRingSuppressed())
    }

    func vibeComposeToolbar() -> some View {
        modifier(VibeComposeToolbarChrome())
    }

    /// Floating panel chrome (Skill Switcher and peers). Glass on macOS 26;
    /// refined hudWindow material with soft elevation earlier.
    func vibeComposeFloatingGlass<S: InsettableShape>(
        in shape: S
    ) -> some View {
        modifier(VibeComposeFloatingGlassChrome(shape: shape))
    }

    func vibeComposeFloatingGlass(
        cornerRadius: CGFloat = VibeComposeFloatingChrome.panelCornerRadius
    ) -> some View {
        vibeComposeFloatingGlass(
            in: RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
    }

    /// Floating source-list rail (Settings shell). Glass on macOS 26; sidebar
    /// material with soft elevation earlier. Use only on the navigation layer.
    func vibeComposeFloatingSidebarGlass<S: InsettableShape>(
        in shape: S,
        materializationID: Int = 0
    ) -> some View {
        modifier(
            VibeComposeFloatingSidebarChrome(
                shape: shape,
                materializationID: materializationID
            )
        )
    }

    func vibeComposeFloatingSidebarGlass(
        cornerRadius: CGFloat = VibeComposeFloatingChrome.sidebarCornerRadius
    ) -> some View {
        vibeComposeFloatingSidebarGlass(
            in: RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
    }

}

/// In-content pane header used when a destination is embedded inside the
/// Settings shell: a large title on the leading edge with the pane's controls
/// trailing, matching how Apple's apps compose headers inside a detail column
/// instead of relying on window toolbar chrome.
struct VibeComposePaneHeader<Controls: View>: View {
    let title: String
    @ViewBuilder let controls: Controls

    var body: some View {
        HStack(alignment: .center, spacing: VibeComposeMetrics.space16) {
            Text(title)
                .font(VibeComposeTypography.display())
                .tracking(-0.45)
                .lineLimit(1)
            Spacer(minLength: VibeComposeMetrics.space12)
            controls
        }
        .padding(.horizontal, VibeComposeMetrics.space20)
        .padding(.top, VibeComposeMetrics.space14)
        .padding(.bottom, VibeComposeMetrics.space12)
    }
}

// MARK: - Shared chrome components

/// Brand emblem tile used in onboarding headers and empty states. Always solid
/// brand blue — never material or multi-stop gradient — so it stays crisp on
/// both light and dark plates without introducing painted washes into the
/// shared visual system (Liquid Glass stays navigation-only).
struct VibeComposeBrandMark: View {
    var size: CGFloat = 36
    var symbolName: String = "waveform"
    var showsGlow: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: size * 0.28,
                style: .continuous
            )
            .fill(Color(nsColor: VibeComposePalette.brandBlue))
            .frame(width: size, height: size)
            .shadow(
                color: showsGlow
                    ? Color(nsColor: VibeComposePalette.brandBlue)
                        .opacity(0.32)
                    : .clear,
                radius: size * 0.28,
                x: 0,
                y: size * 0.12
            )
            Image(systemName: symbolName)
                .font(
                    .system(
                        size: size * 0.44,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityHidden(true)
    }
}

struct VibeComposeIconWell: View {
    let systemName: String
    var size: CGFloat = VibeComposeMetrics.iconWellSize
    var symbolSize: CGFloat = 15
    var tint: Color = Color(nsColor: VibeComposePalette.brandBlue)
    var fillOpacity: Double = 0.09

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                tint.opacity(fillOpacity),
                in: RoundedRectangle(
                    cornerRadius: size * 0.25,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
    }
}

struct VibeComposeStatusChip: View {
    enum Kind {
        case neutral
        case success
        case warning
        case error
        case accent
    }

    let text: String
    var kind: Kind = .neutral

    var body: some View {
        // Icon + color so status is not color-only (Differentiate Without Color).
        Label(text, systemImage: symbolName)
            .labelStyle(.titleAndIcon)
            .font(VibeComposeTypography.micro(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, VibeComposeMetrics.space8)
            .padding(.vertical, VibeComposeMetrics.space4)
            .background(
                background,
                in: Capsule(style: .continuous)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        foreground.opacity(0.14),
                        lineWidth: VibeComposeFloatingChrome.standardHairlineWidth
                    )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private var symbolName: String {
        switch kind {
        case .neutral:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .accent:
            return "circle.fill"
        }
    }

    private var foreground: Color {
        switch kind {
        case .neutral:
            return .secondary
        case .success:
            return Color(nsColor: VibeComposePalette.success)
        case .warning:
            return Color(nsColor: VibeComposePalette.amber)
        case .error:
            return Color(nsColor: VibeComposePalette.error)
        case .accent:
            return Color(nsColor: VibeComposePalette.brandBlue)
        }
    }

    private var background: Color {
        foreground.opacity(0.11)
    }
}

struct VibeComposeSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(VibeComposeTypography.caption(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct VibeComposeWindowHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: VibeComposeMetrics.space14) {
            if let systemImage {
                VibeComposeIconWell(
                    systemName: systemImage,
                    size: VibeComposeMetrics.iconWellSizeLarge,
                    symbolSize: 18
                )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(VibeComposeTypography.title())
                    .tracking(-0.18)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(VibeComposeTypography.caption())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: VibeComposeMetrics.space12)
            trailing
        }
        .padding(.horizontal, VibeComposeMetrics.space20)
        .padding(.vertical, VibeComposeMetrics.space14)
    }
}

extension VibeComposeWindowHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage
        ) {
            EmptyView()
        }
    }
}

struct VibeComposeEmptyState: View {
    let systemImage: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: VibeComposeMetrics.space10) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text(title)
                .font(VibeComposeTypography.title2())
                .multilineTextAlignment(.center)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(VibeComposeTypography.caption())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
            }
        }
        .padding(VibeComposeMetrics.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Button styles

struct VibeComposeSecondaryButtonStyle: PrimitiveButtonStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26, *) {
            Button(role: configuration.role) {
                configuration.trigger()
            } label: {
                configuration.label
            }
            .buttonStyle(.glass)
        } else {
            Button(role: configuration.role) {
                configuration.trigger()
            } label: {
                configuration.label
            }
            .buttonStyle(.bordered)
        }
    }
}

struct VibeComposePrimaryButtonStyle: PrimitiveButtonStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26, *) {
            Button(role: configuration.role) {
                configuration.trigger()
            } label: {
                configuration.label
            }
            .buttonStyle(.glassProminent)
        } else {
            Button(role: configuration.role) {
                configuration.trigger()
            } label: {
                configuration.label
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Onboarding / wizard primary CTA. Solid brand-blue continuous capsule.
///
/// Implemented as `PrimitiveButtonStyle` (same pattern as
/// `VibeComposePrimaryButtonStyle`) so the action fires through a real
/// AppKit/SwiftUI control path — custom `ButtonStyle` label gestures have
/// been flaky for first-click / animated-parent cases on macOS 26.
struct VibeComposeOnboardingCTAButtonStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.trigger()
        } label: {
            configuration.label
                .font(VibeComposeTypography.callout(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, VibeComposeMetrics.space20)
                .padding(.vertical, VibeComposeMetrics.space12)
                .frame(minHeight: 40)
                .background(
                    Color(nsColor: VibeComposePalette.brandBlue),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(
                                colorScheme == .dark ? 0.20 : 0.30
                            ),
                            lineWidth: VibeComposeFloatingChrome.standardHairlineWidth
                        )
                }
                .contentShape(Capsule(style: .continuous))
                .shadow(
                    color: Color(nsColor: VibeComposePalette.brandBlue)
                        .opacity(isEnabled ? 0.36 : 0),
                    radius: 14,
                    x: 0,
                    y: 6
                )
                .opacity(isEnabled ? 1 : 0.42)
                // Press feedback via plain ButtonStyle wrapper below.
        }
        .buttonStyle(VibeComposeOnboardingCTAPressStyle())
        // Plain style still needs an explicit hit capsule — label text alone
        // is smaller than the painted brand pill.
        .contentShape(Capsule(style: .continuous))
    }
}

/// Scales the onboarding primary CTA on press (pointer-down feedback).
private struct VibeComposeOnboardingCTAPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .animation(
                VibeComposeMotion.pressSpring,
                value: configuration.isPressed
            )
    }
}

/// Quiet secondary CTA for onboarding footers (e.g. “Enable Automatic Paste”).
struct VibeComposeOnboardingSecondaryButtonStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.trigger()
        } label: {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    Color.primary.opacity(isEnabled ? 0.72 : 0.34)
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Color.primary.opacity(0.04),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(0.10),
                            lineWidth: 0.5
                        )
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct VibeComposeQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(
                Color.primary.opacity(
                    isEnabled
                        ? (configuration.isPressed ? 0.55 : 0.78)
                        : 0.36
                )
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.07 : 0.03),
                in: RoundedRectangle(
                    cornerRadius: VibeComposeMetrics.radiusS,
                    style: .continuous
                )
            )
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .animation(
                VibeComposeMotion.pressSpring,
                value: configuration.isPressed
            )
    }
}

// MARK: - Sidebar symbol

/// Source-list icon matched to macOS Settings: monochrome, medium weight, no
/// hierarchical layering (which makes multi-layer symbols look busy on glass).
/// The row owns selected/unselected foreground color.
struct VibeComposeSidebarSymbol: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .frame(width: 22, height: 20, alignment: .center)
            .accessibilityHidden(true)
    }
}

// MARK: - Step progress bar

struct VibeComposeStepProgressBar: View {
    let steps: [String]
    let currentStep: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                stepNode(index: index)
                if index < steps.count - 1 {
                    connector(completed: index < currentStep)
                }
            }
        }
        .padding(.horizontal, VibeComposeMetrics.space32)
        .padding(.vertical, VibeComposeMetrics.space12)
        .animation(VibeComposeMotion.indicatorSpring, value: currentStep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.format(
                "Step %d of %d",
                currentStep + 1,
                steps.count
            )
        )
    }

    private func stepNode(index: Int) -> some View {
        let isCompleted = index < currentStep
        let isCurrent = index == currentStep

        return VStack(spacing: VibeComposeMetrics.space6) {
            ZStack {
                // Soft halo behind the active node — brand presence without noise.
                if isCurrent {
                    Circle()
                        .fill(
                            Color(nsColor: VibeComposePalette.brandBlue)
                                .opacity(0.16)
                        )
                        .frame(width: 30, height: 30)
                }
                Circle()
                    .fill(
                        isCompleted
                            ? Color(nsColor: VibeComposePalette.success)
                            : isCurrent
                                ? Color(nsColor: VibeComposePalette.brandBlue)
                                : Color.primary.opacity(0.05)
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(
                                isCompleted
                                    ? Color(nsColor: VibeComposePalette.success)
                                    : isCurrent
                                        ? Color(
                                            nsColor: VibeComposePalette.brandBlue
                                        )
                                        : Color.primary.opacity(0.16),
                                lineWidth: isCurrent || isCompleted ? 0 : 1
                            )
                    )
                    .shadow(
                        color: isCurrent
                            ? Color(nsColor: VibeComposePalette.brandBlue)
                                .opacity(0.28)
                            : .clear,
                        radius: 8,
                        x: 0,
                        y: 2
                    )
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(
                            .scale(scale: 0.5).combined(with: .opacity)
                        )
                } else {
                    Text("\(index + 1)")
                        .font(
                            .system(
                                size: 11,
                                weight: isCurrent ? .bold : .medium
                            )
                        )
                        .foregroundStyle(
                            isCurrent
                                ? .white
                                : Color.primary.opacity(0.38)
                        )
                        .transition(.opacity)
                }
            }
            .frame(height: 30)
            Text(steps[index])
                .font(
                    .system(
                        size: 11,
                        weight: isCurrent ? .semibold : .regular
                    )
                )
                .foregroundStyle(
                    isCurrent
                        ? Color(nsColor: VibeComposePalette.brandBlue)
                        : Color.primary.opacity(isCompleted ? 0.68 : 0.36)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(minWidth: 64)
    }

    private func connector(completed: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(
                completed
                    ? Color(nsColor: VibeComposePalette.success).opacity(0.55)
                    : Color.primary.opacity(0.10)
            )
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .offset(y: -12)
            .padding(.horizontal, 4)
    }
}

// MARK: - Status icon renderer

enum VibeComposeStatusIconRenderer {
    private static let brandTemplateImage: NSImage? = {
        guard
            let url = Bundle.main.url(
                forResource: "StatusBarLogoTemplate",
                withExtension: "png"
            ),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    static func image(for state: StatusMenuVisualState) -> NSImage {
        if let brandTemplateImage,
           let image = brandTemplateImage.copy() as? NSImage
        {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        return fallbackImage(for: state)
    }

    private static func fallbackImage(
        for state: StatusMenuVisualState
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let strokeColor = NSColor.black.withAlphaComponent(state.usesTemplateAttention ? 0.92 : 0.82)
        let barColor = NSColor.black.withAlphaComponent(state.usesTemplateAttention ? 1 : 0.92)

        let bubbleRect = NSRect(x: 1.5, y: 4.0, width: 14.2, height: 9.4)
        let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 4.6, yRadius: 4.6)
        bubble.lineWidth = 1.35
        strokeColor.setStroke()
        bubble.stroke()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 4.1, y: 3.6))
        tail.line(to: NSPoint(x: 6.0, y: 2.0))
        tail.line(to: NSPoint(x: 7.2, y: 3.2))
        tail.line(to: NSPoint(x: 5.3, y: 4.8))
        tail.close()
        tail.lineWidth = 1.15
        strokeColor.setStroke()
        tail.stroke()

        let barXPositions: [CGFloat] = [7.4, 10.0, 12.6]
        for (index, normalizedHeight) in state.barHeights.enumerated() {
            let height = max(3.1, normalizedHeight * 6.2)
            let barRect = NSRect(
                x: barXPositions[index],
                y: 8.6 - (height / 2),
                width: 1.7,
                height: height
            )
            let bar = NSBezierPath(roundedRect: barRect, xRadius: 0.85, yRadius: 0.85)
            barColor.setFill()
            bar.fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

// MARK: - Color helpers

extension NSColor {
    static func blend(from start: NSColor, to end: NSColor, amount: CGFloat) -> NSColor {
        let t = max(0, min(1, amount))
        let startRGB = start.usingColorSpace(.sRGB) ?? start
        let endRGB = end.usingColorSpace(.sRGB) ?? end

        return NSColor(
            srgbRed: startRGB.redComponent + ((endRGB.redComponent - startRGB.redComponent) * t),
            green: startRGB.greenComponent + ((endRGB.greenComponent - startRGB.greenComponent) * t),
            blue: startRGB.blueComponent + ((endRGB.blueComponent - startRGB.blueComponent) * t),
            alpha: startRGB.alphaComponent + ((endRGB.alphaComponent - startRGB.alphaComponent) * t)
        )
    }
}
