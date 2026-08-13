//! Platform-independent delivery logic. The platform backend answers three
//! questions (who has focus, is it editable, did the text arrive); this层
//! enforces the delivery contract:
//!
//! 1. The final text is always written to the clipboard first.
//! 2. Paste is dispatched only when the platform proves a current editable
//!    target; otherwise the outcome is copy-only with a reason.
//! 3. The previous clipboard is restored only after a verified insertion and
//!    only while we still own the clipboard contents.

use thiserror::Error;

use vc_core::delivery::{ClipboardFallbackReason, DeliveryOutcome};

#[derive(Debug, Error)]
pub enum InjectionError {
    #[error("clipboard is unavailable: {0}")]
    Clipboard(String),
    #[error("key dispatch failed: {0}")]
    KeyDispatch(String),
}

/// The focused UI element captured immediately before paste.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FocusedTarget {
    /// Platform application identifier (bundle id / executable name / app id).
    pub application_id: String,
    pub application_name: String,
    /// Whether the platform proved the focused element accepts text.
    pub editable: bool,
    /// Opaque token the backend can use to re-identify the same element.
    pub element_token: Option<String>,
}

/// Result of a platform verification pass after paste dispatch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VerificationResult {
    /// The same element exposed the expected text transition.
    Verified,
    /// Verification is unsupported or was inconclusive.
    Inconclusive,
    /// The focused element changed between capture and paste.
    TargetChanged,
}

/// Platform backend. Implementations must be conservative: when a proof is
/// unavailable they answer `Inconclusive` / `editable: false`, never guess.
pub trait PlatformInjector: Send + Sync {
    /// True when the platform requires a permission that is not granted
    /// (macOS Accessibility). Windows/Linux return false.
    fn requires_permission(&self) -> bool;

    fn focused_target(&self) -> Option<FocusedTarget>;

    /// Dispatches the platform paste chord (Cmd+V / Ctrl+V).
    fn dispatch_paste(&self) -> Result<(), InjectionError>;

    /// Verifies insertion into the captured target within the deadline.
    fn verify_insertion(
        &self,
        target: &FocusedTarget,
        expected_text: &str,
        deadline_ms: u64,
    ) -> VerificationResult;

    /// Reads the selected text in the focused element. Trust rule 5: callers
    /// may invoke this only after per-Skill context authorization. Backends
    /// without a selection source return `None`.
    fn read_selection(&self) -> Option<String> {
        None
    }

    /// Reads the focused element's full text (focused-paragraph context).
    /// Same authorization rule as `read_selection`.
    fn read_focused_text(&self) -> Option<String> {
        None
    }
}

/// Clipboard abstraction (allows tests to run headless).
pub trait ClipboardAccess: Send + Sync {
    fn read_text(&self) -> Option<String>;
    fn write_text(&self, text: &str) -> Result<(), InjectionError>;
}

pub struct SystemClipboard;

impl ClipboardAccess for SystemClipboard {
    fn read_text(&self) -> Option<String> {
        arboard::Clipboard::new().ok()?.get_text().ok()
    }

    fn write_text(&self, text: &str) -> Result<(), InjectionError> {
        arboard::Clipboard::new()
            .and_then(|mut c| c.set_text(text.to_string()))
            .map_err(|e| InjectionError::Clipboard(e.to_string()))
    }
}

pub struct DeliveryRequest<'a> {
    pub text: &'a str,
    /// Restore the previous clipboard after verified insertion.
    pub preserve_clipboard: bool,
    /// Milliseconds to poll for verification after dispatching paste.
    pub verification_deadline_ms: u64,
    /// Milliseconds to wait before restoring the clipboard.
    pub restore_delay_ms: u64,
    /// Copy-only delivery (preview "Copy" button, retry flows).
    pub copy_only: bool,
}

pub struct DeliveryReport {
    pub outcome: DeliveryOutcome,
    pub target: Option<FocusedTarget>,
}

pub struct TextInjector<P: PlatformInjector, C: ClipboardAccess> {
    pub platform: P,
    pub clipboard: C,
}

impl<P: PlatformInjector, C: ClipboardAccess> TextInjector<P, C> {
    pub fn new(platform: P, clipboard: C) -> Self {
        Self { platform, clipboard }
    }

    pub fn deliver(&self, request: &DeliveryRequest) -> Result<DeliveryReport, InjectionError> {
        let previous_clipboard = if request.preserve_clipboard {
            self.clipboard.read_text()
        } else {
            None
        };

        // Rule 1: the transcript reaches the clipboard before anything else,
        // so no failure below can lose the user's dictation.
        self.clipboard.write_text(request.text)?;

        if request.copy_only {
            return Ok(DeliveryReport {
                outcome: DeliveryOutcome::CopiedToClipboard(
                    ClipboardFallbackReason::RetryRequiresManualPaste,
                ),
                target: None,
            });
        }

        if self.platform.requires_permission() {
            return Ok(DeliveryReport {
                outcome: DeliveryOutcome::CopiedToClipboard(
                    ClipboardFallbackReason::AccessibilityPermissionRequired,
                ),
                target: None,
            });
        }

        let Some(target) = self.platform.focused_target() else {
            return Ok(DeliveryReport {
                outcome: DeliveryOutcome::CopiedToClipboard(
                    ClipboardFallbackReason::NoEditableTarget,
                ),
                target: None,
            });
        };
        if !target.editable {
            return Ok(DeliveryReport {
                outcome: DeliveryOutcome::CopiedToClipboard(
                    ClipboardFallbackReason::NoEditableTarget,
                ),
                target: Some(target),
            });
        }

        // A failed key dispatch (e.g. Wayland without a virtual keyboard
        // protocol) degrades to copy-only; the transcript is already safe.
        if self.platform.dispatch_paste().is_err() {
            return Ok(DeliveryReport {
                outcome: DeliveryOutcome::CopiedToClipboard(
                    ClipboardFallbackReason::PlatformUnsupported,
                ),
                target: Some(target),
            });
        }

        let outcome = match self.platform.verify_insertion(
            &target,
            request.text,
            request.verification_deadline_ms,
        ) {
            VerificationResult::Verified => {
                if request.preserve_clipboard {
                    if let Some(previous) = previous_clipboard {
                        std::thread::sleep(std::time::Duration::from_millis(
                            request.restore_delay_ms,
                        ));
                        // Restore only while we still own the clipboard.
                        if self.clipboard.read_text().as_deref() == Some(request.text) {
                            let _ = self.clipboard.write_text(&previous);
                        }
                    }
                }
                DeliveryOutcome::InsertedAndVerified
            }
            VerificationResult::Inconclusive => {
                DeliveryOutcome::PasteDispatchedClipboardRetained
            }
            VerificationResult::TargetChanged => {
                DeliveryOutcome::CopiedToClipboard(ClipboardFallbackReason::TargetChanged)
            }
        };

        Ok(DeliveryReport {
            outcome,
            target: Some(target),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    struct FakePlatform {
        permission_missing: bool,
        target: Option<FocusedTarget>,
        verification: VerificationResult,
        pasted: Mutex<bool>,
    }

    impl PlatformInjector for FakePlatform {
        fn requires_permission(&self) -> bool {
            self.permission_missing
        }
        fn focused_target(&self) -> Option<FocusedTarget> {
            self.target.clone()
        }
        fn dispatch_paste(&self) -> Result<(), InjectionError> {
            *self.pasted.lock().unwrap() = true;
            Ok(())
        }
        fn verify_insertion(&self, _: &FocusedTarget, _: &str, _: u64) -> VerificationResult {
            self.verification
        }
    }

    #[derive(Default)]
    struct FakeClipboard {
        content: Mutex<Option<String>>,
    }

    impl ClipboardAccess for FakeClipboard {
        fn read_text(&self) -> Option<String> {
            self.content.lock().unwrap().clone()
        }
        fn write_text(&self, text: &str) -> Result<(), InjectionError> {
            *self.content.lock().unwrap() = Some(text.to_string());
            Ok(())
        }
    }

    fn editable_target() -> FocusedTarget {
        FocusedTarget {
            application_id: "com.apple.textedit".into(),
            application_name: "TextEdit".into(),
            editable: true,
            element_token: None,
        }
    }

    fn request(text: &str) -> DeliveryRequest<'_> {
        DeliveryRequest {
            text,
            preserve_clipboard: false,
            verification_deadline_ms: 0,
            restore_delay_ms: 0,
            copy_only: false,
        }
    }

    #[test]
    fn missing_permission_is_copy_only_with_reason() {
        let injector = TextInjector::new(
            FakePlatform {
                permission_missing: true,
                target: Some(editable_target()),
                verification: VerificationResult::Verified,
                pasted: Mutex::new(false),
            },
            FakeClipboard::default(),
        );
        let report = injector.deliver(&request("文本")).unwrap();
        assert_eq!(
            report.outcome,
            DeliveryOutcome::CopiedToClipboard(
                ClipboardFallbackReason::AccessibilityPermissionRequired
            )
        );
        assert!(!*injector.platform.pasted.lock().unwrap());
        assert_eq!(injector.clipboard.read_text().as_deref(), Some("文本"));
    }

    #[test]
    fn non_editable_target_never_receives_paste() {
        let mut target = editable_target();
        target.editable = false;
        let injector = TextInjector::new(
            FakePlatform {
                permission_missing: false,
                target: Some(target),
                verification: VerificationResult::Verified,
                pasted: Mutex::new(false),
            },
            FakeClipboard::default(),
        );
        let report = injector.deliver(&request("文本")).unwrap();
        assert_eq!(
            report.outcome,
            DeliveryOutcome::CopiedToClipboard(ClipboardFallbackReason::NoEditableTarget)
        );
        assert!(!*injector.platform.pasted.lock().unwrap());
    }

    #[test]
    fn verified_insertion_restores_previous_clipboard() {
        let clipboard = FakeClipboard::default();
        clipboard.write_text("旧内容").unwrap();
        let injector = TextInjector::new(
            FakePlatform {
                permission_missing: false,
                target: Some(editable_target()),
                verification: VerificationResult::Verified,
                pasted: Mutex::new(false),
            },
            clipboard,
        );
        let report = injector
            .deliver(&DeliveryRequest {
                text: "新文本",
                preserve_clipboard: true,
                verification_deadline_ms: 0,
                restore_delay_ms: 0,
                copy_only: false,
            })
            .unwrap();
        assert_eq!(report.outcome, DeliveryOutcome::InsertedAndVerified);
        assert_eq!(injector.clipboard.read_text().as_deref(), Some("旧内容"));
    }

    #[test]
    fn inconclusive_verification_retains_transcript_in_clipboard() {
        let clipboard = FakeClipboard::default();
        clipboard.write_text("旧内容").unwrap();
        let injector = TextInjector::new(
            FakePlatform {
                permission_missing: false,
                target: Some(editable_target()),
                verification: VerificationResult::Inconclusive,
                pasted: Mutex::new(false),
            },
            clipboard,
        );
        let report = injector
            .deliver(&DeliveryRequest {
                text: "新文本",
                preserve_clipboard: true,
                verification_deadline_ms: 0,
                restore_delay_ms: 0,
                copy_only: false,
            })
            .unwrap();
        assert_eq!(
            report.outcome,
            DeliveryOutcome::PasteDispatchedClipboardRetained
        );
        // The transcript must stay available for manual paste.
        assert_eq!(injector.clipboard.read_text().as_deref(), Some("新文本"));
    }

    #[test]
    fn copy_only_request_skips_all_platform_probes() {
        let injector = TextInjector::new(
            FakePlatform {
                permission_missing: false,
                target: Some(editable_target()),
                verification: VerificationResult::Verified,
                pasted: Mutex::new(false),
            },
            FakeClipboard::default(),
        );
        let report = injector
            .deliver(&DeliveryRequest {
                text: "文本",
                preserve_clipboard: false,
                verification_deadline_ms: 0,
                restore_delay_ms: 0,
                copy_only: true,
            })
            .unwrap();
        assert!(matches!(report.outcome, DeliveryOutcome::CopiedToClipboard(_)));
        assert!(!*injector.platform.pasted.lock().unwrap());
    }
}
