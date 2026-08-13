//! Pure decision logic for post-paste insertion verification, shared with the
//! Windows UIA backend: element token encode/decode, RuntimeId serialization,
//! text snapshot digests, and the expected-text matching policy. Free of any
//! platform calls so the trust rules stay unit-testable on every host.

/// Snapshot digests hash at most this many chars from each end of the text.
/// The digest also records the total char count, so any insertion that
/// changes the length is still detected in arbitrarily large documents.
const DIGEST_SAMPLE_CHARS: usize = 2048;

/// Above this length, containment is checked via head/tail fragments only:
/// hosts may rewrap or partially normalize very long pastes, and requiring a
/// full substring match would spuriously fail.
const LONG_EXPECTED_THRESHOLD_CHARS: usize = 512;
const LONG_EXPECTED_FRAGMENT_CHARS: usize = 256;

const TOKEN_PREFIX: &str = "uia-v1";

/// Which UIA pattern produced the pre-paste text snapshot. Verification must
/// read the same source again so representations stay comparable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SnapshotSource {
    Value,
    Text,
}

/// Length + sampled-hash digest of an element's text at capture time.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct TextDigest {
    pub char_count: u64,
    pub hash: u64,
}

/// Opaque `FocusedTarget::element_token` payload: the UIA RuntimeId that
/// re-identifies the element, plus an optional digest of its pre-paste text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ElementToken {
    pub runtime_id: Vec<i32>,
    pub snapshot: Option<(SnapshotSource, TextDigest)>,
}

impl ElementToken {
    /// Format: `uia-v1;rid=<i32.i32...>;src=<v|t|n>[;len=<u64>;hash=<u64 hex>]`.
    pub(crate) fn encode(&self) -> String {
        let rid = serialize_runtime_id(&self.runtime_id);
        match &self.snapshot {
            Some((source, digest)) => {
                let src = match source {
                    SnapshotSource::Value => "v",
                    SnapshotSource::Text => "t",
                };
                format!(
                    "{TOKEN_PREFIX};rid={rid};src={src};len={};hash={:016x}",
                    digest.char_count, digest.hash
                )
            }
            None => format!("{TOKEN_PREFIX};rid={rid};src=n"),
        }
    }

    /// Strict parse; any deviation yields `None` so verification degrades to
    /// the app-level foreground check instead of trusting a stale token.
    pub(crate) fn decode(token: &str) -> Option<Self> {
        let mut parts = token.split(';');
        if parts.next() != Some(TOKEN_PREFIX) {
            return None;
        }
        let mut rid: Option<Vec<i32>> = None;
        let mut src: Option<&str> = None;
        let mut len: Option<u64> = None;
        let mut hash: Option<u64> = None;
        for part in parts {
            let (key, value) = part.split_once('=')?;
            match key {
                "rid" => rid = Some(parse_runtime_id(value)?),
                "src" => src = Some(value),
                "len" => len = Some(value.parse().ok()?),
                "hash" => hash = Some(u64::from_str_radix(value, 16).ok()?),
                _ => return None,
            }
        }
        let runtime_id = rid?;
        if runtime_id.is_empty() {
            return None;
        }
        let snapshot = match src? {
            "n" => None,
            "v" => Some((
                SnapshotSource::Value,
                TextDigest {
                    char_count: len?,
                    hash: hash?,
                },
            )),
            "t" => Some((
                SnapshotSource::Text,
                TextDigest {
                    char_count: len?,
                    hash: hash?,
                },
            )),
            _ => return None,
        };
        Some(Self {
            runtime_id,
            snapshot,
        })
    }
}

pub(crate) fn serialize_runtime_id(ids: &[i32]) -> String {
    let mut out = String::new();
    for (index, id) in ids.iter().enumerate() {
        if index > 0 {
            out.push('.');
        }
        out.push_str(&id.to_string());
    }
    out
}

fn parse_runtime_id(text: &str) -> Option<Vec<i32>> {
    if text.is_empty() {
        return None;
    }
    text.split('.').map(|part| part.parse::<i32>().ok()).collect()
}

/// FNV-1a over a head sample + separator + tail sample, plus the total char
/// count. Sampling bounds the per-poll hashing cost on huge documents.
pub(crate) fn text_digest(text: &str) -> TextDigest {
    let char_count = text.chars().count() as u64;
    let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
    fnv1a_update(&mut hash, char_prefix(text, DIGEST_SAMPLE_CHARS).as_bytes());
    // 0xC0 never occurs in valid UTF-8, so head/tail runs cannot alias.
    fnv1a_update(&mut hash, &[0xC0]);
    fnv1a_update(&mut hash, char_suffix(text, DIGEST_SAMPLE_CHARS).as_bytes());
    TextDigest { char_count, hash }
}

fn fnv1a_update(state: &mut u64, bytes: &[u8]) {
    for &byte in bytes {
        *state ^= u64::from(byte);
        *state = state.wrapping_mul(0x0000_0100_0000_01B3);
    }
}

fn char_prefix(text: &str, max_chars: usize) -> &str {
    match text.char_indices().nth(max_chars) {
        Some((index, _)) => &text[..index],
        None => text,
    }
}

fn char_suffix(text: &str, max_chars: usize) -> &str {
    if max_chars == 0 {
        return "";
    }
    match text.char_indices().rev().nth(max_chars - 1) {
        Some((index, _)) => &text[index..],
        None => text,
    }
}

/// Containment policy for post-paste proof. Line endings are normalized on
/// both sides because Windows hosts commonly rewrite `\n` as `\r\n` on paste.
/// Long expected texts (> [`LONG_EXPECTED_THRESHOLD_CHARS`] chars) match by
/// head and tail fragments only.
pub(crate) fn text_contains_expected(haystack: &str, expected: &str) -> bool {
    if expected.is_empty() {
        // An empty expectation can never prove an insertion happened.
        return false;
    }
    let haystack = normalize_line_endings(haystack);
    let expected = normalize_line_endings(expected);
    if expected.chars().count() <= LONG_EXPECTED_THRESHOLD_CHARS {
        return haystack.contains(&expected);
    }
    let head = char_prefix(&expected, LONG_EXPECTED_FRAGMENT_CHARS);
    let tail = char_suffix(&expected, LONG_EXPECTED_FRAGMENT_CHARS);
    haystack.contains(head) && haystack.contains(tail)
}

fn normalize_line_endings(text: &str) -> String {
    text.replace("\r\n", "\n").replace('\r', "\n")
}

/// The full post-paste proof, given that the platform layer already proved
/// "same element" via RuntimeId: the current text must contain the expected
/// text AND differ from the pre-paste snapshot.
pub(crate) fn insertion_verified(
    current_text: &str,
    expected_text: &str,
    snapshot: TextDigest,
) -> bool {
    text_digest(current_text) != snapshot && text_contains_expected(current_text, expected_text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_id_serialization_is_stable() {
        assert_eq!(serialize_runtime_id(&[7, 42, -3]), "7.42.-3");
        assert_eq!(serialize_runtime_id(&[]), "");
        assert_eq!(parse_runtime_id("7.42.-3"), Some(vec![7, 42, -3]));
        assert_eq!(parse_runtime_id(""), None);
        assert_eq!(parse_runtime_id("1.two.3"), None);
    }

    #[test]
    fn token_round_trips_with_snapshot() {
        let value_token = ElementToken {
            runtime_id: vec![42, 4_460_498, 4, -1, i32::MAX, i32::MIN],
            snapshot: Some((SnapshotSource::Value, text_digest("hello 世界"))),
        };
        assert_eq!(
            ElementToken::decode(&value_token.encode()),
            Some(value_token.clone())
        );

        let text_token = ElementToken {
            snapshot: Some((SnapshotSource::Text, text_digest("document body"))),
            ..value_token
        };
        assert_eq!(ElementToken::decode(&text_token.encode()), Some(text_token));
    }

    #[test]
    fn token_round_trips_without_snapshot() {
        let token = ElementToken {
            runtime_id: vec![1],
            snapshot: None,
        };
        assert_eq!(ElementToken::decode(&token.encode()), Some(token));
    }

    #[test]
    fn token_decode_rejects_malformed_input() {
        assert_eq!(ElementToken::decode(""), None);
        assert_eq!(ElementToken::decode("ax-v1;rid=1.2;src=n"), None);
        assert_eq!(ElementToken::decode("uia-v1;rid=;src=n"), None);
        assert_eq!(ElementToken::decode("uia-v1;rid=1.two.3;src=n"), None);
        assert_eq!(ElementToken::decode("uia-v1;src=n"), None);
        assert_eq!(ElementToken::decode("uia-v1;rid=1.2"), None);
        assert_eq!(ElementToken::decode("uia-v1;rid=1.2;src=v"), None);
        assert_eq!(
            ElementToken::decode("uia-v1;rid=1.2;src=x;len=1;hash=0"),
            None
        );
        assert_eq!(ElementToken::decode("uia-v1;rid=1.2;src=n;bogus=1"), None);
    }

    #[test]
    fn short_expected_requires_exact_containment() {
        assert!(text_contains_expected("你好，世界！", "世界"));
        assert!(!text_contains_expected("你好，世界！", "宇宙"));
        assert!(!text_contains_expected("anything", ""));
    }

    #[test]
    fn long_expected_matches_by_head_and_tail_fragments() {
        // 720 distinct-ish chars, well above the 512-char threshold.
        let expected: String = (0..120).map(|i| format!("w{i:03} ")).collect();
        let head = char_prefix(&expected, LONG_EXPECTED_FRAGMENT_CHARS).to_string();
        let tail = char_suffix(&expected, LONG_EXPECTED_FRAGMENT_CHARS).to_string();

        // Host rewrapped/altered the middle; head + tail still prove the paste.
        let host_view = format!("prefix {head} …rewrapped middle… {tail} suffix");
        assert!(text_contains_expected(&host_view, &expected));

        // Missing tail fragment fails.
        assert!(!text_contains_expected(&format!("{head} only"), &expected));
        // Missing head fragment fails.
        assert!(!text_contains_expected(&format!("only {tail}"), &expected));
    }

    #[test]
    fn crlf_normalization_bridges_host_rewrites() {
        assert!(text_contains_expected("line1\r\nline2", "line1\nline2"));
        assert!(text_contains_expected("line1\nline2", "line1\r\nline2"));
        assert!(text_contains_expected("a\rb", "a\nb"));
    }

    #[test]
    fn digest_counts_chars_not_bytes() {
        assert_eq!(text_digest("héllo 世界").char_count, 8);
    }

    #[test]
    fn digest_detects_edge_changes_and_length_changes() {
        let base = "x".repeat(10_000);
        assert_eq!(text_digest(&base), text_digest(&base));
        assert_ne!(text_digest(&base), text_digest(&format!("{base}y")));
        assert_ne!(text_digest(&base), text_digest(&format!("y{base}")));

        // Same-length divergence confined to the unsampled middle is
        // intentionally invisible to the digest (conservative: verification
        // then stays inconclusive rather than falsely verified).
        let mut middle_changed: Vec<char> = base.chars().collect();
        middle_changed[5_000] = 'z';
        let middle_changed: String = middle_changed.into_iter().collect();
        assert_eq!(text_digest(&base), text_digest(&middle_changed));
    }

    #[test]
    fn head_and_tail_samples_alias_nothing() {
        // Identical concatenations split differently must not collide via the
        // separator byte.
        let long_head = format!("{}{}", "a".repeat(DIGEST_SAMPLE_CHARS), "b");
        let long_tail = format!("{}{}", "a", "b".repeat(DIGEST_SAMPLE_CHARS));
        assert_ne!(text_digest(&long_head), text_digest(&long_tail));
    }

    #[test]
    fn verification_requires_change_and_containment() {
        let snapshot = text_digest("draft: ");
        // Changed + contains expected -> verified.
        assert!(insertion_verified("draft: 你好世界", "你好世界", snapshot));
        // Expected already present but nothing changed -> not verified.
        let already = "你好世界";
        assert!(!insertion_verified(already, "你好世界", text_digest(already)));
        // Changed but expected missing -> not verified.
        assert!(!insertion_verified("draft: 别的", "你好世界", snapshot));
        // Empty expected -> never verified.
        assert!(!insertion_verified("changed", "", text_digest("before")));
    }
}
