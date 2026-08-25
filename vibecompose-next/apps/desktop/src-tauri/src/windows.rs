//! Overlay windows: dictation feedback (HUD pill or edge glow), result
//! preview, and Skill switcher.
//!
//! Labels are stable so the frontend can route by `getCurrentWindow().label`.
//! Feedback surfaces never steal focus; preview and the switcher do, because
//! they need explicit confirmation.
//!
//! The dictation feedback surface honors `config.visual_feedback.mode`,
//! matching the macOS app's three modes: Refined HUD (status pill, top or
//! bottom of the active display), AI activity glow (edge glow wrapping the
//! display, click-through), and Hidden (no on-screen feedback; tray status,
//! sounds, and cancel still work).

use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindow, WebviewWindowBuilder};

use vc_core::visual_feedback::{HudPlacement, VisualFeedbackMode};

use crate::state::AppState;

pub const HUD_LABEL: &str = "hud";
pub const GLOW_LABEL: &str = "glow";
pub const PREVIEW_LABEL: &str = "preview";
pub const SWITCHER_LABEL: &str = "skill-switcher";
pub const QUICK_ADD_LABEL: &str = "quick-add";

// Compact-box canvas for the Refined HUD, sized to the macOS dictation
// capsule (`OverlayStylePreset.dictationHUD`: <=~300pt wide, 44pt row plus
// the recording hint line). The window stays transparent; the pill inside
// hugs its content, so the canvas only needs room for the pill + shadow.
const HUD_WIDTH: f64 = 320.0;
const HUD_HEIGHT: f64 = 76.0;

/// Shows the configured dictation feedback surface for the active session.
pub fn show_feedback(app: &AppHandle) {
    let mode = app.state::<AppState>().config().visual_feedback.mode;
    match mode {
        VisualFeedbackMode::RefinedHud => {
            hide_glow(app);
            show_hud(app);
        }
        VisualFeedbackMode::AiActivityGlow => {
            hide_hud(app);
            show_glow(app);
        }
        VisualFeedbackMode::Hidden => {
            hide_hud(app);
            hide_glow(app);
        }
    }
}

/// Hides every feedback surface (session finished or cancelled).
pub fn hide_feedback(app: &AppHandle) {
    hide_hud(app);
    hide_glow(app);
}

fn show_hud(app: &AppHandle) {
    match app.get_webview_window(HUD_LABEL) {
        Some(window) => {
            position_hud(app, &window);
            let _ = window.show();
        }
        None => {
            if let Ok(window) = build_overlay(
                app,
                HUD_LABEL,
                "VibeCompose",
                HUD_WIDTH,
                HUD_HEIGHT,
                false,
                false,
            ) {
                position_hud(app, &window);
                let _ = window.show();
            }
        }
    }
}

pub fn hide_hud(app: &AppHandle) {
    if let Some(window) = app.get_webview_window(HUD_LABEL) {
        let _ = window.hide();
    }
}

/// Edge glow: a click-through window covering the active display whose
/// frontend renders a soft border glow. Wraps the primary display; macOS's
/// focused-window framing needs AX geometry that has no portable analog.
fn show_glow(app: &AppHandle) {
    let window = match app.get_webview_window(GLOW_LABEL) {
        Some(window) => window,
        None => {
            let Ok(window) = WebviewWindowBuilder::new(
                app,
                GLOW_LABEL,
                WebviewUrl::App("/".into()),
            )
            .title("VibeCompose")
            .decorations(false)
            .transparent(true)
            .shadow(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .resizable(false)
            .visible(false)
            .focused(false)
            // `focused(false)` only affects creation; on X11 the window
            // manager may still focus the window every time it is mapped.
            // Feedback surfaces must never take keyboard focus away from
            // the user's dictation target.
            .focusable(false)
            .build() else {
                return;
            };
            window
        }
    };
    if let Ok(Some(monitor)) = window.primary_monitor() {
        let _ = window.set_position(tauri::PhysicalPosition::new(
            monitor.position().x,
            monitor.position().y,
        ));
        let _ = window.set_size(tauri::PhysicalSize::new(
            monitor.size().width,
            monitor.size().height,
        ));
    }
    let _ = window.show();
    // Click-through must be applied after show(): on Linux (tao/GTK) the
    // input-shape request unwraps the underlying GdkWindow, which only
    // exists once the window has been realized. Calling it on a
    // never-shown window aborts the process.
    let _ = window.set_ignore_cursor_events(true);
}

pub fn hide_glow(app: &AppHandle) {
    if let Some(window) = app.get_webview_window(GLOW_LABEL) {
        let _ = window.hide();
    }
}

pub fn show_preview(app: &AppHandle) {
    hide_feedback(app);
    match app.get_webview_window(PREVIEW_LABEL) {
        Some(window) => {
            let _ = window.show();
            let _ = window.set_focus();
        }
        None => {
            if let Ok(window) = build_overlay(
                app,
                PREVIEW_LABEL,
                "听写预览",
                460.0,
                420.0,
                true,
                true,
            ) {
                let _ = window.center();
                let _ = window.show();
                let _ = window.set_focus();
            }
        }
    }
}

pub fn hide_preview(app: &AppHandle) {
    if let Some(window) = app.get_webview_window(PREVIEW_LABEL) {
        let _ = window.hide();
    }
}

pub fn toggle_skill_switcher(app: &AppHandle) {
    toggle_focused_overlay(app, SWITCHER_LABEL, "Skill 切换器", 360.0, 480.0);
}

pub fn hide_skill_switcher(app: &AppHandle) {
    if let Some(window) = app.get_webview_window(SWITCHER_LABEL) {
        let _ = window.hide();
    }
}

pub fn toggle_quick_add(app: &AppHandle) {
    toggle_focused_overlay(app, QUICK_ADD_LABEL, "快速添加术语", 440.0, 400.0);
}

pub fn hide_quick_add(app: &AppHandle) {
    if let Some(window) = app.get_webview_window(QUICK_ADD_LABEL) {
        let _ = window.hide();
    }
}

fn toggle_focused_overlay(app: &AppHandle, label: &str, title: &str, width: f64, height: f64) {
    if let Some(window) = app.get_webview_window(label) {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
            return;
        }
        let _ = window.show();
        let _ = window.set_focus();
        return;
    }
    if let Ok(window) = build_overlay(app, label, title, width, height, true, true) {
        let _ = window.center();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

pub fn hide_overlay(app: &AppHandle, label: &str) {
    match label {
        HUD_LABEL => hide_hud(app),
        GLOW_LABEL => hide_glow(app),
        PREVIEW_LABEL => hide_preview(app),
        SWITCHER_LABEL => hide_skill_switcher(app),
        QUICK_ADD_LABEL => hide_quick_add(app),
        _ => {}
    }
}

fn build_overlay(
    app: &AppHandle,
    label: &str,
    title: &str,
    width: f64,
    height: f64,
    decorations: bool,
    focus: bool,
) -> tauri::Result<WebviewWindow> {
    // Linux is fully client-side decorated: the main window draws an
    // Adwaita-style header bar and aux panels (preview, switcher, quick
    // add) are chrome-free rounded dialogs with their own buttons and ESC
    // paths. System decorations would reintroduce arbitrary WM themes —
    // including macOS-lookalike traffic lights — breaking the
    // per-platform design language rule.
    let decorations = if cfg!(target_os = "linux") {
        false
    } else {
        decorations
    };
    let window = WebviewWindowBuilder::new(app, label, WebviewUrl::App("/".into()))
        .title(title)
        .inner_size(width, height)
        .min_inner_size(width, height)
        .resizable(false)
        .decorations(decorations)
        // Undecorated feedback surfaces (the HUD pill) draw their own rounded
        // card; the window canvas must stay transparent so the pill floats
        // like the macOS Refined HUD instead of sitting in an opaque box.
        // The OS shadow would trace that invisible rectangle, so drop it and
        // let the card's CSS box-shadow provide depth.
        .transparent(!decorations)
        .shadow(decorations)
        .always_on_top(true)
        .skip_taskbar(true)
        .visible(false)
        .focused(focus)
        // Non-focus overlays (the HUD pill) must stay that way on every
        // show, not just at creation; otherwise the WM steals focus from
        // the dictation target when the surface reappears.
        .focusable(focus)
        .build()?;

    let handle = window.clone();
    window.on_window_event(move |event| {
        if let tauri::WindowEvent::CloseRequested { api, .. } = event {
            api.prevent_close();
            let _ = handle.hide();
        }
    });
    Ok(window)
}

/// Positions the status pill on the configured display edge (top or bottom),
/// mirroring the macOS `hudPlacement` setting.
///
/// The transparent canvas can end up taller than `HUD_HEIGHT` (WebKitGTK's
/// WebView enforces a ~200px natural minimum on Linux), so the pill inside
/// aligns itself to the matching canvas edge (`.hud-root.is-top/.is-bottom`)
/// and this uses the actual window height for the bottom edge.
fn position_hud(app: &AppHandle, window: &WebviewWindow) {
    let placement = app
        .state::<AppState>()
        .config()
        .visual_feedback
        .hud_placement;
    let Ok(Some(monitor)) = window.primary_monitor() else {
        let _ = window.center();
        return;
    };
    let scale = monitor.scale_factor();
    let screen_w = monitor.size().width as f64 / scale;
    let screen_h = monitor.size().height as f64 / scale;
    let window_h = window
        .outer_size()
        .map(|size| size.height as f64 / scale)
        .unwrap_or(HUD_HEIGHT)
        .max(HUD_HEIGHT);
    let x = (screen_w - HUD_WIDTH) / 2.0;
    let y = match placement {
        HudPlacement::Top => (screen_h * 0.06).max(12.0),
        HudPlacement::Bottom => (screen_h * 0.94 - window_h).max(12.0),
    };
    let _ = window.set_position(tauri::LogicalPosition::new(x.max(12.0), y));
}
