import Foundation

enum VisualFeedbackMode:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Sendable
{
    case refinedHUD
    case blueSignalFrame
    case hidden

    var id: String {
        rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .refinedHUD
    }

    static func fromLaunchValue(
        _ value: String
    ) -> VisualFeedbackMode? {
        switch value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
            .replacingOccurrences(
                of: "_",
                with: "-"
            )
        {
        case "refinedhud",
             "refined-hud",
             "hud":
            return .refinedHUD
        case "bluesignalframe",
             "blue-signal-frame",
             "blue-frame":
            return .blueSignalFrame
        case "hidden",
             "none":
            return .hidden
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .refinedHUD:
            return L10n.text("Refined HUD")
        case .blueSignalFrame:
            return L10n.text("Blue Signal Frame")
        case .hidden:
            return L10n.text("Hidden")
        }
    }

    var detail: String {
        switch self {
        case .refinedHUD:
            return L10n.text(
                "A compact top-center status surface with text, timer, cancel, and Retry controls."
            )
        case .blueSignalFrame:
            return L10n.text(
                "A quiet cold-blue signal around the active display, with compact text only when an action or error needs explanation."
            )
        case .hidden:
            return L10n.text(
                "No visible HUD. Sounds, menu status, notifications, Esc cancellation, and menu Retry remain available."
            )
        }
    }
}

enum VisualFeedbackIntensity:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Sendable
{
    case subtle
    case standard
    case expressive

    var id: String {
        rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .standard
    }

    var title: String {
        switch self {
        case .subtle:
            return L10n.text("Subtle")
        case .standard:
            return L10n.text("Standard")
        case .expressive:
            return L10n.text("Expressive")
        }
    }

    var amplitudeScale: Double {
        switch self {
        case .subtle:
            return 0.72
        case .standard:
            return 1
        case .expressive:
            return 1.22
        }
    }
}

enum BlueSignalFrameTarget:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Sendable
{
    case activeDisplay
    case focusedWindow

    var id: String {
        rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .activeDisplay
    }

    var title: String {
        switch self {
        case .activeDisplay:
            return L10n.text("Active display")
        case .focusedWindow:
            return L10n.text(
                "Focused window (Experimental)"
            )
        }
    }
}

struct VisualFeedbackConfig:
    Codable,
    Sendable,
    Equatable
{
    var mode: VisualFeedbackMode = .refinedHUD
    var intensity: VisualFeedbackIntensity = .standard
    var frameTarget: BlueSignalFrameTarget =
        .activeDisplay
    var showStatusText = true
    var completionNotificationEnabled = false
    var alwaysReduceMotion = false

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        mode = try container.decodeIfPresent(
            VisualFeedbackMode.self,
            forKey: .mode
        ) ?? .refinedHUD
        intensity = try container.decodeIfPresent(
            VisualFeedbackIntensity.self,
            forKey: .intensity
        ) ?? .standard
        frameTarget = try container.decodeIfPresent(
            BlueSignalFrameTarget.self,
            forKey: .frameTarget
        ) ?? .activeDisplay
        showStatusText = try container.decodeIfPresent(
            Bool.self,
            forKey: .showStatusText
        ) ?? true
        completionNotificationEnabled =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .completionNotificationEnabled
            ) ?? false
        alwaysReduceMotion = try container.decodeIfPresent(
            Bool.self,
            forKey: .alwaysReduceMotion
        ) ?? false
    }
}

enum VisualFeedbackPreview:
    String,
    CaseIterable,
    Identifiable,
    Sendable
{
    case recording
    case processing
    case copied
    case error

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recording:
            return L10n.text("Recording")
        case .processing:
            return L10n.text("Processing")
        case .copied:
            return L10n.text("Copied")
        case .error:
            return L10n.text("Error")
        }
    }
}
