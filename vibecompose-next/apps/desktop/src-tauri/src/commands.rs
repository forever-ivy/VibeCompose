//! Tauri IPC commands and the dictation workflow orchestration.

use std::sync::Arc;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State};

use vc_core::config::{validate_shortcut_set, AppConfig, SoundFeedbackEvent};
use vc_core::delivery::{DeliveryOutcome, OutputRoute};
use vc_core::history::{now_rfc3339, HistoryRecord, HistoryStore};
use vc_core::pipeline::{
    DictationPipeline, RecordedAudio, Transcriber, TranscriptionError, TranscriptionMetrics,
    TranscriptionResult,
};
use vc_core::polish::TextPolishing;
use vc_core::recovery::{RecoveryRecord, RecoveryRecordInput, RecoveryStore};
use vc_core::skill::prompt::SkillPromptContext;
use vc_core::skill::resolver::LaunchAppContext;
use vc_core::skill::{SkillDeliveryPolicy, SkillRiskLevel};
use vc_core::SkillResolver;
use vc_core::style::{
    builtin_style_capsules, resolve_style_capsule, summarize_style_samples, StyleCapsule,
    StyleCapsuleStore,
};
use vc_core::terminology::TerminologyNormalizer;
use vc_inject::{ClipboardAccess, DeliveryRequest, PlatformInjector};
use vc_providers::chatgpt_auth::{
    build_authorization_request, ensure_fresh_session, wait_for_callback_and_exchange_cancellable,
    AuthError, CancelHandle, ChatGptManagedPolisher, ChatGptManagedTranscriber, ChatGptSession,
    ChatGptSessionStore, DEFAULT_LOGIN_TIMEOUT,
};
use vc_providers::openai_compatible::{OpenAiCompatiblePolisher, OpenAiCompatibleTranscriber};

use crate::session::{
    history_path, now_epoch_seconds, onboarding_complete_path, recovery_dir, app_support_dir,
    SessionSnapshot,
};
use crate::state::{
    AppState, LastSource, PendingPreview, OPENAI_KEYRING_ACCOUNT, OPENAI_KEYRING_SERVICE,
};
use crate::windows;

/// Event payload describing the outcome of one dictation.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DictationResultEvent {
    pub session_id: u64,
    pub outcome: String,
    pub final_text: String,
    pub skill_id: String,
    pub skill_name: String,
    pub app_name: String,
    pub polish_attempted: bool,
    pub polish_error: Option<String>,
    pub duration_ms: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DictationErrorEvent {
    pub session_id: Option<u64>,
    pub message: String,
    pub retryable: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SkillSummary {
    pub id: String,
    pub version: String,
    pub name: String,
    pub summary: Option<String>,
    pub use_case: Option<String>,
    pub output_format: String,
    pub delivery: String,
    pub risk: String,
    pub enabled: bool,
    pub is_default: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountStatus {
    pub chatgpt_connected: bool,
    pub openai_key_present: bool,
    pub accessibility_permission_missing: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatGptLoginEvent {
    pub ok: bool,
    pub message: Option<String>,
}

fn emit_state(app: &AppHandle, snapshot: &SessionSnapshot) {
    let _ = app.emit("dictation-state", snapshot);
}

fn emit_sound(app: &AppHandle, config: &AppConfig, event: SoundFeedbackEvent) {
    if config.transcription.feedback_sounds_enabled {
        let _ = app.emit("sound-feedback", event.resource_name());
    }
}

#[tauri::command]
pub fn get_config(state: State<'_, AppState>) -> AppConfig {
    state.config()
}

#[tauri::command]
pub fn save_config(
    app: AppHandle,
    state: State<'_, AppState>,
    config: AppConfig,
) -> Result<(), String> {
    validate_shortcut_set(
        &config.transcription.dictation_hotkey,
        config.skill_switcher_hotkey.as_ref(),
        config.result_preview_hotkey.as_ref(),
    )
    .map_err(|e| e.to_string())?;
    state.save_config(config)?;
    crate::reregister_shortcuts(&app)
}

#[tauri::command]
pub fn list_skills(state: State<'_, AppState>) -> Vec<SkillSummary> {
    let config = state.config();
    let registry = state.registry();
    registry
        .all()
        .iter()
        .map(|skill| SkillSummary {
            id: skill.id.clone(),
            version: skill.version.clone(),
            name: skill.name.clone(),
            summary: skill.summary.clone(),
            use_case: skill.use_case.clone(),
            output_format: skill.output.format.code().to_string(),
            delivery: skill.output.delivery.code().to_string(),
            risk: format!("{:?}", skill.output.risk).to_lowercase(),
            enabled: config.transcription.skills.is_enabled(&skill.id),
            is_default: config.transcription.skills.default_skill_id == skill.id,
        })
        .collect()
}

#[tauri::command]
pub fn get_history(state: State<'_, AppState>) -> Result<Vec<HistoryRecord>, String> {
    let config = state.config();
    let store = HistoryStore::new(
        history_path(),
        config.privacy.history_record_limit,
        config.privacy.history_retention_days,
    );
    let mut records = store.read_all().map_err(|e| e.to_string())?;
    records.reverse();
    Ok(records)
}

#[tauri::command]
pub fn delete_history_record(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let config = state.config();
    let store = HistoryStore::new(
        history_path(),
        config.privacy.history_record_limit,
        config.privacy.history_retention_days,
    );
    let uuid = id.parse().map_err(|_| "invalid id".to_string())?;
    store.delete(uuid).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn clear_history(state: State<'_, AppState>) -> Result<(), String> {
    let config = state.config();
    HistoryStore::new(
        history_path(),
        config.privacy.history_record_limit,
        config.privacy.history_retention_days,
    )
    .clear()
    .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn set_openai_api_key(key: String) -> Result<(), String> {
    let entry = keyring::Entry::new(OPENAI_KEYRING_SERVICE, OPENAI_KEYRING_ACCOUNT)
        .map_err(|e| e.to_string())?;
    if key.trim().is_empty() {
        match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(e.to_string()),
        }
    } else {
        entry.set_password(key.trim()).map_err(|e| e.to_string())
    }
}

#[tauri::command]
pub fn get_account_status(state: State<'_, AppState>) -> AccountStatus {
    AccountStatus {
        chatgpt_connected: ChatGptSessionStore::load().is_some(),
        openai_key_present: crate::state::load_openai_key().is_some(),
        accessibility_permission_missing: state.injector_requires_permission(),
    }
}

#[tauri::command]
pub fn start_chatgpt_login(app: AppHandle, state: State<'_, AppState>) -> Result<String, String> {
    if let Some(previous) = state.take_login_cancel() {
        previous.cancel();
    }
    let request = build_authorization_request();
    let cancel = CancelHandle::new();
    state.set_login_cancel(cancel.clone());
    let url = request.url.clone();
    let pending = request.clone();
    let app_handle = app.clone();
    tauri::async_runtime::spawn(async move {
        let wait = wait_for_callback_and_exchange_cancellable(
            &pending,
            DEFAULT_LOGIN_TIMEOUT,
            cancel,
        );
        let open = async {
            tokio::time::sleep(std::time::Duration::from_millis(120)).await;
            let _ = tauri_plugin_opener::OpenerExt::opener(&app_handle)
                .open_url(url, None::<String>);
        };
        let (result, _) = tokio::join!(wait, open);
        let event = match result {
            Ok(_) => ChatGptLoginEvent {
                ok: true,
                message: None,
            },
            Err(AuthError::Cancelled) => ChatGptLoginEvent {
                ok: false,
                message: Some("已取消登录".into()),
            },
            Err(error) => ChatGptLoginEvent {
                ok: false,
                message: Some(error.to_string()),
            },
        };
        let _ = app_handle.emit("chatgpt-login", event);
    });
    Ok(request.state)
}

#[tauri::command]
pub fn cancel_chatgpt_login(state: State<'_, AppState>) {
    if let Some(cancel) = state.take_login_cancel() {
        cancel.cancel();
    }
}

#[tauri::command]
pub fn disconnect_chatgpt() -> Result<(), String> {
    ChatGptSessionStore::clear()
}

#[tauri::command]
pub fn cancel_dictation(app: AppHandle, state: State<'_, AppState>) {
    if state.sessions.cancel() {
        emit_state(&app, &state.sessions.snapshot());
        windows::hide_hud(&app);
    }
}

/// The single-trigger workflow: the configured shortcut starts recording and
/// the same shortcut stops recording and runs the pipeline.
#[tauri::command]
pub fn toggle_dictation(app: AppHandle, state: State<'_, AppState>) {
    toggle_dictation_inner(&app, &state);
}

pub fn toggle_dictation_inner(app: &AppHandle, state: &AppState) {
    if state.sessions.is_recording() {
        stop_and_process(app.clone(), state);
        return;
    }
    if !state.sessions.is_idle() {
        return; // Processing: ignore the trigger, matching single-flight rule.
    }

    windows::hide_preview(app);
    windows::hide_skill_switcher(app);

    let config = state.config();
    let recorder = vc_audio::AudioRecorder::new(
        config.transcription.sample_rate_hz,
        config.transcription.max_duration_seconds,
        crate::session::recordings_dir(),
    );
    let handle = match recorder.start() {
        Ok(handle) => handle,
        Err(error) => {
            let _ = app.emit(
                "dictation-error",
                DictationErrorEvent {
                    session_id: None,
                    message: error.to_string(),
                    retryable: false,
                },
            );
            return;
        }
    };

    // Freeze the launch application context at recording start.
    let (app_id, app_name) = state.frontmost_application();
    // Trust rule 5: context is read only for capabilities the frozen plan
    // declares, and never inside a sensitive application.
    let captured = capture_authorized_context(state, &config, app_id.as_deref());
    if state
        .sessions
        .begin_recording(handle, app_id, app_name, captured)
        .is_some()
    {
        emit_sound(app, &config, SoundFeedbackEvent::RecordingStarted);
        emit_state(app, &state.sessions.snapshot());
        windows::show_hud(app);
        state.start_level_ticker(app.clone());
    }
}

/// Reads selection / clipboard / focused-paragraph context at recording
/// start, mirroring the macOS "frozen at launch" semantics. Each source is
/// read only when the resolved plan's Skill declares the capability. The
/// macOS per-Skill consent dialog has no Tauri equivalent yet; the Skill
/// declaration plus the user's explicit enablement of that Skill is the
/// authorization gate on Windows/Linux.
fn capture_authorized_context(
    state: &AppState,
    config: &AppConfig,
    launch_app_id: Option<&str>,
) -> crate::session::CapturedContext {
    use vc_core::skill::SkillCapability;

    let sensitive = launch_app_id
        .map(|id| config.is_sensitive_app(id))
        .unwrap_or(false);
    if sensitive {
        return crate::session::CapturedContext::default();
    }

    let registry = state.registry();
    let plan = SkillResolver.resolve(
        &registry,
        None,
        &config.transcription.skills,
        Some(&LaunchAppContext {
            application_id: launch_app_id.map(str::to_string),
            application_name: None,
        }),
    );
    let capabilities = plan.skill.all_capabilities();
    let max_chars = vc_core::skill::prompt::MAX_SELECTION_CHARS;

    let selection = capabilities
        .contains(&SkillCapability::Selection)
        .then(|| state.injector.platform.read_selection())
        .flatten()
        .and_then(|text| vc_inject::context::clipped_snippet(&text, max_chars));
    let clipboard = capabilities
        .contains(&SkillCapability::Clipboard)
        .then(|| state.injector.clipboard.read_text())
        .flatten()
        .and_then(|text| vc_inject::context::clipped_snippet(&text, max_chars));
    let focused_paragraph = capabilities
        .contains(&SkillCapability::FocusedParagraph)
        .then(|| state.injector.platform.read_focused_text())
        .flatten()
        .and_then(|text| vc_inject::context::trailing_paragraph(&text, max_chars));

    crate::session::CapturedContext {
        selection,
        clipboard,
        focused_paragraph,
    }
}

fn stop_and_process(app: AppHandle, state: &AppState) {
    let Some((session_id, handle, launch_app_id, launch_app_name, captured)) =
        state.sessions.begin_processing()
    else {
        return;
    };
    emit_sound(&app, &state.config(), SoundFeedbackEvent::RecordingStopped);
    emit_state(&app, &state.sessions.snapshot());
    windows::show_hud(&app);

    let audio = match handle.stop() {
        Ok(audio) => audio,
        Err(error) => {
            state.sessions.finish(session_id);
            emit_state(&app, &state.sessions.snapshot());
            windows::hide_hud(&app);
            let _ = app.emit(
                "dictation-error",
                DictationErrorEvent {
                    session_id: Some(session_id),
                    message: error.to_string(),
                    retryable: false,
                },
            );
            return;
        }
    };

    spawn_pipeline(
        app,
        state,
        session_id,
        audio,
        launch_app_id,
        launch_app_name,
        None,
        true,
        None,
        captured,
    );
}

#[allow(clippy::too_many_arguments)]
fn spawn_pipeline(
    app: AppHandle,
    state: &AppState,
    session_id: u64,
    audio: RecordedAudio,
    launch_app_id: Option<String>,
    launch_app_name: Option<String>,
    skill_override: Option<String>,
    persist_recovery: bool,
    recovery_id: Option<uuid::Uuid>,
    captured: crate::session::CapturedContext,
) {
    let config = state.config();
    let registry = state.registry();
    let app_handle = app.clone();
    let sessions = Arc::clone(&state.sessions);
    let injector = Arc::clone(&state.injector);

    tauri::async_runtime::spawn(async move {
        let result = run_pipeline(
            &config,
            &registry,
            &audio,
            launch_app_id.as_deref(),
            launch_app_name.as_deref(),
            skill_override.as_deref(),
            None,
            &captured,
        )
        .await;

        // Rule 4: a late result may act only while its session is current.
        if !sessions.finish(session_id) {
            let _ = std::fs::remove_file(&audio.wav_path);
            return;
        }
        let _ = app_handle.emit("dictation-state", sessions.snapshot());

        let state = app_handle.state::<AppState>();
        match result {
            Ok((plan, prepared)) => {
                if persist_recovery {
                    let _ = std::fs::remove_file(&audio.wav_path);
                }
                if let Some(id) = recovery_id {
                    let _ = recovery_store(&config).delete(id);
                }
                state.set_last_source(LastSource {
                    raw_text: prepared.raw_text.clone(),
                    launch_app_id: launch_app_id.clone(),
                    launch_app_name: launch_app_name.clone(),
                    duration_ms: prepared.metrics.transcription.audio_duration_ms,
                    captured: captured.clone(),
                });

                let copy_only = plan.skill.output.delivery == SkillDeliveryPolicy::CopyOnly;
                let preview = PendingPreview {
                    session_id,
                    final_text: prepared.final_text.clone(),
                    raw_text: prepared.raw_text.clone(),
                    skill_id: plan.skill.id.clone(),
                    skill_name: plan.skill.name.clone(),
                    app_name: launch_app_name.clone().unwrap_or_default(),
                    app_id: launch_app_id.clone().unwrap_or_default(),
                    polish_attempted: prepared.metrics.text_polish_attempted,
                    polish_error: prepared.metrics.text_polish_error_message.clone(),
                    duration_ms: prepared.metrics.transcription.audio_duration_ms,
                    copy_only,
                };
                state.set_pending_preview(preview.clone());

                let route = output_route(&plan.skill.output.delivery, plan.skill.output.risk, &config);
                if route == OutputRoute::PreviewThenPaste {
                    windows::hide_hud(&app_handle);
                    let _ = app_handle.emit("dictation-preview", &preview);
                    windows::show_preview(&app_handle);
                    return;
                }

                finish_delivery(
                    &app_handle,
                    &state,
                    &config,
                    preview,
                    injector,
                    launch_app_id,
                    launch_app_name,
                )
                .await;
            }
            Err(error) => {
                if persist_recovery {
                    persist_failed_audio(
                        &config,
                        &audio,
                        launch_app_id.as_deref(),
                        launch_app_name.as_deref(),
                        &error,
                    );
                    let _ = std::fs::remove_file(&audio.wav_path);
                }
                windows::hide_hud(&app_handle);
                let _ = app_handle.emit(
                    "dictation-error",
                    DictationErrorEvent {
                        session_id: Some(session_id),
                        message: error.to_string(),
                        retryable: true,
                    },
                );
            }
        }
    });
}

fn output_route(
    delivery: &SkillDeliveryPolicy,
    risk: SkillRiskLevel,
    config: &AppConfig,
) -> OutputRoute {
    if risk == SkillRiskLevel::High {
        return OutputRoute::PreviewThenPaste;
    }
    match delivery {
        SkillDeliveryPolicy::AutomaticPasteWhenVerified => OutputRoute::AutomaticPasteWhenVerified,
        SkillDeliveryPolicy::PreviewThenPaste => {
            if config.injection.skip_result_preview_when_safe {
                OutputRoute::AutomaticPasteWhenVerified
            } else {
                OutputRoute::PreviewThenPaste
            }
        }
        SkillDeliveryPolicy::CopyOnly => OutputRoute::CopyOnly,
    }
}

async fn finish_delivery(
    app: &AppHandle,
    state: &AppState,
    config: &AppConfig,
    preview: PendingPreview,
    injector: Arc<vc_inject::TextInjector<vc_inject::NativeInjector, vc_inject::SystemClipboard>>,
    launch_app_id: Option<String>,
    launch_app_name: Option<String>,
) {
    let copy_only = preview.copy_only;
    let delivery = tauri::async_runtime::spawn_blocking({
        let text = preview.final_text.clone();
        let preserve = config.injection.preserve_clipboard;
        let restore_delay = config.injection.restore_delay_milliseconds;
        move || {
            injector.deliver(&DeliveryRequest {
                text: &text,
                preserve_clipboard: preserve,
                verification_deadline_ms: 500,
                restore_delay_ms: restore_delay,
                copy_only,
            })
        }
    })
    .await;

    let outcome = match delivery {
        Ok(Ok(report)) => report.outcome,
        _ => DeliveryOutcome::CopiedToClipboard(
            vc_core::delivery::ClipboardFallbackReason::PlatformUnsupported,
        ),
    };

    let sensitive = launch_app_id
        .as_deref()
        .map(|id| config.is_sensitive_app(id))
        .unwrap_or(false);
    if config.privacy.history_enabled && !sensitive {
        let store = HistoryStore::new(
            history_path(),
            config.privacy.history_record_limit,
            config.privacy.history_retention_days,
        );
        let _ = store.append(&HistoryRecord {
            id: uuid_from_session(preview.session_id),
            timestamp: now_rfc3339(),
            outcome: outcome.code().to_string(),
            final_text: preview.final_text.clone(),
            raw_text: config
                .privacy
                .store_raw_transcripts
                .then(|| preview.raw_text.clone()),
            app_name: launch_app_name.clone().unwrap_or_default(),
            app_id: launch_app_id.clone().unwrap_or_default(),
            skill_id: preview.skill_id.clone(),
            skill_name: preview.skill_name.clone(),
            skill_version: String::new(),
            text_polish_provider: None,
        });
    }

    windows::hide_hud(app);
    windows::hide_preview(app);
    let _ = app.emit(
        "dictation-result",
        DictationResultEvent {
            session_id: preview.session_id,
            outcome: outcome.code().to_string(),
            final_text: preview.final_text,
            skill_id: preview.skill_id,
            skill_name: preview.skill_name,
            app_name: launch_app_name.unwrap_or_else(|| preview.app_name),
            polish_attempted: preview.polish_attempted,
            polish_error: preview.polish_error,
            duration_ms: preview.duration_ms,
        },
    );
    let _ = state;
}

fn persist_failed_audio(
    config: &AppConfig,
    audio: &RecordedAudio,
    app_id: Option<&str>,
    app_name: Option<&str>,
    error: &TranscriptionError,
) {
    if !config.privacy.failed_audio_recovery_enabled {
        return;
    }
    if app_id
        .map(|id| config.is_sensitive_app(id))
        .unwrap_or(false)
    {
        return;
    }
    let store = RecoveryStore::new(recovery_dir());
    let retention = config
        .privacy
        .recovery_retention_policy(now_epoch_seconds());
    let _ = store.record(
        &RecoveryRecordInput {
            timestamp: now_rfc3339(),
            source_audio_path: audio.wav_path.clone(),
            duration_ms: audio.duration_ms,
            asr_text: None,
            polish_text: None,
            app_name: app_name.map(str::to_string),
            app_id: app_id.map(str::to_string),
            outcome: "failed".into(),
            error_message: Some(error.to_string()),
        },
        &retention,
    );
}

async fn run_pipeline(
    config: &AppConfig,
    registry: &vc_core::SkillRegistry,
    audio: &RecordedAudio,
    launch_app_id: Option<&str>,
    launch_app_name: Option<&str>,
    skill_override: Option<&str>,
    replay_text: Option<&str>,
    captured: &crate::session::CapturedContext,
) -> Result<
    (
        vc_core::skill::ResolvedSkillExecutionPlan,
        vc_core::pipeline::PreparedDictation,
    ),
    TranscriptionError,
> {
    let mut skills = config.transcription.skills.clone();
    if let Some(skill_id) = skill_override {
        skills.default_skill_id = skill_id.to_string();
        if !skills.enabled_skill_ids.iter().any(|id| id == skill_id) {
            skills.enabled_skill_ids.push(skill_id.to_string());
        }
    }
    let plan = SkillResolver.resolve(
        registry,
        skill_override,
        &skills,
        Some(&LaunchAppContext {
            application_id: launch_app_id.map(str::to_string),
            application_name: launch_app_name.map(str::to_string),
        }),
    );

    let style_store = StyleCapsuleStore::new(&app_support_dir());
    let available = style_store
        .load_all()
        .unwrap_or_else(|_| builtin_style_capsules());
    let style = resolve_style_capsule(&config.style_capsules, &available, &plan.skill);
    // Captured context flows in unconditionally; the prompt compiler injects
    // each section only when the plan's Skill holds the capability.
    let prompt_context = SkillPromptContext {
        style_capsule: style.map(|capsule| capsule.prompt_text()),
        selection: captured.selection.clone(),
        clipboard: captured.clipboard.clone(),
        focused_paragraph: captured.focused_paragraph.clone(),
    };

    let terminology = merged_terminology(config, &plan);
    let locale = config.app_language.clone().unwrap_or_else(|| "zh-CN".into());
    let punctuation = vc_core::TranscriptPunctuationPreference::parse(
        &config.transcription.punctuation_preference,
    );
    // macOS `promptHintTerms`: free hint terms plus enabled term-type
    // terminology originals steer the ASR spelling.
    let mut prompt_hint_terms = config.transcription.hint_terms.clone();
    prompt_hint_terms.extend(
        config
            .transcription
            .terminology
            .entries
            .iter()
            .filter(|e| {
                e.is_enabled && e.entry_type == vc_core::terminology::TerminologyEntryType::Term
            })
            .map(|e| e.original.clone()),
    );
    let transcription_prompt = vc_core::TranscriptionPromptBuilder.build_prompt(
        &prompt_hint_terms,
        config.transcription.speech_cleanup_enabled,
        punctuation,
        &locale,
    );
    let session = load_fresh_session().await?;
    let openai_key = crate::state::load_openai_key();

    let replay = replay_text.map(|text| ReplayTranscriber {
        text: text.to_string(),
        duration_ms: audio.duration_ms,
    });

    let managed_transcriber;
    let compatible_transcriber;
    let transcriber: &dyn Transcriber = if let Some(replay) = replay.as_ref() {
        replay
    } else if let Some(session) = &session {
        managed_transcriber = ChatGptManagedTranscriber::new(&session.access_token)
            .with_prompt(Some(transcription_prompt.clone()));
        &managed_transcriber
    } else if let Some(key) = &openai_key {
        compatible_transcriber = OpenAiCompatibleTranscriber::new(
            &config.transcription.open_ai_transcription_url,
            &config.transcription.open_ai_model,
            key,
        )
        .map_err(|e| TranscriptionError::Request(e.to_string()))?
        .with_prompt(Some(transcription_prompt.clone()));
        &compatible_transcriber
    } else {
        return Err(TranscriptionError::NotAuthenticated);
    };

    let polish = &config.transcription.text_polish;
    let managed_polisher;
    let compatible_polisher;
    let polisher: Option<&dyn TextPolishing> = if let Some(session) = &session {
        if polish.chat_gpt_auth_enabled {
            managed_polisher = ChatGptManagedPolisher::new(
                &session.access_token,
                &polish.chat_gpt_response_model,
                polish.glossary_budget_characters,
                plan.clone(),
                prompt_context.clone(),
                &locale,
            );
            Some(&managed_polisher)
        } else {
            None
        }
    } else if let Some(key) = &openai_key {
        match OpenAiCompatiblePolisher::new(
            &polish.open_ai_compatible_url,
            &polish.open_ai_compatible_model,
            key,
            polish.temperature,
            polish.max_output_tokens,
            polish.glossary_budget_characters,
            plan.clone(),
            prompt_context.clone(),
            &locale,
        ) {
            Ok(p) => {
                compatible_polisher = p;
                Some(&compatible_polisher)
            }
            Err(_) => None,
        }
    } else {
        None
    };

    let normalizer = TerminologyNormalizer::new(punctuation);
    let pipeline = DictationPipeline {
        transcriber,
        normalizer: &normalizer,
        imported_entries: terminology,
        hint_terms: config.transcription.hint_terms.clone(),
        text_polisher: polisher,
        polish_mode: polish.mode,
        plan: plan.clone(),
        prompt_context,
    };
    let prepared = pipeline.prepare(audio).await?;
    Ok((plan, prepared))
}

async fn load_fresh_session() -> Result<Option<ChatGptSession>, TranscriptionError> {
    if ChatGptSessionStore::load().is_none() {
        return Ok(None);
    }
    match ensure_fresh_session().await {
        Ok(session) => Ok(Some(session)),
        Err(AuthError::NotLoggedIn) => Ok(None),
        Err(error) => Err(TranscriptionError::Request(error.to_string())),
    }
}

struct ReplayTranscriber {
    text: String,
    duration_ms: i64,
}

#[async_trait::async_trait]
impl Transcriber for ReplayTranscriber {
    async fn transcribe(
        &self,
        _audio: &RecordedAudio,
    ) -> Result<TranscriptionResult, TranscriptionError> {
        Ok(TranscriptionResult {
            text: self.text.clone(),
            metrics: TranscriptionMetrics {
                audio_duration_ms: self.duration_ms,
                transcribe_ms: 0,
                audio_bytes: 0,
                provider: "replay".into(),
            },
        })
    }
}

/// User terminology first, then Skill-local entries (fixed priority order).
fn merged_terminology(
    config: &AppConfig,
    plan: &vc_core::skill::ResolvedSkillExecutionPlan,
) -> Vec<vc_core::terminology::TerminologyEntry> {
    let mut entries = Vec::new();
    if config.transcription.terminology.enabled {
        entries.extend(config.transcription.terminology.entries.iter().cloned());
    }
    entries.extend(plan.skill.terminology_entries.iter().cloned());
    entries
}

fn uuid_from_session(session_id: u64) -> uuid::Uuid {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let mut bytes = [0u8; 16];
    bytes[..8].copy_from_slice(&(nanos as u64).to_be_bytes());
    bytes[8..].copy_from_slice(&session_id.to_be_bytes());
    uuid::Builder::from_random_bytes(bytes).into_uuid()
}

// ---------------------------------------------------------------------------
// Preview / overlays
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn get_pending_preview(state: State<'_, AppState>) -> Option<PendingPreview> {
    state.pending_preview()
}

#[tauri::command]
pub async fn confirm_preview(
    app: AppHandle,
    state: State<'_, AppState>,
    text: Option<String>,
) -> Result<(), String> {
    let Some(mut preview) = state.pending_preview() else {
        return Err("没有待确认的预览".into());
    };
    if let Some(text) = text {
        preview.final_text = text;
        state.set_pending_preview(preview.clone());
    }
    let config = state.config();
    let injector = Arc::clone(&state.injector);
    let app_id = (!preview.app_id.is_empty()).then_some(preview.app_id.clone());
    let app_name = (!preview.app_name.is_empty()).then_some(preview.app_name.clone());
    finish_delivery(
        &app,
        &state,
        &config,
        preview,
        injector,
        app_id,
        app_name,
    )
    .await;
    Ok(())
}

#[tauri::command]
pub fn copy_preview(app: AppHandle, state: State<'_, AppState>) -> Result<(), String> {
    let Some(mut preview) = state.pending_preview() else {
        return Err("没有待确认的预览".into());
    };
    preview.copy_only = true;
    let config = state.config();
    let injector = Arc::clone(&state.injector);
    let app_id = (!preview.app_id.is_empty()).then_some(preview.app_id.clone());
    let app_name = (!preview.app_name.is_empty()).then_some(preview.app_name.clone());
    tauri::async_runtime::spawn(async move {
        let state = app.state::<AppState>();
        finish_delivery(&app, &state, &config, preview, injector, app_id, app_name).await;
    });
    Ok(())
}

#[tauri::command]
pub fn dismiss_preview(app: AppHandle) {
    windows::hide_preview(&app);
}

#[tauri::command]
pub fn open_result_preview(app: AppHandle, state: State<'_, AppState>) {
    if state.pending_preview().is_some() {
        let _ = app.emit("dictation-preview", state.pending_preview());
        windows::show_preview(&app);
    }
}

#[tauri::command]
pub fn open_skill_switcher(app: AppHandle) {
    windows::toggle_skill_switcher(&app);
}

#[tauri::command]
pub fn hide_overlay(app: AppHandle, label: String) {
    windows::hide_overlay(&app, &label);
}

#[tauri::command]
pub fn set_default_skill(app: AppHandle, state: State<'_, AppState>, id: String) -> Result<(), String> {
    let mut config = state.config();
    config.transcription.skills.default_skill_id = id;
    state.save_config(config)?;
    windows::hide_skill_switcher(&app);
    Ok(())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReprocessArgs {
    pub skill_id: String,
    pub source_text: String,
}

#[tauri::command]
pub async fn reprocess_preview(
    app: AppHandle,
    state: State<'_, AppState>,
    args: ReprocessArgs,
) -> Result<PendingPreview, String> {
    let source = state.last_source();
    let preview = state.pending_preview();
    let raw = if args.source_text.trim().is_empty() {
        source
            .as_ref()
            .map(|s| s.raw_text.clone())
            .or_else(|| preview.as_ref().map(|p| p.raw_text.clone()))
            .ok_or_else(|| "没有可重跑的转写".to_string())?
    } else {
        args.source_text.clone()
    };
    let duration_ms = source
        .as_ref()
        .map(|s| s.duration_ms)
        .or_else(|| preview.as_ref().map(|p| p.duration_ms))
        .unwrap_or(0);
    let launch_app_id = source.as_ref().and_then(|s| s.launch_app_id.clone());
    let launch_app_name = source.as_ref().and_then(|s| s.launch_app_name.clone());
    let captured = source
        .as_ref()
        .map(|s| s.captured.clone())
        .unwrap_or_default();

    let config = state.config();
    let registry = state.registry();
    let dummy = RecordedAudio {
        wav_path: std::env::temp_dir().join("vibecompose-replay.wav"),
        duration_ms,
        sample_rate_hz: config.transcription.sample_rate_hz,
    };
    let (plan, prepared) = run_pipeline(
        &config,
        &registry,
        &dummy,
        launch_app_id.as_deref(),
        launch_app_name.as_deref(),
        Some(&args.skill_id),
        Some(&raw),
        &captured,
    )
    .await
    .map_err(|e| e.to_string())?;

    let next = PendingPreview {
        session_id: preview.map(|p| p.session_id).unwrap_or(0),
        final_text: prepared.final_text,
        raw_text: prepared.raw_text,
        skill_id: plan.skill.id,
        skill_name: plan.skill.name,
        app_name: launch_app_name.unwrap_or_default(),
        app_id: launch_app_id.unwrap_or_default(),
        polish_attempted: prepared.metrics.text_polish_attempted,
        polish_error: prepared.metrics.text_polish_error_message,
        duration_ms,
        copy_only: plan.skill.output.delivery == SkillDeliveryPolicy::CopyOnly,
    };
    state.set_pending_preview(next.clone());
    state.set_last_source(LastSource {
        raw_text: next.raw_text.clone(),
        launch_app_id: (!next.app_id.is_empty()).then_some(next.app_id.clone()),
        launch_app_name: (!next.app_name.is_empty()).then_some(next.app_name.clone()),
        duration_ms,
        captured,
    });
    let _ = app.emit("dictation-preview", &next);
    Ok(next)
}

// ---------------------------------------------------------------------------
// Recovery
// ---------------------------------------------------------------------------

fn recovery_store(config: &AppConfig) -> RecoveryStore {
    RecoveryStore::with_limits(
        recovery_dir(),
        config.privacy.failed_audio_record_limit.max(1),
        1_000_000,
    )
}

#[tauri::command]
pub fn list_recovery(state: State<'_, AppState>) -> Result<Vec<RecoveryRecord>, String> {
    let config = state.config();
    let store = recovery_store(&config);
    let _ = store.prune(&config.privacy.recovery_retention_policy(now_epoch_seconds()));
    let mut records = store
        .load_recent(config.privacy.failed_audio_record_limit.max(1))
        .map_err(|e| e.to_string())?;
    records.reverse();
    Ok(records)
}

#[tauri::command]
pub fn delete_recovery(state: State<'_, AppState>, id: String) -> Result<(), String> {
    let uuid = id.parse().map_err(|_| "invalid id".to_string())?;
    recovery_store(&state.config())
        .delete(uuid)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn retry_recovery(app: AppHandle, state: State<'_, AppState>, id: String) -> Result<(), String> {
    if !state.sessions.is_idle() {
        return Err("当前有听写正在进行".into());
    }
    let uuid: uuid::Uuid = id.parse().map_err(|_| "invalid id".to_string())?;
    let config = state.config();
    let store = recovery_store(&config);
    let records = store
        .load_recent(config.privacy.failed_audio_record_limit.max(1))
        .map_err(|e| e.to_string())?;
    let record = records
        .into_iter()
        .find(|r| r.id == uuid)
        .ok_or_else(|| "找不到这条恢复记录".to_string())?;
    let path = store.resolve_audio_path(&record).map_err(|e| e.to_string())?;
    let Some(session_id) = state.sessions.begin_orphan_processing() else {
        return Err("当前有听写正在进行".into());
    };
    emit_state(&app, &state.sessions.snapshot());
    windows::show_hud(&app);
    let audio = RecordedAudio {
        wav_path: path,
        duration_ms: record.audio_duration_ms,
        sample_rate_hz: config.transcription.sample_rate_hz,
    };
    spawn_pipeline(
        app,
        &state,
        session_id,
        audio,
        record.app_bundle_identifier,
        record.app_name,
        None,
        false,
        Some(uuid),
        crate::session::CapturedContext::default(),
    );
    Ok(())
}

// ---------------------------------------------------------------------------
// Style capsules
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn list_style_capsules() -> Result<Vec<StyleCapsule>, String> {
    StyleCapsuleStore::new(&app_support_dir())
        .load_all()
        .map_err(|e| e.to_string())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StyleCapsuleDraft {
    pub id: Option<String>,
    pub name: String,
    pub summary: String,
    pub examples: Vec<String>,
}

#[tauri::command]
pub fn save_style_capsule(draft: StyleCapsuleDraft) -> Result<StyleCapsule, String> {
    let id = match draft.id {
        Some(id) if !id.trim().is_empty() => id,
        _ => {
            let slug: String = draft
                .name
                .chars()
                .flat_map(|c| {
                    if c.is_ascii_alphanumeric() {
                        Some(c.to_ascii_lowercase())
                    } else if c.is_whitespace() || matches!(c, '-' | '_' | '.') {
                        Some('-')
                    } else {
                        None
                    }
                })
                .collect();
            let slug = slug.trim_matches('-');
            let slug = if slug.len() < 3 { "custom-style" } else { slug };
            format!("user.{slug}")
        }
    };
    if !id.starts_with("user.") {
        return Err("内置写作风格不能修改".into());
    }
    let now = now_rfc3339();
    let capsule = StyleCapsule::new(
        id,
        &draft.name,
        &draft.summary,
        &draft.examples,
        now.clone(),
        now,
        false,
    );
    StyleCapsuleStore::new(&app_support_dir())
        .save(&capsule)
        .map_err(|e| e.to_string())?;
    Ok(capsule)
}

#[tauri::command]
pub fn delete_style_capsule(id: String) -> Result<(), String> {
    StyleCapsuleStore::new(&app_support_dir())
        .delete(&id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn summarize_style(samples: String) -> String {
    summarize_style_samples(&samples)
}

// ---------------------------------------------------------------------------
// Terminology Quick Add
// ---------------------------------------------------------------------------

const MAX_TERMINOLOGY_FIELD_CHARS: usize = 240;

/// Identity key for duplicate detection, ported from Swift
/// `TerminologyLibrary.identityKey`: entry type plus the case-folded,
/// trimmed original. (Swift also folds diacritics; lowercase is the
/// portable approximation.)
fn terminology_identity_key(
    entry_type: vc_core::terminology::TerminologyEntryType,
    original: &str,
) -> String {
    let type_code = match entry_type {
        vc_core::terminology::TerminologyEntryType::Term => "term",
        vc_core::terminology::TerminologyEntryType::Correction => "correction",
    };
    format!("{type_code}|{}", original.trim().to_lowercase())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminologyDraft {
    /// "term" | "correction"
    pub entry_type: String,
    pub original: String,
    pub replacement: String,
    /// Comma-separated aliases.
    pub aliases: String,
}

#[tauri::command]
pub fn add_terminology_entry(
    app: AppHandle,
    state: State<'_, AppState>,
    draft: TerminologyDraft,
) -> Result<(), String> {
    use vc_core::terminology::{TerminologyEntry, TerminologyEntryType};

    let entry_type = match draft.entry_type.as_str() {
        "correction" => TerminologyEntryType::Correction,
        _ => TerminologyEntryType::Term,
    };
    let original = draft.original.trim().to_string();
    if original.is_empty() || original.chars().count() > MAX_TERMINOLOGY_FIELD_CHARS {
        return Err("请输入不超过 240 字符的术语或错误文本。".into());
    }
    let replacement = draft.replacement.trim().to_string();
    if entry_type == TerminologyEntryType::Correction
        && (replacement.is_empty() || replacement.chars().count() > MAX_TERMINOLOGY_FIELD_CHARS)
    {
        return Err("纠错需要不超过 240 字符的替换文本。".into());
    }

    let mut seen_aliases = std::collections::HashSet::new();
    let aliases: Vec<String> = draft
        .aliases
        .split(',')
        .map(str::trim)
        .filter(|alias| {
            !alias.is_empty()
                && alias.chars().count() <= MAX_TERMINOLOGY_FIELD_CHARS
                && seen_aliases.insert(alias.to_lowercase())
        })
        .map(str::to_string)
        .collect();

    let mut config = state.config();
    let key = terminology_identity_key(entry_type, &original);
    let duplicate = config
        .transcription
        .terminology
        .entries
        .iter()
        .any(|existing| {
            terminology_identity_key(existing.entry_type, &existing.original) == key
        });
    if duplicate {
        return Err("相同术语或错误文本的条目已存在。".into());
    }

    config.transcription.terminology.entries.push(TerminologyEntry {
        id: uuid::Uuid::new_v4(),
        entry_type,
        original,
        replacement: (entry_type == TerminologyEntryType::Correction).then_some(replacement),
        aliases,
        is_enabled: true,
        source: "user".into(),
        usage_count: 0,
        created_at: now_rfc3339(),
    });
    state.save_config(config)?;
    windows::hide_quick_add(&app);
    Ok(())
}

#[tauri::command]
pub fn open_quick_add(app: AppHandle) {
    windows::toggle_quick_add(&app);
}

// ---------------------------------------------------------------------------
// Onboarding / diagnostics
// ---------------------------------------------------------------------------

#[tauri::command]
pub fn get_onboarding_complete() -> bool {
    onboarding_complete_path().is_file()
}

#[tauri::command]
pub fn complete_onboarding() -> Result<(), String> {
    let path = onboarding_complete_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::write(path, b"ok").map_err(|e| e.to_string())
}

#[tauri::command]
pub fn reset_onboarding() -> Result<(), String> {
    match std::fs::remove_file(onboarding_complete_path()) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.to_string()),
    }
}

#[tauri::command]
pub fn export_diagnostics(state: State<'_, AppState>) -> Result<String, String> {
    let config = state.config();
    if !config.privacy.diagnostics_enabled {
        return Err("诊断导出已在设置中关闭".into());
    }
    let recovery_count = recovery_store(&config)
        .load_recent(config.privacy.failed_audio_record_limit.max(1))
        .map(|r| r.len())
        .unwrap_or(0);
    let history_count = HistoryStore::new(
        history_path(),
        config.privacy.history_record_limit,
        config.privacy.history_retention_days,
    )
    .read_all()
    .map(|r| r.len())
    .unwrap_or(0);

    let payload = serde_json::json!({
        "product": "VibeCompose",
        "version": env!("CARGO_PKG_VERSION"),
        "os": std::env::consts::OS,
        "arch": std::env::consts::ARCH,
        "exportedAt": now_rfc3339(),
        "chatgptConnected": ChatGptSessionStore::load().is_some(),
        "openaiKeyPresent": crate::state::load_openai_key().is_some(),
        "accessibilityPermissionMissing": state.injector_requires_permission(),
        "onboardingComplete": onboarding_complete_path().is_file(),
        "dictationHotkey": config.transcription.dictation_hotkey,
        "skillSwitcherHotkey": config.skill_switcher_hotkey,
        "resultPreviewHotkey": config.result_preview_hotkey,
        "defaultSkillId": config.transcription.skills.default_skill_id,
        "enabledSkillIds": config.transcription.skills.enabled_skill_ids,
        "applicationRuleCount": config.transcription.skills.application_rules.len(),
        "polishMode": config.transcription.text_polish.mode,
        "feedbackSoundsEnabled": config.transcription.feedback_sounds_enabled,
        "styleCapsulesEnabled": config.style_capsules.enabled,
        "privacy": {
            "historyEnabled": config.privacy.history_enabled,
            "storeRawTranscripts": config.privacy.store_raw_transcripts,
            "failedAudioRecoveryEnabled": config.privacy.failed_audio_recovery_enabled,
            "excludeSensitiveApps": config.privacy.exclude_sensitive_apps,
        },
        "historyCount": history_count,
        "recoveryCount": recovery_count,
        "terminologyCount": config.transcription.terminology.entries.len(),
    });
    let path = app_support_dir().join(format!(
        "diagnostics-{}.json",
        now_epoch_seconds()
    ));
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::write(&path, serde_json::to_vec_pretty(&payload).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().into_owned())
}
