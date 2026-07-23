import SwiftUI

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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: OpenWhisperMetrics.space18) {
                labels
                Spacer(minLength: OpenWhisperMetrics.space20)
                control()
            }
            VStack(alignment: .leading, spacing: OpenWhisperMetrics.space10) {
                labels
                control()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var labels: some View {
        Text(title)
            .font(OpenWhisperTypography.body(.medium))
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
            .font(OpenWhisperTypography.caption(.medium))
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
        case .success: Color(nsColor: OpenWhisperPalette.success)
        case .warning: Color(nsColor: OpenWhisperPalette.amber)
        case .error: Color(nsColor: OpenWhisperPalette.error)
        }
    }
}

struct SettingsCardContainer<Content: View>: View {
    enum Style {
        /// Default grouped-form card: title + rows with dividers.
        case grouped
        /// App Store editorial card: no title chrome, content is the focus.
        case hero
    }

    let title: String?
    let style: Style
    let content: Content

    init(
        title: String? = nil,
        style: Style = .grouped,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.style = style
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
        VStack(alignment: .leading, spacing: OpenWhisperMetrics.space8) {
            if let title {
                Text(L10n.text(title))
                    .textCase(.uppercase)
                    .font(OpenWhisperTypography.micro(.semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.4)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .font(OpenWhisperTypography.callout())
        }
        .openWhisperCard(
            padding: OpenWhisperMetrics.space16,
            cornerRadius: OpenWhisperMetrics.radiusL,
            elevated: false
        )
    }

    private var heroBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
            .font(OpenWhisperTypography.callout())
            .openWhisperCard(
                padding: OpenWhisperMetrics.space20,
                cornerRadius: OpenWhisperMetrics.radiusXL,
                elevated: true
            )
    }
}
