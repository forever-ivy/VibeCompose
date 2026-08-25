//! ChatGPT hosted-login availability: an explicit, honest state machine.
//!
//! The hosted ChatGPT session rides on a private ChatGPT backend that is not
//! a stable public API. On Windows and Linux the browser OAuth login can be
//! unavailable in ways macOS never sees: the packager/operator may disable
//! it outright, the platform credential store may be missing (no Secret
//! Service on a bare Linux session), the loopback callback listener may be
//! blocked by sandbox policy, or the token endpoint may reject this client.
//!
//! Instead of a dead-end error, the shells keep one `LoginAvailability`
//! value that the UI renders explicitly, always paired with the honest
//! fallback that keeps the app fully usable: the OpenAI-compatible API-key
//! provider path. This module is platform-agnostic and fully unit-tested;
//! the desktop shell feeds it events and serializes snapshots over IPC.

use serde::Serialize;

/// Why the hosted login path is considered unavailable.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum UnavailableReason {
    /// Disabled by build/operator policy for this platform.
    PlatformPolicy,
    /// The loopback callback listener cannot run (sandbox/firewall policy).
    CallbackBlocked,
    /// The token endpoint rejected this client (unsupported platform/build).
    BackendRejected,
    /// The platform credential store cannot hold the session (for example
    /// no Secret Service/keyring on Linux), so a login could not persist.
    CredentialStoreUnavailable,
}

impl UnavailableReason {
    pub fn code(&self) -> &'static str {
        match self {
            Self::PlatformPolicy => "platformPolicy",
            Self::CallbackBlocked => "callbackBlocked",
            Self::BackendRejected => "backendRejected",
            Self::CredentialStoreUnavailable => "credentialStoreUnavailable",
        }
    }
}

/// Platform-agnostic classification of a login (or refresh) failure.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum LoginFailure {
    /// The user cancelled the browser flow.
    Cancelled,
    /// The browser flow timed out without a callback.
    Timeout,
    /// The authorization server reported that the user denied access.
    UserDenied,
    /// A callback arrived with the wrong one-time state and was rejected.
    StateMismatch,
    /// The callback was malformed (missing code, duplicated parameters).
    InvalidCallback,
    /// The fixed loopback port is in use by another application.
    PortOccupied,
    /// The loopback listener could not run at all.
    ListenerFailed,
    /// The token endpoint rejected this client/platform.
    ExchangeRejected,
    /// A network-level error reaching the token endpoint.
    Network,
    /// The platform credential store failed to persist the session.
    CredentialStore,
    /// The stored session expired and cannot refresh; sign in again.
    SessionExpired,
}

/// What a failure means for future attempts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoginDisposition {
    /// Trying again may work; the UI keeps the login button live.
    Retryable,
    /// The login path is unavailable on this platform/environment; the UI
    /// must lead with the API-key fallback (retry stays possible).
    Unavailable(UnavailableReason),
}

impl LoginFailure {
    pub fn disposition(&self) -> LoginDisposition {
        match self {
            Self::Cancelled
            | Self::Timeout
            | Self::UserDenied
            | Self::StateMismatch
            | Self::InvalidCallback
            | Self::PortOccupied
            | Self::Network
            | Self::SessionExpired => LoginDisposition::Retryable,
            Self::ListenerFailed => {
                LoginDisposition::Unavailable(UnavailableReason::CallbackBlocked)
            }
            Self::ExchangeRejected => {
                LoginDisposition::Unavailable(UnavailableReason::BackendRejected)
            }
            Self::CredentialStore => {
                LoginDisposition::Unavailable(UnavailableReason::CredentialStoreUnavailable)
            }
        }
    }
}

/// Heuristic over token-endpoint error detail: HTTP 4xx statuses and OAuth
/// client-rejection codes mean this client/platform is refused (not a
/// transient network problem).
pub fn exchange_detail_is_rejection(detail: &str) -> bool {
    let lowered = detail.to_lowercase();
    let status_rejected = detail
        .split(&[':', ' '][..])
        .next()
        .and_then(|s| s.parse::<u16>().ok())
        .is_some_and(|status| (400..500).contains(&status));
    status_rejected
        || lowered.contains("unauthorized_client")
        || lowered.contains("invalid_client")
        || lowered.contains("unsupported_grant_type")
        || lowered.contains("access_denied")
}

/// Operator/build policy for the hosted login path.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LoginPolicy {
    #[default]
    Enabled,
    /// The hosted login is switched off for this build/platform.
    Disabled,
}

impl LoginPolicy {
    /// Parses the `VIBECOMPOSE_CHATGPT_LOGIN` environment override; anything
    /// other than an explicit "off" keeps the login path enabled.
    pub fn from_env_value(value: Option<&str>) -> Self {
        match value.map(|v| v.trim().to_lowercase()).as_deref() {
            Some("unavailable") | Some("disabled") | Some("off") | Some("0") => Self::Disabled,
            _ => Self::Enabled,
        }
    }
}

/// The availability state the UI renders.
#[derive(Debug, Clone, PartialEq)]
pub enum LoginAvailability {
    /// A managed session is stored and usable.
    Connected,
    /// Login may be attempted; carries the last transient failure, if any.
    Available { last_failure: Option<FailureDetail> },
    /// Login is unavailable here; the fallback path must lead.
    Unavailable {
        reason: UnavailableReason,
        detail: Option<String>,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct FailureDetail {
    pub failure: LoginFailure,
    pub message: String,
}

/// Serializable snapshot for IPC / UI.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginAvailabilitySnapshot {
    /// "connected" | "available" | "unavailable"
    pub status: &'static str,
    /// Unavailable reason code, when status == "unavailable".
    pub reason: Option<&'static str>,
    /// Human-readable detail of the most recent failure, if any.
    pub detail: Option<String>,
    /// Whether re-attempting the browser login makes sense. Policy-disabled
    /// builds are the only case where retry is pointless.
    pub can_retry: bool,
    /// The honest fallback provider id that keeps the app usable.
    pub fallback: &'static str,
}

/// State machine driven by the shell. Trust boundaries stay elsewhere: this
/// type only tracks availability for the UI; it never holds tokens.
#[derive(Debug, Clone)]
pub struct LoginAvailabilityMachine {
    policy: LoginPolicy,
    state: LoginAvailability,
}

impl LoginAvailabilityMachine {
    pub fn new(policy: LoginPolicy, has_stored_session: bool) -> Self {
        let state = if has_stored_session {
            // A stored session keeps working even where new logins are
            // switched off; Connected wins until it is disconnected.
            LoginAvailability::Connected
        } else {
            Self::baseline(policy)
        };
        Self { policy, state }
    }

    fn baseline(policy: LoginPolicy) -> LoginAvailability {
        match policy {
            LoginPolicy::Enabled => LoginAvailability::Available { last_failure: None },
            LoginPolicy::Disabled => LoginAvailability::Unavailable {
                reason: UnavailableReason::PlatformPolicy,
                detail: None,
            },
        }
    }

    pub fn state(&self) -> &LoginAvailability {
        &self.state
    }

    pub fn policy(&self) -> LoginPolicy {
        self.policy
    }

    /// True when starting a browser login attempt is permitted. Everything
    /// except policy-disabled allows retry so the user never hits a dead
    /// end even in an "unavailable" state.
    pub fn attempt_allowed(&self) -> bool {
        self.policy == LoginPolicy::Enabled
    }

    /// A completed login proves the path works here.
    pub fn connected(&mut self) {
        self.state = LoginAvailability::Connected;
    }

    /// User disconnect or an invalidated session returns to the baseline.
    pub fn disconnected(&mut self) {
        self.state = Self::baseline(self.policy);
    }

    /// A login or refresh attempt failed.
    pub fn attempt_failed(&mut self, failure: LoginFailure, message: impl Into<String>) {
        let message = message.into();
        if self.policy == LoginPolicy::Disabled {
            // Policy dominates: the state stays policy-unavailable but the
            // detail records what happened.
            self.state = LoginAvailability::Unavailable {
                reason: UnavailableReason::PlatformPolicy,
                detail: Some(message),
            };
            return;
        }
        self.state = match failure.disposition() {
            LoginDisposition::Retryable => LoginAvailability::Available {
                last_failure: Some(FailureDetail { failure, message }),
            },
            LoginDisposition::Unavailable(reason) => LoginAvailability::Unavailable {
                reason,
                detail: Some(message),
            },
        };
    }

    pub fn snapshot(&self) -> LoginAvailabilitySnapshot {
        match &self.state {
            LoginAvailability::Connected => LoginAvailabilitySnapshot {
                status: "connected",
                reason: None,
                detail: None,
                can_retry: true,
                fallback: "openAiCompatible",
            },
            LoginAvailability::Available { last_failure } => LoginAvailabilitySnapshot {
                status: "available",
                reason: None,
                detail: last_failure.as_ref().map(|f| f.message.clone()),
                can_retry: true,
                fallback: "openAiCompatible",
            },
            LoginAvailability::Unavailable { reason, detail } => LoginAvailabilitySnapshot {
                status: "unavailable",
                reason: Some(reason.code()),
                detail: detail.clone(),
                can_retry: *reason != UnavailableReason::PlatformPolicy,
                fallback: "openAiCompatible",
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn starts_available_when_enabled_without_session() {
        let machine = LoginAvailabilityMachine::new(LoginPolicy::Enabled, false);
        assert_eq!(
            machine.state(),
            &LoginAvailability::Available { last_failure: None }
        );
        assert!(machine.attempt_allowed());
        let snapshot = machine.snapshot();
        assert_eq!(snapshot.status, "available");
        assert_eq!(snapshot.fallback, "openAiCompatible");
        assert!(snapshot.can_retry);
    }

    #[test]
    fn starts_connected_when_a_session_is_stored() {
        let machine = LoginAvailabilityMachine::new(LoginPolicy::Enabled, true);
        assert_eq!(machine.state(), &LoginAvailability::Connected);
        assert_eq!(machine.snapshot().status, "connected");
    }

    #[test]
    fn a_stored_session_wins_over_a_disabled_policy() {
        // Users who logged in before the policy flipped keep working.
        let machine = LoginAvailabilityMachine::new(LoginPolicy::Disabled, true);
        assert_eq!(machine.state(), &LoginAvailability::Connected);
        assert!(!machine.attempt_allowed());
    }

    #[test]
    fn policy_disabled_is_unavailable_without_retry() {
        let machine = LoginAvailabilityMachine::new(LoginPolicy::Disabled, false);
        let snapshot = machine.snapshot();
        assert_eq!(snapshot.status, "unavailable");
        assert_eq!(snapshot.reason, Some("platformPolicy"));
        assert!(!snapshot.can_retry);
        assert!(!machine.attempt_allowed());
        // The fallback path is always advertised.
        assert_eq!(snapshot.fallback, "openAiCompatible");
    }

    #[test]
    fn transient_failures_keep_login_available_with_detail() {
        let mut machine = LoginAvailabilityMachine::new(LoginPolicy::Enabled, false);
        for failure in [
            LoginFailure::Cancelled,
            LoginFailure::Timeout,
            LoginFailure::UserDenied,
            LoginFailure::StateMismatch,
            LoginFailure::InvalidCallback,
            LoginFailure::PortOccupied,
            LoginFailure::Network,
            LoginFailure::SessionExpired,
        ] {
            machine.attempt_failed(failure, "boom");
            let snapshot = machine.snapshot();
            assert_eq!(snapshot.status, "available", "{failure:?}");
            assert_eq!(snapshot.detail.as_deref(), Some("boom"));
            assert!(snapshot.can_retry);
        }
    }

    #[test]
    fn infrastructure_failures_flip_to_unavailable_with_reasons() {
        let cases = [
            (LoginFailure::ListenerFailed, "callbackBlocked"),
            (LoginFailure::ExchangeRejected, "backendRejected"),
            (
                LoginFailure::CredentialStore,
                "credentialStoreUnavailable",
            ),
        ];
        for (failure, reason) in cases {
            let mut machine = LoginAvailabilityMachine::new(LoginPolicy::Enabled, false);
            machine.attempt_failed(failure, "why it broke");
            let snapshot = machine.snapshot();
            assert_eq!(snapshot.status, "unavailable", "{failure:?}");
            assert_eq!(snapshot.reason, Some(reason));
            assert_eq!(snapshot.detail.as_deref(), Some("why it broke"));
            // Not a dead end: everything except policy still offers retry.
            assert!(snapshot.can_retry);
        }
    }

    #[test]
    fn success_recovers_from_unavailable() {
        let mut machine = LoginAvailabilityMachine::new(LoginPolicy::Enabled, false);
        machine.attempt_failed(LoginFailure::ExchangeRejected, "403: nope");
        assert_eq!(machine.snapshot().status, "unavailable");
        machine.connected();
        assert_eq!(machine.snapshot().status, "connected");
    }

    #[test]
    fn disconnect_returns_to_the_policy_baseline() {
        let mut enabled = LoginAvailabilityMachine::new(LoginPolicy::Enabled, true);
        enabled.disconnected();
        assert_eq!(enabled.snapshot().status, "available");

        let mut disabled = LoginAvailabilityMachine::new(LoginPolicy::Disabled, true);
        disabled.disconnected();
        let snapshot = disabled.snapshot();
        assert_eq!(snapshot.status, "unavailable");
        assert_eq!(snapshot.reason, Some("platformPolicy"));
    }

    #[test]
    fn failures_under_disabled_policy_stay_policy_unavailable() {
        let mut machine = LoginAvailabilityMachine::new(LoginPolicy::Disabled, false);
        machine.attempt_failed(LoginFailure::Timeout, "timed out");
        let snapshot = machine.snapshot();
        assert_eq!(snapshot.reason, Some("platformPolicy"));
        assert_eq!(snapshot.detail.as_deref(), Some("timed out"));
        assert!(!snapshot.can_retry);
    }

    #[test]
    fn env_policy_parsing_only_disables_on_explicit_off_values() {
        assert_eq!(
            LoginPolicy::from_env_value(Some("unavailable")),
            LoginPolicy::Disabled
        );
        assert_eq!(LoginPolicy::from_env_value(Some("OFF")), LoginPolicy::Disabled);
        assert_eq!(LoginPolicy::from_env_value(Some("0")), LoginPolicy::Disabled);
        assert_eq!(
            LoginPolicy::from_env_value(Some("disabled")),
            LoginPolicy::Disabled
        );
        assert_eq!(LoginPolicy::from_env_value(Some("1")), LoginPolicy::Enabled);
        assert_eq!(LoginPolicy::from_env_value(Some("")), LoginPolicy::Enabled);
        assert_eq!(LoginPolicy::from_env_value(None), LoginPolicy::Enabled);
    }

    #[test]
    fn exchange_rejection_heuristic_reads_status_and_oauth_codes() {
        assert!(exchange_detail_is_rejection("403 Forbidden: blocked"));
        assert!(exchange_detail_is_rejection("400: invalid_client"));
        assert!(exchange_detail_is_rejection(
            "the server said unauthorized_client"
        ));
        assert!(exchange_detail_is_rejection("ACCESS_DENIED for this build"));
        assert!(!exchange_detail_is_rejection("500: upstream exploded"));
        assert!(!exchange_detail_is_rejection(
            "connection reset by peer while sending request"
        ));
        assert!(!exchange_detail_is_rejection("dns error: no such host"));
    }

    #[test]
    fn snapshot_serializes_camel_case_for_ipc() {
        let mut machine = LoginAvailabilityMachine::new(LoginPolicy::Enabled, false);
        machine.attempt_failed(LoginFailure::ExchangeRejected, "403: nope");
        let json = serde_json::to_value(machine.snapshot()).unwrap();
        assert_eq!(json["status"], "unavailable");
        assert_eq!(json["reason"], "backendRejected");
        assert_eq!(json["canRetry"], true);
        assert_eq!(json["fallback"], "openAiCompatible");
    }
}
