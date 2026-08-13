//! Dictation session state machine.
//!
//! This replaces the Swift `AppCoordinator`'s coordinator-owned state fields
//! with the dedicated session model its architecture docs called for:
//!
//! ```text
//! idle → recording(session) → processing(session)
//!      → delivered | error → idle
//! ```
//!
//! Rule 4 of the trust boundary: an asynchronous result may mutate UI,
//! storage, or paste state only while its dictation session is still
//! current. Every async completion checks the session id before acting.

use std::path::PathBuf;
use std::sync::Mutex;

use serde::Serialize;
use vc_audio::RecordingHandle;

/// Context snippets captured at recording start, gated by the frozen plan's
/// declared capabilities (trust rule 5) before any read happens.
#[derive(Debug, Clone, Default)]
pub struct CapturedContext {
    pub selection: Option<String>,
    pub clipboard: Option<String>,
    pub focused_paragraph: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum SessionPhase {
    Idle,
    Recording,
    Processing,
}

/// Snapshot pushed to the UI on every transition.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionSnapshot {
    pub phase: SessionPhase,
    pub session_id: Option<u64>,
    pub elapsed_ms: i64,
    pub level: f32,
}

pub enum SessionState {
    Idle,
    Recording {
        session_id: u64,
        handle: RecordingHandle,
        /// Foreground app captured at recording start (frozen skill context).
        launch_app_id: Option<String>,
        launch_app_name: Option<String>,
        /// Authorized context captured at recording start.
        captured: CapturedContext,
    },
    Processing {
        session_id: u64,
    },
}

pub struct SessionMachine {
    state: Mutex<SessionState>,
    counter: std::sync::atomic::AtomicU64,
}

impl SessionMachine {
    pub fn new() -> Self {
        Self {
            state: Mutex::new(SessionState::Idle),
            counter: std::sync::atomic::AtomicU64::new(0),
        }
    }

    pub fn snapshot(&self) -> SessionSnapshot {
        let state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        match &*state {
            SessionState::Idle => SessionSnapshot {
                phase: SessionPhase::Idle,
                session_id: None,
                elapsed_ms: 0,
                level: 0.0,
            },
            SessionState::Recording {
                session_id, handle, ..
            } => SessionSnapshot {
                phase: SessionPhase::Recording,
                session_id: Some(*session_id),
                elapsed_ms: handle.elapsed_ms(),
                level: handle.level(),
            },
            SessionState::Processing { session_id } => SessionSnapshot {
                phase: SessionPhase::Processing,
                session_id: Some(*session_id),
                elapsed_ms: 0,
                level: 0.0,
            },
        }
    }

    /// Transitions idle → recording. Returns None when not idle.
    pub fn begin_recording(
        &self,
        handle: RecordingHandle,
        launch_app_id: Option<String>,
        launch_app_name: Option<String>,
        captured: CapturedContext,
    ) -> Option<u64> {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if !matches!(*state, SessionState::Idle) {
            return None;
        }
        let session_id = self
            .counter
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
            + 1;
        *state = SessionState::Recording {
            session_id,
            handle,
            launch_app_id,
            launch_app_name,
            captured,
        };
        Some(session_id)
    }

    /// Transitions recording → processing, returning the recording handle and
    /// frozen launch context for the pipeline.
    #[allow(clippy::type_complexity)]
    pub fn begin_processing(
        &self,
    ) -> Option<(u64, RecordingHandle, Option<String>, Option<String>, CapturedContext)> {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        let current = std::mem::replace(&mut *state, SessionState::Idle);
        match current {
            SessionState::Recording {
                session_id,
                handle,
                launch_app_id,
                launch_app_name,
                captured,
            } => {
                *state = SessionState::Processing { session_id };
                Some((session_id, handle, launch_app_id, launch_app_name, captured))
            }
            other => {
                *state = other;
                None
            }
        }
    }

    /// Completes the given session (only if still current) and returns to idle.
    pub fn finish(&self, session_id: u64) -> bool {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        match &*state {
            SessionState::Processing { session_id: current } if *current == session_id => {
                *state = SessionState::Idle;
                true
            }
            _ => false,
        }
    }

    /// Cancels whatever is in flight. A recording is discarded (temporary
    /// audio deleted by the handle); a processing session is orphaned so its
    /// late result fails the `finish` check and cannot mutate state.
    pub fn cancel(&self) -> bool {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        match std::mem::replace(&mut *state, SessionState::Idle) {
            SessionState::Idle => false,
            SessionState::Recording { handle, .. } => {
                handle.cancel();
                true
            }
            SessionState::Processing { .. } => true,
        }
    }

    pub fn is_recording(&self) -> bool {
        matches!(
            &*self.state.lock().unwrap_or_else(|e| e.into_inner()),
            SessionState::Recording { .. }
        )
    }

    pub fn is_idle(&self) -> bool {
        matches!(
            &*self.state.lock().unwrap_or_else(|e| e.into_inner()),
            SessionState::Idle
        )
    }

    /// Starts a processing session without a live recording (recovery retry).
    pub fn begin_orphan_processing(&self) -> Option<u64> {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if !matches!(*state, SessionState::Idle) {
            return None;
        }
        let session_id = self
            .counter
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
            + 1;
        *state = SessionState::Processing { session_id };
        Some(session_id)
    }
}

impl Default for SessionMachine {
    fn default() -> Self {
        Self::new()
    }
}

/// Application support directory: `~/Library/Application Support/VibeComposeX`
/// on macOS, `%APPDATA%/VibeComposeX` on Windows, XDG data dir on Linux.
pub fn app_support_dir() -> PathBuf {
    dirs::data_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join("VibeComposeX")
}

pub fn config_path() -> PathBuf {
    app_support_dir().join("config.json")
}

pub fn history_path() -> PathBuf {
    app_support_dir().join("transcription-history.jsonl")
}

pub fn recordings_dir() -> PathBuf {
    std::env::temp_dir()
}

pub fn recovery_dir() -> PathBuf {
    app_support_dir().join("Recovery")
}

pub fn onboarding_complete_path() -> PathBuf {
    app_support_dir().join("onboarding-complete")
}

pub fn now_epoch_seconds() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}
