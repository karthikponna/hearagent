use hearagent_core::backend::{Backend, BackendError, Credits, Rendered, Renderer};
use hearagent_core::bus::{request_decision, send_event, Decision};
use hearagent_core::event::{Agent, AgentEvent, EventKind};
use hearagent_core::location::Location;
use hearagent_core::speech::{SpeechKind, SpeechRequest};
use hearagent_ffi::{Engine, EngineListener, HearAccountState, HearAllowRule, HearDecision, HearSession, HearSessionStatus, HearUtterance};
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
    fn session_changed(&self, _session: Option<String>) {}
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
    let backend = Arc::new(Backend::new("http://127.0.0.1:9", "http://127.0.0.1:9", "sb_publishable_test"));
    (Engine::build(listener, backend, Arc::new(FakeBackend { fail_with })), (rx, srx))
}

fn ev(sid: &str, project: &str, kind: EventKind) -> AgentEvent {
    AgentEvent {
        agent: Agent::ClaudeCode,
        session_id: sid.into(),
        cwd: format!("/w/{project}"),
        location: Location { project: project.into(), worktree: None, branch: None },
        kind,
        extra: Default::default(),
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
    assert!(!engine.clone().inject_payload("claude-code".into(), r#"{"hook_event_name":"PostToolUse"}"#.into()));
}

fn approval_event() -> AgentEvent {
    let mut e = ev("p", "billing", EventKind::ApprovalNeeded { tool: "Bash".into(), action: "run pnpm prisma migrate deploy".into() });
    e.extra.subject = "pnpm prisma migrate deploy".into();
    e
}

fn wait_for_pending(engine: &Engine) -> u64 {
    for _ in 0..100 {
        if let Some(p) = engine.sessions().into_iter().find_map(|s| s.pending) {
            return p.id;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    panic!("no pending approval");
}

#[test]
fn approvals_wait_for_a_decision_from_the_app() {
    let dir = tempfile::tempdir().unwrap();
    let sock = dir.path().join("e.sock");
    let (engine, _) = engine(None);
    engine.clone().start(Some(sock.to_string_lossy().into())).unwrap();

    let hook_sock = sock.clone();
    let hook = std::thread::spawn(move || request_decision(&hook_sock, &approval_event(), Duration::from_secs(5)));
    let id = wait_for_pending(&engine);
    let session = engine.sessions().into_iter().find(|s| s.pending.is_some()).unwrap();
    assert_eq!(session.status, HearSessionStatus::NeedsYou);
    assert_eq!(session.pending.unwrap().subject, "pnpm prisma migrate deploy");

    assert!(engine.decide(id, HearDecision::Allow));
    assert_eq!(hook.join().unwrap(), Some(Decision::Allow));
    let after = engine.sessions().into_iter().find(|s| s.key.ends_with(":p")).unwrap();
    assert!(after.pending.is_none());
    assert_eq!(after.status, HearSessionStatus::Working);
    engine.stop();
}

#[test]
fn always_allow_rules_answer_without_asking() {
    let dir = tempfile::tempdir().unwrap();
    let sock = dir.path().join("e.sock");
    let (engine, _) = engine(None);
    engine.clone().start(Some(sock.to_string_lossy().into())).unwrap();
    engine.set_allow_rules(vec![HearAllowRule { tool: "Bash".into(), pattern: "pnpm prisma *".into() }]);
    assert_eq!(request_decision(&sock, &approval_event(), Duration::from_secs(2)), Some(Decision::Allow));
    assert!(engine.sessions().iter().all(|s| s.pending.is_none()));
    engine.stop();
}

#[test]
fn pending_clears_when_the_hook_goes_away() {
    let dir = tempfile::tempdir().unwrap();
    let sock = dir.path().join("e.sock");
    let (engine, _) = engine(None);
    engine.clone().start(Some(sock.to_string_lossy().into())).unwrap();
    let hook_sock = sock.clone();
    let hook = std::thread::spawn(move || request_decision(&hook_sock, &approval_event(), Duration::from_millis(300)));
    let id = wait_for_pending(&engine);
    assert_eq!(hook.join().unwrap(), None);
    std::thread::sleep(Duration::from_millis(100));
    assert!(engine.sessions().iter().all(|s| s.pending.is_none()));
    assert!(!engine.decide(id, HearDecision::Allow), "the hook is gone");
    engine.stop();
}
