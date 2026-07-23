import Foundation

enum VisualFeedbackMode:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Sendable
{
    case refinedHUD
    case aiActivityGlow
    case hidden

    var id: String {
        rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "blueSignalFrame", "aiActivityGlow":
            self = .aiActivityGlow
        default:
            self = Self(rawValue: rawValue) ?? .refinedHUD
        }
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
             "blue-frame",
             "aiactivityglow",
             "ai-activity-glow",
             "activity-glow",
             "agent-activity-indicator":
            return .aiActivityGlow
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
            return L10n.text("Status Bar")
        case .aiActivityGlow:
            return L10n.text("Edge Glow")
        case .hidden:
            return L10n.text("Off")
        }
    }

    var detail: String {
        switch self {
        case .refinedHUD:
            return L10n.text(
                "A quiet center pill with status, timer, cancel, and Retry. Choose top or bottom in Settings."
            )
        case .aiActivityGlow:
            return L10n.text(
                "A soft edge glow on the active display or focused window while VibeWhisper works."
            )
        case .hidden:
            return L10n.text(
                "No on-screen feedback. Menu status, sounds, Esc cancel, and Retry still work."
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
            return L10n.text("Focused window")
        }
    }

    var detail: String {
        switch self {
        case .activeDisplay:
            return L10n.text(
                "Wraps the edge of the display under the pointer."
            )
        case .focusedWindow:
            return L10n.text(
                "Wraps the frontmost app window. Needs Accessibility access; falls back to the active display if the window cannot be read."
            )
        }
    }
}

/// Vertical edge for the Status Bar pill on the active display.
enum HUDPlacement:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Sendable
{
    case top
    case bottom

    var id: String { rawValue }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .top
    }

    var title: String {
        switch self {
        case .top:
            return L10n.text("Top of screen")
        case .bottom:
            return L10n.text("Bottom of screen")
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
    /// Status Bar edge on the active display. Ignored for Edge Glow / Off.
    var hudPlacement: HUDPlacement = .top
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
        hudPlacement = try container.decodeIfPresent(
            HUDPlacement.self,
            forKey: .hudPlacement
        ) ?? .top
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
