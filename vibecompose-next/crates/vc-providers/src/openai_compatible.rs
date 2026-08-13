//! User-owned OpenAI-compatible providers: multipart WAV transcription and
//! chat-completions polish. The user's API key is attached only to the
//! validated user-owned HTTPS endpoint.

use async_trait::async_trait;
use serde_json::json;

use vc_core::pipeline::{
    RecordedAudio, Transcriber, TranscriptionError, TranscriptionMetrics, TranscriptionResult,
};
use vc_core::polish::{PolishError, PolishedText, TextPolishProviderId, TextPolishing};
use vc_core::skill::prompt::{PolishMessage, SkillPromptCompiler, SkillPromptContext};
use vc_core::skill::ResolvedSkillExecutionPlan;
use vc_core::terminology::TerminologyEntry;

use crate::endpoint_policy::{secure_http_client, ManagedEndpointPolicy};

pub const MAX_AUDIO_UPLOAD_BYTES: u64 = 25 * 1024 * 1024;

/// Estimates tokens the same coarse way the Swift estimator does (~4 chars).
pub fn estimate_tokens(text: &str) -> u32 {
    (text.chars().count() as u32).div_ceil(4)
}

pub struct OpenAiCompatibleTranscriber {
    client: reqwest::Client,
    url: url::Url,
    model: String,
    api_key: String,
    /// Instruction prompt uploaded with the audio (`prompt` multipart field).
    prompt: Option<String>,
}

impl OpenAiCompatibleTranscriber {
    pub fn new(url: &str, model: &str, api_key: &str) -> Result<Self, TranscriptionError> {
        let url = ManagedEndpointPolicy::validated_user_owned_url(url)
            .map_err(|e| TranscriptionError::Request(e.to_string()))?;
        Ok(Self {
            client: secure_http_client(),
            url,
            model: model.to_string(),
            api_key: api_key.to_string(),
            prompt: None,
        })
    }

    pub fn with_prompt(mut self, prompt: Option<String>) -> Self {
        self.prompt = prompt.filter(|p| !p.trim().is_empty());
        self
    }
}

#[async_trait]
impl Transcriber for OpenAiCompatibleTranscriber {
    async fn transcribe(&self, audio: &RecordedAudio) -> Result<TranscriptionResult, TranscriptionError> {
        let metadata = tokio::fs::metadata(&audio.wav_path)
            .await
            .map_err(|e| TranscriptionError::InvalidAudio(e.to_string()))?;
        if !metadata.is_file() {
            return Err(TranscriptionError::InvalidAudio(
                "source audio is not a regular file".into(),
            ));
        }
        if metadata.len() > MAX_AUDIO_UPLOAD_BYTES {
            return Err(TranscriptionError::InvalidAudio(
                "recording exceeds the 25 MB upload limit".into(),
            ));
        }
        let bytes = tokio::fs::read(&audio.wav_path)
            .await
            .map_err(|e| TranscriptionError::InvalidAudio(e.to_string()))?;
        if bytes.len() < 12 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
            return Err(TranscriptionError::InvalidAudio(
                "recording does not contain a RIFF/WAVE header".into(),
            ));
        }
        let audio_bytes = bytes.len() as u64;

        let mut form = reqwest::multipart::Form::new()
            .text("model", self.model.clone())
            .part(
                "file",
                reqwest::multipart::Part::bytes(bytes)
                    .file_name("voice.wav")
                    .mime_str("audio/wav")
                    .map_err(|e| TranscriptionError::Request(e.to_string()))?,
            );
        if let Some(prompt) = &self.prompt {
            form = form.text("prompt", prompt.clone());
        }

        let started = std::time::Instant::now();
        let response = self
            .client
            .post(self.url.clone())
            .bearer_auth(&self.api_key)
            .multipart(form)
            .send()
            .await
            .map_err(|e| TranscriptionError::Request(e.to_string()))?;

        let status = response.status();
        let body = response
            .text()
            .await
            .map_err(|e| TranscriptionError::Request(e.to_string()))?;
        if !status.is_success() {
            return Err(TranscriptionError::Request(format!(
                "transcription endpoint returned {status}: {}",
                clip_error_body(&body)
            )));
        }
        let parsed: serde_json::Value = serde_json::from_str(&body)
            .map_err(|e| TranscriptionError::Request(e.to_string()))?;
        let text = parsed
            .get("text")
            .and_then(|t| t.as_str())
            .unwrap_or_default()
            .to_string();

        Ok(TranscriptionResult {
            text,
            metrics: TranscriptionMetrics {
                audio_duration_ms: audio.duration_ms,
                transcribe_ms: started.elapsed().as_millis() as i64,
                audio_bytes,
                provider: "openAICompatible".into(),
            },
        })
    }
}

/// Per-session polisher: the frozen execution plan and authorized context are
/// captured at construction, matching the "freeze at recording start" rule.
pub struct OpenAiCompatiblePolisher {
    client: reqwest::Client,
    url: url::Url,
    model: String,
    api_key: String,
    temperature: f64,
    max_output_tokens: u32,
    glossary_budget_characters: usize,
    plan: ResolvedSkillExecutionPlan,
    context: SkillPromptContext,
    locale: String,
}

impl OpenAiCompatiblePolisher {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        url: &str,
        model: &str,
        api_key: &str,
        temperature: f64,
        max_output_tokens: u32,
        glossary_budget_characters: usize,
        plan: ResolvedSkillExecutionPlan,
        context: SkillPromptContext,
        locale: &str,
    ) -> Result<Self, PolishError> {
        let url = ManagedEndpointPolicy::validated_user_owned_url(url)
            .map_err(|e| PolishError::Request(e.to_string()))?;
        Ok(Self {
            client: secure_http_client(),
            url,
            model: model.to_string(),
            api_key: api_key.to_string(),
            temperature,
            max_output_tokens,
            glossary_budget_characters,
            plan,
            context,
            locale: locale.to_string(),
        })
    }

    fn build_messages(
        &self,
        masked_text: &str,
        terminology_entries: &[TerminologyEntry],
    ) -> Vec<PolishMessage> {
        SkillPromptCompiler.compile(
            masked_text,
            terminology_entries,
            self.glossary_budget_characters,
            &self.plan,
            &self.context,
            &[],
            &self.locale,
        )
    }
}

#[async_trait]
impl TextPolishing for OpenAiCompatiblePolisher {
    async fn polish(
        &self,
        masked_text: &str,
        terminology_entries: &[TerminologyEntry],
        _hint_terms: &[String],
    ) -> Result<PolishedText, PolishError> {
        let messages = self.build_messages(masked_text, terminology_entries);
        let payload = json!({
            "model": self.model,
            "messages": messages.iter().map(|m| json!({
                "role": m.role,
                "content": m.content,
            })).collect::<Vec<_>>(),
            "temperature": self.temperature,
            "max_tokens": self.max_output_tokens,
        });

        let response = self
            .client
            .post(self.url.clone())
            .bearer_auth(&self.api_key)
            .json(&payload)
            .send()
            .await
            .map_err(|e| PolishError::Request(e.to_string()))?;

        let status = response.status();
        let body = response
            .text()
            .await
            .map_err(|e| PolishError::Request(e.to_string()))?;
        if !status.is_success() {
            return Err(PolishError::Request(format!(
                "polish endpoint returned {status}: {}",
                clip_error_body(&body)
            )));
        }
        let parsed: serde_json::Value =
            serde_json::from_str(&body).map_err(|e| PolishError::Request(e.to_string()))?;
        let text = parsed
            .pointer("/choices/0/message/content")
            .and_then(|c| c.as_str())
            .unwrap_or_default()
            .trim()
            .to_string();
        if text.is_empty() {
            return Err(PolishError::Request("polish response was empty".into()));
        }

        let input_chars: usize = messages.iter().map(|m| m.content.chars().count()).sum();
        Ok(PolishedText {
            estimated_input_tokens: (input_chars as u32).div_ceil(4),
            estimated_output_tokens: estimate_tokens(&text),
            text,
            provider: TextPolishProviderId::OpenAiCompatible,
        })
    }
}

/// Error bodies may echo user content; clip and flatten before logging.
fn clip_error_body(body: &str) -> String {
    body.chars().take(300).collect::<String>().replace('\n', " ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_estimation_is_ceiling_div_4() {
        assert_eq!(estimate_tokens(""), 0);
        assert_eq!(estimate_tokens("abcd"), 1);
        assert_eq!(estimate_tokens("abcde"), 2);
    }

    #[test]
    fn transcriber_rejects_non_https_endpoint() {
        assert!(OpenAiCompatibleTranscriber::new(
            "http://api.openai.com/v1/audio/transcriptions",
            "gpt-4o-mini-transcribe",
            "sk-x",
        )
        .is_err());
    }
}
