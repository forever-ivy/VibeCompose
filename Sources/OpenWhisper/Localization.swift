import Foundation

enum L10n {
    static let supportedLocalizations = ["en", "zh-Hans"]

    static let selectedLocalization: String = {
        Bundle.preferredLocalizations(
            from: supportedLocalizations,
            forPreferences: Locale.preferredLanguages
        ).first ?? "en"
    }()

    private static let lookupBundle: Bundle = {
        guard selectedLocalization == "zh-Hans",
              let path = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }

        return bundle
    }()

    static func text(_ key: String) -> String {
        lookupBundle.localizedString(
            forKey: key,
            value: key,
            table: nil
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: Locale.current,
            arguments: arguments
        )
    }
}
