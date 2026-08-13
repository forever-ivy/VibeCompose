//! Failure recovery storage: when a dictation fails after audio was captured,
//! the WAV file plus ASR/polish text (when available) are kept in a bounded,
//! owner-only store so the user can retry or copy what survived. Ported from
//! Swift `RecoveryHistory` / `StoragePrivacy`.
//!
//! Trust boundary: recovery metadata can never select an arbitrary file path.
//! Audio file names are derived from the record UUID only, resolved paths must
//! stay inside the store's `Audio/` directory, symbolic links are rejected,
//! and payloads are validated as bounded RIFF/WAVE files before use.

use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::config::{create_private_dir, write_private};
use crate::history::parse_epoch_seconds;

pub const DEFAULT_RECOVERY_RECORD_LIMIT: usize = 10;
/// Recovery audio larger than this is never persisted or replayed.
pub const MAX_RECOVERY_AUDIO_BYTES: u64 = 25_000_000;
const MINIMUM_INDEX_READ_BYTES: u64 = 64_000;
const DEFAULT_INDEX_READ_BYTES: u64 = 1_000_000;

#[derive(Debug, thiserror::Error)]
pub enum RecoveryError {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error("Saved recovery audio is missing.")]
    Missing,
    #[error("VibeCompose blocked an unsafe recovery audio path.")]
    UnsafePath,
    #[error("VibeCompose blocked a symbolic link in recovery storage.")]
    SymbolicLink,
    #[error("Saved recovery audio is not a regular file.")]
    NotRegularFile,
    #[error("Saved recovery audio is not a valid WAV file.")]
    InvalidWaveFile,
    #[error("Saved recovery audio is too large to retry.")]
    PayloadTooLarge,
}

/// Bounded retention: newest `max_records` records, optionally no older than
/// `retention_hours`. `max_records == 0` clears the store.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RecoveryRetentionPolicy {
    pub max_records: usize,
    pub retention_hours: Option<u32>,
    pub now_epoch_seconds: i64,
}

impl RecoveryRetentionPolicy {
    pub fn new(max_records: usize, retention_hours: Option<u32>, now_epoch_seconds: i64) -> Self {
        Self {
            max_records,
            retention_hours: retention_hours.map(|hours| hours.max(1)),
            now_epoch_seconds,
        }
    }

    pub fn cutoff_epoch_seconds(&self) -> Option<i64> {
        self.retention_hours
            .map(|hours| self.now_epoch_seconds - i64::from(hours.max(1)) * 3_600)
    }
}

/// Input captured at the failure site; the store assigns the record identity.
#[derive(Debug, Clone)]
pub struct RecoveryRecordInput {
    /// RFC 3339 UTC timestamp.
    pub timestamp: String,
    pub source_audio_path: PathBuf,
    pub duration_ms: i64,
    pub asr_text: Option<String>,
    pub polish_text: Option<String>,
    pub app_name: Option<String>,
    pub app_id: Option<String>,
    pub outcome: String,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RecoveryRecord {
    pub id: Uuid,
    /// RFC 3339 UTC timestamp.
    pub timestamp: String,
    pub audio_duration_ms: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub asr_text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub polish_text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub app_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub app_bundle_identifier: Option<String>,
    pub outcome: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error_message: Option<String>,
}

impl RecoveryRecord {
    /// Audio file names are derived from the record id only; metadata can
    /// never point the store at an arbitrary path.
    pub fn audio_file_name(&self) -> String {
        format!("{}.wav", self.id)
    }
}

/// JSONL index (`recovery-history.jsonl`) plus an `Audio/` directory holding
/// one WAV per record. Every write re-validates and prunes both.
#[derive(Debug, Clone)]
pub struct RecoveryStore {
    directory: PathBuf,
    retained_limit: usize,
    maximum_read_bytes: u64,
}

impl RecoveryStore {
    pub fn new(directory: PathBuf) -> Self {
        Self::with_limits(
            directory,
            DEFAULT_RECOVERY_RECORD_LIMIT,
            DEFAULT_INDEX_READ_BYTES,
        )
    }

    pub fn with_limits(directory: PathBuf, retained_limit: usize, maximum_read_bytes: u64) -> Self {
        Self {
            directory,
            retained_limit,
            maximum_read_bytes: maximum_read_bytes.max(MINIMUM_INDEX_READ_BYTES),
        }
    }

    pub fn directory(&self) -> &Path {
        &self.directory
    }

    fn index_path(&self) -> PathBuf {
        self.directory.join("recovery-history.jsonl")
    }

    fn audio_directory(&self) -> PathBuf {
        self.directory.join("Audio")
    }

    /// Copies the source audio into the store and appends the record, then
    /// prunes to the retention policy. Returns the stored record.
    pub fn record(
        &self,
        input: &RecoveryRecordInput,
        retention: &RecoveryRetentionPolicy,
    ) -> Result<RecoveryRecord, RecoveryError> {
        self.ensure_secure_storage_directories()?;
        validate_source_audio(&input.source_audio_path)?;

        let mut records =
            self.load_recent(self.retained_limit.max(retention.max_records).max(1))?;
        let record = RecoveryRecord {
            id: Uuid::new_v4(),
            timestamp: input.timestamp.clone(),
            audio_duration_ms: input.duration_ms,
            asr_text: input.asr_text.clone(),
            polish_text: input.polish_text.clone(),
            app_name: input.app_name.clone(),
            app_bundle_identifier: input.app_id.clone(),
            outcome: input.outcome.clone(),
            error_message: input.error_message.clone(),
        };
        let destination = self.audio_directory().join(record.audio_file_name());
        std::fs::copy(&input.source_audio_path, &destination)?;
        restrict_file_permissions(&destination)?;

        records.push(record.clone());
        self.rewrite(retained(records, retention))?;
        Ok(record)
    }

    /// Bounded tail read of the index, oldest first, at most `limit` records.
    pub fn load_recent(&self, limit: usize) -> Result<Vec<RecoveryRecord>, RecoveryError> {
        let index = self.index_path();
        if !index.exists() {
            return Ok(Vec::new());
        }

        validate_existing_secure_directory(&self.directory)?;
        let metadata = std::fs::symlink_metadata(&index)?;
        if metadata.file_type().is_symlink() {
            return Err(RecoveryError::SymbolicLink);
        }
        if !metadata.is_file() {
            return Err(RecoveryError::NotRegularFile);
        }

        let mut records: Vec<RecoveryRecord> = tail_lines(&index, self.maximum_read_bytes)?
            .iter()
            .filter_map(|line| serde_json::from_str(line).ok())
            .collect();
        records.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));
        let excess = records.len().saturating_sub(limit);
        records.drain(0..excess);
        Ok(records)
    }

    /// Resolves and fully validates the audio path for a record: inside the
    /// store's audio directory, a regular non-symlink file, bounded size, and
    /// a RIFF/WAVE header.
    pub fn resolve_audio_path(&self, record: &RecoveryRecord) -> Result<PathBuf, RecoveryError> {
        validate_existing_secure_directory(&self.directory)?;
        let audio_directory = self.audio_directory();
        validate_existing_secure_directory(&audio_directory)?;

        let candidate = audio_directory.join(record.audio_file_name());
        if candidate.parent() != Some(audio_directory.as_path()) {
            return Err(RecoveryError::UnsafePath);
        }
        if !candidate.exists() {
            return Err(RecoveryError::Missing);
        }

        let metadata = std::fs::symlink_metadata(&candidate)?;
        if metadata.file_type().is_symlink() {
            return Err(RecoveryError::SymbolicLink);
        }
        if !metadata.is_file() {
            return Err(RecoveryError::NotRegularFile);
        }
        if metadata.len() > MAX_RECOVERY_AUDIO_BYTES {
            return Err(RecoveryError::PayloadTooLarge);
        }

        // Re-check containment through resolved symlinks in parent components.
        let resolved = candidate.canonicalize()?;
        let resolved_directory = audio_directory.canonicalize()?;
        if resolved.parent() != Some(resolved_directory.as_path()) {
            return Err(RecoveryError::UnsafePath);
        }
        if !has_wave_header(&resolved)? {
            return Err(RecoveryError::InvalidWaveFile);
        }
        Ok(resolved)
    }

    pub fn delete(&self, id: Uuid) -> Result<(), RecoveryError> {
        let records = self.load_recent(self.retained_limit.max(1_000))?;
        self.rewrite(records.into_iter().filter(|r| r.id != id).collect())
    }

    pub fn prune(&self, retention: &RecoveryRetentionPolicy) -> Result<(), RecoveryError> {
        let records =
            self.load_recent(retention.max_records.max(self.retained_limit).max(1_000))?;
        self.rewrite(retained(records, retention))
    }

    fn rewrite(&self, records: Vec<RecoveryRecord>) -> Result<(), RecoveryError> {
        if records.is_empty() {
            return self.clear_stored_recovery();
        }

        self.ensure_secure_storage_directories()?;
        let safe_records: Vec<RecoveryRecord> = records
            .into_iter()
            .filter(|record| {
                self.resolve_audio_path(record)
                    .and_then(|path| secure_file(&path))
                    .is_ok()
            })
            .collect();
        if safe_records.is_empty() {
            return self.clear_stored_recovery();
        }

        let mut out = String::new();
        for record in &safe_records {
            out.push_str(&serde_json::to_string(record).map_err(std::io::Error::other)?);
            out.push('\n');
        }
        write_private(&self.index_path(), out.as_bytes())?;

        let retained_names: std::collections::HashSet<String> = safe_records
            .iter()
            .map(RecoveryRecord::audio_file_name)
            .collect();
        for entry in std::fs::read_dir(self.audio_directory())? {
            let entry = entry?;
            let name = entry.file_name().to_string_lossy().into_owned();
            if !retained_names.contains(&name) {
                remove_dir_entry(&entry.path())?;
            }
        }
        Ok(())
    }

    fn ensure_secure_storage_directories(&self) -> Result<(), RecoveryError> {
        let audio_directory = self.audio_directory();
        if audio_directory.parent() != Some(self.directory.as_path()) {
            return Err(RecoveryError::UnsafePath);
        }
        ensure_secure_directory(&self.directory)?;
        ensure_secure_directory(&audio_directory)
    }

    fn clear_stored_recovery(&self) -> Result<(), RecoveryError> {
        if !self.directory.exists() {
            return Ok(());
        }
        validate_existing_secure_directory(&self.directory)?;

        let index = self.index_path();
        if index.exists() {
            std::fs::remove_file(&index)?;
        }

        let audio_directory = self.audio_directory();
        let Ok(metadata) = std::fs::symlink_metadata(&audio_directory) else {
            return Ok(());
        };
        if metadata.file_type().is_symlink() {
            std::fs::remove_file(&audio_directory)?;
            return Ok(());
        }
        if !metadata.is_dir() {
            std::fs::remove_file(&audio_directory)?;
            return Ok(());
        }
        for entry in std::fs::read_dir(&audio_directory)? {
            remove_dir_entry(&entry?.path())?;
        }
        create_private_dir(&audio_directory)?;
        Ok(())
    }
}

fn retained(
    records: Vec<RecoveryRecord>,
    policy: &RecoveryRetentionPolicy,
) -> Vec<RecoveryRecord> {
    if policy.max_records == 0 {
        return Vec::new();
    }
    let cutoff = policy.cutoff_epoch_seconds();
    let mut kept: Vec<RecoveryRecord> = records
        .into_iter()
        .filter(|record| match cutoff {
            None => true,
            Some(cutoff) => parse_epoch_seconds(&record.timestamp)
                .map(|ts| ts >= cutoff)
                .unwrap_or(true),
        })
        .collect();
    kept.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));
    let excess = kept.len().saturating_sub(policy.max_records);
    kept.drain(0..excess);
    kept
}

fn ensure_secure_directory(path: &Path) -> Result<(), RecoveryError> {
    if path.exists() {
        validate_existing_secure_directory(path)?;
    }
    create_private_dir(path)?;
    Ok(())
}

fn validate_existing_secure_directory(path: &Path) -> Result<(), RecoveryError> {
    let metadata = std::fs::symlink_metadata(path).map_err(|_| RecoveryError::Missing)?;
    if metadata.file_type().is_symlink() {
        return Err(RecoveryError::SymbolicLink);
    }
    if !metadata.is_dir() {
        return Err(RecoveryError::UnsafePath);
    }
    Ok(())
}

fn validate_source_audio(path: &Path) -> Result<(), RecoveryError> {
    let metadata = std::fs::symlink_metadata(path)?;
    if metadata.file_type().is_symlink() {
        return Err(RecoveryError::SymbolicLink);
    }
    if !metadata.is_file() {
        return Err(RecoveryError::NotRegularFile);
    }
    if metadata.len() > MAX_RECOVERY_AUDIO_BYTES {
        return Err(RecoveryError::PayloadTooLarge);
    }
    if !has_wave_header(path)? {
        return Err(RecoveryError::InvalidWaveFile);
    }
    Ok(())
}

fn secure_file(path: &Path) -> Result<(), RecoveryError> {
    let metadata = std::fs::symlink_metadata(path)?;
    if metadata.file_type().is_symlink() {
        return Err(RecoveryError::SymbolicLink);
    }
    if !metadata.is_file() {
        return Err(RecoveryError::NotRegularFile);
    }
    restrict_file_permissions(path)?;
    Ok(())
}

fn restrict_file_permissions(path: &Path) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    }
    #[cfg(not(unix))]
    {
        let _ = path;
    }
    Ok(())
}

fn remove_dir_entry(path: &Path) -> std::io::Result<()> {
    let metadata = std::fs::symlink_metadata(path)?;
    if metadata.is_dir() {
        std::fs::remove_dir_all(path)
    } else {
        std::fs::remove_file(path)
    }
}

fn has_wave_header(path: &Path) -> std::io::Result<bool> {
    let mut file = std::fs::File::open(path)?;
    let mut header = [0u8; 12];
    match file.read_exact(&mut header) {
        Ok(()) => Ok(&header[0..4] == b"RIFF" && &header[8..12] == b"WAVE"),
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => Ok(false),
        Err(e) => Err(e),
    }
}

/// Reads at most `maximum_bytes` from the end of a JSONL file, discarding a
/// leading partial line, so a corrupt or oversized index cannot cause an
/// unbounded read.
fn tail_lines(path: &Path, maximum_bytes: u64) -> std::io::Result<Vec<String>> {
    let mut file = std::fs::File::open(path)?;
    let length = file.metadata()?.len();
    let start = length.saturating_sub(maximum_bytes.max(1));
    file.seek(SeekFrom::Start(start))?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)?;
    let mut text = String::from_utf8_lossy(&buffer).into_owned();
    if start > 0 {
        match text.find('\n') {
            Some(index) => text = text.split_off(index + 1),
            None => return Ok(Vec::new()),
        }
    }
    Ok(text
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(str::to_string)
        .collect())
}

// ---------------------------------------------------------------------------
// Recovery previews (menu / settings list items)
// ---------------------------------------------------------------------------

pub const RECOVERY_PREVIEW_MAX_CHARS: usize = 120;
/// Shown when a record carries no usable application name; shells localize.
pub const UNKNOWN_RECOVERY_TARGET: &str = "Unknown target";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryHistoryKind {
    Audio,
    Asr,
    Polish,
}

impl RecoveryHistoryKind {
    pub const ALL: [RecoveryHistoryKind; 3] = [Self::Audio, Self::Asr, Self::Polish];

    pub fn code(&self) -> &'static str {
        match self {
            Self::Audio => "audio",
            Self::Asr => "asr",
            Self::Polish => "polish",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryCopyKind {
    AudioFile,
    Text,
}

/// A display-ready row for one aspect (audio / ASR text / polish text) of a
/// recovery record.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecoveryHistoryPreview {
    pub id: String,
    pub record_id: Uuid,
    pub kind: RecoveryHistoryKind,
    pub timestamp: String,
    pub text: String,
    pub copy_text: String,
    pub copy_kind: RecoveryCopyKind,
    pub target: String,
    pub outcome: String,
    pub error_message: Option<String>,
    pub audio_duration_ms: i64,
}

impl RecoveryHistoryPreview {
    /// Newest first; records without usable text for the requested kind are
    /// skipped.
    pub fn recent_items(
        records: &[RecoveryRecord],
        kind: RecoveryHistoryKind,
        limit: usize,
    ) -> Vec<RecoveryHistoryPreview> {
        let mut sorted: Vec<&RecoveryRecord> = records.iter().collect();
        sorted.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
        sorted
            .into_iter()
            .filter_map(|record| Self::make(record, kind))
            .take(limit)
            .collect()
    }

    fn make(record: &RecoveryRecord, kind: RecoveryHistoryKind) -> Option<RecoveryHistoryPreview> {
        let (display_text, copy_text, copy_kind) = match kind {
            RecoveryHistoryKind::Audio => (
                format!("{} WAV", formatted_duration(record.audio_duration_ms)),
                String::new(),
                RecoveryCopyKind::AudioFile,
            ),
            RecoveryHistoryKind::Asr => {
                let text = record.asr_text.as_deref()?.trim();
                if text.is_empty() {
                    return None;
                }
                (
                    collapsed_preview(text, RECOVERY_PREVIEW_MAX_CHARS),
                    text.to_string(),
                    RecoveryCopyKind::Text,
                )
            }
            RecoveryHistoryKind::Polish => {
                let text = record.polish_text.as_deref()?.trim();
                if text.is_empty() {
                    return None;
                }
                (
                    collapsed_preview(text, RECOVERY_PREVIEW_MAX_CHARS),
                    text.to_string(),
                    RecoveryCopyKind::Text,
                )
            }
        };

        let target = record
            .app_name
            .as_deref()
            .map(str::trim)
            .filter(|name| !name.is_empty())
            .unwrap_or(UNKNOWN_RECOVERY_TARGET)
            .to_string();

        Some(RecoveryHistoryPreview {
            id: format!("{}-{}", kind.code(), record.id),
            record_id: record.id,
            kind,
            timestamp: record.timestamp.clone(),
            text: display_text,
            copy_text,
            copy_kind,
            target,
            outcome: record.outcome.clone(),
            error_message: record.error_message.clone(),
            audio_duration_ms: record.audio_duration_ms,
        })
    }
}

fn collapsed_preview(text: &str, max_characters: usize) -> String {
    let collapsed = text
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
        .trim()
        .to_string();
    if collapsed.chars().count() <= max_characters {
        return collapsed;
    }
    let mut clipped: String = collapsed.chars().take(max_characters).collect();
    clipped.push_str("...");
    clipped
}

fn formatted_duration(duration_ms: i64) -> String {
    let seconds = duration_ms.max(0) / 1_000;
    format!("{:02}:{:02}", seconds / 60, seconds % 60)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn wav_bytes() -> Vec<u8> {
        let mut data = Vec::new();
        data.extend_from_slice(b"RIFF");
        data.extend_from_slice(&36u32.to_le_bytes());
        data.extend_from_slice(b"WAVE");
        data.extend_from_slice(&[0u8; 64]);
        data
    }

    fn write_wav(dir: &Path, name: &str) -> PathBuf {
        let path = dir.join(name);
        std::fs::write(&path, wav_bytes()).unwrap();
        path
    }

    fn input(source: PathBuf, timestamp: &str) -> RecoveryRecordInput {
        RecoveryRecordInput {
            timestamp: timestamp.into(),
            source_audio_path: source,
            duration_ms: 65_000,
            asr_text: Some("原始转写".into()),
            polish_text: None,
            app_name: Some("TextEdit".into()),
            app_id: Some("com.apple.textedit".into()),
            outcome: "transcriptionFailed".into(),
            error_message: Some("network".into()),
        }
    }

    fn policy(max_records: usize) -> RecoveryRetentionPolicy {
        RecoveryRetentionPolicy::new(max_records, Some(24), 1_770_000_000)
    }

    #[test]
    fn record_load_resolve_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let source = write_wav(dir.path(), "source.wav");
        let store = RecoveryStore::new(dir.path().join("Recovery"));
        let record = store
            .record(&input(source, "2026-08-12T10:00:00Z"), &policy(10))
            .unwrap();

        let loaded = store.load_recent(10).unwrap();
        assert_eq!(loaded, vec![record.clone()]);
        let audio = store.resolve_audio_path(&record).unwrap();
        assert!(audio.ends_with(record.audio_file_name()));
        assert!(audio.exists());
    }

    #[test]
    fn retention_keeps_newest_records_and_deletes_orphan_audio() {
        let dir = tempfile::tempdir().unwrap();
        let source = write_wav(dir.path(), "source.wav");
        let store = RecoveryStore::new(dir.path().join("Recovery"));
        for hour in 0..5 {
            store
                .record(
                    &input(source.clone(), &format!("2026-08-12T{hour:02}:00:00Z")),
                    &policy(3),
                )
                .unwrap();
        }
        let records = store.load_recent(10).unwrap();
        assert_eq!(records.len(), 3);
        assert_eq!(records[0].timestamp, "2026-08-12T02:00:00Z");
        let audio_files: Vec<_> = std::fs::read_dir(store.directory().join("Audio"))
            .unwrap()
            .collect();
        assert_eq!(audio_files.len(), 3);
    }

    #[test]
    fn prune_drops_records_older_than_cutoff() {
        let dir = tempfile::tempdir().unwrap();
        let source = write_wav(dir.path(), "source.wav");
        let store = RecoveryStore::new(dir.path().join("Recovery"));
        let loose = RecoveryRetentionPolicy::new(10, None, 0);
        store
            .record(&input(source.clone(), "2026-08-11T00:00:00Z"), &loose)
            .unwrap();
        store
            .record(&input(source, "2026-08-12T09:00:00Z"), &loose)
            .unwrap();

        let now = parse_epoch_seconds("2026-08-12T10:00:00Z").unwrap();
        store
            .prune(&RecoveryRetentionPolicy::new(10, Some(24), now))
            .unwrap();
        let records = store.load_recent(10).unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].timestamp, "2026-08-12T09:00:00Z");
    }

    #[test]
    fn zero_record_policy_clears_store() {
        let dir = tempfile::tempdir().unwrap();
        let source = write_wav(dir.path(), "source.wav");
        let store = RecoveryStore::new(dir.path().join("Recovery"));
        store
            .record(&input(source, "2026-08-12T10:00:00Z"), &policy(10))
            .unwrap();
        store
            .prune(&RecoveryRetentionPolicy::new(0, None, 0))
            .unwrap();
        assert!(store.load_recent(10).unwrap().is_empty());
        assert!(!store.directory().join("recovery-history.jsonl").exists());
    }

    #[test]
    fn delete_removes_record_and_audio() {
        let dir = tempfile::tempdir().unwrap();
        let source = write_wav(dir.path(), "source.wav");
        let store = RecoveryStore::new(dir.path().join("Recovery"));
        let a = store
            .record(&input(source.clone(), "2026-08-12T10:00:00Z"), &policy(10))
            .unwrap();
        let b = store
            .record(&input(source, "2026-08-12T11:00:00Z"), &policy(10))
            .unwrap();

        store.delete(a.id).unwrap();
        let records = store.load_recent(10).unwrap();
        assert_eq!(records, vec![b.clone()]);
        assert!(matches!(
            store.resolve_audio_path(&a),
            Err(RecoveryError::Missing)
        ));
        assert!(store.resolve_audio_path(&b).is_ok());
    }

    #[test]
    fn rejects_non_wave_source_audio() {
        let dir = tempfile::tempdir().unwrap();
        let bogus = dir.path().join("notes.wav");
        std::fs::write(&bogus, b"plain text, not audio").unwrap();
        let store = RecoveryStore::new(dir.path().join("Recovery"));
        assert!(matches!(
            store.record(&input(bogus, "2026-08-12T10:00:00Z"), &policy(10)),
            Err(RecoveryError::InvalidWaveFile)
        ));
    }

    #[cfg(unix)]
    #[test]
    fn rejects_symlinked_source_audio() {
        let dir = tempfile::tempdir().unwrap();
        let real = write_wav(dir.path(), "real.wav");
        let link = dir.path().join("link.wav");
        std::os::unix::fs::symlink(&real, &link).unwrap();
        let store = RecoveryStore::new(dir.path().join("Recovery"));
        assert!(matches!(
            store.record(&input(link, "2026-08-12T10:00:00Z"), &policy(10)),
            Err(RecoveryError::SymbolicLink)
        ));
    }

    #[test]
    fn tampered_audio_record_is_dropped_on_rewrite() {
        let dir = tempfile::tempdir().unwrap();
        let source = write_wav(dir.path(), "source.wav");
        let store = RecoveryStore::new(dir.path().join("Recovery"));
        let a = store
            .record(&input(source.clone(), "2026-08-12T10:00:00Z"), &policy(10))
            .unwrap();
        let b = store
            .record(&input(source, "2026-08-12T11:00:00Z"), &policy(10))
            .unwrap();

        // Corrupt A's audio payload; the next rewrite must drop the record.
        let audio_a = store.directory().join("Audio").join(a.audio_file_name());
        std::fs::write(&audio_a, b"no longer a wav").unwrap();
        store.prune(&policy(10)).unwrap();
        assert_eq!(store.load_recent(10).unwrap(), vec![b]);
    }

    #[test]
    fn preview_formats_audio_and_collapses_text() {
        let record = RecoveryRecord {
            id: Uuid::new_v4(),
            timestamp: "2026-08-12T10:00:00Z".into(),
            audio_duration_ms: 65_000,
            asr_text: Some("  第一行\n\n  第二行  \n".into()),
            polish_text: None,
            app_name: Some("  ".into()),
            app_bundle_identifier: None,
            outcome: "polishFailed".into(),
            error_message: None,
        };

        let audio = RecoveryHistoryPreview::recent_items(
            std::slice::from_ref(&record),
            RecoveryHistoryKind::Audio,
            5,
        );
        assert_eq!(audio.len(), 1);
        assert_eq!(audio[0].text, "01:05 WAV");
        assert_eq!(audio[0].copy_kind, RecoveryCopyKind::AudioFile);
        assert_eq!(audio[0].target, UNKNOWN_RECOVERY_TARGET);
        assert_eq!(audio[0].id, format!("audio-{}", record.id));

        let asr = RecoveryHistoryPreview::recent_items(
            std::slice::from_ref(&record),
            RecoveryHistoryKind::Asr,
            5,
        );
        assert_eq!(asr[0].text, "第一行 第二行");
        assert_eq!(asr[0].copy_text, "第一行\n\n  第二行");

        let polish =
            RecoveryHistoryPreview::recent_items(&[record], RecoveryHistoryKind::Polish, 5);
        assert!(polish.is_empty());
    }

    #[test]
    fn preview_truncates_long_text_and_sorts_newest_first() {
        let long_text = "字".repeat(200);
        let make = |timestamp: &str, text: &str| RecoveryRecord {
            id: Uuid::new_v4(),
            timestamp: timestamp.into(),
            audio_duration_ms: 1_000,
            asr_text: Some(text.into()),
            polish_text: None,
            app_name: Some("Mail".into()),
            app_bundle_identifier: None,
            outcome: "transcriptionFailed".into(),
            error_message: None,
        };
        let records = vec![
            make("2026-08-12T09:00:00Z", "旧"),
            make("2026-08-12T11:00:00Z", &long_text),
        ];
        let items = RecoveryHistoryPreview::recent_items(&records, RecoveryHistoryKind::Asr, 1);
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].timestamp, "2026-08-12T11:00:00Z");
        assert_eq!(
            items[0].text,
            format!("{}...", "字".repeat(RECOVERY_PREVIEW_MAX_CHARS))
        );
    }
}
