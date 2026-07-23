import AppKit
import SwiftUI

/// Brief in-window toast (Sonner-style): top-center capsule over Settings content.
enum SonnerToastKind: Equatable, Sendable {
    case success
    case error
    case info
    case loading
}

struct SonnerToastItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let detail: String?
    let kind: SonnerToastKind

    init(
        id: UUID = UUID(),
        title: String,
        detail: String? = nil,
        kind: SonnerToastKind
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
    }
}

@MainActor
final class SonnerToastCenter: ObservableObject {
    @Published private(set) var current: SonnerToastItem?

    private var dismissTask: Task<Void, Never>?
    private let defaultDuration: Duration = .milliseconds(2_400)

    func show(
        _ title: String,
        detail: String? = nil,
        kind: SonnerToastKind = .info,
        duration: Duration? = nil
    ) {
        let item = SonnerToastItem(
            title: title,
            detail: detail,
            kind: kind
        )
        present(item, duration: duration)
    }

    func success(_ title: String, detail: String? = nil) {
        show(title, detail: detail, kind: .success)
    }

    func error(_ title: String, detail: String? = nil) {
        show(title, detail: detail, kind: .error, duration: .milliseconds(3_200))
    }

    func info(_ title: String, detail: String? = nil) {
        show(title, detail: detail, kind: .info)
    }

    func loading(_ title: String, detail: String? = nil) {
        show(title, detail: detail, kind: .loading, duration: nil)
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.easeOut(duration: 0.16)) {
            current = nil
        }
    }

    private func present(
        _ item: SonnerToastItem,
        duration: Duration?
    ) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            current = item
        }

        guard item.kind != .loading else {
            dismissTask = nil
            return
        }

        let wait = duration ?? defaultDuration
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            guard current?.id == item.id else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                if current?.id == item.id {
                    current = nil
                }
            }
        }
    }
}

struct SonnerToastHost: View {
    @ObservedObject var center: SonnerToastCenter
    var reduceMotion: Bool = false

    var body: some View {
        VStack {
            if let item = center.current {
                SonnerToastBanner(item: item)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .padding(.top, VibeWhisperMetrics.space12)
                    .zIndex(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .animation(
            reduceMotion
                ? .linear(duration: 0)
                : .spring(response: 0.32, dampingFraction: 0.86),
            value: center.current?.id
        )
    }
}

private struct SonnerToastBanner: View {
    let item: SonnerToastItem

    var body: some View {
        HStack(alignment: .center, spacing: VibeWhisperMetrics.space10) {
            leadingGlyph
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(VibeWhisperTypography.callout(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(VibeWhisperTypography.caption())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VibeWhisperMetrics.space16)
        .padding(.vertical, VibeWhisperMetrics.space12)
        .frame(maxWidth: 420, alignment: .leading)
        .background {
            toastBackground
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: VibeWhisperMetrics.radiusL,
                style: .continuous
            )
            .stroke(
                Color(nsColor: VibeWhisperPalette.hairline).opacity(0.55),
                lineWidth: 0.5
            )
        }
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        switch item.kind {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(nsColor: VibeWhisperPalette.success))
                .symbolRenderingMode(.hierarchical)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(nsColor: VibeWhisperPalette.error))
                .symbolRenderingMode(.hierarchical)
        case .info:
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(nsColor: VibeWhisperPalette.brandBlue))
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var toastBackground: some View {
        RoundedRectangle(
            cornerRadius: VibeWhisperMetrics.radiusL,
            style: .continuous
        )
        .fill(Color(nsColor: VibeWhisperPalette.elevatedSurface))
    }

    private var accessibilityLabel: String {
        if let detail = item.detail, !detail.isEmpty {
            return "\(item.title). \(detail)"
        }
        return item.title
    }
}

