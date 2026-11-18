use hearagent_core::backend::{Backend, BackendError, Credits, Rendered, Renderer};
use hearagent_core::bus::send_event;
use hearagent_core::event::{Agent, AgentEvent, EventKind};
use hearagent_core::location::Location;
use hearagent_core::speech::{SpeechKind, SpeechRequest};
use hearagent_ffi::{Engine, EngineListener, HearAccountState, HearSession, HearUtterance};
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;

struct Recorder {
    spoken: Mutex<mpsc::Sender<HearUtterance>>,
    states: Mutex<mpsc::Sender<HearAccountState>>,
}

impl EngineListener for Recorder {
    fn speak(&self, utterance: HearUtterance) {
        self.spoken.lock().unwrap().send(utterance).unwrap();
    }
    fn sessions_changed(&self, _sessions: Vec<HearSession>) {}
    fn account_state_changed(&self, state: HearAccountState) {
        self.states.lock().unwrap().send(state).unwrap();
    }
}

/// Fake backend: summaries take longer than approvals, like the real one.
struct FakeBackend {
    fail_with: Option<BackendError>,
}

impl Renderer for FakeBackend {
    fn render(&self, req: &SpeechRequest) -> Result<Rendered, BackendError> {
        if let Some(e) = &self.fail_with {
            return Err(e.clone());
        }
        let text = match req.kind {
            SpeechKind::Approval => req.text.clone().unwrap(),
            SpeechKind::Summary => {
                std::thread::sleep(Duration::from_millis(150));
                format!("Hey, {} just finished.", req.name)
            }
            SpeechKind::StopFailure => format!("Heads up, {} stopped.", req.name),
        };
        Ok(Rendered {
            text,
            audio: vec![1, 2, 3],
            credits: Some(Credits { credits_remaining: 1000, credits_total: 150_000, period_end: None }),
        })
    }
}

type Channels = (mpsc::Receiver<HearUtterance>, mpsc::Receiver<HearAccountState>);

fn engine(fail_with: Option<BackendError>) -> (Arc<Engine>, Channels) {
    let (tx, rx) = mpsc::channel();
    let (stx, srx) = mpsc::channel();
    let listener = Arc::new(Recorder { spoken: Mutex::new(tx), states: Mutex::new(stx) });
    let backend = Arc::new(Backend::new("http://127.0.0.1:9"));
    (Engine::build(listener, backend, Arc::new(FakeBackend { fail_with })), (rx, srx))
}

fn ev(sid: &str, project: &str, kind: EventKind) -> AgentEvent {
    AgentEvent {
        agent: Agent::ClaudeCode,
        session_id: sid.into(),
        cwd: format!("/w/{project}"),
        location: Location { project: project.into(), worktree: None, branch: None },
        kind,
    }
}

#[test]
fn renders_and_plays_in_priority_order() {
    let dir = tempfile::tempdir().unwrap();
    let sock = dir.path().join("e.sock");
    let (engine, (rx, states)) = engine(None);
    engine.clone().start(Some(sock.to_string_lossy().into())).unwrap();

    send_event(&sock, &ev("a", "api", EventKind::Finished { message: "API done.".into(), digest: None })).unwrap();
    let first = rx.recv_timeout(Duration::from_secs(2)).unwrap();
    assert_eq!(first.text, "Hey, api just finished.");
    assert_eq!(first.audio, vec![1, 2, 3]);
    assert!(matches!(states.recv_timeout(Duration::from_secs(1)).unwrap(), HearAccountState::Active { credits_remaining: 1000, .. }));

    // While "api" plays, a summary and an approval arrive; the approval plays first.
    send_event(&sock, &ev("b", "web", EventKind::Finished { message: "Web done.".into(), digest: None })).unwrap();
    send_event(&sock, &ev("c", "ios", EventKind::ApprovalNeeded { tool: "Bash".into(), action: "run rm -rf build".into() })).unwrap();
    std::thread::sleep(Duration::from_millis(400));
    assert!(rx.try_recv().is_err(), "nothing plays until playback finishes");

    engine.speech_finished();
    assert_eq!(rx.recv_timeout(Duration::from_secs(2)).unwrap().text, "ios needs approval to run rm -rf build.");
    engine.speech_finished();
    assert_eq!(rx.recv_timeout(Duration::from_secs(2)).unwrap().text, "Hey, web just finished.");
    engine.stop();
}

#[test]
fn backend_refusal_reports_account_state_and_stays_silent() {
    let (engine, (rx, states)) = engine(Some(BackendError::CreditsExhausted { period_end: Some("2026-12-14".into()) }));
    let payload = r#"{"session_id":"x","cwd":"/w/shop","hook_event_name":"Stop","last_assistant_message":"Checkout works."}"#;
    assert!(engine.clone().inject_payload("claude-code".into(), payload.into()));
    assert_eq!(
        states.recv_timeout(Duration::from_secs(1)).unwrap(),
        HearAccountState::CreditsExhausted { period_end: Some("2026-12-14".into()) }
    );
    assert!(rx.recv_timeout(Duration::from_millis(300)).is_err(), "no fallback voice");
}

#[test]
fn unknown_payloads_are_rejected() {
    let (engine, _) = engine(None);
    assert!(!engine.clone().inject_payload("unknown-agent".into(), "{}".into()));
    assert!(!engine.clone().inject_payload("claude-code".into(), r#"{"hook_event_name":"PreToolUse"}"#.into()));
}
