//! VibeCompose desktop shell: tray, global shortcut, windows, IPC.

mod commands;
mod session;
mod state;
mod windows;

use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Manager};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

use state::AppState;
use vc_core::config::HotkeyBindingConfig;

/// Maps the platform-neutral hotkey config ("F5", modifiers) to a shortcut
/// accepted by the global-shortcut plugin.
fn shortcut_from_config(config: &HotkeyBindingConfig) -> String {
    let mut parts: Vec<String> = config
        .modifiers
        .iter()
        .filter_map(|m| match m.as_str() {
            "cmd" => Some("CommandOrControl".to_string()),
            "ctrl" => Some("Control".to_string()),
            "alt" => Some("Alt".to_string()),
            "shift" => Some("Shift".to_string()),
            _ => None,
        })
        .collect();
    parts.push(config.key.clone());
    parts.join("+")
}

fn register_one(
    app: &AppHandle,
    binding: &HotkeyBindingConfig,
    on_press: impl Fn(&AppHandle) + Send + Sync + 'static,
) -> Result<(), String> {
    let accelerator = shortcut_from_config(binding);
    let shortcut: Shortcut = accelerator
        .parse()
        .map_err(|e| format!("invalid shortcut {accelerator}: {e}"))?;
    app.global_shortcut()
        .on_shortcut(shortcut, move |app, _shortcut, event| {
            if event.state() == ShortcutState::Pressed {
                on_press(app);
            }
        })
        .map_err(|e| e.to_string())?;
    Ok(())
}

pub fn reregister_shortcuts(app: &AppHandle) -> Result<(), String> {
    let _ = app.global_shortcut().unregister_all();
    register_dictation_shortcut(app)
}

fn register_dictation_shortcut(app: &AppHandle) -> Result<(), String> {
    let state = app.state::<AppState>();
    let config = state.config();

    register_one(app, &config.transcription.dictation_hotkey, |app| {
        let state = app.state::<AppState>();
        commands::toggle_dictation_inner(app, &state);
    })?;

    if let Some(binding) = config.skill_switcher_hotkey.clone() {
        if let Err(error) = register_one(app, &binding, |app| {
            windows::toggle_skill_switcher(app);
        }) {
            tracing::warn!("skill switcher shortcut not registered: {error}");
        }
    }
    if let Some(binding) = config.result_preview_hotkey.clone() {
        if let Err(error) = register_one(app, &binding, |app| {
            let state = app.state::<AppState>();
            if state.pending_preview().is_some() {
                let _ = tauri::Emitter::emit(app, "dictation-preview", state.pending_preview());
                windows::show_preview(app);
            }
        }) {
            tracing::warn!("result preview shortcut not registered: {error}");
        }
    }

    // Terminology Quick Add: the fixed reserved chord (Ctrl+Alt+Space), the
    // same as the macOS product. Config validation prevents other bindings
    // from claiming it.
    if let Err(error) = register_one(app, &HotkeyBindingConfig::quick_add(), |app| {
        windows::toggle_quick_add(app);
    }) {
        tracing::warn!("quick add shortcut not registered: {error}");
    }

    // ESC cancels only while a session is active; registered globally and
    // forwarded when idle would swallow every ESC press system-wide, so the
    // cancel path is exposed through the tray and UI instead. HUD-focused ESC
    // is handled by the webview.
    Ok(())
}

fn build_tray(app: &AppHandle) -> tauri::Result<()> {
    let toggle = MenuItem::with_id(app, "toggle", "开始/停止听写", true, None::<&str>)?;
    let cancel = MenuItem::with_id(app, "cancel", "取消当前会话", true, None::<&str>)?;
    let switcher = MenuItem::with_id(app, "switcher", "Skill 切换器", true, None::<&str>)?;
    let quick_add =
        MenuItem::with_id(app, "quick-add", "快速添加术语", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "设置…", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "退出 VibeCompose", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&toggle, &cancel, &switcher, &quick_add, &settings, &quit])?;

    TrayIconBuilder::with_id("main")
        .icon(app.default_window_icon().cloned().expect("icon"))
        .icon_as_template(true)
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "toggle" => {
                let state = app.state::<AppState>();
                commands::toggle_dictation_inner(app, &state);
            }
            "cancel" => {
                let state = app.state::<AppState>();
                if state.sessions.cancel() {
                    use tauri::Emitter;
                    let _ = app.emit("dictation-state", state.sessions.snapshot());
                    windows::hide_hud(app);
                }
            }
            "switcher" => windows::toggle_skill_switcher(app),
            "quick-add" => windows::toggle_quick_add(app),
            "settings" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info".into()),
        )
        .init();

    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let state = AppState::initialize();
            state.ensure_default_skills();
            app.manage(state);
            build_tray(app.handle())?;
            register_dictation_shortcut(app.handle())?;

            // Native window chrome: Windows DWM caption, Linux CSD.
            // macOS overlay titlebar only appears when debugging this
            // shell on a Mac; the shipping macOS app is SwiftUI.
            // Menu-bar style app: closing the settings window hides it.
            if let Some(window) = app.get_webview_window("main") {
                let handle = window.clone();
                window.on_window_event(move |event| {
                    if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                        api.prevent_close();
                        let _ = handle.hide();
                    }
                });
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_config,
            commands::save_config,
            commands::list_skills,
            commands::get_history,
            commands::delete_history_record,
            commands::clear_history,
            commands::set_openai_api_key,
            commands::get_account_status,
            commands::start_chatgpt_login,
            commands::cancel_chatgpt_login,
            commands::disconnect_chatgpt,
            commands::toggle_dictation,
            commands::cancel_dictation,
            commands::get_pending_preview,
            commands::confirm_preview,
            commands::copy_preview,
            commands::dismiss_preview,
            commands::open_result_preview,
            commands::open_skill_switcher,
            commands::hide_overlay,
            commands::set_default_skill,
            commands::reprocess_preview,
            commands::add_terminology_entry,
            commands::open_quick_add,
            commands::list_recovery,
            commands::delete_recovery,
            commands::retry_recovery,
            commands::list_style_capsules,
            commands::save_style_capsule,
            commands::delete_style_capsule,
            commands::summarize_style,
            commands::get_onboarding_complete,
            commands::complete_onboarding,
            commands::reset_onboarding,
            commands::export_diagnostics,
        ])
        .run(tauri::generate_context!())
        .expect("error while running VibeCompose");
}
