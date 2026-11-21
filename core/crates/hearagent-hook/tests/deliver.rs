use hearagent_core::bus::{BusHandler, Decision, EventServer, Reply};
use hearagent_core::event::{Agent, AgentEvent};
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{mpsc, Arc};
use std::time::{Duration, Instant};

fn fixture_bytes(name: &str) -> Vec<u8> {
    std::fs::read(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures").join(name)).unwrap()
}

fn run_hook(agent: &str, sock: &std::path::Path, payload: &[u8]) -> std::process::Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_hearagent-hook"))
        .arg(agent)
        .env("HEARAGENT_SOCKET", sock)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(payload).unwrap();
    child.wait_with_output().unwrap()
}

#[test]
fn hook_delivers_event_to_running_app() {
    let dir = tempfile::tempdir().unwrap();
    let sock = dir.path().join("events.sock");
    let (tx, rx) = mpsc::channel();
    let _server = EventServer::start(&sock, move |ev| tx.send(ev).unwrap()).unwrap();

    let payload = fixture_bytes("claude_stop.json");
    let out = run_hook("claude-code", &sock, &payload);
    assert!(out.status.success());
    assert!(out.stdout.is_empty(), "hook must print nothing");

    let got = rx.recv_timeout(Duration::from_secs(2)).unwrap();
    let expected = AgentEvent::from_hook_payload(Agent::ClaudeCode, &serde_json::from_slice(&payload).unwrap()).unwrap();
    assert_eq!(got.kind, expected.kind);
    assert_eq!(got.session_id, expected.session_id);
}

struct Answer(Decision, mpsc::Sender<AgentEvent>);

impl BusHandler for Answer {
    fn event(&self, _event: AgentEvent) {}
    fn approval(&self, event: AgentEvent, reply: Arc<Reply>) {
        self.1.send(event).unwrap();
        reply.send(&self.0);
    }
    fn approval_closed(&self, _reply_id: u64) {}
}

fn answered(decision: Decision) -> (std::process::Output, AgentEvent) {
    let dir = tempfile::tempdir().unwrap();
    let sock = dir.path().join("events.sock");
    let (tx, rx) = mpsc::channel();
    let _server = EventServer::start_with(&sock, Arc::new(Answer(decision, tx))).unwrap();
    let out = run_hook("claude-code", &sock, &fixture_bytes("claude_permission.json"));
    (out, rx.recv_timeout(Duration::from_secs(2)).unwrap())
}

#[test]
fn approval_allowed_from_the_app_prints_the_decision() {
    let (out, event) = answered(Decision::Allow);
    assert!(out.status.success());
    assert!(event.extra.awaits_decision);
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_eq!(v["hookSpecificOutput"]["hookEventName"], "PermissionRequest");
    assert_eq!(v["hookSpecificOutput"]["decision"]["behavior"], "allow");
}

#[test]
fn approval_denied_from_the_app_prints_a_reason() {
    let (out, _) = answered(Decision::Deny { message: String::new() });
    let v: serde_json::Value = serde_json::from_slice(&out.stdout).unwrap();
    assert_eq!(v["hookSpecificOutput"]["decision"]["behavior"], "deny");
    assert!(v["hookSpecificOutput"]["decision"]["message"].as_str().is_some_and(|m| !m.is_empty()));
}

#[test]
fn approval_left_to_the_terminal_prints_nothing() {
    let (out, _) = answered(Decision::Ask);
    assert!(out.status.success());
    assert!(out.stdout.is_empty());
}

#[test]
fn hook_exits_quickly_when_app_is_not_running() {
    let dir = tempfile::tempdir().unwrap();
    let start = Instant::now();
    let out = run_hook("codex", &dir.path().join("none.sock"), &fixture_bytes("codex_stop.json"));
    assert!(out.status.success());
    assert!(start.elapsed() < Duration::from_secs(1));
}
