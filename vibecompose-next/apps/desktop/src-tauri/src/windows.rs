//! Overlay windows: dictation HUD, result preview, and Skill switcher.
//!
//! Labels are stable so the frontend can route by `getCurrentWindow().label`.
//! The HUD never steals focus; preview and the switcher do, because they
//! need explicit confirmation.

use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindow, WebviewWindowBuilder};

pub const HUD_LABEL: &str = "hud";
pub const PREVIEW_LABEL: &str = "preview";
pub const SWITCHER_LABEL: &str = "skill-switcher";
pub const QUICK_ADD_LABEL: &str = "quick-add";

pub fn show_hud(app: &AppHandle) {
    match app.get_webview_window(HUD_LABEL) {
        Some(window) => {
            let _ = window.show();
            position_hud(&window);
        }
        None => {
            if let Ok(window) = build_overlay(
                app,
                HUD_LABEL,
                "VibeCompose",
                340.0,
                96.0,
                false,
                false,
            ) {
                position_hud(&window);
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

pub fn show_preview(app: &AppHandle) {
    hide_hud(app);
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
    let window = WebviewWindowBuilder::new(app, label, WebviewUrl::App("/".into()))
        .title(title)
        .inner_size(width, height)
        .min_inner_size(width, height)
        .resizable(false)
        .decorations(decorations)
        .always_on_top(true)
        .skip_taskbar(true)
        .visible(false)
        .focused(focus)
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

fn position_hud(window: &WebviewWindow) {
    let Ok(Some(monitor)) = window.primary_monitor() else {
        let _ = window.center();
        return;
    };
    let scale = monitor.scale_factor();
    let screen = monitor.size();
    let width = 340.0;
    let x = (screen.width as f64 / scale - width) / 2.0;
    let y = (screen.height as f64 / scale) * 0.12;
    let _ = window.set_position(tauri::LogicalPosition::new(x.max(12.0), y.max(12.0)));
}
