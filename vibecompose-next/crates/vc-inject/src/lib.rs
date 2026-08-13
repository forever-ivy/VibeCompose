//! Text delivery with verification. Platform backends implement the traits;
//! outcomes use the shared three-state model from `vc-core`.

pub mod context;
pub mod injector;

/// Pure decision logic behind the Windows UIA verification backend; compiled
/// on every platform so the trust rules stay unit-testable on any host.
#[cfg_attr(not(target_os = "windows"), allow(dead_code))]
mod verification;

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "windows")]
mod windows_impl;
#[cfg(all(unix, not(target_os = "macos")))]
mod linux;

pub use injector::{
    ClipboardAccess, DeliveryReport, DeliveryRequest, FocusedTarget, InjectionError,
    PlatformInjector, SystemClipboard, TextInjector, VerificationResult,
};

#[cfg(target_os = "macos")]
pub use macos::MacInjector as NativeInjector;
#[cfg(target_os = "windows")]
pub use windows_impl::WindowsInjector as NativeInjector;
#[cfg(all(unix, not(target_os = "macos")))]
pub use linux::LinuxInjector as NativeInjector;

/// The default injector stack for this platform.
pub fn native_injector() -> TextInjector<NativeInjector, SystemClipboard> {
    TextInjector::new(NativeInjector::default(), SystemClipboard)
}
