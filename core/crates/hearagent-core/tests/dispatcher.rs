use hearagent_core::dispatcher::{Dispatcher, DispatcherConfig, ReadySpeech, SessionStatus};
use hearagent_core::event::{Agent, AgentEvent, EventKind};
use hearagent_core::location::Location;
use hearagent_core::speech::{Priority, SpeechKind, SpeechRequest};

fn ev(agent: Agent, sid: &str, project: &str, kind: EventKind) -> AgentEvent {
    AgentEvent {
        agent,
        session_id: sid.into(),
        cwd: format!("/work/{project}"),
        location: Location { project: project.into(), worktree: None, branch: None },
        kind,
        extra: Default::default(),
    }
}
fn done(msg: &str) -> EventKind {
    EventKind::Finished { message: msg.into(), digest: None }
}
fn approval(action: &str) -> EventKind {
    EventKind::ApprovalNeeded { tool: "Bash".into(), action: action.into() }
}
fn stopped() -> EventKind {
    EventKind::StoppedWithError { error: "rate_limit".into(), details: String::new(), message: String::new() }
}

/// Stands in for the backend: the spoken text is the request's fixed text or its kind.
fn render(req: &SpeechRequest) -> ReadySpeech {
    ReadySpeech {
        request_id: req.id,
        session_key: req.session_key.clone(),
        session_seq: req.session_seq,
        kind: req.kind,
        priority: req.priority,
        text: req.text.clone().unwrap_or_else(|| format!("{:?} for {}", req.kind, req.name)),
        audio: vec![1, 2, 3],
    }
}

fn drain(d: &mut Dispatcher, now: u64) -> Vec<String> {
    let mut out = vec![];
    while let Some(s) = d.next(now) {
        out.push(s.text);
        d.speech_finished();
    }
    out
}

#[test]
fn only_approval_finish_and_stop_are_spoken() {
    let mut d = Dispatcher::new(DispatcherConfig::default());
    assert!(d.ingest(ev(Agent::ClaudeCode, "a", "api", EventKind::SessionStarted), 0).is_none());
    assert!(d.ingest(ev(Agent::ClaudeCode, "a", "api", EventKind::PromptSubmitted), 1).is_none());
    assert_eq!(d.sessions()[0].status, SessionStatus::Working);
    assert_eq!(d.sessions()[0].last_update, "Working…");
    assert!(d.ingest(ev(Agent::ClaudeCode, "a", "api", approval("run npm test")), 2).is_some());
    assert!(d.ingest(ev(Agent::ClaudeCode, "a", "api", done("All green.")), 3).is_some());
    assert!(d.ingest(ev(Agent::ClaudeCode, "a", "api", stopped()), 4).is_some());
}

#[test]
fn three_sessions_play_by_urgency() {
    let mut d = Dispatcher::new(DispatcherConfig::default());
    let a = d.ingest(ev(Agent::ClaudeCode, "a", "auth-service", done("Login works.")), 0).unwrap();
    let b = d.ingest(ev(Agent::Codex, "b", "ios-app", stopped()), 10).unwrap();
    let c = d.ingest(ev(Agent::ClaudeCode, "c", "web", approval("remove node_modules directory")), 20).unwrap();
    // Renders finish in any order; playback still follows urgency.
    for r in [&a, &b, &c] {
        d.enqueue(render(r), 100);
    }
    assert_eq!(
        drain(&mut d, 200),
        vec!["web needs approval to remove node_modules directory.", "StopFailure for ios app", "Summary for auth service"]
    );
    let statuses: Vec<_> = d.sessions().iter().map(|s| s.status).collect();
    assert_eq!(statuses, vec![SessionStatus::NeedsYou, SessionStatus::Failed, SessionStatus::Done]);
}

#[test]
fn approval_is_dropped_if_session_moved_on_before_it_was_ready() {
    let mut d = Dispatcher::new(DispatcherConfig::default());
    let ask = d.ingest(ev(Agent::ClaudeCode, "a", "api", approval("run npm test")), 0).unwrap();
    // The user approved in the terminal; the turn finished before the audio came back.
    let fin = d.ingest(ev(Agent::ClaudeCode, "a", "api", done("Tests pass.")), 500).unwrap();
    d.enqueue(render(&ask), 900);
    d.enqueue(render(&fin), 1_000);
    assert_eq!(drain(&mut d, 1_000), vec!["Summary for api"]);
}

#[test]
fn queued_approval_is_dropped_when_session_continues() {
    let mut d = Dispatcher::new(DispatcherConfig::default());
    let other = d.ingest(ev(Agent::ClaudeCode, "z", "docs", done("Docs built.")), 0).unwrap();
    d.enqueue(render(&other), 0);
    let playing = d.next(0).unwrap();
    assert_eq!(playing.priority, Priority::Done);

    let ask = d.ingest(ev(Agent::ClaudeCode, "a", "api", approval("run npm test")), 10).unwrap();
    d.enqueue(render(&ask), 20);
    d.ingest(ev(Agent::ClaudeCode, "a", "api", EventKind::PromptSubmitted), 30);
    d.speech_finished();
    assert!(d.next(40).is_none(), "approval no longer relevant");
}

#[test]
fn one_line_at_a_time() {
    let mut d = Dispatcher::new(DispatcherConfig::default());
    for (sid, p) in [("a", "api"), ("b", "web")] {
        let r = d.ingest(ev(Agent::ClaudeCode, sid, p, done("ok")), 0).unwrap();
        d.enqueue(render(&r), 0);
    }
    assert!(d.next(0).is_some());
    assert!(d.next(0).is_none(), "waits for speech_finished");
    d.speech_finished();
    assert!(d.next(0).is_some());
}

#[test]
fn newer_summary_replaces_older_one_from_same_session() {
    let mut d = Dispatcher::new(DispatcherConfig::default());
    let first = d.ingest(ev(Agent::ClaudeCode, "a", "api", done("First.")), 0).unwrap();
    let second = d.ingest(ev(Agent::ClaudeCode, "a", "api", done("Second.")), 1).unwrap();
    d.enqueue(render(&first), 2);
    d.enqueue(render(&second), 3);
    assert_eq!(d.pending_len(), 1);
}

#[test]
fn pinned_session_wins_ties() {
    let mut d = Dispatcher::new(DispatcherConfig::default());
    let a = d.ingest(ev(Agent::ClaudeCode, "a", "api", done("API done.")), 0).unwrap();
    let b = d.ingest(ev(Agent::ClaudeCode, "b", "web", done("Web done.")), 0).unwrap();
    d.set_pinned(Some(&Dispatcher::session_key(Agent::ClaudeCode, "b")));
    d.enqueue(render(&a), 0);
    d.enqueue(render(&b), 1);
    assert_eq!(drain(&mut d, 2)[0], "Summary for web");
}

#[test]
fn muted_tracks_sessions_but_requests_nothing() {
    let mut d = Dispatcher::new(DispatcherConfig::default());
    d.set_muted(true);
    assert!(d.ingest(ev(Agent::ClaudeCode, "a", "api", approval("run x")), 0).is_none());
    assert_eq!(d.sessions()[0].status, SessionStatus::NeedsYou);
}

#[test]
fn stale_lines_are_dropped() {
    let mut d = Dispatcher::new(DispatcherConfig::default());
    let r = d.ingest(ev(Agent::ClaudeCode, "a", "api", done("Old news.")), 0).unwrap();
    d.enqueue(render(&r), 0);
    assert!(d.next(6 * 60_000).is_none());
}

#[test]
fn session_end_removes_session_and_its_lines() {
    let mut d = Dispatcher::new(DispatcherConfig::default());
    let r = d.ingest(ev(Agent::ClaudeCode, "a", "api", done("Done.")), 0).unwrap();
    d.ingest(ev(Agent::ClaudeCode, "a", "api", EventKind::SessionEnded), 1);
    d.enqueue(render(&r), 2);
    assert!(d.sessions().is_empty());
    assert!(d.next(3).is_none());
    assert_eq!(r.kind, SpeechKind::Summary);
}
