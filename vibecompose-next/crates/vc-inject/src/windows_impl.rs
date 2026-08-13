//! Windows backend: Win32 foreground-window identification, UI Automation
//! (UIA) focused-element inspection, Ctrl+V dispatch, and post-paste
//! verification against the captured element.
//!
//! Trust rules mirror the macOS AX backend:
//! - Editability must be proven by the focused UIA element: a writable
//!   ValuePattern, or a TextPattern on an Edit/Document/ComboBox control.
//!   Password fields are never treated as paste targets. Without proof the
//!   delivery stays copy-only.
//! - Verification only trusts the element captured before paste. The element
//!   is re-identified by RuntimeId; a mismatch is immediately `Inconclusive`,
//!   never `Verified`.
//! - `Verified` additionally requires the element text to contain the
//!   expected text AND to differ from the pre-paste snapshot digest. Anything
//!   unprovable stays `Inconclusive`, so upstream reports "paste dispatched"
//!   and the transcript stays in the clipboard.
//!
//! COM lifecycle: `focused_target` / `verify_insertion` run on blocking-pool
//! threads. Each call initializes the MTA via `CoInitializeEx` (the
//! recommended apartment for UIA clients), tolerates `RPC_E_CHANGED_MODE`
//! when the thread is already committed to an STA, and balances every
//! successful initialization with `CoUninitialize` before returning.

use std::ffi::c_void;
use std::time::{Duration, Instant};

use enigo::{Direction, Enigo, Key, Keyboard, Settings};
use windows::core::Interface;
use windows::Win32::Foundation::{CloseHandle, HWND, RPC_E_CHANGED_MODE};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoUninitialize, CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED,
    SAFEARRAY,
};
use windows::Win32::System::Ole::{
    SafeArrayDestroy, SafeArrayGetElement, SafeArrayGetLBound, SafeArrayGetUBound,
};
use windows::Win32::System::Threading::{
    OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
    PROCESS_QUERY_LIMITED_INFORMATION,
};
use windows::Win32::UI::Accessibility::{
    CUIAutomation, IUIAutomation, IUIAutomationElement, IUIAutomationTextPattern,
    IUIAutomationTextRangeArray, IUIAutomationValuePattern, UIA_ComboBoxControlTypeId,
    UIA_DocumentControlTypeId, UIA_EditControlTypeId, UIA_TextPatternId, UIA_ValuePatternId,
    UIA_CONTROLTYPE_ID,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetForegroundWindow, GetGUIThreadInfo, GetWindowTextW, GetWindowThreadProcessId,
    GUITHREADINFO,
};

use crate::injector::{FocusedTarget, InjectionError, PlatformInjector, VerificationResult};
use crate::verification::{
    insertion_verified, text_digest, ElementToken, SnapshotSource, TextDigest,
};

const VERIFY_POLL_INTERVAL: Duration = Duration::from_millis(50);
/// Upper bound for TextPattern document reads, mirroring the macOS
/// verification text cap. UIA interprets the limit in characters.
const MAX_PATTERN_TEXT_CHARS: i32 = 1_000_000;
/// Upper bound per selected range when reading selection context.
const MAX_SELECTION_READ_CHARS: i32 = 24_000;

pub struct WindowsInjector;

impl WindowsInjector {
    pub fn new() -> Self {
        Self
    }
}

impl Default for WindowsInjector {
    fn default() -> Self {
        Self::new()
    }
}

fn foreground_window() -> Option<HWND> {
    let hwnd = unsafe { GetForegroundWindow() };
    if hwnd.is_invalid() {
        None
    } else {
        Some(hwnd)
    }
}

fn process_image_name(hwnd: HWND) -> Option<String> {
    let mut pid = 0u32;
    let thread_id = unsafe { GetWindowThreadProcessId(hwnd, Some(&mut pid)) };
    if thread_id == 0 || pid == 0 {
        return None;
    }
    let handle = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) }.ok()?;
    let mut buffer = [0u16; 1024];
    let mut size = buffer.len() as u32;
    let result = unsafe {
        QueryFullProcessImageNameW(
            handle,
            PROCESS_NAME_WIN32,
            windows::core::PWSTR(buffer.as_mut_ptr()),
            &mut size,
        )
    };
    unsafe {
        let _ = CloseHandle(handle);
    }
    result.ok()?;
    let full_path = String::from_utf16_lossy(&buffer[..size as usize]);
    // Canonical application id: lowercase executable name without path.
    full_path
        .rsplit(['\\', '/'])
        .next()
        .map(|name| name.to_lowercase())
}

fn window_title(hwnd: HWND) -> String {
    let mut buffer = [0u16; 512];
    let length = unsafe { GetWindowTextW(hwnd, &mut buffer) };
    if length <= 0 {
        return String::new();
    }
    String::from_utf16_lossy(&buffer[..length as usize])
}

/// Legacy editability heuristic, used only when COM/UIA itself is
/// unavailable: a visible caret or focus window in the foreground GUI thread
/// is a weak signal for a classic editable control.
fn gui_thread_has_focus_window(hwnd: HWND) -> bool {
    let thread_id = unsafe { GetWindowThreadProcessId(hwnd, None) };
    if thread_id == 0 {
        return false;
    }
    let mut info = GUITHREADINFO {
        cbSize: std::mem::size_of::<GUITHREADINFO>() as u32,
        ..Default::default()
    };
    let ok = unsafe { GetGUIThreadInfo(thread_id, &mut info) }.is_ok();
    ok && (!info.hwndFocus.is_invalid() || !info.hwndCaret.is_invalid())
}

/// Balances `CoInitializeEx` with `CoUninitialize`. `S_FALSE` (already
/// initialized on this thread) still needs the balancing uninitialize;
/// `RPC_E_CHANGED_MODE` (thread already committed to an STA) means COM is
/// usable but this call added no reference, so dropping must not uninitialize.
struct ComGuard {
    must_uninitialize: bool,
}

impl ComGuard {
    fn initialize_mta() -> Option<Self> {
        let hr = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
        if hr.is_ok() {
            Some(Self {
                must_uninitialize: true,
            })
        } else if hr == RPC_E_CHANGED_MODE {
            Some(Self {
                must_uninitialize: false,
            })
        } else {
            None
        }
    }
}

impl Drop for ComGuard {
    fn drop(&mut self) {
        if self.must_uninitialize {
            unsafe { CoUninitialize() };
        }
    }
}

/// One COM-scoped UIA client instance. Field order matters: `automation`
/// must release before `_com` uninitializes COM on this thread.
struct UiaSession {
    automation: IUIAutomation,
    _com: ComGuard,
}

impl UiaSession {
    fn new() -> Option<Self> {
        let com = ComGuard::initialize_mta()?;
        let automation: IUIAutomation =
            unsafe { CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER) }.ok()?;
        Some(Self {
            automation,
            _com: com,
        })
    }

    fn focused_element(&self) -> Option<IUIAutomationElement> {
        unsafe { self.automation.GetFocusedElement() }.ok()
    }
}

/// Control types whose TextPattern support marks them as text-input surfaces
/// even without a writable ValuePattern (rich documents typically expose
/// TextPattern only).
const EDITABLE_TEXT_CONTROL_TYPES: [UIA_CONTROLTYPE_ID; 3] = [
    UIA_EditControlTypeId,
    UIA_DocumentControlTypeId,
    UIA_ComboBoxControlTypeId,
];

struct UiaFocusProbe {
    editable: bool,
    element_token: Option<String>,
}

fn probe_focused_element(session: &UiaSession) -> UiaFocusProbe {
    let Some(element) = session.focused_element() else {
        return UiaFocusProbe {
            editable: false,
            element_token: None,
        };
    };

    let has_keyboard_focus = unsafe { element.CurrentHasKeyboardFocus() }
        .map(|value| value.as_bool())
        .unwrap_or(false);
    let is_password = unsafe { element.CurrentIsPassword() }
        .map(|value| value.as_bool())
        .unwrap_or(false);

    let value_pattern = value_pattern(&element);
    let value_writable = value_pattern
        .as_ref()
        .map(|pattern| {
            unsafe { pattern.CurrentIsReadOnly() }
                .map(|read_only| !read_only.as_bool())
                .unwrap_or(false)
        })
        .unwrap_or(false);

    let text_pattern = text_pattern(&element);
    let control_type_is_text_input = unsafe { element.CurrentControlType() }
        .map(|control_type| EDITABLE_TEXT_CONTROL_TYPES.contains(&control_type))
        .unwrap_or(false);

    let editable = has_keyboard_focus
        && !is_password
        && (value_writable || (text_pattern.is_some() && control_type_is_text_input));

    // Identity token: RuntimeId re-identifies the element after paste; the
    // text digest lets verification prove the content actually changed.
    let element_token = element_runtime_id(&element).map(|runtime_id| {
        let snapshot = read_snapshot(value_pattern.as_ref(), text_pattern.as_ref());
        ElementToken {
            runtime_id,
            snapshot,
        }
        .encode()
    });

    UiaFocusProbe {
        editable,
        element_token,
    }
}

fn read_snapshot(
    value_pattern: Option<&IUIAutomationValuePattern>,
    text_pattern: Option<&IUIAutomationTextPattern>,
) -> Option<(SnapshotSource, TextDigest)> {
    if let Some(pattern) = value_pattern {
        if let Ok(value) = unsafe { pattern.CurrentValue() } {
            return Some((SnapshotSource::Value, text_digest(&value.to_string())));
        }
    }
    if let Some(pattern) = text_pattern {
        if let Some(document) = text_pattern_document(pattern) {
            return Some((SnapshotSource::Text, text_digest(&document)));
        }
    }
    None
}

fn value_pattern(element: &IUIAutomationElement) -> Option<IUIAutomationValuePattern> {
    unsafe { element.GetCurrentPattern(UIA_ValuePatternId) }
        .ok()?
        .cast()
        .ok()
}

fn text_pattern(element: &IUIAutomationElement) -> Option<IUIAutomationTextPattern> {
    unsafe { element.GetCurrentPattern(UIA_TextPatternId) }
        .ok()?
        .cast()
        .ok()
}

fn text_pattern_document(pattern: &IUIAutomationTextPattern) -> Option<String> {
    let range = unsafe { pattern.DocumentRange() }.ok()?;
    let text = unsafe { range.GetText(MAX_PATTERN_TEXT_CHARS) }.ok()?;
    Some(text.to_string())
}

/// Joins the focused element's selected ranges (TextPattern). Multi-range
/// selections (e.g. table columns) concatenate with newlines, matching how
/// applications serialize them to the clipboard.
fn text_pattern_selection(pattern: &IUIAutomationTextPattern) -> Option<String> {
    let ranges: IUIAutomationTextRangeArray = unsafe { pattern.GetSelection() }.ok()?;
    let length = unsafe { ranges.Length() }.ok()?;
    let mut pieces: Vec<String> = Vec::new();
    for index in 0..length {
        let Ok(range) = (unsafe { ranges.GetElement(index) }) else {
            continue;
        };
        if let Ok(text) = unsafe { range.GetText(MAX_SELECTION_READ_CHARS) } {
            let text = text.to_string();
            if !text.is_empty() {
                pieces.push(text);
            }
        }
    }
    let joined = pieces.join("\n");
    (!joined.trim().is_empty()).then_some(joined)
}

/// Reads the element text from the same source that produced the pre-paste
/// snapshot, keeping representations comparable across polls.
fn element_text(element: &IUIAutomationElement, source: SnapshotSource) -> Option<String> {
    match source {
        SnapshotSource::Value => {
            let pattern = value_pattern(element)?;
            unsafe { pattern.CurrentValue() }
                .ok()
                .map(|value| value.to_string())
        }
        SnapshotSource::Text => {
            let pattern = text_pattern(element)?;
            text_pattern_document(&pattern)
        }
    }
}

fn element_runtime_id(element: &IUIAutomationElement) -> Option<Vec<i32>> {
    let array = unsafe { element.GetRuntimeId() }.ok()?;
    if array.is_null() {
        return None;
    }
    let ids = unsafe { read_i32_safearray(array) };
    unsafe {
        let _ = SafeArrayDestroy(array);
    }
    ids.filter(|ids| !ids.is_empty())
}

unsafe fn read_i32_safearray(array: *const SAFEARRAY) -> Option<Vec<i32>> {
    let lower = SafeArrayGetLBound(array, 1).ok()?;
    let upper = SafeArrayGetUBound(array, 1).ok()?;
    if upper < lower {
        return Some(Vec::new());
    }
    let mut ids = Vec::with_capacity((upper - lower + 1) as usize);
    for index in lower..=upper {
        let mut value: i32 = 0;
        SafeArrayGetElement(array, &index, &mut value as *mut i32 as *mut c_void).ok()?;
        ids.push(value);
    }
    Some(ids)
}

/// Fallback verification when no per-element token exists (UIA unavailable
/// or the element exposed no RuntimeId): only prove the foreground app did
/// not change, then stay honestly inconclusive.
fn verify_foreground_only(target: &FocusedTarget, deadline_ms: u64) -> VerificationResult {
    std::thread::sleep(Duration::from_millis(deadline_ms.min(150)));
    match foreground_window().and_then(process_image_name) {
        Some(current) if current == target.application_id => VerificationResult::Inconclusive,
        Some(_) => VerificationResult::TargetChanged,
        None => VerificationResult::Inconclusive,
    }
}

impl PlatformInjector for WindowsInjector {
    fn requires_permission(&self) -> bool {
        // Windows has no Accessibility-style TCC gate for SendInput/UIA.
        false
    }

    fn focused_target(&self) -> Option<FocusedTarget> {
        let hwnd = foreground_window()?;
        let application_id = process_image_name(hwnd).unwrap_or_default();
        if application_id.is_empty() {
            return None;
        }
        let application_name = window_title(hwnd);

        // UIA proof preferred. The caret heuristic only remains for
        // environments where COM/UIA itself cannot be brought up.
        if let Some(session) = UiaSession::new() {
            let probe = probe_focused_element(&session);
            return Some(FocusedTarget {
                application_id,
                application_name,
                editable: probe.editable,
                element_token: probe.element_token,
            });
        }

        Some(FocusedTarget {
            application_id,
            application_name,
            editable: gui_thread_has_focus_window(hwnd),
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
        target: &FocusedTarget,
        expected_text: &str,
        deadline_ms: u64,
    ) -> VerificationResult {
        let token = target
            .element_token
            .as_deref()
            .and_then(ElementToken::decode);
        let Some(token) = token else {
            return verify_foreground_only(target, deadline_ms);
        };
        let Some((source, snapshot)) = token.snapshot else {
            // Same-element identity exists, but no pre-paste text snapshot was
            // readable, so a content change can never be proven.
            return verify_foreground_only(target, deadline_ms);
        };
        let Some(session) = UiaSession::new() else {
            return verify_foreground_only(target, deadline_ms);
        };

        let deadline = Instant::now() + Duration::from_millis(deadline_ms);
        loop {
            // App-level drift: another application took the foreground.
            match foreground_window().and_then(process_image_name) {
                Some(current) if current != target.application_id => {
                    return VerificationResult::TargetChanged;
                }
                _ => {}
            }

            if let Some(element) = session.focused_element() {
                if let Some(runtime_id) = element_runtime_id(&element) {
                    // Rule 1: only the captured element is trusted. Focus
                    // drift — even inside the same app — makes the paste
                    // unprovable, never "verified by proxy".
                    if runtime_id != token.runtime_id {
                        return VerificationResult::Inconclusive;
                    }
                    if let Some(current_text) = element_text(&element, source) {
                        if insertion_verified(&current_text, expected_text, snapshot) {
                            return VerificationResult::Verified;
                        }
                    }
                }
            }

            if Instant::now() >= deadline {
                return VerificationResult::Inconclusive;
            }
            std::thread::sleep(VERIFY_POLL_INTERVAL);
        }
    }

    fn read_selection(&self) -> Option<String> {
        let session = UiaSession::new()?;
        let element = session.focused_element()?;
        if unsafe { element.CurrentIsPassword() }
            .map(|value| value.as_bool())
            .unwrap_or(false)
        {
            return None;
        }
        let pattern = text_pattern(&element)?;
        text_pattern_selection(&pattern)
    }

    fn read_focused_text(&self) -> Option<String> {
        let session = UiaSession::new()?;
        let element = session.focused_element()?;
        if unsafe { element.CurrentIsPassword() }
            .map(|value| value.as_bool())
            .unwrap_or(false)
        {
            return None;
        }
        if let Some(pattern) = value_pattern(&element) {
            if let Ok(value) = unsafe { pattern.CurrentValue() } {
                let value = value.to_string();
                if !value.trim().is_empty() {
                    return Some(value);
                }
            }
        }
        let pattern = text_pattern(&element)?;
        text_pattern_document(&pattern).filter(|text| !text.trim().is_empty())
    }
}
