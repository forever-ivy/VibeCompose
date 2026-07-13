import AppKit
import Combine
import SwiftUI

struct AccessibilityDisplayOptions: Sendable, Equatable {
    let reduceMotion: Bool
    let increaseContrast: Bool

    @MainActor
    static var system: AccessibilityDisplayOptions {
        AccessibilityDisplayOptions(
            reduceMotion:
                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            increaseContrast:
                NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
    }
}

struct AccessibilityDisplayOptionsOverride: Sendable, Equatable {
    let reduceMotion: Bool?
    let increaseContrast: Bool?

    static let none = AccessibilityDisplayOptionsOverride(
        reduceMotion: nil,
        increaseContrast: nil
    )

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
            increaseContrast: increaseContrast ?? base.increaseContrast
        )
    }

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
