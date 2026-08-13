//! ChatGPT managed session: OAuth + PKCE through the default browser with a
//! local loopback callback, secret storage in the platform credential store,
//! and managed transcription/polish against the approved chatgpt.com
//! endpoints. Ported from Swift `BrowserAuthBridge` / `ChatGPTSessionStore` /
//! `ChatGPTTranscriber`.
//!
//! The private ChatGPT backend dependency is explicit product policy: it is
//! not a stable public API and may break; the OpenAI-compatible provider is
//! the recovery path.

use async_trait::async_trait;
use base64::Engine;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::net::{Ipv4Addr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use vc_core::pipeline::{
    RecordedAudio, Transcriber, TranscriptionError, TranscriptionMetrics, TranscriptionResult,
};
use vc_core::polish::{PolishError, PolishedText, TextPolishProviderId, TextPolishing};
use vc_core::skill::prompt::{SkillPromptCompiler, SkillPromptContext};
use vc_core::skill::ResolvedSkillExecutionPlan;
use vc_core::terminology::TerminologyEntry;

use crate::endpoint_policy::{secure_http_client, ManagedEndpointKind, ManagedEndpointPolicy};

const KEYRING_SERVICE: &str = "app.vibecompose.desktop.ChatGPTSession";
const KEYRING_ACCOUNT: &str = "managed-session";

// OAuth client configuration mirrors the platform-neutral Codex CLI flow.
pub const OAUTH_ISSUER: &str = "https://auth.openai.com";
pub const OAUTH_CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";
pub const OAUTH_REDIRECT_PORT: u16 = 1455;
pub const OAUTH_REDIRECT_PATH: &str = "/auth/callback";

/// Default browser-login timeout; the UI may pass a different one.
pub const DEFAULT_LOGIN_TIMEOUT: Duration = Duration::from_secs(300);
/// Refresh the access token when it expires within this many seconds.
pub const REFRESH_LEEWAY_SECONDS: i64 = 60;

const ACCEPT_POLL_INTERVAL: Duration = Duration::from_millis(25);
const CONNECTION_IO_TIMEOUT: Duration = Duration::from_secs(2);
const MAX_REQUEST_HEAD_BYTES: usize = 16 * 1024;

fn redirect_uri() -> String {
    format!("http://localhost:{OAUTH_REDIRECT_PORT}{OAUTH_REDIRECT_PATH}")
}

fn base64_url(data: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(data)
}

/// PKCE verifier + S256 challenge.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PkcePair {
    pub verifier: String,
    pub challenge: String,
}

impl PkcePair {
    pub fn generate() -> Self {
        let mut bytes = [0u8; 64];
        rand::rng().fill_bytes(&mut bytes);
        let verifier = base64_url(&bytes);
        Self::from_verifier(&verifier)
    }

    pub fn from_verifier(verifier: &str) -> Self {
        let digest = Sha256::digest(verifier.as_bytes());
        Self {
            verifier: verifier.to_string(),
            challenge: base64_url(&digest),
        }
    }
}

/// A pending browser login: authorization URL plus the state/verifier the
/// callback must prove.
#[derive(Debug, Clone)]
pub struct AuthorizationRequest {
    pub url: String,
    pub state: String,
    pub pkce: PkcePair,
}

pub fn build_authorization_request() -> AuthorizationRequest {
    let mut state_bytes = [0u8; 32];
    rand::rng().fill_bytes(&mut state_bytes);
    let state = base64_url(&state_bytes);
    let pkce = PkcePair::generate();
    let redirect = redirect_uri();
    let url = format!(
        "{OAUTH_ISSUER}/oauth/authorize?response_type=code&client_id={OAUTH_CLIENT_ID}&redirect_uri={}&scope=openid%20profile%20email%20offline_access&state={state}&code_challenge={}&code_challenge_method=S256&prompt=login",
        urlencode(&redirect),
        pkce.challenge,
    );
    AuthorizationRequest { url, state, pkce }
}

fn urlencode(value: &str) -> String {
    let mut out = String::new();
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char)
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum CallbackError {
    #[error("callback used an unsupported method")]
    WrongMethod,
    #[error("callback path did not match")]
    WrongPath,
    #[error("state mismatch")]
    StateMismatch,
    #[error("duplicate query parameter {0}")]
    DuplicateParameter(String),
    #[error("authorization was denied: {0}")]
    Denied(String),
    #[error("missing authorization code")]
    MissingCode,
}

/// Validates the loopback callback request line the way Swift does: exact
/// method and path, exact state (checked before anything else so only a
/// state-proven callback can affect the flow), and no duplicated query
/// parameters. A denial carries `error_description` when present, otherwise
/// the `error` code.
pub fn validate_callback(
    method: &str,
    path_and_query: &str,
    expected_state: &str,
) -> Result<String, CallbackError> {
    if method != "GET" {
        return Err(CallbackError::WrongMethod);
    }
    let (path, query) = match path_and_query.split_once('?') {
        Some((p, q)) => (p, q),
        None => (path_and_query, ""),
    };
    if path != OAUTH_REDIRECT_PATH {
        return Err(CallbackError::WrongPath);
    }
    let mut code: Option<String> = None;
    let mut state: Option<String> = None;
    let mut error: Option<String> = None;
    let mut error_description: Option<String> = None;
    for pair in query.split('&').filter(|p| !p.is_empty()) {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        let value = urldecode(value);
        match key {
            "code" => {
                if code.replace(value).is_some() {
                    return Err(CallbackError::DuplicateParameter("code".into()));
                }
            }
            "state" => {
                if state.replace(value).is_some() {
                    return Err(CallbackError::DuplicateParameter("state".into()));
                }
            }
            "error" => {
                if error.replace(value).is_some() {
                    return Err(CallbackError::DuplicateParameter("error".into()));
                }
            }
            "error_description" => {
                if error_description.replace(value).is_some() {
                    return Err(CallbackError::DuplicateParameter("error_description".into()));
                }
            }
            _ => {}
        }
    }
    if state.as_deref() != Some(expected_state) {
        return Err(CallbackError::StateMismatch);
    }
    if let Some(error) = error {
        let detail = error_description.filter(|d| !d.is_empty()).unwrap_or(error);
        return Err(CallbackError::Denied(detail));
    }
    code.filter(|c| !c.is_empty()).ok_or(CallbackError::MissingCode)
}

fn urldecode(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Some(hex) = std::str::from_utf8(&bytes[i + 1..i + 3])
                .ok()
                .and_then(|h| u8::from_str_radix(h, 16).ok())
            {
                out.push(hex);
                i += 3;
                continue;
            }
        }
        out.push(if bytes[i] == b'+' { b' ' } else { bytes[i] });
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// The persisted managed session.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ChatGptSession {
    pub access_token: String,
    #[serde(default)]
    pub refresh_token: Option<String>,
    #[serde(default)]
    pub account_id: Option<String>,
    /// Epoch seconds when the access token expires.
    #[serde(default)]
    pub expires_at: Option<i64>,
}

impl ChatGptSession {
    /// True when the access token is expired or expires within
    /// [`REFRESH_LEEWAY_SECONDS`]. Sessions without a known expiry are
    /// treated as usable, matching the Swift `tokenIsUsable` semantics.
    pub fn needs_refresh(&self, now_epoch: i64) -> bool {
        match self.expires_at {
            Some(expires_at) => expires_at - now_epoch < REFRESH_LEEWAY_SECONDS,
            None => false,
        }
    }
}

/// Stores the managed session in the platform credential store
/// (Keychain / Windows Credential Manager / Secret Service).
pub struct ChatGptSessionStore;

impl ChatGptSessionStore {
    fn entry() -> Result<keyring::Entry, keyring::Error> {
        keyring::Entry::new(KEYRING_SERVICE, KEYRING_ACCOUNT)
    }

    pub fn load() -> Option<ChatGptSession> {
        let entry = Self::entry().ok()?;
        let raw = entry.get_password().ok()?;
        serde_json::from_str(&raw).ok()
    }

    pub fn save(session: &ChatGptSession) -> Result<(), String> {
        let entry = Self::entry().map_err(|e| e.to_string())?;
        let raw = serde_json::to_string(session).map_err(|e| e.to_string())?;
        entry.set_password(&raw).map_err(|e| e.to_string())
    }

    pub fn clear() -> Result<(), String> {
        let entry = Self::entry().map_err(|e| e.to_string())?;
        match entry.delete_credential() {
            Ok(()) => Ok(()),
            Err(keyring::Error::NoEntry) => Ok(()),
            Err(e) => Err(e.to_string()),
        }
    }
}

// ---------------------------------------------------------------------------
// Browser login: loopback callback listener, code exchange, token refresh.
// ---------------------------------------------------------------------------

/// Errors from the browser-login and session-refresh flows.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum AuthError {
    #[error(
        "the local callback port {port} is already in use by another application",
        port = OAUTH_REDIRECT_PORT
    )]
    PortOccupied,
    #[error("the login callback listener failed: {0}")]
    Listener(String),
    #[error("browser login timed out")]
    Timeout,
    #[error("browser login was cancelled")]
    Cancelled,
    #[error("browser login was rejected because the one-time state did not match")]
    StateMismatch,
    #[error("authorization was denied: {0}")]
    UserDenied(String),
    #[error("browser login sent an invalid callback: {0}")]
    InvalidCallback(String),
    #[error("token exchange failed: {0}")]
    Exchange(String),
    #[error("token refresh failed: {0}")]
    RefreshFailed(String),
    #[error("no ChatGPT session is stored; connect via the browser first")]
    NotLoggedIn,
    #[error("the stored ChatGPT session can no longer refresh; sign in again")]
    SessionExpired,
    #[error("the session store failed: {0}")]
    Store(String),
}

/// Cooperative cancellation for a pending browser login: keep a clone in the
/// UI layer and call [`CancelHandle::cancel`] to abort the wait.
#[derive(Debug, Clone, Default)]
pub struct CancelHandle(Arc<AtomicBool>);

impl CancelHandle {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.0.store(true, Ordering::SeqCst);
    }

    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::SeqCst)
    }
}

/// Loopback HTTP listener for the OAuth redirect. Binding is separate from
/// waiting so the caller can hold the port before opening the browser.
pub struct CallbackServer {
    listener: TcpListener,
    port: u16,
}

impl CallbackServer {
    /// Binds the fixed port of the registered redirect URI (`localhost:1455`).
    pub fn bind_default() -> Result<Self, AuthError> {
        Self::bind(OAUTH_REDIRECT_PORT)
    }

    /// Binds an explicit loopback port; `0` picks a free one (used in tests).
    pub fn bind(port: u16) -> Result<Self, AuthError> {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, port)).map_err(|e| {
            if e.kind() == std::io::ErrorKind::AddrInUse {
                AuthError::PortOccupied
            } else {
                AuthError::Listener(e.to_string())
            }
        })?;
        listener
            .set_nonblocking(true)
            .map_err(|e| AuthError::Listener(e.to_string()))?;
        let port = listener
            .local_addr()
            .map_err(|e| AuthError::Listener(e.to_string()))?
            .port();
        Ok(Self { listener, port })
    }

    pub fn local_port(&self) -> u16 {
        self.port
    }

    /// Serves loopback requests until the OAuth callback arrives, the timeout
    /// elapses, or `cancel` fires. Unrelated requests (favicon probes, wrong
    /// method) get a 404 and the wait continues; a state mismatch, denial, or
    /// malformed callback ends the flow with the matching error.
    pub fn wait_for_code(
        &self,
        expected_state: &str,
        timeout: Duration,
        cancel: &CancelHandle,
    ) -> Result<String, AuthError> {
        let deadline = Instant::now() + timeout;
        loop {
            if cancel.is_cancelled() {
                return Err(AuthError::Cancelled);
            }
            if Instant::now() >= deadline {
                return Err(AuthError::Timeout);
            }
            match self.listener.accept() {
                Ok((stream, _)) => match handle_connection(stream, expected_state) {
                    Some(outcome) => return outcome,
                    None => continue,
                },
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(ACCEPT_POLL_INTERVAL);
                }
                Err(e) => return Err(AuthError::Listener(e.to_string())),
            }
        }
    }
}

/// Handles one loopback connection. `None` means "keep waiting".
fn handle_connection(mut stream: TcpStream, expected_state: &str) -> Option<Result<String, AuthError>> {
    let _ = stream.set_read_timeout(Some(CONNECTION_IO_TIMEOUT));
    let _ = stream.set_write_timeout(Some(CONNECTION_IO_TIMEOUT));
    let Some((method, target)) = read_request_head(&mut stream) else {
        let _ = stream.write_all(&http_response(400, "Bad Request", &failure_html("无法解析回调请求")));
        return None;
    };
    match validate_callback(&method, &target, expected_state) {
        Ok(code) => {
            let _ = stream.write_all(&http_response(200, "OK", &success_html()));
            Some(Ok(code))
        }
        // Unrelated loopback traffic; answer politely and keep waiting.
        Err(CallbackError::WrongPath | CallbackError::WrongMethod) => {
            let _ = stream.write_all(&http_response(404, "Not Found", &failure_html("路径不是登录回调地址")));
            None
        }
        Err(CallbackError::StateMismatch) => {
            let _ = stream.write_all(&http_response(
                400,
                "Bad Request",
                &failure_html("一次性 state 校验失败，已拒绝该回调"),
            ));
            Some(Err(AuthError::StateMismatch))
        }
        Err(CallbackError::Denied(reason)) => {
            let _ = stream.write_all(&http_response(400, "Bad Request", &failure_html(&reason)));
            Some(Err(AuthError::UserDenied(reason)))
        }
        Err(err @ (CallbackError::MissingCode | CallbackError::DuplicateParameter(_))) => {
            let message = err.to_string();
            let _ = stream.write_all(&http_response(400, "Bad Request", &failure_html(&message)));
            Some(Err(AuthError::InvalidCallback(message)))
        }
    }
}

/// Reads until the end of the request headers and returns (method, target).
fn read_request_head(stream: &mut TcpStream) -> Option<(String, String)> {
    let mut buffer: Vec<u8> = Vec::new();
    let mut chunk = [0u8; 2048];
    while !buffer.windows(4).any(|window| window == b"\r\n\r\n") {
        if buffer.len() > MAX_REQUEST_HEAD_BYTES {
            return None;
        }
        match stream.read(&mut chunk) {
            Ok(0) => return None,
            Ok(read) => buffer.extend_from_slice(&chunk[..read]),
            Err(_) => return None,
        }
    }
    let head = String::from_utf8_lossy(&buffer);
    let request_line = head.lines().next()?;
    let mut parts = request_line.split_whitespace();
    let method = parts.next()?.to_string();
    let target = parts.next()?.to_string();
    Some((method, target))
}

fn http_response(status: u16, reason: &str, html: &str) -> Vec<u8> {
    let body = html.as_bytes();
    let header = format!(
        "HTTP/1.1 {status} {reason}\r\n\
         Content-Type: text/html; charset=utf-8\r\n\
         Content-Length: {}\r\n\
         Cache-Control: no-store\r\n\
         Referrer-Policy: no-referrer\r\n\
         X-Content-Type-Options: nosniff\r\n\
         X-Frame-Options: DENY\r\n\
         Connection: close\r\n\r\n",
        body.len()
    );
    let mut response = header.into_bytes();
    response.extend_from_slice(body);
    response
}

fn html_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

fn callback_page(title: &str, message_html: &str) -> String {
    format!(
        concat!(
            "<!doctype html><html lang=\"zh-CN\"><head><meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            "<meta name=\"color-scheme\" content=\"light dark\">",
            "<title>VibeCompose — {title}</title></head>",
            "<body style=\"margin:0;min-height:100vh;display:grid;place-items:center;",
            "font-family:system-ui,-apple-system,'Segoe UI','Microsoft YaHei',sans-serif;",
            "background:#f7f7f5;color:#18181a\">",
            "<main style=\"text-align:center;padding:2rem\">",
            "<h1 style=\"font-size:1.6rem;font-weight:600;letter-spacing:-0.02em\">{title}</h1>",
            "<p style=\"font-size:1rem;opacity:0.75\">{message}</p>",
            "</main></body></html>"
        ),
        title = title,
        message = message_html,
    )
}

fn success_html() -> String {
    callback_page("登录成功", "登录成功，可以关闭此页面回到 VibeCompose。")
}

fn failure_html(reason: &str) -> String {
    callback_page("登录失败", &html_escape(reason))
}

/// Raw token endpoint response (authorization_code and refresh_token grants).
#[derive(Debug, Clone, Deserialize)]
struct OAuthTokenResponse {
    access_token: String,
    #[serde(default)]
    refresh_token: Option<String>,
    #[serde(default)]
    id_token: Option<String>,
    #[serde(default)]
    expires_in: Option<i64>,
}

/// POSTs a form-encoded grant to the approved issuer token endpoint.
async fn request_token(form: &[(&str, &str)]) -> Result<OAuthTokenResponse, String> {
    let endpoint = ManagedEndpointPolicy::validated_url(
        &ManagedEndpointKind::OAuthToken.approved_url(),
        ManagedEndpointKind::OAuthToken,
    )
    .map_err(|e| e.to_string())?;
    let response = secure_http_client()
        .post(endpoint.as_str())
        .form(form)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let status = response.status();
    let body = response.text().await.map_err(|e| e.to_string())?;
    if !status.is_success() {
        let detail: String = body.trim().chars().take(300).collect();
        return Err(format!("{status}: {detail}"));
    }
    serde_json::from_str(&body).map_err(|e| format!("unexpected token response: {e}"))
}

async fn exchange_authorization_code(
    code: &str,
    code_verifier: &str,
) -> Result<OAuthTokenResponse, AuthError> {
    let redirect = redirect_uri();
    request_token(&[
        ("grant_type", "authorization_code"),
        ("code", code),
        ("redirect_uri", redirect.as_str()),
        ("client_id", OAUTH_CLIENT_ID),
        ("code_verifier", code_verifier),
    ])
    .await
    .map_err(AuthError::Exchange)
}

async fn refresh_token_grant(refresh_token: &str) -> Result<OAuthTokenResponse, AuthError> {
    request_token(&[
        ("grant_type", "refresh_token"),
        ("refresh_token", refresh_token),
        ("client_id", OAUTH_CLIENT_ID),
    ])
    .await
    .map_err(AuthError::RefreshFailed)
}

/// Decodes a JWT payload segment without verifying the signature. Only used
/// to read non-security-critical display claims; never to grant trust.
fn decode_jwt_payload(token: &str) -> Option<serde_json::Value> {
    let payload = token.split('.').nth(1)?;
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload.trim_end_matches('='))
        .ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn account_id_from_id_token(id_token: &str) -> Option<String> {
    let payload = decode_jwt_payload(id_token)?;
    let auth_claim = payload.get("https://api.openai.com/auth");
    let account_id = [
        auth_claim.and_then(|a| a.get("chatgpt_account_id")),
        payload.get("chatgpt_account_id"),
        auth_claim.and_then(|a| a.get("organization_id")),
        auth_claim.and_then(|a| a.get("org_id")),
    ]
    .into_iter()
    .flatten()
    .find_map(|value| value.as_str().filter(|s| !s.is_empty()))
    .map(str::to_string);
    account_id
}

fn jwt_expiry_epoch(token: &str) -> Option<i64> {
    decode_jwt_payload(token)?.get("exp")?.as_i64()
}

/// Builds the persisted session from a token response. `previous` carries the
/// prior session through a refresh, keeping the refresh token and account id
/// when the response omits them.
fn session_from_token_response(
    response: &OAuthTokenResponse,
    now_epoch: i64,
    previous: Option<&ChatGptSession>,
) -> Result<ChatGptSession, String> {
    let access_token = response.access_token.trim().to_string();
    if access_token.is_empty() {
        return Err("token response did not include a usable access token".into());
    }
    let expires_at = response
        .expires_in
        .map(|seconds| now_epoch + seconds)
        .or_else(|| jwt_expiry_epoch(&access_token));
    let refresh_token = response
        .refresh_token
        .clone()
        .filter(|token| !token.is_empty())
        .or_else(|| previous.and_then(|p| p.refresh_token.clone()));
    let account_id = response
        .id_token
        .as_deref()
        .and_then(account_id_from_id_token)
        .or_else(|| previous.and_then(|p| p.account_id.clone()));
    Ok(ChatGptSession {
        access_token,
        refresh_token,
        account_id,
        expires_at,
    })
}

fn now_epoch() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Runs the whole browser-login tail: listen on the fixed loopback port,
/// validate the callback, exchange the code, persist the session, return it.
/// Call [`build_authorization_request`], start this future, then open
/// `request.url` in the default browser.
pub async fn wait_for_callback_and_exchange(
    request: &AuthorizationRequest,
    timeout: Duration,
) -> Result<ChatGptSession, AuthError> {
    wait_for_callback_and_exchange_cancellable(request, timeout, CancelHandle::new()).await
}

/// Same as [`wait_for_callback_and_exchange`], but aborts with
/// [`AuthError::Cancelled`] when the handle fires.
pub async fn wait_for_callback_and_exchange_cancellable(
    request: &AuthorizationRequest,
    timeout: Duration,
    cancel: CancelHandle,
) -> Result<ChatGptSession, AuthError> {
    let server = CallbackServer::bind_default()?;
    let expected_state = request.state.clone();
    let code = tokio::task::spawn_blocking(move || {
        server.wait_for_code(&expected_state, timeout, &cancel)
    })
    .await
    .map_err(|e| AuthError::Listener(e.to_string()))??;
    let response = exchange_authorization_code(&code, &request.pkce.verifier).await?;
    let session =
        session_from_token_response(&response, now_epoch(), None).map_err(AuthError::Exchange)?;
    ChatGptSessionStore::save(&session).map_err(AuthError::Store)?;
    Ok(session)
}

/// Loads the stored session and returns it, refreshing it first when the
/// access token is expired or expires within [`REFRESH_LEEWAY_SECONDS`]. The
/// refreshed session is written back to the store. Errors that require a new
/// browser login: [`AuthError::NotLoggedIn`], [`AuthError::SessionExpired`],
/// and [`AuthError::RefreshFailed`].
pub async fn ensure_fresh_session() -> Result<ChatGptSession, AuthError> {
    let session = ChatGptSessionStore::load().ok_or(AuthError::NotLoggedIn)?;
    if !session.needs_refresh(now_epoch()) {
        return Ok(session);
    }
    let refresh_token = session
        .refresh_token
        .clone()
        .filter(|token| !token.is_empty())
        .ok_or(AuthError::SessionExpired)?;
    let response = refresh_token_grant(&refresh_token).await?;
    let refreshed = session_from_token_response(&response, now_epoch(), Some(&session))
        .map_err(AuthError::RefreshFailed)?;
    ChatGptSessionStore::save(&refreshed).map_err(AuthError::Store)?;
    Ok(refreshed)
}

/// Managed transcription against the approved chatgpt.com endpoint.
pub struct ChatGptManagedTranscriber {
    client: reqwest::Client,
    access_token: String,
    /// Instruction prompt uploaded with the audio (`prompt` multipart field).
    prompt: Option<String>,
}

impl ChatGptManagedTranscriber {
    pub fn new(access_token: &str) -> Self {
        Self {
            client: secure_http_client(),
            access_token: access_token.to_string(),
            prompt: None,
        }
    }

    pub fn with_prompt(mut self, prompt: Option<String>) -> Self {
        self.prompt = prompt.filter(|p| !p.trim().is_empty());
        self
    }
}

#[async_trait]
impl Transcriber for ChatGptManagedTranscriber {
    async fn transcribe(&self, audio: &RecordedAudio) -> Result<TranscriptionResult, TranscriptionError> {
        let endpoint = ManagedEndpointPolicy::validated_url(
            &ManagedEndpointKind::Transcription.approved_url(),
            ManagedEndpointKind::Transcription,
        )
        .map_err(|e| TranscriptionError::Request(e.to_string()))?;

        let bytes = tokio::fs::read(&audio.wav_path)
            .await
            .map_err(|e| TranscriptionError::InvalidAudio(e.to_string()))?;
        if bytes.len() as u64 > crate::openai_compatible::MAX_AUDIO_UPLOAD_BYTES {
            return Err(TranscriptionError::InvalidAudio(
                "recording exceeds the 25 MB upload limit".into(),
            ));
        }
        if bytes.len() < 12 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE" {
            return Err(TranscriptionError::InvalidAudio(
                "recording does not contain a RIFF/WAVE header".into(),
            ));
        }
        let audio_bytes = bytes.len() as u64;

        let mut form = reqwest::multipart::Form::new().part(
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
            .post(endpoint.as_str())
            .bearer_auth(&self.access_token)
            .multipart(form)
            .send()
            .await
            .map_err(|e| TranscriptionError::Request(e.to_string()))?;

        let status = response.status();
        if status.as_u16() == 401 || status.as_u16() == 403 {
            return Err(TranscriptionError::NotAuthenticated);
        }
        let body = response
            .text()
            .await
            .map_err(|e| TranscriptionError::Request(e.to_string()))?;
        if !status.is_success() {
            return Err(TranscriptionError::Request(format!(
                "managed transcription returned {status}"
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
                provider: "chatGPTManagedAuth".into(),
            },
        })
    }
}

/// Managed polish through the approved responses endpoint (SSE stream).
pub struct ChatGptManagedPolisher {
    client: reqwest::Client,
    access_token: String,
    model: String,
    glossary_budget_characters: usize,
    plan: ResolvedSkillExecutionPlan,
    context: SkillPromptContext,
    locale: String,
}

impl ChatGptManagedPolisher {
    pub fn new(
        access_token: &str,
        model: &str,
        glossary_budget_characters: usize,
        plan: ResolvedSkillExecutionPlan,
        context: SkillPromptContext,
        locale: &str,
    ) -> Self {
        Self {
            client: secure_http_client(),
            access_token: access_token.to_string(),
            model: model.to_string(),
            glossary_budget_characters,
            plan,
            context,
            locale: locale.to_string(),
        }
    }
}

#[async_trait]
impl TextPolishing for ChatGptManagedPolisher {
    async fn polish(
        &self,
        masked_text: &str,
        terminology_entries: &[TerminologyEntry],
        _hint_terms: &[String],
    ) -> Result<PolishedText, PolishError> {
        let endpoint = ManagedEndpointPolicy::validated_url(
            &ManagedEndpointKind::Responses.approved_url(),
            ManagedEndpointKind::Responses,
        )
        .map_err(|e| PolishError::Request(e.to_string()))?;

        let messages = SkillPromptCompiler.compile(
            masked_text,
            terminology_entries,
            self.glossary_budget_characters,
            &self.plan,
            &self.context,
            &[],
            &self.locale,
        );
        let system = messages
            .iter()
            .find(|m| m.role == "system")
            .map(|m| m.content.clone())
            .unwrap_or_default();
        let user_text = messages
            .iter()
            .filter(|m| m.role == "user")
            .map(|m| m.content.clone())
            .collect::<Vec<_>>()
            .join("\n");

        let payload = serde_json::json!({
            "model": self.model,
            "instructions": system,
            "input": [{
                "role": "user",
                "content": [{ "type": "input_text", "text": user_text }],
            }],
            "stream": true,
        });

        let response = self
            .client
            .post(endpoint.as_str())
            .bearer_auth(&self.access_token)
            .header("Accept", "text/event-stream")
            .json(&payload)
            .send()
            .await
            .map_err(|e| PolishError::Request(e.to_string()))?;

        let status = response.status();
        if status.as_u16() == 401 || status.as_u16() == 403 {
            return Err(PolishError::Unavailable);
        }
        let body = response
            .text()
            .await
            .map_err(|e| PolishError::Request(e.to_string()))?;
        if !status.is_success() {
            return Err(PolishError::Request(format!(
                "managed polish returned {status}"
            )));
        }

        let text = extract_sse_output_text(&body);
        if text.trim().is_empty() {
            return Err(PolishError::Request("polish response was empty".into()));
        }
        let input_chars: usize = messages.iter().map(|m| m.content.chars().count()).sum();
        Ok(PolishedText {
            estimated_input_tokens: (input_chars as u32).div_ceil(4),
            estimated_output_tokens: crate::openai_compatible::estimate_tokens(&text),
            text: text.trim().to_string(),
            provider: TextPolishProviderId::ChatGptAuth,
        })
    }
}

/// Accumulates `response.output_text.delta` events; falls back to the
/// completed response's `output_text` when present.
pub fn extract_sse_output_text(sse_body: &str) -> String {
    let mut deltas = String::new();
    let mut completed: Option<String> = None;
    for line in sse_body.lines() {
        let Some(payload) = line.strip_prefix("data: ") else {
            continue;
        };
        if payload == "[DONE]" {
            continue;
        }
        let Ok(event) = serde_json::from_str::<serde_json::Value>(payload) else {
            continue;
        };
        match event.get("type").and_then(|t| t.as_str()) {
            Some("response.output_text.delta") => {
                if let Some(delta) = event.get("delta").and_then(|d| d.as_str()) {
                    deltas.push_str(delta);
                }
            }
            Some("response.completed") => {
                if let Some(text) = event
                    .pointer("/response/output/0/content/0/text")
                    .and_then(|t| t.as_str())
                {
                    completed = Some(text.to_string());
                }
            }
            _ => {}
        }
    }
    completed.unwrap_or(deltas)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pkce_challenge_matches_rfc7636_vector() {
        // RFC 7636 appendix B test vector.
        let pair = PkcePair::from_verifier("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk");
        assert_eq!(pair.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
    }

    #[test]
    fn callback_requires_exact_state_and_path() {
        let ok = validate_callback("GET", "/auth/callback?code=abc&state=xyz", "xyz");
        assert_eq!(ok.unwrap(), "abc");
        assert_eq!(
            validate_callback("POST", "/auth/callback?code=abc&state=xyz", "xyz"),
            Err(CallbackError::WrongMethod)
        );
        assert_eq!(
            validate_callback("GET", "/other?code=abc&state=xyz", "xyz"),
            Err(CallbackError::WrongPath)
        );
        assert_eq!(
            validate_callback("GET", "/auth/callback?code=abc&state=WRONG", "xyz"),
            Err(CallbackError::StateMismatch)
        );
    }

    #[test]
    fn callback_rejects_duplicate_parameters() {
        assert_eq!(
            validate_callback("GET", "/auth/callback?code=a&code=b&state=xyz", "xyz"),
            Err(CallbackError::DuplicateParameter("code".into()))
        );
        assert_eq!(
            validate_callback("GET", "/auth/callback?code=a&state=xyz&state=xyz", "xyz"),
            Err(CallbackError::DuplicateParameter("state".into()))
        );
    }

    #[test]
    fn callback_propagates_denial_and_missing_code() {
        assert_eq!(
            validate_callback("GET", "/auth/callback?error=access_denied&state=xyz", "xyz"),
            Err(CallbackError::Denied("access_denied".into()))
        );
        assert_eq!(
            validate_callback("GET", "/auth/callback?state=xyz", "xyz"),
            Err(CallbackError::MissingCode)
        );
    }

    #[test]
    fn sse_extraction_prefers_completed_event() {
        let body = concat!(
            "data: {\"type\":\"response.output_text.delta\",\"delta\":\"你\"}\n",
            "data: {\"type\":\"response.output_text.delta\",\"delta\":\"好\"}\n",
            "data: {\"type\":\"response.completed\",\"response\":{\"output\":[{\"content\":[{\"text\":\"你好，世界\"}]}]}}\n",
            "data: [DONE]\n",
        );
        assert_eq!(extract_sse_output_text(body), "你好，世界");
        let deltas_only = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"片段\"}\n";
        assert_eq!(extract_sse_output_text(deltas_only), "片段");
    }

    #[test]
    fn authorization_url_contains_pkce_and_state() {
        let request = build_authorization_request();
        assert!(request.url.starts_with(OAUTH_ISSUER));
        assert!(request.url.contains("code_challenge_method=S256"));
        assert!(request.url.contains(&format!("state={}", request.state)));
        assert!(request.url.contains(&request.pkce.challenge));
    }

    fn fake_jwt(payload: serde_json::Value) -> String {
        format!(
            "{}.{}.signature",
            base64_url(br#"{"alg":"none","typ":"JWT"}"#),
            base64_url(payload.to_string().as_bytes())
        )
    }

    fn send_request(port: u16, request: &str) -> String {
        let mut stream =
            std::net::TcpStream::connect(("127.0.0.1", port)).expect("connect to listener");
        stream.write_all(request.as_bytes()).expect("write request");
        let mut response = String::new();
        stream.read_to_string(&mut response).expect("read response");
        response
    }

    #[test]
    fn callback_prefers_error_description_over_error_code() {
        assert_eq!(
            validate_callback(
                "GET",
                "/auth/callback?error=access_denied&error_description=user%20said%20no&state=xyz",
                "xyz"
            ),
            Err(CallbackError::Denied("user said no".into()))
        );
        assert_eq!(
            validate_callback(
                "GET",
                "/auth/callback?error=x&error_description=a&error_description=b&state=xyz",
                "xyz"
            ),
            Err(CallbackError::DuplicateParameter("error_description".into()))
        );
    }

    #[test]
    fn state_is_checked_before_error_parameters() {
        assert_eq!(
            validate_callback("GET", "/auth/callback?error=access_denied&state=WRONG", "xyz"),
            Err(CallbackError::StateMismatch)
        );
    }

    #[test]
    fn token_response_deserializes_with_and_without_optional_fields() {
        let full: OAuthTokenResponse = serde_json::from_str(
            r#"{"access_token":"at","refresh_token":"rt","id_token":"idt","expires_in":3600,"token_type":"Bearer","scope":"openid"}"#,
        )
        .unwrap();
        assert_eq!(full.access_token, "at");
        assert_eq!(full.refresh_token.as_deref(), Some("rt"));
        assert_eq!(full.id_token.as_deref(), Some("idt"));
        assert_eq!(full.expires_in, Some(3600));

        let minimal: OAuthTokenResponse =
            serde_json::from_str(r#"{"access_token":"at"}"#).unwrap();
        assert_eq!(minimal.access_token, "at");
        assert_eq!(minimal.refresh_token, None);
        assert_eq!(minimal.id_token, None);
        assert_eq!(minimal.expires_in, None);
    }

    #[test]
    fn session_from_token_response_computes_expiry_and_account_id() {
        let id_token = fake_jwt(serde_json::json!({
            "https://api.openai.com/auth": { "chatgpt_account_id": "acct-42" }
        }));
        let response = OAuthTokenResponse {
            access_token: " at ".into(),
            refresh_token: Some("rt".into()),
            id_token: Some(id_token),
            expires_in: Some(3600),
        };
        let session = session_from_token_response(&response, 1_000_000, None).unwrap();
        assert_eq!(session.access_token, "at");
        assert_eq!(session.refresh_token.as_deref(), Some("rt"));
        assert_eq!(session.expires_at, Some(1_003_600));
        assert_eq!(session.account_id.as_deref(), Some("acct-42"));
    }

    #[test]
    fn session_expiry_falls_back_to_the_access_token_jwt() {
        let response = OAuthTokenResponse {
            access_token: fake_jwt(serde_json::json!({ "exp": 1_700_000_000i64 })),
            refresh_token: None,
            id_token: None,
            expires_in: None,
        };
        let session = session_from_token_response(&response, 1_000, None).unwrap();
        assert_eq!(session.expires_at, Some(1_700_000_000));
        assert_eq!(session.account_id, None);
    }

    #[test]
    fn refresh_result_keeps_previous_refresh_token_and_account_id() {
        let previous = ChatGptSession {
            access_token: "old".into(),
            refresh_token: Some("old-rt".into()),
            account_id: Some("acct-1".into()),
            expires_at: Some(10),
        };
        let response = OAuthTokenResponse {
            access_token: "new".into(),
            refresh_token: None,
            id_token: None,
            expires_in: Some(60),
        };
        let session = session_from_token_response(&response, 100, Some(&previous)).unwrap();
        assert_eq!(session.access_token, "new");
        assert_eq!(session.refresh_token.as_deref(), Some("old-rt"));
        assert_eq!(session.account_id.as_deref(), Some("acct-1"));
        assert_eq!(session.expires_at, Some(160));
    }

    #[test]
    fn blank_access_token_is_rejected() {
        let response = OAuthTokenResponse {
            access_token: "   ".into(),
            refresh_token: None,
            id_token: None,
            expires_in: None,
        };
        assert!(session_from_token_response(&response, 0, None).is_err());
    }

    #[test]
    fn needs_refresh_uses_the_sixty_second_leeway() {
        let mut session = ChatGptSession {
            access_token: "at".into(),
            refresh_token: None,
            account_id: None,
            expires_at: None,
        };
        assert!(!session.needs_refresh(1_000));
        session.expires_at = Some(1_060);
        assert!(!session.needs_refresh(1_000));
        session.expires_at = Some(1_059);
        assert!(session.needs_refresh(1_000));
        session.expires_at = Some(999);
        assert!(session.needs_refresh(1_000));
    }

    #[test]
    fn account_id_reads_top_level_claim_as_fallback() {
        let id_token = fake_jwt(serde_json::json!({ "chatgpt_account_id": "acct-top" }));
        assert_eq!(account_id_from_id_token(&id_token).as_deref(), Some("acct-top"));
        assert_eq!(account_id_from_id_token("not-a-jwt"), None);
    }

    #[test]
    fn callback_pages_contain_copy_and_escape_reasons() {
        assert!(success_html().contains("登录成功，可以关闭此页面回到 VibeCompose"));
        let page = failure_html("<script>alert(1)</script>");
        assert!(page.contains("登录失败"));
        assert!(!page.contains("<script>"));
        assert!(page.contains("&lt;script&gt;"));
    }

    #[test]
    fn listener_returns_the_code_and_serves_the_success_page() {
        let server = CallbackServer::bind(0).unwrap();
        let port = server.local_port();
        let client = std::thread::spawn(move || {
            send_request(
                port,
                "GET /auth/callback?code=abc123&state=teststate HTTP/1.1\r\nHost: localhost\r\n\r\n",
            )
        });
        let code = server
            .wait_for_code("teststate", Duration::from_secs(5), &CancelHandle::new())
            .unwrap();
        assert_eq!(code, "abc123");
        let response = client.join().unwrap();
        assert!(response.starts_with("HTTP/1.1 200"));
        assert!(response.contains("登录成功，可以关闭此页面回到 VibeCompose"));
    }

    #[test]
    fn listener_ignores_unrelated_requests_until_the_callback_arrives() {
        let server = CallbackServer::bind(0).unwrap();
        let port = server.local_port();
        let client = std::thread::spawn(move || {
            let favicon =
                send_request(port, "GET /favicon.ico HTTP/1.1\r\nHost: localhost\r\n\r\n");
            let callback = send_request(
                port,
                "GET /auth/callback?code=late&state=st HTTP/1.1\r\nHost: localhost\r\n\r\n",
            );
            (favicon, callback)
        });
        let code = server
            .wait_for_code("st", Duration::from_secs(5), &CancelHandle::new())
            .unwrap();
        assert_eq!(code, "late");
        let (favicon, callback) = client.join().unwrap();
        assert!(favicon.starts_with("HTTP/1.1 404"));
        assert!(callback.starts_with("HTTP/1.1 200"));
    }

    #[test]
    fn listener_rejects_a_state_mismatch_with_an_error_page() {
        let server = CallbackServer::bind(0).unwrap();
        let port = server.local_port();
        let client = std::thread::spawn(move || {
            send_request(
                port,
                "GET /auth/callback?code=abc&state=WRONG HTTP/1.1\r\nHost: localhost\r\n\r\n",
            )
        });
        let result =
            server.wait_for_code("expected", Duration::from_secs(5), &CancelHandle::new());
        assert_eq!(result, Err(AuthError::StateMismatch));
        let response = client.join().unwrap();
        assert!(response.starts_with("HTTP/1.1 400"));
        assert!(response.contains("登录失败"));
    }

    #[test]
    fn listener_reports_user_denial_with_the_description() {
        let server = CallbackServer::bind(0).unwrap();
        let port = server.local_port();
        let client = std::thread::spawn(move || {
            send_request(
                port,
                "GET /auth/callback?error=access_denied&error_description=user%20said%20no&state=st HTTP/1.1\r\n\r\n",
            )
        });
        let result = server.wait_for_code("st", Duration::from_secs(5), &CancelHandle::new());
        assert_eq!(result, Err(AuthError::UserDenied("user said no".into())));
        let response = client.join().unwrap();
        assert!(response.starts_with("HTTP/1.1 400"));
    }

    #[test]
    fn listener_times_out_without_a_callback() {
        let server = CallbackServer::bind(0).unwrap();
        let started = Instant::now();
        let result = server.wait_for_code("st", Duration::from_millis(120), &CancelHandle::new());
        assert_eq!(result, Err(AuthError::Timeout));
        assert!(started.elapsed() < Duration::from_secs(5));
    }

    #[test]
    fn listener_can_be_cancelled_from_another_thread() {
        let server = CallbackServer::bind(0).unwrap();
        let cancel = CancelHandle::new();
        let remote = cancel.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(50));
            remote.cancel();
        });
        let result = server.wait_for_code("st", Duration::from_secs(30), &cancel);
        assert_eq!(result, Err(AuthError::Cancelled));
    }

    #[test]
    fn binding_an_occupied_port_reports_port_occupied() {
        let first = CallbackServer::bind(0).unwrap();
        let second = CallbackServer::bind(first.local_port());
        assert_eq!(second.err(), Some(AuthError::PortOccupied));
    }
}
