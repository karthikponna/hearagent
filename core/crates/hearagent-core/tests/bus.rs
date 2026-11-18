mod common;

use common::event;
use hearagent_core::bus::{send_event, EventServer};
use hearagent_core::event::Agent;
use std::sync::mpsc;
use std::time::Duration;

#[test]
fn events_round_trip_through_socket() {
    let dir = tempfile::tempdir().unwrap();
    let sock = dir.path().join("events.sock");
    let (tx, rx) = mpsc::channel();
    let server = EventServer::start(&sock, move |ev| tx.send(ev).unwrap()).unwrap();

    let a = event(Agent::ClaudeCode, "claude_stop.json");
    let b = event(Agent::Codex, "codex_stop.json");
    send_event(&sock, &a).unwrap();
    send_event(&sock, &b).unwrap();

    let mut got = vec![
        rx.recv_timeout(Duration::from_secs(2)).unwrap(),
        rx.recv_timeout(Duration::from_secs(2)).unwrap(),
    ];
    got.sort_by(|x, y| x.session_id.cmp(&y.session_id));
    assert_eq!(got, vec![a, b]);

    drop(server);
    assert!(!sock.exists(), "socket file is removed on shutdown");
}

#[test]
fn send_fails_fast_without_server() {
    let dir = tempfile::tempdir().unwrap();
    let ev = event(Agent::ClaudeCode, "claude_stop.json");
    assert!(send_event(&dir.path().join("missing.sock"), &ev).is_err());
}
