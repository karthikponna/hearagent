mod common;

use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine as _;
use common::event;
use hearagent_core::backend::{Backend, BackendError, Renderer};
use hearagent_core::event::Agent;
use hearagent_core::speech::speech_for;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::sync::mpsc;

/// Serves one canned response per request and reports what it received.
fn server(responses: Vec<(u16, Value)>) -> (String, mpsc::Receiver<(String, String, Value)>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        for (status, body) in responses {
            let (stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut request_line = String::new();
            reader.read_line(&mut request_line).unwrap();
            let (mut auth, mut len) = (String::new(), 0usize);
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
            }
            let mut buf = vec![0; len];
            reader.read_exact(&mut buf).unwrap();
            let received = serde_json::from_slice(&buf).unwrap_or(Value::Null);
            let path = request_line.split_whitespace().nth(1).unwrap_or_default().to_string();
            tx.send((path, auth, received)).unwrap();
            let text = body.to_string();
            let mut stream = stream;
            write!(stream, "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{text}", text.len()).unwrap();
        }
    });
    (base, rx)
}

#[test]
fn render_sends_request_and_decodes_audio() {
    let audio = vec![0x49, 0x44, 0x33, 7, 7];
    let (base, rx) = server(vec![(
        200,
        json!({"text": "Hey, auth service is done.", "audio_base64": STANDARD.encode(&audio), "credits_remaining": 149_000, "credits_total": 150_000, "period_end": "2026-12-14T00:00:00Z"}),
    )]);
    let backend = Backend::new(&base);
    backend.set_token(Some("ha_abc".into()));
    let req = speech_for(&event(Agent::ClaudeCode, "claude_stop_transcript.json")).unwrap();
    let out = backend.render(&req).unwrap();
    assert_eq!(out.text, "Hey, auth service is done.");
    assert_eq!(out.audio, audio);
    assert_eq!(out.credits.unwrap().credits_remaining, 149_000);

    let (path, auth, body) = rx.recv().unwrap();
    assert_eq!(path, "/v1/speak");
    assert_eq!(auth, "Bearer ha_abc");
    assert_eq!(body["kind"], "summary");
    assert_eq!(body["name"], "auth service");
}

#[test]
fn errors_map_to_account_states() {
    let (base, _rx) = server(vec![
        (401, json!({"error": "unauthorized"})),
        (402, json!({"error": "no_subscription"})),
        (402, json!({"error": "credits_exhausted", "period_end": "2026-12-14T00:00:00Z"})),
        (500, json!({"error": "tts_failed"})),
    ]);
    let backend = Backend::new(&base);
    backend.set_token(Some("t".into()));
    let req = speech_for(&event(Agent::ClaudeCode, "claude_permission.json")).unwrap();
    assert_eq!(backend.render(&req), Err(BackendError::SignedOut));
    assert_eq!(backend.render(&req), Err(BackendError::NoSubscription));
    assert_eq!(backend.render(&req), Err(BackendError::CreditsExhausted { period_end: Some("2026-12-14T00:00:00Z".into()) }));
    assert_eq!(backend.render(&req), Err(BackendError::Server("tts_failed".into())));
}

#[test]
fn no_token_and_no_network() {
    let req = speech_for(&event(Agent::ClaudeCode, "claude_permission.json")).unwrap();
    let signed_out = Backend::new("http://127.0.0.1:9");
    assert_eq!(signed_out.render(&req), Err(BackendError::SignedOut));

    signed_out.set_token(Some("t".into()));
    assert!(matches!(signed_out.render(&req), Err(BackendError::Offline(_))));
}

#[test]
fn sign_in_uses_pkce() {
    let (base, rx) = server(vec![(200, json!({"token": "ha_new"}))]);
    let backend = Backend::new(&base);
    let start = backend.start_sign_in();
    let expected_challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(start.verifier.as_bytes()));
    assert!(start.url.starts_with(&format!("{base}/auth/google/start?")));
    assert!(start.url.contains(&format!("app_state={}", start.state)));
    assert!(start.url.contains(&format!("code_challenge={expected_challenge}")));

    assert_eq!(backend.finish_sign_in("code123", &start.verifier).unwrap(), "ha_new");
    assert!(backend.has_token());
    let (path, _, body) = rx.recv().unwrap();
    assert_eq!(path, "/auth/exchange");
    assert_eq!(body, json!({"code": "code123", "code_verifier": start.verifier}));
}
