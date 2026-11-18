//! Client for the Hear Agent backend (Cloudflare Worker). The backend holds the
//! OpenAI and ElevenLabs keys; the app only ever holds the user's session token.

use crate::speech::SpeechRequest;
use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine as _;
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::sync::RwLock;
use std::time::Duration;

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
    pub plan_name: String,
    pub credits_total: i64,
    pub credits_used: i64,
    pub credits_remaining: i64,
    #[serde(default)]
    pub period_end: Option<String>,
    #[serde(default)]
    pub cancel_at_period_end: bool,
}

/// A sign-in attempt: open `url` in the browser, then finish with `verifier`
/// when the `hearagent://auth` callback arrives carrying `state`.
#[derive(Debug, Clone, PartialEq)]
pub struct SignInStart {
    pub url: String,
    pub state: String,
    pub verifier: String,
}

pub struct Backend {
    base_url: String,
    token: RwLock<Option<String>>,
    http: reqwest::blocking::Client,
}

impl Backend {
    pub fn new(base_url: &str) -> Backend {
        let http = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(30))
            .connect_timeout(Duration::from_secs(8))
            .user_agent(concat!("HearAgent/", env!("CARGO_PKG_VERSION")))
            .build()
            .expect("http client");
        Backend { base_url: base_url.trim_end_matches('/').to_string(), token: RwLock::new(None), http }
    }

    pub fn set_token(&self, token: Option<String>) {
        *self.token.write().unwrap() = token;
    }

    pub fn has_token(&self) -> bool {
        self.token.read().unwrap().is_some()
    }

    pub fn start_sign_in(&self) -> SignInStart {
        let verifier = random_token(32);
        let state = random_token(16);
        let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
        let url = format!("{}/auth/google/start?app_state={state}&code_challenge={challenge}", self.base_url);
        SignInStart { url, state, verifier }
    }

    /// Exchanges the one-time code from the callback for a session token, and keeps it.
    pub fn finish_sign_in(&self, code: &str, verifier: &str) -> Result<String, BackendError> {
        let body = self.post("/auth/exchange", &json!({ "code": code, "code_verifier": verifier }), false)?;
        let token = body.get("token").and_then(Value::as_str).ok_or_else(|| BackendError::Server("no token in response".into()))?;
        self.set_token(Some(token.to_string()));
        Ok(token.to_string())
    }

    pub fn sign_out(&self) {
        if self.has_token() {
            let _ = self.post("/auth/sign-out", &json!({}), true);
        }
        self.set_token(None);
    }

    pub fn account(&self) -> Result<Account, BackendError> {
        let body = self.send(self.http.get(self.url("/v1/account")), true)?;
        serde_json::from_value(body).map_err(|e| BackendError::Server(e.to_string()))
    }

    pub fn checkout_url(&self) -> Result<String, BackendError> {
        self.url_field("/v1/billing/checkout")
    }

    pub fn portal_url(&self) -> Result<String, BackendError> {
        self.url_field("/v1/billing/portal")
    }

    fn url_field(&self, path: &str) -> Result<String, BackendError> {
        let body = self.post(path, &json!({}), true)?;
        body.get("url").and_then(Value::as_str).map(str::to_string).ok_or_else(|| BackendError::Server("no url in response".into()))
    }

    fn url(&self, path: &str) -> String {
        format!("{}{path}", self.base_url)
    }

    fn post(&self, path: &str, body: &Value, auth: bool) -> Result<Value, BackendError> {
        self.send(self.http.post(self.url(path)).json(body), auth)
    }

    fn send(&self, mut req: reqwest::blocking::RequestBuilder, auth: bool) -> Result<Value, BackendError> {
        if auth {
            let token = self.token.read().unwrap().clone().ok_or(BackendError::SignedOut)?;
            req = req.bearer_auth(token);
        }
        let resp = req.send().map_err(|e| BackendError::Offline(e.to_string()))?;
        let status = resp.status().as_u16();
        let body: Value = resp.json().unwrap_or(Value::Null);
        match status {
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

fn random_token(bytes: usize) -> String {
    let mut buf = vec![0u8; bytes];
    getrandom::fill(&mut buf).expect("system random source");
    URL_SAFE_NO_PAD.encode(buf)
}
