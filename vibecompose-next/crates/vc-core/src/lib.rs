//! VibeCompose platform-independent core.
//!
//! One global dictation workflow:
//!
//! ```text
//! focus an editable target
//! → configured shortcut starts recording (default F5)
//! → the same shortcut stops recording
//! → transcribe
//! → normalize terminology
//! → optionally polish (Skill-shaped, validated)
//! → re-check the current target
//! → paste when proven safe, otherwise copy
//! ```
//!
//! Trust-boundary rules inherited from the original macOS implementation:
//! Skill packages are untrusted declarative data; managed tokens attach only
//! to approved HTTPS origins; async results mutate state only while their
//! session is current; selection is read only after per-Skill authorization;
//! delivery outcomes (verified / dispatched / copied) are never conflated.

pub mod config;
pub mod delivery;
pub mod history;
pub mod literal;
pub mod pipeline;
pub mod polish;
pub mod recovery;
pub mod skill;
pub mod style;
pub mod terminology;
pub mod transcription_prompt;
pub mod yamlite;

pub use config::{
    AppConfig, HotkeyBindingConfig, SoundFeedbackEvent, TranscriptPunctuationPreference,
};
pub use delivery::{ClipboardFallbackReason, DeliveryOutcome, OutputRoute};
pub use pipeline::{
    DictationMetrics, DictationPipeline, PreparedDictation, RecordedAudio, Transcriber,
    TranscriptionError, TranscriptionMetrics, TranscriptionResult,
};
pub use polish::{TextPolishMode, TextPolishing};
pub use recovery::{
    RecoveryError, RecoveryHistoryKind, RecoveryHistoryPreview, RecoveryRecord,
    RecoveryRecordInput, RecoveryRetentionPolicy, RecoveryStore,
};
pub use skill::registry::SkillRegistry;
pub use skill::resolver::{LaunchAppContext, SkillResolver, SkillsConfig};
pub use style::{
    builtin_style_capsules, resolve_style_capsule, summarize_style_samples, StyleCapsule,
    StyleCapsuleConfig, StyleCapsuleError, StyleCapsuleStore,
};
pub use terminology::{TerminologyEntry, TerminologyNormalizer, TranscriptNormalizing};
pub use transcription_prompt::TranscriptionPromptBuilder;
