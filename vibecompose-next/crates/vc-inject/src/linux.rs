//! Linux backend (X11 / partial Wayland). AT-SPI coverage in the wild is too
//! inconsistent for insertion proofs, so this backend is deliberately
//! degraded: paste is dispatched optimistically and the outcome never
//! upgrades past "paste dispatched"; the transcript always stays in the
//! clipboard. On Wayland compositors without a virtual-keyboard protocol the
//! key dispatch fails and delivery falls back to copy-only upstream.

use enigo::{Direction, Enigo, Key, Keyboard, Settings};

use crate::injector::{FocusedTarget, InjectionError, PlatformInjector, VerificationResult};

pub struct LinuxInjector;

impl LinuxInjector {
    pub fn new() -> Self {
        Self
    }
}

impl Default for LinuxInjector {
    fn default() -> Self {
        Self::new()
    }
}

impl PlatformInjector for LinuxInjector {
    fn requires_permission(&self) -> bool {
        false
    }

    fn focused_target(&self) -> Option<FocusedTarget> {
        Some(FocusedTarget {
            application_id: String::new(),
            application_name: String::new(),
            editable: true,
            element_token: None,
        })
    }

    fn dispatch_paste(&self) -> Result<(), InjectionError> {
        let mut enigo =
            Enigo::new(&Settings::default()).map_err(|e| InjectionError::KeyDispatch(e.to_string()))?;
        enigo
            .key(Key::Control, Direction::Press)
            .and_then(|_| enigo.key(Key::Unicode('v'), Direction::Click))
            .and_then(|_| enigo.key(Key::Control, Direction::Release))
            .map_err(|e| InjectionError::KeyDispatch(e.to_string()))
    }

    fn verify_insertion(
        &self,
        _target: &FocusedTarget,
        _expected_text: &str,
        _deadline_ms: u64,
    ) -> VerificationResult {
        VerificationResult::Inconclusive
    }

    /// X11 exposes the live selection as the PRIMARY buffer; most Wayland
    /// compositors mirror it (wlroots primary-selection protocol). Absence is
    /// reported honestly as `None`. Focused-element text has no portable
    /// source here (AT-SPI coverage is too inconsistent), so the
    /// focused-paragraph capability stays unavailable by design.
    fn read_selection(&self) -> Option<String> {
        use arboard::{GetExtLinux, LinuxClipboardKind};
        let mut clipboard = arboard::Clipboard::new().ok()?;
        let text = clipboard
            .get()
            .clipboard(LinuxClipboardKind::Primary)
            .text()
            .ok()?;
        (!text.trim().is_empty()).then_some(text)
    }
}
