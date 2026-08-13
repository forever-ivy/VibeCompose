//! Delivery outcome model. The three states are intentionally distinct and
//! must never be conflated (trust-boundary rule from the original design):
//!
//! - `InsertedAndVerified`: the same focused target exposed the expected text
//!   transition after paste; original clipboard may be restored.
//! - `PasteDispatchedClipboardRetained`: paste was sent but verification was
//!   unavailable or inconclusive; the transcript stays in the clipboard.
//! - `CopiedToClipboard`: no paste event was sent.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ClipboardFallbackReason {
    AccessibilityPermissionRequired,
    NoEditableTarget,
    RetryRequiresManualPaste,
    TargetChanged,
    PlatformUnsupported,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", tag = "status", content = "reason")]
pub enum DeliveryOutcome {
    /// Verified insertion into the original focused target.
    InsertedAndVerified,
    /// Paste keystroke dispatched; verification unavailable or inconclusive.
    PasteDispatchedClipboardRetained,
    /// Copy-only delivery.
    CopiedToClipboard(ClipboardFallbackReason),
}

impl DeliveryOutcome {
    /// Stable telemetry/history code, aligned with the Swift naming.
    pub fn code(&self) -> &'static str {
        match self {
            Self::InsertedAndVerified => "inserted_verified",
            Self::PasteDispatchedClipboardRetained => "paste_dispatched",
            Self::CopiedToClipboard(_) => "clipboard",
        }
    }

    /// Only a verified insertion permits restoring the previous clipboard,
    /// and only when the pasteboard change count still proves ownership.
    pub fn permits_clipboard_restore(&self) -> bool {
        matches!(self, Self::InsertedAndVerified)
    }
}

/// How the final text is routed after preparation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum OutputRoute {
    AutomaticPasteWhenVerified,
    PreviewThenPaste,
    CopyOnly,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_verified_insertion_restores_clipboard() {
        assert!(DeliveryOutcome::InsertedAndVerified.permits_clipboard_restore());
        assert!(!DeliveryOutcome::PasteDispatchedClipboardRetained.permits_clipboard_restore());
        assert!(!DeliveryOutcome::CopiedToClipboard(ClipboardFallbackReason::NoEditableTarget)
            .permits_clipboard_restore());
    }

    #[test]
    fn codes_are_stable() {
        assert_eq!(DeliveryOutcome::InsertedAndVerified.code(), "inserted_verified");
        assert_eq!(
            DeliveryOutcome::PasteDispatchedClipboardRetained.code(),
            "paste_dispatched"
        );
    }
}
