import AppKit
import Combine
import SwiftUI

struct AccessibilityDisplayOptions: Sendable, Equatable {
    let reduceMotion: Bool
    let increaseContrast: Bool
    let reduceTransparency: Bool
    let differentiateWithoutColor: Bool

    init(
        reduceMotion: Bool,
        increaseContrast: Bool,
        reduceTransparency: Bool = false,
        differentiateWithoutColor: Bool = false
    ) {
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
        self.differentiateWithoutColor = differentiateWithoutColor
    }

    @MainActor
    static var system: AccessibilityDisplayOptions {
        AccessibilityDisplayOptions(
            reduceMotion:
                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            increaseContrast:
                NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            reduceTransparency:
                NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            differentiateWithoutColor:
                NSWorkspace.shared
                    .accessibilityDisplayShouldDifferentiateWithoutColor
        )
    }

    /// System options with visual-acceptance launch overrides applied.
    @MainActor
    static var current: AccessibilityDisplayOptions {
        AccessibilityDisplayOptionsOverride.currentVisualAcceptance
            .applying(to: .system)
    }
}

struct AccessibilityDisplayOptionsOverride: Sendable, Equatable {
    let reduceMotion: Bool?
    let increaseContrast: Bool?
    let reduceTransparency: Bool?
    let differentiateWithoutColor: Bool?

    init(
        reduceMotion: Bool? = nil,
        increaseContrast: Bool? = nil,
        reduceTransparency: Bool? = nil,
        differentiateWithoutColor: Bool? = nil
    ) {
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
        self.differentiateWithoutColor = differentiateWithoutColor
    }

    static let none = AccessibilityDisplayOptionsOverride()

    @MainActor
    static var currentVisualAcceptance:
        AccessibilityDisplayOptionsOverride
    {
        AppLaunchMode.visualAcceptanceDisplayOptionsOverride(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    func applying(
        to base: AccessibilityDisplayOptions
    ) -> AccessibilityDisplayOptions {
        AccessibilityDisplayOptions(
            reduceMotion: reduceMotion ?? base.reduceMotion,
            increaseContrast: increaseContrast ?? base.increaseContrast,
            reduceTransparency: reduceTransparency ?? base.reduceTransparency,
            differentiateWithoutColor: differentiateWithoutColor
                ?? base.differentiateWithoutColor
        )
    }

    /// Resolved options for the current process (system + acceptance overrides).
    /// Kept on the override type for call-site compatibility with Overlay /
    /// FeedbackSurface providers.
    @MainActor
    static var current: AccessibilityDisplayOptions {
        currentVisualAcceptance.applying(to: .system)
    }

    @MainActor
    func applyAppearance(to window: NSWindow) {
        guard let increaseContrast else {
            return
        }
        let isDark =
            NSApp.effectiveAppearance.bestMatch(
                from: [.darkAqua, .aqua]
            ) == .darkAqua
        let appearanceName: NSAppearance.Name
        switch (isDark, increaseContrast) {
        case (true, true):
            appearanceName = .accessibilityHighContrastDarkAqua
        case (true, false):
            appearanceName = .darkAqua
        case (false, true):
            appearanceName = .accessibilityHighContrastAqua
        case (false, false):
            appearanceName = .aqua
        }
        window.appearance = NSAppearance(named: appearanceName)
    }
}

@MainActor
private final class AccessibilityDisplayOptionsModel:
    ObservableObject
{
    @Published private(set) var options: AccessibilityDisplayOptions

    private let optionsOverride: AccessibilityDisplayOptionsOverride

    init(optionsOverride: AccessibilityDisplayOptionsOverride) {
        self.optionsOverride = optionsOverride
        options = optionsOverride.applying(to: .system)
    }

    func refresh() {
        options = optionsOverride.applying(to: .system)
    }
}

private struct AccessibilityDisplayOptionsOverrideModifier: ViewModifier {
    @StateObject private var model: AccessibilityDisplayOptionsModel

    @MainActor
    init(options: AccessibilityDisplayOptionsOverride) {
        _model = StateObject(
            wrappedValue: AccessibilityDisplayOptionsModel(
                optionsOverride: options
            )
        )
    }

    func body(content: Content) -> some View {
        Group {
            if model.options.increaseContrast {
                content
                    .fontWeight(.medium)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                Color.primary.opacity(0.34),
                                lineWidth: 2
                            )
                            .padding(1)
                            .allowsHitTesting(false)
                    }
            } else {
                content
            }
        }
        .transaction { transaction in
            if model.options.reduceMotion {
                transaction.animation = nil
            }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for:
                    NSWorkspace
                        .accessibilityDisplayOptionsDidChangeNotification
            )
        ) { _ in
            Task { @MainActor in
                model.refresh()
            }
        }
    }
}

extension View {
    @MainActor
    func applyingAccessibilityDisplayOptionsOverride(
        _ options: AccessibilityDisplayOptionsOverride
    ) -> some View {
        modifier(
            AccessibilityDisplayOptionsOverrideModifier(options: options)
        )
    }
}
