import Foundation

enum TextDeliveryKind: Sendable, Equatable {
    case insertedAndVerified
    case pasteDispatched
    case clipboard
    case error
    case unknown
}

enum TextDeliveryStatus {
    static let insertedAndVerified = "inserted_verified"
    static let pasteDispatched = "paste_dispatched"
    static let clipboard = "clipboard"
    static let error = "error"

    // Builds created before paste verification used `pasted` after merely
    // dispatching Cmd+V. Preserve that distinction when reading old records.
    static let legacyPasteDispatched = "pasted"

    static let diagnosticsAllowedValues: Set<String> = [
        insertedAndVerified,
        pasteDispatched,
        clipboard,
        error,
        legacyPasteDispatched,
    ]

    static func kind(for rawValue: String) -> TextDeliveryKind {
        switch rawValue {
        case insertedAndVerified:
            return .insertedAndVerified
        case pasteDispatched, legacyPasteDispatched:
            return .pasteDispatched
        case clipboard:
            return .clipboard
        case error:
            return .error
        default:
            return .unknown
        }
    }

    static func localizedLabel(for rawValue: String) -> String {
        switch kind(for: rawValue) {
        case .insertedAndVerified:
            return L10n.text("Inserted")
        case .pasteDispatched:
            return rawValue == legacyPasteDispatched
                ? L10n.text("Paste sent (legacy)")
                : L10n.text("Paste sent")
        case .clipboard:
            return L10n.text("Copied")
        case .error:
            return L10n.text("Error")
        case .unknown:
            return rawValue
        }
    }
}
