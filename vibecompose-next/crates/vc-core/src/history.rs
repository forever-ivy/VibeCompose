//! Transcription history: bounded JSONL store with time/count pruning.
//! Raw ASR text is stored only when explicitly enabled; sensitive
//! applications are excluded upstream. Ported from Swift
//! `TranscriptionHistory` / `HistoryLibrary` (bounded-tail semantics).

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::config::write_private;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryRecord {
    #[serde(default = "Uuid::new_v4")]
    pub id: Uuid,
    /// RFC 3339 UTC timestamp.
    pub timestamp: String,
    pub outcome: String,
    pub final_text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub raw_text: Option<String>,
    #[serde(default)]
    pub app_name: String,
    #[serde(default)]
    pub app_id: String,
    #[serde(default)]
    pub skill_id: String,
    #[serde(default)]
    pub skill_name: String,
    #[serde(default)]
    pub skill_version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text_polish_provider: Option<String>,
}

#[derive(Debug, Clone)]
pub struct HistoryStore {
    path: PathBuf,
    pub record_limit: usize,
    pub retention_days: u32,
}

impl HistoryStore {
    pub fn new(path: PathBuf, record_limit: usize, retention_days: u32) -> Self {
        Self {
            path,
            record_limit,
            retention_days,
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn append(&self, record: &HistoryRecord) -> std::io::Result<()> {
        let mut records = self.read_all()?;
        records.push(record.clone());
        self.write_pruned(records)
    }

    /// Reads the trailing records without loading unbounded content: the file
    /// itself is pruned on every write, so a full read remains bounded.
    pub fn read_all(&self) -> std::io::Result<Vec<HistoryRecord>> {
        let Ok(data) = std::fs::read_to_string(&self.path) else {
            return Ok(Vec::new());
        };
        Ok(data
            .lines()
            .filter(|line| !line.trim().is_empty())
            .filter_map(|line| serde_json::from_str::<HistoryRecord>(line).ok())
            .collect())
    }

    pub fn delete(&self, id: Uuid) -> std::io::Result<()> {
        let records = self
            .read_all()?
            .into_iter()
            .filter(|r| r.id != id)
            .collect();
        self.write_pruned(records)
    }

    pub fn clear(&self) -> std::io::Result<()> {
        self.write_pruned(Vec::new())
    }

    /// Startup pruning: enforce record and age limits.
    pub fn prune(&self, now_epoch_seconds: i64) -> std::io::Result<()> {
        let mut records = self.read_all()?;
        let cutoff = now_epoch_seconds - i64::from(self.retention_days) * 86_400;
        records.retain(|record| {
            parse_epoch_seconds(&record.timestamp)
                .map(|ts| ts >= cutoff)
                .unwrap_or(true)
        });
        self.write_pruned(records)
    }

    fn write_pruned(&self, mut records: Vec<HistoryRecord>) -> std::io::Result<()> {
        if records.len() > self.record_limit {
            let excess = records.len() - self.record_limit;
            records.drain(0..excess);
        }
        if let Some(parent) = self.path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut out = String::new();
        for record in &records {
            out.push_str(&serde_json::to_string(record).map_err(std::io::Error::other)?);
            out.push('\n');
        }
        write_private(&self.path, out.as_bytes())
    }
}

/// Parses RFC 3339 UTC ("2026-08-12T10:24:56Z") into epoch seconds without a
/// date-time dependency; returns None for anything else.
pub(crate) fn parse_epoch_seconds(timestamp: &str) -> Option<i64> {
    let bytes = timestamp.as_bytes();
    if bytes.len() < 20 || bytes[4] != b'-' || bytes[7] != b'-' || bytes[10] != b'T' {
        return None;
    }
    let year: i64 = timestamp.get(0..4)?.parse().ok()?;
    let month: i64 = timestamp.get(5..7)?.parse().ok()?;
    let day: i64 = timestamp.get(8..10)?.parse().ok()?;
    let hour: i64 = timestamp.get(11..13)?.parse().ok()?;
    let minute: i64 = timestamp.get(14..16)?.parse().ok()?;
    let second: i64 = timestamp.get(17..19)?.parse().ok()?;
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    // Days since Unix epoch (civil-from-days algorithm, valid for year >= 1970).
    let y = if month <= 2 { year - 1 } else { year };
    let era = y / 400;
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(days * 86_400 + hour * 3_600 + minute * 60 + second)
}

pub fn now_rfc3339() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    epoch_to_rfc3339(now)
}

pub fn epoch_to_rfc3339(epoch: i64) -> String {
    // Inverse of civil-from-days.
    let days = epoch.div_euclid(86_400);
    let secs = epoch.rem_euclid(86_400);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if month <= 2 { y + 1 } else { y };
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year,
        month,
        day,
        secs / 3_600,
        (secs % 3_600) / 60,
        secs % 60
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(text: &str, timestamp: &str) -> HistoryRecord {
        HistoryRecord {
            id: Uuid::new_v4(),
            timestamp: timestamp.into(),
            outcome: "clipboard".into(),
            final_text: text.into(),
            raw_text: None,
            app_name: "TextEdit".into(),
            app_id: "com.apple.textedit".into(),
            skill_id: "app.vibecompose.skill.direct".into(),
            skill_name: "Direct".into(),
            skill_version: "1.2.0".into(),
            text_polish_provider: None,
        }
    }

    #[test]
    fn append_read_delete_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = HistoryStore::new(dir.path().join("history.jsonl"), 500, 30);
        let a = record("第一条", "2026-08-12T10:00:00Z");
        let b = record("第二条", "2026-08-12T11:00:00Z");
        store.append(&a).unwrap();
        store.append(&b).unwrap();
        assert_eq!(store.read_all().unwrap().len(), 2);
        store.delete(a.id).unwrap();
        let remaining = store.read_all().unwrap();
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].final_text, "第二条");
    }

    #[test]
    fn record_limit_drops_oldest() {
        let dir = tempfile::tempdir().unwrap();
        let store = HistoryStore::new(dir.path().join("history.jsonl"), 3, 30);
        for i in 0..5 {
            store
                .append(&record(&format!("记录{i}"), "2026-08-12T10:00:00Z"))
                .unwrap();
        }
        let records = store.read_all().unwrap();
        assert_eq!(records.len(), 3);
        assert_eq!(records[0].final_text, "记录2");
    }

    #[test]
    fn prune_removes_expired_records() {
        let dir = tempfile::tempdir().unwrap();
        let store = HistoryStore::new(dir.path().join("history.jsonl"), 500, 30);
        store.append(&record("old", "2026-06-01T00:00:00Z")).unwrap();
        store.append(&record("new", "2026-08-10T00:00:00Z")).unwrap();
        let now = parse_epoch_seconds("2026-08-12T00:00:00Z").unwrap();
        store.prune(now).unwrap();
        let records = store.read_all().unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].final_text, "new");
    }

    #[test]
    fn epoch_conversion_roundtrip() {
        let ts = "2026-08-12T10:24:56Z";
        let epoch = parse_epoch_seconds(ts).unwrap();
        assert_eq!(epoch_to_rfc3339(epoch), ts);
    }
}
