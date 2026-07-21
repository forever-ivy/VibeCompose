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

enum OpenWhisperPalette {
    /// Semantic foregrounds let the system resolve legibility for the current
    /// appearance and accessibility settings above the native AppKit material.
    static let hudText = NSColor.labelColor
    static let hudTextMuted = NSColor.secondaryLabelColor
    /// State accents live in the glyphs and badges. The material shell stays
    /// neutral so the HUD remains calm and legible in every appearance.
    static let hudProcessingAccent = NSColor(
        srgbRed: 0.44,
        green: 0.52,
        blue: 1,
        alpha: 1
    )
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
    /// Light appearance selection fill sampled from the same artwork.
    /// #EFEFEF / RGB 239, 239, 239.
    static let sidebarSelectionLightColor = NSColor(
        srgbRed: 239.0 / 255.0,
        green: 239.0 / 255.0,
        blue: 239.0 / 255.0,
        alpha: 1
    )
    static let sidebarSelectionBackground = NSColor(
        name: "OpenWhisperSidebarSelectionBackground"
    ) { appearance in
        if appearance.bestMatch(
            from: [.darkAqua, .aqua]
        ) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.12)
        }
        return sidebarSelectionLightColor
    }
    /// Foreground (icon + label) of a selected source-list row.
    static let sidebarSelectionForeground = NSColor(
        name: "OpenWhisperSidebarSelectionForeground"
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
    static let signalBlue = brandBlue
    static let success = NSColor(srgbRed: 0.32, green: 0.80, blue: 0.58, alpha: 1)
    static let amber = NSColor(srgbRed: 1, green: 0.72, blue: 0.28, alpha: 1)
    static let error = NSColor(srgbRed: 1, green: 0.42, blue: 0.44, alpha: 1)

    /// Semantic system colors keep content surfaces adaptive without trying to
    /// imitate the optical behavior of Liquid Glass.
    static let hairline = NSColor.separatorColor
    static let elevatedSurface = NSColor.controlBackgroundColor
    static let insetSurface = NSColor.textBackgroundColor
}

// MARK: - Design tokens

enum OpenWhisperMetrics {
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

    static let radiusXS: CGFloat = 6
    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 9
    static let radiusL: CGFloat = 12
    static let radiusXL: CGFloat = 14
    static let radiusXXL: CGFloat = 20
    static let radiusPill: CGFloat = 999

    static let controlHeight: CGFloat = 28
    static let iconWellSize: CGFloat = 32
    static let iconWellSizeLarge: CGFloat = 40
    static let iconWellSizeXL: CGFloat = 48
    static let windowChromePadding: CGFloat = 20
    static let contentMaxWidth: CGFloat = 720
}

// MARK: - Motion tokens

enum OpenWhisperMotion {
    // MARK: Durations (AppKit / TimeInterval)
    static let hudAppear: TimeInterval = 0.18
    static let hudDismiss: TimeInterval = 0.20
    static let hudSizeMorph: TimeInterval = 0.22
    static let pageTransition: Double = 0.18
    static let quickFade: Double = 0.12
    static let panelAppear: TimeInterval = 0.22

    // MARK: Springs (SwiftUI Animation)
    /// Standard spring — settings sidebar navigation, content pane transitions
    static var standardSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.86)
    }
    /// Snappy spring — settings sidebar selection (navigation, not content swap)
    static var snappySpring: Animation {
        .spring(response: 0.24, dampingFraction: 0.86)
    }
    /// Press spring — button active-state scale feedback
    static var pressSpring: Animation {
        .spring(response: 0.20, dampingFraction: 0.85)
    }
    /// Panel spring — floating panel / skill switcher entrance scale
    static var panelSpring: Animation {
        .spring(response: 0.28, dampingFraction: 0.88)
    }
    /// Step spring — onboarding step content transition
    static var stepSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.86)
    }
    /// Indicator spring — onboarding step circle color/icon morph
    static var indicatorSpring: Animation {
        .spring(response: 0.30, dampingFraction: 0.80)
    }
}

enum OpenWhisperTypography {
    static func display(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 28, weight: weight, design: .default)
    }

    static func title(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 19, weight: weight, design: .default)
    }

    static func title2(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 15, weight: weight, design: .default)
    }

    static func headline(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 13, weight: weight, design: .default)
    }

    static func body(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 13, weight: weight, design: .default)
    }

    static func callout(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 12, weight: weight, design: .default)
    }

    static func caption(_ weight: Font.Weight = .regular) -> Font {
        .system(size: 11, weight: weight, design: .default)
    }

    static func micro(_ weight: Font.Weight = .medium) -> Font {
        .system(size: 10, weight: weight, design: .default)
    }

    /// App Store editorial eyebrow: tracked-out 11pt semibold labels
    /// ("OUR FAVOURITES", "EDITORS' CHOICE") used above hero content.
    static func eyebrow(_ weight: Font.Weight = .semibold) -> Font {
        .system(size: 11, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Brand tint

extension View {
    func applyingOpenWhisperBrandTint() -> some View {
        tint(
            Color(nsColor: OpenWhisperPalette.brandBlue)
        )
    }
}

// MARK: - Surface modifiers

struct OpenWhisperCardChrome: ViewModifier {
    var padding: CGFloat = OpenWhisperMetrics.space16
    var cornerRadius: CGFloat = OpenWhisperMetrics.radiusL
    var elevated = true

    // Content cards remain solid. Liquid Glass belongs to navigation chrome and
    // floating controls, not grouped form content.
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: OpenWhisperPalette.elevatedSurface),
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
    }
}

struct OpenWhisperInsetChrome: ViewModifier {
    var padding: CGFloat = OpenWhisperMetrics.space12
    var cornerRadius: CGFloat = OpenWhisperMetrics.radiusM

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Color(nsColor: OpenWhisperPalette.insetSurface),
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
                    Color(nsColor: OpenWhisperPalette.hairline).opacity(0.7),
                    lineWidth: 0.5
                )
            }
    }
}

struct OpenWhisperSearchFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, OpenWhisperMetrics.space12)
            .padding(.vertical, OpenWhisperMetrics.space6)
            .frame(minHeight: 30)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(
                    cornerRadius: OpenWhisperMetrics.radiusL,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: OpenWhisperMetrics.radiusL,
                    style: .continuous
                )
                .stroke(
                    Color(nsColor: .separatorColor),
                    lineWidth: 0.5
                )
            }
    }
}

struct OpenWhisperToolbarChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, OpenWhisperMetrics.space20)
            .padding(.vertical, OpenWhisperMetrics.space12)
            .background(.bar)
    }
}

extension View {
    func openWhisperCard(
        padding: CGFloat = OpenWhisperMetrics.space16,
        cornerRadius: CGFloat = OpenWhisperMetrics.radiusL,
        elevated: Bool = true
    ) -> some View {
        modifier(
            OpenWhisperCardChrome(
                padding: padding,
                cornerRadius: cornerRadius,
                elevated: elevated
            )
        )
    }

    func openWhisperInset(
        padding: CGFloat = OpenWhisperMetrics.space12,
        cornerRadius: CGFloat = OpenWhisperMetrics.radiusM
    ) -> some View {
        modifier(
            OpenWhisperInsetChrome(
                padding: padding,
                cornerRadius: cornerRadius
            )
        )
    }

    func openWhisperSearchField() -> some View {
        modifier(OpenWhisperSearchFieldChrome())
    }

    func openWhisperToolbar() -> some View {
        modifier(OpenWhisperToolbarChrome())
    }
}

/// In-content pane header used when a destination is embedded inside the
/// Settings shell: a large title on the leading edge with the pane's controls
/// trailing, matching how Apple's apps compose headers inside a detail column
/// instead of relying on window toolbar chrome.
struct OpenWhisperPaneHeader<Controls: View>: View {
    let title: String
    @ViewBuilder let controls: Controls

    var body: some View {
        HStack(alignment: .center, spacing: OpenWhisperMetrics.space16) {
            Text(title)
                .font(OpenWhisperTypography.display())
                .tracking(-0.25)
                .lineLimit(1)
            Spacer(minLength: OpenWhisperMetrics.space12)
            controls
        }
        .padding(.horizontal, OpenWhisperMetrics.space20)
        .padding(.top, OpenWhisperMetrics.space12)
        .padding(.bottom, OpenWhisperMetrics.space10)
    }
}

// MARK: - Shared chrome components

struct OpenWhisperIconWell: View {
    let systemName: String
    var size: CGFloat = OpenWhisperMetrics.iconWellSize
    var symbolSize: CGFloat = 15
    var tint: Color = Color(nsColor: OpenWhisperPalette.brandBlue)
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

struct OpenWhisperStatusChip: View {
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
        Text(text)
            .font(OpenWhisperTypography.micro(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                background,
                in: Capsule(style: .continuous)
            )
    }

    private var foreground: Color {
        switch kind {
        case .neutral:
            return .secondary
        case .success:
            return Color(nsColor: OpenWhisperPalette.success)
        case .warning:
            return Color(nsColor: OpenWhisperPalette.amber)
        case .error:
            return Color(nsColor: OpenWhisperPalette.error)
        case .accent:
            return Color(nsColor: OpenWhisperPalette.brandBlue)
        }
    }

    private var background: Color {
        foreground.opacity(0.10)
    }
}

struct OpenWhisperSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(OpenWhisperTypography.caption(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct OpenWhisperWindowHeader<Trailing: View>: View {
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
        HStack(alignment: .center, spacing: OpenWhisperMetrics.space14) {
            if let systemImage {
                OpenWhisperIconWell(
                    systemName: systemImage,
                    size: OpenWhisperMetrics.iconWellSizeLarge,
                    symbolSize: 18
                )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(OpenWhisperTypography.title())
                    .tracking(-0.18)
                    .accessibilityHint(subtitle ?? "")
            }
            Spacer(minLength: OpenWhisperMetrics.space12)
            trailing
        }
        .padding(.horizontal, OpenWhisperMetrics.space20)
        .padding(.vertical, OpenWhisperMetrics.space14)
    }
}

extension OpenWhisperWindowHeader where Trailing == EmptyView {
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

struct OpenWhisperEmptyState: View {
    let systemImage: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: OpenWhisperMetrics.space10) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(OpenWhisperTypography.title2())
                .accessibilityHint(detail ?? "")
        }
        .padding(OpenWhisperMetrics.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Button styles

struct OpenWhisperSecondaryButtonStyle: PrimitiveButtonStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26, *) {
            Button(role: configuration.role) {
                configuration.trigger()
            } label: {
                configuration.label
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        } else {
            Button(role: configuration.role) {
                configuration.trigger()
            } label: {
                configuration.label
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

struct OpenWhisperPrimaryButtonStyle: PrimitiveButtonStyle {
    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26, *) {
            Button(role: configuration.role) {
                configuration.trigger()
            } label: {
                configuration.label
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
        } else {
            Button(role: configuration.role) {
                configuration.trigger()
            } label: {
                configuration.label
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

struct OpenWhisperQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(
                Color.primary.opacity(
                    isEnabled
                        ? (configuration.isPressed ? 0.55 : 0.78)
                        : 0.36
                )
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.06 : 0),
                in: RoundedRectangle(
                    cornerRadius: OpenWhisperMetrics.radiusXS,
                    style: .continuous
                )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(OpenWhisperMotion.pressSpring, value: configuration.isPressed)
    }
}

// MARK: - Sidebar symbol

/// App Store-style source-list icon: a direct SF Symbol with no decorative
/// container. The source list owns active/inactive foreground treatment so
/// selected symbols retain the system's correct contrast automatically.
struct OpenWhisperSidebarSymbol: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .frame(width: 22, height: 20)
        .accessibilityHidden(true)
    }
}

// MARK: - Step progress bar

struct OpenWhisperStepProgressBar: View {
    let steps: [String]
    let currentStep: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, _ in
                stepNode(index: index)
                if index < steps.count - 1 {
                    connector(completed: index < currentStep)
                }
            }
        }
        .padding(.horizontal, OpenWhisperMetrics.space24)
        .padding(.vertical, OpenWhisperMetrics.space14)
        .animation(OpenWhisperMotion.indicatorSpring, value: currentStep)
    }

    private func stepNode(index: Int) -> some View {
        let isCompleted = index < currentStep
        let isCurrent = index == currentStep

        return VStack(spacing: OpenWhisperMetrics.space4) {
            ZStack {
                Circle()
                    .fill(
                        isCompleted
                            ? Color(nsColor: OpenWhisperPalette.success)
                            : isCurrent
                                ? Color(nsColor: OpenWhisperPalette.brandBlue)
                                : Color.primary.opacity(0.06)
                    )
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(
                                isCompleted
                                    ? Color(nsColor: OpenWhisperPalette.success)
                                    : isCurrent
                                        ? Color(nsColor: OpenWhisperPalette.brandBlue)
                                        : Color.primary.opacity(0.18),
                                lineWidth: isCurrent || isCompleted ? 0 : 1
                            )
                    )
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: isCurrent ? .bold : .medium))
                        .foregroundStyle(
                            isCurrent ? .white : Color.primary.opacity(0.40)
                        )
                        .transition(.opacity)
                }
            }
            Text(steps[index])
                .font(.system(
                    size: 10,
                    weight: isCurrent ? .semibold : .regular
                ))
                .foregroundStyle(
                    isCurrent
                        ? Color(nsColor: OpenWhisperPalette.brandBlue)
                        : Color.primary.opacity(isCompleted ? 0.65 : 0.38)
                )
        }
    }

    private func connector(completed: Bool) -> some View {
        Rectangle()
            .fill(
                completed
                    ? Color(nsColor: OpenWhisperPalette.success).opacity(0.55)
                    : Color.primary.opacity(0.12)
            )
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .offset(y: -10)
    }
}

// MARK: - Status icon renderer

enum OpenWhisperStatusIconRenderer {
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
