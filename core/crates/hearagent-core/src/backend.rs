//! Clients for Supabase Auth (sign-in, sessions) and the Hear Agent backend
//! (Cloudflare Worker). The backend holds the OpenAI, ElevenLabs and Dodo keys;
//! the app only ever holds the user's Supabase session.

use crate::speech::SpeechRequest;
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine as _;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::sync::{Mutex, RwLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Where Supabase sends the browser after sign-in. Add it to the project's Redirect URLs.
pub const AUTH_REDIRECT: &str = "hearagent://auth";
/// Refresh this long before the access token expires.
const REFRESH_MARGIN_SECS: i64 = 60;

#[derive(Debug, Clone, PartialEq)]
pub struct Rendered {
    pub text: String,
    pub audio: Vec<u8>,
    pub credits: Option<Credits>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Credits {
    pub credits_remaining: i64,
    pub credits_total: i64,
    #[serde(default)]
    pub period_end: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BackendError {
    SignedOut,
    NoSubscription,
    CreditsExhausted { period_end: Option<String> },
    Offline(String),
    Server(String),
}

impl std::fmt::Display for BackendError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            BackendError::SignedOut => write!(f, "signed out"),
            BackendError::NoSubscription => write!(f, "no active subscription"),
            BackendError::CreditsExhausted { .. } => write!(f, "monthly credits used up"),
            BackendError::Offline(e) => write!(f, "can't reach Hear Agent: {e}"),
            BackendError::Server(e) => write!(f, "Hear Agent server error: {e}"),
        }
    }
}

/// Turns a speech request into spoken audio. The backend implements it; tests fake it.
pub trait Renderer: Send + Sync {
    fn render(&self, request: &SpeechRequest) -> Result<Rendered, BackendError>;
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Account {
    pub email: String,
    #[serde(default)]
    pub name: String,
    pub subscription: Option<Subscription>,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Subscription {
    pub status: String,
    pub active: bool,
    #[serde(default)]
    pub plan_id: String,
    pub plan_name: String,
    pub credits_total: i64,
    pub credits_used: i64,
    pub credits_remaining: i64,
    /// When credits next refill.
    #[serde(default)]
    pub period_end: Option<String>,
    /// When the plan renews; none for lifetime.
    #[serde(default)]
    pub renews_at: Option<String>,
    #[serde(default)]
    pub cancel_at_period_end: bool,
}

/// A sign-in attempt: open `url` in the browser, then finish with `verifier`
/// when the `hearagent://auth?code=…` callback arrives.
#[derive(Debug, Clone, PartialEq)]
pub struct SignInStart {
    pub url: String,
    pub verifier: String,
}

/// A Supabase session, stored by the app (Keychain) as JSON.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Session {
    pub access_token: String,
    pub refresh_token: String,
    /// Unix seconds.
    pub expires_at: i64,
}

impl Session {
    fn from_token_response(body: &Value) -> Option<Session> {
        let access = body.get("access_token")?.as_str()?;
        let refresh = body.get("refresh_token")?.as_str()?;
        let expires_at = body
            .get("expires_at")
            .and_then(Value::as_i64)
            .unwrap_or_else(|| now_secs() + body.get("expires_in").and_then(Value::as_i64).unwrap_or(3600));
        Some(Session { access_token: access.into(), refresh_token: refresh.into(), expires_at })
    }

    fn fresh(&self) -> bool {
        self.expires_at - now_secs() > REFRESH_MARGIN_SECS
    }
}

type SessionListener = Box<dyn Fn(Option<String>) + Send + Sync>;

pub struct Backend {
    base_url: String,
    supabase_url: String,
    supabase_key: String,
    session: RwLock<Option<Session>>,
    /// Held while refreshing, so a rotated refresh token is never used twice.
    refreshing: Mutex<()>,
    on_session: RwLock<Option<SessionListener>>,
    http: reqwest::blocking::Client,
}

impl Backend {
    /// `supabase_key` is the project's publishable (or legacy anon) key; it's safe to ship.
    pub fn new(base_url: &str, supabase_url: &str, supabase_key: &str) -> Backend {
        let http = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(30))
            .connect_timeout(Duration::from_secs(8))
            .user_agent(concat!("HearAgent/", env!("CARGO_PKG_VERSION")))
            .build()
            .expect("http client");
        Backend {
            base_url: base_url.trim_end_matches('/').to_string(),
            supabase_url: supabase_url.trim_end_matches('/').to_string(),
            supabase_key: supabase_key.to_string(),
            session: RwLock::new(None),
            refreshing: Mutex::new(()),
            on_session: RwLock::new(None),
            http,
        }
    }

    /// Called with the session JSON whenever it changes (sign-in, refresh), or none on sign-out.
    pub fn on_session_changed(&self, listener: SessionListener) {
        *self.on_session.write().unwrap() = Some(listener);
    }

    /// Restores a session saved by the app. Anything unreadable counts as signed out.
    pub fn set_session(&self, json: Option<String>) {
        *self.session.write().unwrap() = json.and_then(|j| serde_json::from_str(&j).ok());
    }

    pub fn has_session(&self) -> bool {
        self.session.read().unwrap().is_some()
    }

    /// `provider` is a Supabase provider name: "google" or "apple".
    pub fn start_sign_in(&self, provider: &str) -> SignInStart {
        let verifier = random_token(48);
        let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
        let url = format!(
            "{}/auth/v1/authorize?provider={}&redirect_to={}&code_challenge={challenge}&code_challenge_method=s256",
            self.supabase_url,
            encode(provider),
            encode(AUTH_REDIRECT),
        );
        SignInStart { url, verifier }
    }

    /// Exchanges the code from the callback for a session, and keeps it.
    pub fn finish_sign_in(&self, code: &str, verifier: &str) -> Result<(), BackendError> {
        let resp = self
            .http
            .post(format!("{}/auth/v1/token?grant_type=pkce", self.supabase_url))
            .header("apikey", &self.supabase_key)
            .json(&json!({ "auth_code": code, "code_verifier": verifier }))
            .send()
            .map_err(|e| BackendError::Offline(e.to_string()))?;
        let status = resp.status().as_u16();
        let body: Value = resp.json().unwrap_or(Value::Null);
        if !(200..300).contains(&status) {
            return Err(BackendError::Server(auth_error(&body).unwrap_or_else(|| format!("sign-in failed (HTTP {status})"))));
        }
        let session = Session::from_token_response(&body).ok_or_else(|| BackendError::Server("no session in response".into()))?;
        self.store(Some(session));
        Ok(())
    }

    pub fn sign_out(&self) {
        let token = self.session.read().unwrap().as_ref().map(|s| s.access_token.clone());
        if let Some(token) = token {
            let _ = self
                .http
                .post(format!("{}/auth/v1/logout", self.supabase_url))
                .header("apikey", &self.supabase_key)
                .bearer_auth(token)
                .send();
        }
        self.store(None);
    }

    pub fn account(&self) -> Result<Account, BackendError> {
        let body = self.send(|| self.http.get(self.url("/v1/account")), true)?;
        serde_json::from_value(body).map_err(|e| BackendError::Server(e.to_string()))
    }

    /// `plan` is a plan id from the plans table: "monthly", "yearly" or "lifetime".
    pub fn checkout_url(&self, plan: &str) -> Result<String, BackendError> {
        self.url_field("/v1/billing/checkout", json!({ "plan": plan }))
    }

    pub fn portal_url(&self) -> Result<String, BackendError> {
        self.url_field("/v1/billing/portal", json!({}))
    }

    fn url_field(&self, path: &str, body: Value) -> Result<String, BackendError> {
        let body = self.post(path, &body, true)?;
        body.get("url").and_then(Value::as_str).map(str::to_string).ok_or_else(|| BackendError::Server("no url in response".into()))
    }

    fn store(&self, session: Option<Session>) {
        let json = session.as_ref().and_then(|s| serde_json::to_string(s).ok());
        *self.session.write().unwrap() = session;
        if let Some(listener) = self.on_session.read().unwrap().as_ref() {
            listener(json);
        }
    }

    /// A usable access token, refreshing first if it's about to expire.
    fn access_token(&self, force_refresh: bool) -> Result<String, BackendError> {
        if !force_refresh {
            if let Some(s) = self.session.read().unwrap().as_ref().filter(|s| s.fresh()) {
                return Ok(s.access_token.clone());
            }
        }
        let stale = self.session.read().unwrap().as_ref().map(|s| s.access_token.clone()).ok_or(BackendError::SignedOut)?;
        let _guard = self.refreshing.lock().unwrap();
        // Another thread may have refreshed while we waited.
        let current = self.session.read().unwrap().clone().ok_or(BackendError::SignedOut)?;
        if current.access_token != stale && current.fresh() {
            return Ok(current.access_token);
        }
        let resp = self
            .http
            .post(format!("{}/auth/v1/token?grant_type=refresh_token", self.supabase_url))
            .header("apikey", &self.supabase_key)
            .json(&json!({ "refresh_token": current.refresh_token }))
            .send()
            .map_err(|e| BackendError::Offline(e.to_string()))?;
        let status = resp.status().as_u16();
        let body: Value = resp.json().unwrap_or(Value::Null);
        match status {
            200..=299 => {
                let session = Session::from_token_response(&body).ok_or_else(|| BackendError::Server("no session in refresh".into()))?;
                let token = session.access_token.clone();
                self.store(Some(session));
                Ok(token)
            }
            // The refresh token was revoked, reused or expired: the user has to sign in again.
            400 | 401 | 403 => {
                self.store(None);
                Err(BackendError::SignedOut)
            }
            _ => Err(BackendError::Server(auth_error(&body).unwrap_or_else(|| format!("refresh failed (HTTP {status})")))),
        }
    }

    fn url(&self, path: &str) -> String {
        format!("{}{path}", self.base_url)
    }

    fn post(&self, path: &str, body: &Value, auth: bool) -> Result<Value, BackendError> {
        self.send(|| self.http.post(self.url(path)).json(body), auth)
    }

    /// Sends a request; on a 401 it refreshes the session once and retries.
    fn send(&self, build: impl Fn() -> reqwest::blocking::RequestBuilder, auth: bool) -> Result<Value, BackendError> {
        let mut retried = false;
        loop {
            let mut req = build();
            if auth {
                req = req.bearer_auth(self.access_token(retried)?);
            }
            let resp = req.send().map_err(|e| BackendError::Offline(e.to_string()))?;
            let status = resp.status().as_u16();
            if status == 401 && auth && !retried {
                retried = true;
                continue;
            }
            let body: Value = resp.json().unwrap_or(Value::Null);
            return match status {
                200..=299 => Ok(body),
                401 => Err(BackendError::SignedOut),
                402 => Err(match body.get("error").and_then(Value::as_str) {
                    Some("credits_exhausted") => BackendError::CreditsExhausted {
                        period_end: body.get("period_end").and_then(Value::as_str).map(str::to_string),
                    },
                    _ => BackendError::NoSubscription,
                }),
                _ => Err(BackendError::Server(
                    body.get("error").and_then(Value::as_str).map(str::to_string).unwrap_or_else(|| format!("HTTP {status}")),
                )),
            };
        }
    }
}

impl Renderer for Backend {
    fn render(&self, request: &SpeechRequest) -> Result<Rendered, BackendError> {
        let body = self.post("/v1/speak", &serde_json::to_value(request).unwrap_or(Value::Null), true)?;
        let text = body.get("text").and_then(Value::as_str).unwrap_or_default().to_string();
        let audio = body
            .get("audio_base64")
            .and_then(Value::as_str)
            .and_then(|b| STANDARD.decode(b).ok())
            .filter(|a| !a.is_empty())
            .ok_or_else(|| BackendError::Server("no audio in response".into()))?;
        let credits = serde_json::from_value::<Credits>(body).ok();
        Ok(Rendered { text, audio, credits })
    }
}

fn auth_error(body: &Value) -> Option<String> {
    ["error_description", "msg", "message", "error"]
        .iter()
        .find_map(|k| body.get(*k).and_then(Value::as_str))
        .map(str::to_string)
}

/// Percent-encodes everything but RFC 3986 unreserved characters.
fn encode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

fn now_secs() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

fn random_token(bytes: usize) -> String {
    let mut buf = vec![0u8; bytes];
    getrandom::fill(&mut buf).expect("system random source");
    URL_SAFE_NO_PAD.encode(buf)
}
