import SwiftUI


/// Shared trailing-control geometry for the General settings form so every
/// row’s control cluster shares the same right edge (System Settings style).
enum GeneralSettingsChrome {
    static let controlClusterWidth: CGFloat = 220
    static let recorderWidth: CGFloat = 120
    static let controlHeight: CGFloat = 28
}

/// System Settings–style row: leading title (+ optional caption), trailing control.
/// Controls stay trailing and never stack under the title until the pane is
/// genuinely too narrow for a single line.
struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    let control: () -> Control

    init(
        title: String,
        detail: String? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: VibeWhisperMetrics.space16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VibeWhisperTypography.body(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(VibeWhisperTypography.caption())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            control()
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, VibeWhisperMetrics.space8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(detail ?? "")
    }
}

struct InlineStatus: View {
    enum Kind {
        case neutral
        case success
        case warning
        case error
    }

    let text: String
    var kind: Kind = .neutral

    var body: some View {
        Label(text, systemImage: icon)
            .font(VibeWhisperTypography.caption(.medium))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .labelStyle(.titleAndIcon)
    }

    private var icon: String {
        switch kind {
        case .neutral: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .neutral: .secondary
        case .success: Color(nsColor: VibeWhisperPalette.success)
        case .warning: Color(nsColor: VibeWhisperPalette.amber)
        case .error: Color(nsColor: VibeWhisperPalette.error)
        }
    }
}

struct SettingsCardContainer<Content: View, HeaderAccessory: View>: View {
    enum Style {
        /// Default grouped-form card: title + rows with dividers.
        case grouped
        /// App Store editorial card: no title chrome, content is the focus.
        case hero
    }

    let title: String?
    let style: Style
    let headerAccessory: HeaderAccessory
    let content: Content

    init(
        title: String? = nil,
        style: Style = .grouped,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.style = style
        self.headerAccessory = headerAccessory()
        self.content = content()
    }

    var body: some View {
        switch style {
        case .grouped:
            groupedBody
        case .hero:
            heroBody
        }
    }

    private var groupedBody: some View {
        VStack(alignment: .leading, spacing: VibeWhisperMetrics.space10) {
            if title != nil || !(headerAccessory is EmptyView) {
                HStack(alignment: .center, spacing: VibeWhisperMetrics.space12) {
                    if let title {
                        Text(L10n.text(title))
                            .textCase(.uppercase)
                            .font(VibeWhisperTypography.micro(.semibold))
                            .foregroundStyle(.tertiary)
                            .tracking(0.55)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }
                    headerAccessory
                }
                .padding(.horizontal, VibeWhisperMetrics.space4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .font(VibeWhisperTypography.callout())
        }
        .openWhisperCard(
            padding: VibeWhisperMetrics.space16,
            cornerRadius: VibeWhisperMetrics.radiusXL,
            elevated: false
        )
    }

    private var heroBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .font(VibeWhisperTypography.callout())
        .openWhisperCard(
            padding: VibeWhisperMetrics.space20,
            cornerRadius: VibeWhisperMetrics.radiusXL,
            elevated: true
        )
    }
}

extension SettingsCardContainer where HeaderAccessory == EmptyView {
    init(
        title: String? = nil,
        style: Style = .grouped,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            style: style,
            headerAccessory: { EmptyView() },
            content: content
        )
    }
}
