//! Managed endpoint policy: a managed ChatGPT token can only be attached to
//! the built-in approved HTTPS origins and paths, and the OAuth flow may only
//! talk to the built-in issuer token endpoint. Ported from Swift
//! `ManagedEndpointPolicy`.

use thiserror::Error;
use url::Url;

pub const TRANSCRIPTION_URL: &str = "https://chatgpt.com/backend-api/transcribe";
pub const RESPONSES_URL: &str = "https://chatgpt.com/backend-api/codex/responses";
pub const MODELS_URL: &str = "https://chatgpt.com/backend-api/codex/models";
pub const OAUTH_TOKEN_URL: &str = "https://auth.openai.com/oauth/token";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ManagedEndpointKind {
    Transcription,
    Responses,
    /// Account-scoped model catalog; query may only add `client_version`.
    Models,
    /// OAuth token endpoint on the issuer origin (code exchange + refresh).
    OAuthToken,
}

impl ManagedEndpointKind {
    pub fn approved_url(&self) -> Url {
        let raw = match self {
            Self::Transcription => TRANSCRIPTION_URL,
            Self::Responses => RESPONSES_URL,
            Self::Models => MODELS_URL,
            Self::OAuthToken => OAUTH_TOKEN_URL,
        };
        Url::parse(raw).expect("built-in endpoint must parse")
    }
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum EndpointPolicyError {
    #[error("the configured endpoint is invalid: {0}")]
    InvalidUrl(String),
    #[error("VibeCompose blocked a non-approved endpoint for the managed ChatGPT session")]
    DisallowedManagedEndpoint(String),
}

pub struct ManagedEndpointPolicy;

impl ManagedEndpointPolicy {
    /// Validates a candidate URL against the fixed managed endpoint set:
    /// https-only, the approved endpoint's exact host, default port, no
    /// credentials, exact path, no fragment; every kind except the model
    /// catalog additionally allows no query.
    pub fn validated_url(candidate: &Url, kind: ManagedEndpointKind) -> Result<Url, EndpointPolicyError> {
        let expected = kind.approved_url();
        let disallowed =
            || EndpointPolicyError::DisallowedManagedEndpoint(candidate.to_string());

        if candidate.scheme().to_lowercase() != "https" {
            return Err(disallowed());
        }
        let host = candidate.host_str().map(str::to_lowercase);
        let expected_host = expected.host_str().map(str::to_lowercase);
        if host.is_none() || host != expected_host {
            return Err(disallowed());
        }
        if !matches!(candidate.port(), None | Some(443)) {
            return Err(disallowed());
        }
        if !candidate.username().is_empty() || candidate.password().is_some() {
            return Err(disallowed());
        }
        if candidate.path() != expected.path() {
            return Err(disallowed());
        }
        if candidate.fragment().is_some() {
            return Err(disallowed());
        }

        match kind {
            ManagedEndpointKind::Transcription
            | ManagedEndpointKind::Responses
            | ManagedEndpointKind::OAuthToken => {
                if candidate.query().is_some() {
                    return Err(disallowed());
                }
                Ok(expected)
            }
            ManagedEndpointKind::Models => {
                let pairs: Vec<(String, String)> = candidate
                    .query_pairs()
                    .map(|(k, v)| (k.to_string(), v.to_string()))
                    .collect();
                if pairs.is_empty() {
                    return Ok(expected);
                }
                let valid = pairs.len() == 1
                    && pairs[0].0 == "client_version"
                    && !pairs[0].1.is_empty()
                    && pairs[0].1.chars().all(|c| c.is_ascii() && !c.is_whitespace());
                if !valid {
                    return Err(disallowed());
                }
                Ok(candidate.clone())
            }
        }
    }

    pub fn models_list_url(client_version: &str) -> Result<Url, EndpointPolicyError> {
        let trimmed = client_version.trim();
        if trimmed.is_empty() {
            return Self::validated_url(
                &ManagedEndpointKind::Models.approved_url(),
                ManagedEndpointKind::Models,
            );
        }
        let mut url = ManagedEndpointKind::Models.approved_url();
        url.query_pairs_mut().append_pair("client_version", trimmed);
        Self::validated_url(&url, ManagedEndpointKind::Models)
    }

    /// User-owned endpoints: https with a host and no embedded credentials.
    pub fn validated_user_owned_url(value: &str) -> Result<Url, EndpointPolicyError> {
        let trimmed = value.trim();
        let url =
            Url::parse(trimmed).map_err(|_| EndpointPolicyError::InvalidUrl(value.to_string()))?;
        let valid = url.scheme().to_lowercase() == "https"
            && url.host_str().is_some_and(|h| !h.is_empty())
            && url.username().is_empty()
            && url.password().is_none();
        if !valid {
            return Err(EndpointPolicyError::InvalidUrl(value.to_string()));
        }
        Ok(url)
    }
}

/// Builds a hardened HTTP client: no redirects; the cookies feature is not
/// enabled, so no cookie store exists.
pub fn secure_http_client() -> reqwest::Client {
    reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .expect("client must build")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn url(s: &str) -> Url {
        Url::parse(s).unwrap()
    }

    #[test]
    fn accepts_exact_managed_endpoints() {
        for (raw, kind) in [
            (TRANSCRIPTION_URL, ManagedEndpointKind::Transcription),
            (RESPONSES_URL, ManagedEndpointKind::Responses),
            (MODELS_URL, ManagedEndpointKind::Models),
            (OAUTH_TOKEN_URL, ManagedEndpointKind::OAuthToken),
        ] {
            assert!(ManagedEndpointPolicy::validated_url(&url(raw), kind).is_ok());
        }
    }

    #[test]
    fn rejects_wrong_host_scheme_port_credentials_query() {
        let kind = ManagedEndpointKind::Transcription;
        for bad in [
            "http://chatgpt.com/backend-api/transcribe",
            "https://evil.com/backend-api/transcribe",
            "https://auth.openai.com/backend-api/transcribe",
            "https://chatgpt.com:8443/backend-api/transcribe",
            "https://user:pass@chatgpt.com/backend-api/transcribe",
            "https://chatgpt.com/backend-api/transcribe?x=1",
            "https://chatgpt.com/backend-api/transcribe#frag",
            "https://chatgpt.com/other/path",
        ] {
            assert!(
                ManagedEndpointPolicy::validated_url(&url(bad), kind).is_err(),
                "should reject {bad}"
            );
        }
    }

    #[test]
    fn oauth_token_endpoint_is_pinned_to_the_issuer_origin() {
        let kind = ManagedEndpointKind::OAuthToken;
        assert!(ManagedEndpointPolicy::validated_url(&url(OAUTH_TOKEN_URL), kind).is_ok());
        for bad in [
            "http://auth.openai.com/oauth/token",
            "https://chatgpt.com/oauth/token",
            "https://auth.openai.com.evil.com/oauth/token",
            "https://auth.openai.com:8443/oauth/token",
            "https://auth.openai.com/oauth/token?x=1",
            "https://auth.openai.com/oauth/authorize",
        ] {
            assert!(
                ManagedEndpointPolicy::validated_url(&url(bad), kind).is_err(),
                "should reject {bad}"
            );
        }
    }

    #[test]
    fn models_allows_only_client_version_query() {
        let ok = ManagedEndpointPolicy::models_list_url("0.1.0").unwrap();
        assert!(ok.as_str().contains("client_version=0.1.0"));
        let bad = url("https://chatgpt.com/backend-api/codex/models?client_version=1&extra=2");
        assert!(
            ManagedEndpointPolicy::validated_url(&bad, ManagedEndpointKind::Models).is_err()
        );
        let spaced = url("https://chatgpt.com/backend-api/codex/models?client_version=a%20b");
        assert!(
            ManagedEndpointPolicy::validated_url(&spaced, ManagedEndpointKind::Models).is_err()
        );
    }

    #[test]
    fn user_owned_requires_https_without_credentials() {
        assert!(ManagedEndpointPolicy::validated_user_owned_url(
            "https://api.openai.com/v1/chat/completions"
        )
        .is_ok());
        assert!(ManagedEndpointPolicy::validated_user_owned_url("http://api.example.com").is_err());
        assert!(
            ManagedEndpointPolicy::validated_user_owned_url("https://u:p@api.example.com").is_err()
        );
        assert!(ManagedEndpointPolicy::validated_user_owned_url("not a url").is_err());
    }
}
