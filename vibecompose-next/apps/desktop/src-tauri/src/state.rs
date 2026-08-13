//! Shared application state: configuration, skill registry, session machine,
//! and the platform injector.

use std::sync::{Arc, Mutex, RwLock};

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

use vc_core::config::AppConfig;
use vc_core::skill::registry::SkillRegistry;
use vc_inject::{NativeInjector, PlatformInjector, SystemClipboard, TextInjector};
use vc_providers::chatgpt_auth::CancelHandle;

use crate::session::{config_path, SessionMachine};

pub const OPENAI_KEYRING_SERVICE: &str = "app.vibecompose.desktop.OpenAIKey";
pub const OPENAI_KEYRING_ACCOUNT: &str = "openai-compatible";

/// Last prepared dictation held for Preview confirm / Skill reprocess.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PendingPreview {
    pub session_id: u64,
    pub final_text: String,
    pub raw_text: String,
    pub skill_id: String,
    pub skill_name: String,
    pub app_name: String,
    pub app_id: String,
    pub polish_attempted: bool,
    pub polish_error: Option<String>,
    pub duration_ms: i64,
    pub copy_only: bool,
}

#[derive(Debug, Clone)]
pub struct LastSource {
    pub raw_text: String,
    pub launch_app_id: Option<String>,
    pub launch_app_name: Option<String>,
    pub duration_ms: i64,
    /// Context captured for the original session, reused on reprocess. The
    /// prompt compiler still gates injection by the new Skill's capabilities.
    pub captured: crate::session::CapturedContext,
}

pub struct AppState {
    config: RwLock<AppConfig>,
    registry: RwLock<Arc<SkillRegistry>>,
    pub sessions: Arc<SessionMachine>,
    pub injector: Arc<TextInjector<NativeInjector, SystemClipboard>>,
    level_ticker_running: Mutex<bool>,
    login_cancel: Mutex<Option<CancelHandle>>,
    pending_preview: Mutex<Option<PendingPreview>>,
    last_source: Mutex<Option<LastSource>>,
}

impl AppState {
    pub fn initialize() -> Self {
        let config = AppConfig::load(&config_path()).unwrap_or_default();
        let (registry, failures) = SkillRegistry::load_directory(&bundled_skills_dir());
        for (name, error) in &failures {
            tracing::warn!("skipped bundled skill {name}: {error}");
        }
        Self {
            config: RwLock::new(config),
            registry: RwLock::new(Arc::new(registry)),
            sessions: Arc::new(SessionMachine::new()),
            injector: Arc::new(vc_inject::native_injector()),
            level_ticker_running: Mutex::new(false),
            login_cancel: Mutex::new(None),
            pending_preview: Mutex::new(None),
            last_source: Mutex::new(None),
        }
    }

    pub fn config(&self) -> AppConfig {
        self.config.read().unwrap_or_else(|e| e.into_inner()).clone()
    }

    pub fn save_config(&self, mut config: AppConfig) -> Result<(), String> {
        config.transcription.text_polish = config.transcription.text_polish.clone().normalized();
        config.save(&config_path()).map_err(|e| e.to_string())?;
        *self.config.write().unwrap_or_else(|e| e.into_inner()) = config;
        Ok(())
    }

    /// Ensures first-run defaults: all bundled skills enabled, Direct as the
    /// global default.
    pub fn ensure_default_skills(&self) {
        let registry = self.registry();
        let mut config = self.config();
        if config.transcription.skills.enabled_skill_ids.is_empty() {
            config.transcription.skills.enabled_skill_ids =
                registry.all().iter().map(|s| s.id.clone()).collect();
        }
        if config.transcription.skills.default_skill_id.is_empty() {
            config.transcription.skills.default_skill_id =
                vc_core::skill::DIRECT_SKILL_ID.to_string();
        }
        let _ = self.save_config(config);
    }

    pub fn registry(&self) -> Arc<SkillRegistry> {
        Arc::clone(&self.registry.read().unwrap_or_else(|e| e.into_inner()))
    }

    pub fn injector_requires_permission(&self) -> bool {
        self.injector.platform.requires_permission()
    }

    /// Foreground application at recording start (skill rule context).
    pub fn frontmost_application(&self) -> (Option<String>, Option<String>) {
        match self.injector.platform.focused_target() {
            Some(target) => (
                (!target.application_id.is_empty()).then_some(target.application_id),
                (!target.application_name.is_empty()).then_some(target.application_name),
            ),
            None => (None, None),
        }
    }

    pub fn set_login_cancel(&self, handle: CancelHandle) {
        *self.login_cancel.lock().unwrap_or_else(|e| e.into_inner()) = Some(handle);
    }

    pub fn take_login_cancel(&self) -> Option<CancelHandle> {
        self.login_cancel
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
    }

    pub fn set_pending_preview(&self, preview: PendingPreview) {
        *self
            .pending_preview
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(preview);
    }

    pub fn pending_preview(&self) -> Option<PendingPreview> {
        self.pending_preview
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }

    pub fn set_last_source(&self, source: LastSource) {
        *self.last_source.lock().unwrap_or_else(|e| e.into_inner()) = Some(source);
    }

    pub fn last_source(&self) -> Option<LastSource> {
        self.last_source
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone()
    }

    /// Streams recording level/elapsed to the UI at ~20 Hz while recording.
    pub fn start_level_ticker(&self, app: AppHandle) {
        {
            let mut running = self
                .level_ticker_running
                .lock()
                .unwrap_or_else(|e| e.into_inner());
            if *running {
                return;
            }
            *running = true;
        }
        tauri::async_runtime::spawn(async move {
            loop {
                tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                let state = app.state::<AppState>();
                let snapshot = state.sessions.snapshot();
                let recording =
                    snapshot.phase == crate::session::SessionPhase::Recording;
                let _ = app.emit("dictation-state", &snapshot);
                if recording
                    && snapshot.elapsed_ms
                        >= i64::from(state.config().transcription.max_duration_seconds) * 1000
                {
                    // Hard recording limit: the same path as pressing the key.
                    crate::commands::toggle_dictation_inner(&app, &state);
                }
                if !recording {
                    let mut running = state
                        .level_ticker_running
                        .lock()
                        .unwrap_or_else(|e| e.into_inner());
                    *running = false;
                    break;
                }
            }
        });
    }
}

pub fn load_openai_key() -> Option<String> {
    let entry = keyring::Entry::new(OPENAI_KEYRING_SERVICE, OPENAI_KEYRING_ACCOUNT).ok()?;
    entry.get_password().ok().filter(|k| !k.is_empty())
}

/// Bundled skills directory: resolved relative to the executable in a
/// packaged app, with a dev-mode fallback to the repository layout.
pub fn bundled_skills_dir() -> std::path::PathBuf {
    if let Ok(exe) = std::env::current_exe() {
        // macOS bundle: Contents/MacOS/exe → Contents/Resources/skills
        if let Some(contents) = exe.parent().and_then(|p| p.parent()) {
            let bundled = contents.join("Resources/skills");
            if bundled.is_dir() {
                return bundled;
            }
        }
        // Windows/Linux: skills next to the executable.
        if let Some(dir) = exe.parent() {
            let bundled = dir.join("skills");
            if bundled.is_dir() {
                return bundled;
            }
        }
    }
    // Dev mode: repo layout (apps/desktop/src-tauri → ../../../skills).
    let dev = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../skills");
    if dev.is_dir() {
        return dev;
    }
    std::path::PathBuf::from("skills")
}
