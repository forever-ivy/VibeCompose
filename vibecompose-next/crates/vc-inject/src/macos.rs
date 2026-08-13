//! macOS backend: Accessibility (AX) focused-element inspection, Cmd+V paste
//! via enigo, and post-paste AXValue verification. Delivery stays
//! conservative: without AX trust the outcome is copy-only; without a
//! provable value transition it stays "paste dispatched".

use std::ffi::c_void;

use accessibility_sys::{
    kAXErrorSuccess, kAXFocusedUIElementAttribute, kAXRoleAttribute, kAXSelectedTextAttribute,
    kAXValueAttribute, AXIsProcessTrusted, AXUIElementCopyAttributeValue,
    AXUIElementCreateSystemWide, AXUIElementIsAttributeSettable, AXUIElementRef,
};
use core_foundation::base::{CFRelease, CFTypeRef, TCFType};
use core_foundation::string::{CFString, CFStringRef};
use enigo::{Direction, Enigo, Key, Keyboard, Settings};
use objc2_app_kit::NSWorkspace;

use crate::injector::{FocusedTarget, InjectionError, PlatformInjector, VerificationResult};

pub struct MacInjector;

impl MacInjector {
    pub fn new() -> Self {
        Self
    }

    fn frontmost_application() -> (String, String) {
        let workspace = NSWorkspace::sharedWorkspace();
        match workspace.frontmostApplication() {
            Some(app) => {
                let id = app
                    .bundleIdentifier()
                    .map(|s| s.to_string())
                    .unwrap_or_default();
                let name = app
                    .localizedName()
                    .map(|s| s.to_string())
                    .unwrap_or_default();
                (id, name)
            }
            None => (String::new(), String::new()),
        }
    }

    /// Reads the system-wide focused AX element; returns (role, value settable,
    /// current value) when available.
    fn focused_element_info() -> Option<(String, bool, Option<String>)> {
        unsafe {
            let system_wide = AXUIElementCreateSystemWide();
            if system_wide.is_null() {
                return None;
            }
            let mut focused: CFTypeRef = std::ptr::null();
            let attribute = CFString::new(kAXFocusedUIElementAttribute);
            let error = AXUIElementCopyAttributeValue(
                system_wide,
                attribute.as_concrete_TypeRef(),
                &mut focused as *mut CFTypeRef,
            );
            CFRelease(system_wide as CFTypeRef);
            if error != kAXErrorSuccess || focused.is_null() {
                return None;
            }
            let element = focused as AXUIElementRef;

            let role = copy_string_attribute(element, kAXRoleAttribute);
            let mut settable: u8 = 0;
            let value_attribute = CFString::new(kAXValueAttribute);
            let settable_error = AXUIElementIsAttributeSettable(
                element,
                value_attribute.as_concrete_TypeRef(),
                &mut settable,
            );
            let value = copy_string_attribute(element, kAXValueAttribute);
            CFRelease(element as CFTypeRef);

            Some((
                role.unwrap_or_default(),
                settable_error == kAXErrorSuccess && settable != 0,
                value,
            ))
        }
    }

    /// Reads a string attribute from the system-wide focused AX element.
    fn focused_string_attribute(attribute: &'static str) -> Option<String> {
        unsafe {
            let system_wide = AXUIElementCreateSystemWide();
            if system_wide.is_null() {
                return None;
            }
            let mut focused: CFTypeRef = std::ptr::null();
            let focus_attribute = CFString::new(kAXFocusedUIElementAttribute);
            let error = AXUIElementCopyAttributeValue(
                system_wide,
                focus_attribute.as_concrete_TypeRef(),
                &mut focused as *mut CFTypeRef,
            );
            CFRelease(system_wide as CFTypeRef);
            if error != kAXErrorSuccess || focused.is_null() {
                return None;
            }
            let element = focused as AXUIElementRef;
            let value = copy_string_attribute(element, attribute);
            CFRelease(element as CFTypeRef);
            value
        }
    }
}

impl Default for MacInjector {
    fn default() -> Self {
        Self::new()
    }
}

unsafe fn copy_string_attribute(element: AXUIElementRef, attribute: &str) -> Option<String> {
    let mut value: CFTypeRef = std::ptr::null();
    let attribute = CFString::new(attribute);
    let error = AXUIElementCopyAttributeValue(
        element,
        attribute.as_concrete_TypeRef(),
        &mut value as *mut CFTypeRef,
    );
    if error != kAXErrorSuccess || value.is_null() {
        return None;
    }
    // Only string values are interesting here; other CFTypes are released
    // and ignored.
    let cf_string_id = core_foundation::string::CFString::type_id();
    let actual_id = core_foundation::base::CFGetTypeID(value);
    let result = if actual_id == cf_string_id {
        let s = CFString::wrap_under_get_rule(value as CFStringRef).to_string();
        Some(s)
    } else {
        None
    };
    CFRelease(value as *const c_void);
    result
}

const EDITABLE_ROLES: &[&str] = &["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"];

impl PlatformInjector for MacInjector {
    fn requires_permission(&self) -> bool {
        !unsafe { AXIsProcessTrusted() }
    }

    fn focused_target(&self) -> Option<FocusedTarget> {
        let (application_id, application_name) = Self::frontmost_application();
        let Some((role, value_settable, _value)) = Self::focused_element_info() else {
            return None;
        };
        // Editable proof: a focused element whose AXValue is settable, or a
        // classic text role. Web areas/custom editors that expose neither
        // stay non-editable and deliver copy-only, matching the conservative
        // contract.
        let editable = value_settable || EDITABLE_ROLES.contains(&role.as_str());
        Some(FocusedTarget {
            application_id,
            application_name,
            editable,
            element_token: None,
        })
    }

    fn dispatch_paste(&self) -> Result<(), InjectionError> {
        let mut enigo =
            Enigo::new(&Settings::default()).map_err(|e| InjectionError::KeyDispatch(e.to_string()))?;
        enigo
            .key(Key::Meta, Direction::Press)
            .and_then(|_| enigo.key(Key::Unicode('v'), Direction::Click))
            .and_then(|_| enigo.key(Key::Meta, Direction::Release))
            .map_err(|e| InjectionError::KeyDispatch(e.to_string()))
    }

    fn verify_insertion(
        &self,
        target: &FocusedTarget,
        expected_text: &str,
        deadline_ms: u64,
    ) -> VerificationResult {
        let deadline = std::time::Instant::now() + std::time::Duration::from_millis(deadline_ms);
        loop {
            let (current_app, _) = Self::frontmost_application();
            if current_app != target.application_id {
                return VerificationResult::TargetChanged;
            }
            if let Some((_, _, Some(value))) = Self::focused_element_info() {
                if value.contains(expected_text) {
                    return VerificationResult::Verified;
                }
            }
            if std::time::Instant::now() >= deadline {
                return VerificationResult::Inconclusive;
            }
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
    }

    fn read_selection(&self) -> Option<String> {
        if unsafe { !AXIsProcessTrusted() } {
            return None;
        }
        Self::focused_string_attribute(kAXSelectedTextAttribute).filter(|s| !s.trim().is_empty())
    }

    fn read_focused_text(&self) -> Option<String> {
        if unsafe { !AXIsProcessTrusted() } {
            return None;
        }
        Self::focused_string_attribute(kAXValueAttribute).filter(|s| !s.trim().is_empty())
    }
}
