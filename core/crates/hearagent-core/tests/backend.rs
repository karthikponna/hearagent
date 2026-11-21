mod common;

use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine as _;
use common::event;
use hearagent_core::backend::{Backend, BackendError, Renderer, Session};
use hearagent_core::event::Agent;
use hearagent_core::speech::speech_for;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::sync::{mpsc, Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

struct Received {
    path: String,
    auth: String,
    apikey: String,
    body: Value,
}

/// Serves one canned response per request and reports what it received.
fn server(responses: Vec<(u16, Value)>) -> (String, mpsc::Receiver<Received>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        for (status, body) in responses {
            let (stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut request_line = String::new();
            reader.read_line(&mut request_line).unwrap();
            let (mut auth, mut apikey, mut len) = (String::new(), String::new(), 0usize);
            loop {
                let mut line = String::new();
                reader.read_line(&mut line).unwrap();
                if line == "\r\n" {
                    break;
                }
                let lower = line.to_lowercase();
                if let Some(v) = lower.strip_prefix("content-length:") {
                    len = v.trim().parse().unwrap();
                }
                if lower.starts_with("authorization:") {
                    auth = line["authorization:".len()..].trim().to_string();
                }
                if lower.starts_with("apikey:") {
                    apikey = line["apikey:".len()..].trim().to_string();
                }
            }
            let mut buf = vec![0; len];
            reader.read_exact(&mut buf).unwrap();
            let body_in = serde_json::from_slice(&buf).unwrap_or(Value::Null);
            let path = request_line.split_whitespace().nth(1).unwrap_or_default().to_string();
            tx.send(Received { path, auth, apikey, body: body_in }).unwrap();
            let text = body.to_string();
            let mut stream = stream;
            write!(stream, "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{text}", text.len()).unwrap();
        }
    });
    (base, rx)
}

fn now() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as i64
}

fn session(access: &str, expires_in: i64) -> Option<String> {
    Some(serde_json::to_string(&Session { access_token: access.into(), refresh_token: "rt_1".into(), expires_at: now() + expires_in }).unwrap())
}

/// A backend whose session changes are recorded.
fn client(base: &str) -> (Backend, Arc<Mutex<Vec<Option<String>>>>) {
    let b = Backend::new(base, base, "sb_publishable_test");
    let seen = Arc::new(Mutex::new(Vec::new()));
    let log = seen.clone();
    b.on_session_changed(Box::new(move |s| log.lock().unwrap().push(s)));
    (b, seen)
}

#[test]
fn render_sends_request_and_decodes_audio() {
    let audio = vec![0x49, 0x44, 0x33, 7, 7];
    let (base, rx) = server(vec![(
        200,
        json!({"text": "Hey, auth service is done.", "audio_base64": STANDARD.encode(&audio), "credits_remaining": 149_000, "credits_total": 150_000, "period_end": "2026-12-14T00:00:00Z"}),
    )]);
    let (backend, _) = client(&base);
    backend.set_session(session("jwt_abc", 3600));
    let req = speech_for(&event(Agent::ClaudeCode, "claude_stop_transcript.json")).unwrap();
    let out = backend.render(&req).unwrap();
    assert_eq!(out.text, "Hey, auth service is done.");
    assert_eq!(out.audio, audio);
    assert_eq!(out.credits.unwrap().credits_remaining, 149_000);

    let r = rx.recv().unwrap();
    assert_eq!(r.path, "/v1/speak");
    assert_eq!(r.auth, "Bearer jwt_abc");
    assert_eq!(r.body["kind"], "summary");
    assert_eq!(r.body["name"], "auth service");
}

#[test]
fn errors_map_to_account_states() {
    let (base, _rx) = server(vec![
        (402, json!({"error": "no_subscription"})),
        (402, json!({"error": "credits_exhausted", "period_end": "2026-12-14T00:00:00Z"})),
        (500, json!({"error": "tts_failed"})),
    ]);
    let (backend, _) = client(&base);
    backend.set_session(session("t", 3600));
    let req = speech_for(&event(Agent::ClaudeCode, "claude_permission.json")).unwrap();
    assert_eq!(backend.render(&req), Err(BackendError::NoSubscription));
    assert_eq!(backend.render(&req), Err(BackendError::CreditsExhausted { period_end: Some("2026-12-14T00:00:00Z".into()) }));
    assert_eq!(backend.render(&req), Err(BackendError::Server("tts_failed".into())));
}

#[test]
fn no_session_and_no_network() {
    let req = speech_for(&event(Agent::ClaudeCode, "claude_permission.json")).unwrap();
    let (signed_out, _) = client("http://127.0.0.1:9");
    assert_eq!(signed_out.render(&req), Err(BackendError::SignedOut));
    // A token saved by an older build isn't a session.
    signed_out.set_session(Some("ha_legacy".into()));
    assert!(!signed_out.has_session());

    signed_out.set_session(session("t", 3600));
    assert!(matches!(signed_out.render(&req), Err(BackendError::Offline(_))));
}

#[test]
fn sign_in_uses_supabase_pkce() {
    let (base, rx) = server(vec![(200, json!({"access_token": "jwt_new", "refresh_token": "rt_new", "expires_in": 3600, "token_type": "bearer"}))]);
    let (backend, seen) = client(&base);
    let start = backend.start_sign_in("apple");
    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(start.verifier.as_bytes()));
    assert_eq!(
        start.url,
        format!("{base}/auth/v1/authorize?provider=apple&redirect_to=hearagent%3A%2F%2Fauth&code_challenge={challenge}&code_challenge_method=s256")
    );

    backend.finish_sign_in("code123", &start.verifier).unwrap();
    assert!(backend.has_session());
    let r = rx.recv().unwrap();
    assert_eq!(r.path, "/auth/v1/token?grant_type=pkce");
    assert_eq!(r.apikey, "sb_publishable_test");
    assert_eq!(r.body, json!({"auth_code": "code123", "code_verifier": start.verifier}));
    let saved: Session = serde_json::from_str(seen.lock().unwrap()[0].as_ref().unwrap()).unwrap();
    assert_eq!((saved.access_token.as_str(), saved.refresh_token.as_str()), ("jwt_new", "rt_new"));
}

#[test]
fn refreshes_an_expiring_token_before_calling() {
    let (base, rx) = server(vec![
        (200, json!({"access_token": "jwt_2", "refresh_token": "rt_2", "expires_in": 3600})),
        (200, json!({"email": "a@example.com", "subscription": null})),
    ]);
    let (backend, seen) = client(&base);
    backend.set_session(session("jwt_1", 10));
    assert_eq!(backend.account().unwrap().email, "a@example.com");

    let refresh = rx.recv().unwrap();
    assert_eq!(refresh.path, "/auth/v1/token?grant_type=refresh_token");
    assert_eq!(refresh.body, json!({"refresh_token": "rt_1"}));
    assert_eq!(rx.recv().unwrap().auth, "Bearer jwt_2");
    assert!(seen.lock().unwrap()[0].as_ref().unwrap().contains("rt_2"));
}

#[test]
fn retries_once_after_a_401_and_signs_out_when_the_refresh_token_is_dead() {
    let (base, rx) = server(vec![
        (401, json!({"error": "unauthorized"})),
        (200, json!({"access_token": "jwt_2", "refresh_token": "rt_2", "expires_in": 3600})),
        (200, json!({"email": "a@example.com", "subscription": null})),
    ]);
    let (backend, _) = client(&base);
    backend.set_session(session("jwt_1", 3600));
    assert!(backend.account().is_ok());
    let paths: Vec<String> = rx.try_iter().map(|r| r.path).collect();
    assert_eq!(paths, ["/v1/account", "/auth/v1/token?grant_type=refresh_token", "/v1/account"]);

    let (base, _rx) = server(vec![(400, json!({"error_description": "Invalid Refresh Token: Already Used"}))]);
    let (backend, seen) = client(&base);
    backend.set_session(session("jwt_1", 5));
    assert_eq!(backend.account(), Err(BackendError::SignedOut));
    assert!(!backend.has_session());
    assert_eq!(seen.lock().unwrap().as_slice(), [None]);
}

#[test]
fn checkout_sends_the_plan() {
    let (base, rx) = server(vec![(200, json!({"url": "https://checkout.dodo/x"}))]);
    let (backend, _) = client(&base);
    backend.set_session(session("t", 3600));
    assert_eq!(backend.checkout_url("lifetime").unwrap(), "https://checkout.dodo/x");
    let r = rx.recv().unwrap();
    assert_eq!((r.path.as_str(), r.body), ("/v1/billing/checkout", json!({"plan": "lifetime"})));
}
