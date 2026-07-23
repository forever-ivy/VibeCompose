import Foundation

enum AppLanguage:
    String,
    Codable,
    Sendable,
    Equatable,
    CaseIterable,
    Identifiable
{
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return L10n.text("System Language")
        case .simplifiedChinese:
            return L10n.text("简体中文")
        case .english:
            return L10n.text("English")
        }
    }

    var resolvedLocalization: String {
        switch self {
        case .system:
            return Bundle.preferredLocalizations(
                from: L10n.supportedLocalizations,
                forPreferences: Locale.preferredLanguages
            ).first ?? "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }
}

extension Notification.Name {
    static let openWhisperLanguageDidChange = Notification.Name(
        "VibeWhisper.LanguageDidChange"
    )
    static let openWhisperNavigateSettingsPane = Notification.Name(
        "VibeWhisper.NavigateSettingsPane"
    )
}

private final class LocalizationState:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var language: AppLanguage = .system
    private var localization = AppLanguage.system.resolvedLocalization
    private var bundle: Bundle = .main

    init() {
        bundle = Self.bundle(for: localization)
    }

    func snapshot() -> (AppLanguage, String, Bundle) {
        lock.lock()
        defer { lock.unlock() }
        return (language, localization, bundle)
    }

    @discardableResult
    func set(_ value: AppLanguage) -> Bool {
        let resolved = value.resolvedLocalization
        lock.lock()
        let changed = language != value || localization != resolved
        language = value
        localization = resolved
        bundle = Self.bundle(for: resolved)
        lock.unlock()
        return changed
    }

    private static func bundle(for localization: String) -> Bundle {
        guard localization != "en",
              let path = Bundle.main.path(
                forResource: localization,
                ofType: "lproj"
              ),
              let bundle = Bundle(path: path)
        else {
            return .main
        }
        return bundle
    }
}

enum L10n {
    static let supportedLocalizations = ["en", "zh-Hans"]
    private static let state = LocalizationState()

    static var selectedLanguage: AppLanguage {
        state.snapshot().0
    }

    static var selectedLocalization: String {
        state.snapshot().1
    }

    static func setLanguage(
        _ language: AppLanguage
    ) {
        guard state.set(language) else { return }
        NotificationCenter.default.post(
            name: .openWhisperLanguageDidChange,
            object: language
        )
    }

    static func text(_ key: String) -> String {
        let snapshot = state.snapshot()
        // English source strings are the localization keys. Returning the key
        // directly is required when English is explicitly selected; using the
        // main bundle would still resolve zh-Hans on a Chinese macOS account.
        guard snapshot.1 != "en" else {
            return key
        }
        let bundle = snapshot.2
        return bundle.localizedString(
            forKey: key,
            value: key,
            table: nil
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: Locale(identifier: selectedLocalization),
            arguments: arguments
        )
    }
}
