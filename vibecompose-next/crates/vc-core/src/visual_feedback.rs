//! Visual feedback configuration, ported from Swift `VisualFeedback.swift`.
//!
//! The macOS app offers three dictation feedback surfaces — the Refined HUD
//! status pill, the Blue Signal Frame edge glow, and Hidden — plus placement,
//! intensity, and motion options. The cross-platform shells honor the same
//! modes and the same `visualFeedback` config keys so a macOS `config.json`
//! round-trips, while each shell renders the surface in its own design
//! language (Fluent on Windows, Adwaita on Linux).

use serde::{Deserialize, Serialize};

/// Which on-screen feedback surface accompanies a dictation session.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum VisualFeedbackMode {
    /// A quiet center pill with status, timer, and cancel.
    #[default]
    RefinedHud,
    /// A soft edge glow wrapping the active display while dictation runs.
    /// (Historically named "Blue Signal Frame"; the legacy raw value is
    /// still accepted on decode.)
    AiActivityGlow,
    /// No on-screen feedback. Tray status, sounds, and cancel still work.
    Hidden,
}

impl VisualFeedbackMode {
    pub const ALL: [VisualFeedbackMode; 3] =
        [Self::RefinedHud, Self::AiActivityGlow, Self::Hidden];

    /// Swift decode rule: the legacy `blueSignalFrame` raw value maps to
    /// `aiActivityGlow`; anything unknown falls back to `refinedHUD`.
    pub fn parse(raw: &str) -> Self {
        match raw {
            "aiActivityGlow" | "blueSignalFrame" => Self::AiActivityGlow,
            "hidden" => Self::Hidden,
            _ => Self::RefinedHud,
        }
    }

    /// The Swift raw value written to `config.json`.
    pub fn code(&self) -> &'static str {
        match self {
            Self::RefinedHud => "refinedHUD",
            Self::AiActivityGlow => "aiActivityGlow",
            Self::Hidden => "hidden",
        }
    }
}

impl Serialize for VisualFeedbackMode {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.code())
    }
}

impl<'de> Deserialize<'de> for VisualFeedbackMode {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Ok(Self::parse(&String::deserialize(deserializer)?))
    }
}

/// Vertical edge for the status pill on the active display.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum HudPlacement {
    #[default]
    Top,
    Bottom,
}

impl HudPlacement {
    pub fn parse(raw: &str) -> Self {
        match raw {
            "bottom" => Self::Bottom,
            _ => Self::Top,
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            Self::Top => "top",
            Self::Bottom => "bottom",
        }
    }
}

impl Serialize for HudPlacement {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.code())
    }
}

impl<'de> Deserialize<'de> for HudPlacement {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Ok(Self::parse(&String::deserialize(deserializer)?))
    }
}

/// Animation/emphasis intensity for the feedback surfaces.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum VisualFeedbackIntensity {
    Subtle,
    #[default]
    Standard,
    Expressive,
}

impl VisualFeedbackIntensity {
    pub fn parse(raw: &str) -> Self {
        match raw {
            "subtle" => Self::Subtle,
            "expressive" => Self::Expressive,
            _ => Self::Standard,
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            Self::Subtle => "subtle",
            Self::Standard => "standard",
            Self::Expressive => "expressive",
        }
    }

    /// Waveform / glow amplitude multiplier (matches the Swift values).
    pub fn amplitude_scale(&self) -> f64 {
        match self {
            Self::Subtle => 0.72,
            Self::Standard => 1.0,
            Self::Expressive => 1.22,
        }
    }
}

impl Serialize for VisualFeedbackIntensity {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.code())
    }
}

impl<'de> Deserialize<'de> for VisualFeedbackIntensity {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Ok(Self::parse(&String::deserialize(deserializer)?))
    }
}

/// How long a delivered-result state stays on the feedback surface before
/// auto-hiding, matching macOS `FeedbackSurfaceController.resultDisplayDuration`
/// (0.9s inserted / 1.5s paste-sent / 2s copied).
pub fn result_display_millis(outcome: &crate::delivery::DeliveryOutcome) -> u64 {
    use crate::delivery::DeliveryOutcome;
    match outcome {
        DeliveryOutcome::InsertedAndVerified => 900,
        DeliveryOutcome::PasteDispatchedClipboardRetained => 1500,
        DeliveryOutcome::CopiedToClipboard(_) => 2000,
    }
}

/// Error display window before auto-hide, matching macOS
/// `FeedbackSurfaceController.showError`'s 5-second schedule.
pub const ERROR_DISPLAY_MILLIS: u64 = 5000;

/// The `visualFeedback` section of `config.json`, key-compatible with the
/// Swift `VisualFeedbackConfig`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct VisualFeedbackConfig {
    pub mode: VisualFeedbackMode,
    pub intensity: VisualFeedbackIntensity,
    /// Kept for macOS config-file compatibility. The Windows/Linux glow
    /// always wraps the active display; focused-window framing is a macOS
    /// AX capability.
    pub frame_target: String,
    /// Status pill edge on the active display. Ignored for glow / hidden.
    pub hud_placement: HudPlacement,
    pub show_status_text: bool,
    pub completion_notification_enabled: bool,
    pub always_reduce_motion: bool,
}

impl Default for VisualFeedbackConfig {
    fn default() -> Self {
        Self {
            mode: VisualFeedbackMode::default(),
            intensity: VisualFeedbackIntensity::default(),
            frame_target: "activeDisplay".into(),
            hud_placement: HudPlacement::default(),
            show_status_text: true,
            completion_notification_enabled: false,
            always_reduce_motion: false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_match_the_swift_config() {
        let config = VisualFeedbackConfig::default();
        assert_eq!(config.mode, VisualFeedbackMode::RefinedHud);
        assert_eq!(config.intensity, VisualFeedbackIntensity::Standard);
        assert_eq!(config.hud_placement, HudPlacement::Top);
        assert_eq!(config.frame_target, "activeDisplay");
        assert!(config.show_status_text);
        assert!(!config.completion_notification_enabled);
        assert!(!config.always_reduce_motion);
    }

    #[test]
    fn mode_decodes_the_legacy_blue_signal_frame_alias() {
        assert_eq!(
            VisualFeedbackMode::parse("blueSignalFrame"),
            VisualFeedbackMode::AiActivityGlow
        );
        assert_eq!(
            VisualFeedbackMode::parse("aiActivityGlow"),
            VisualFeedbackMode::AiActivityGlow
        );
        assert_eq!(VisualFeedbackMode::parse("hidden"), VisualFeedbackMode::Hidden);
        // Unknown values fall back to the HUD, matching Swift.
        assert_eq!(
            VisualFeedbackMode::parse("something-new"),
            VisualFeedbackMode::RefinedHud
        );
    }

    #[test]
    fn serialization_uses_swift_raw_values() {
        let config = VisualFeedbackConfig {
            mode: VisualFeedbackMode::AiActivityGlow,
            intensity: VisualFeedbackIntensity::Expressive,
            hud_placement: HudPlacement::Bottom,
            ..Default::default()
        };
        let json = serde_json::to_value(&config).unwrap();
        assert_eq!(json["mode"], "aiActivityGlow");
        assert_eq!(json["intensity"], "expressive");
        assert_eq!(json["hudPlacement"], "bottom");
        assert_eq!(json["frameTarget"], "activeDisplay");

        let round: VisualFeedbackConfig = serde_json::from_value(json).unwrap();
        assert_eq!(round, config);
    }

    #[test]
    fn a_macos_visual_feedback_section_decodes() {
        let raw = r#"{
            "mode": "blueSignalFrame",
            "intensity": "subtle",
            "frameTarget": "focusedWindow",
            "hudPlacement": "bottom",
            "showStatusText": false,
            "completionNotificationEnabled": true,
            "alwaysReduceMotion": true
        }"#;
        let config: VisualFeedbackConfig = serde_json::from_str(raw).unwrap();
        assert_eq!(config.mode, VisualFeedbackMode::AiActivityGlow);
        assert_eq!(config.intensity, VisualFeedbackIntensity::Subtle);
        assert_eq!(config.frame_target, "focusedWindow");
        assert_eq!(config.hud_placement, HudPlacement::Bottom);
        assert!(!config.show_status_text);
        assert!(config.completion_notification_enabled);
        assert!(config.always_reduce_motion);
    }

    #[test]
    fn missing_section_fields_use_defaults() {
        let config: VisualFeedbackConfig = serde_json::from_str("{}").unwrap();
        assert_eq!(config, VisualFeedbackConfig::default());
    }

    #[test]
    fn intensity_scales_match_swift() {
        assert_eq!(VisualFeedbackIntensity::Subtle.amplitude_scale(), 0.72);
        assert_eq!(VisualFeedbackIntensity::Standard.amplitude_scale(), 1.0);
        assert_eq!(VisualFeedbackIntensity::Expressive.amplitude_scale(), 1.22);
    }

    #[test]
    fn terminal_display_durations_match_the_macos_feedback_controller() {
        use crate::delivery::{ClipboardFallbackReason, DeliveryOutcome};
        assert_eq!(
            result_display_millis(&DeliveryOutcome::InsertedAndVerified),
            900
        );
        assert_eq!(
            result_display_millis(&DeliveryOutcome::PasteDispatchedClipboardRetained),
            1500
        );
        assert_eq!(
            result_display_millis(&DeliveryOutcome::CopiedToClipboard(
                ClipboardFallbackReason::NoEditableTarget
            )),
            2000
        );
        assert_eq!(ERROR_DISPLAY_MILLIS, 5000);
    }
}
