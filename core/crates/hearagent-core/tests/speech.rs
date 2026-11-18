mod common;

use common::event;
use hearagent_core::event::Agent;
use hearagent_core::speech::{asks_user, speech_for, Priority, SpeechKind};
use serde_json::json;

#[test]
fn approval_is_a_fixed_sentence_starting_with_the_name() {
    let req = speech_for(&event(Agent::ClaudeCode, "claude_permission.json")).unwrap();
    assert_eq!(req.kind, SpeechKind::Approval);
    assert_eq!(req.priority, Priority::NeedsYou);
    assert_eq!(req.text.as_deref(), Some("auth service needs approval to remove node_modules directory."));
}

#[test]
fn finished_turn_requests_a_summary_with_context() {
    let req = speech_for(&event(Agent::ClaudeCode, "claude_stop_transcript.json")).unwrap();
    assert_eq!(req.kind, SpeechKind::Summary);
    assert_eq!(req.priority, Priority::Done);
    assert_eq!(req.name, "auth service");
    assert!(req.digest.is_some());

    let body = serde_json::to_value(&req).unwrap();
    assert_eq!(body["kind"], "summary");
    assert_eq!(body["agent"], "Claude");
    assert_eq!(body["digest"]["failures"].as_array().unwrap().len(), 1);
    assert!(body.get("text").is_none(), "unset fields are omitted");
    assert!(body.get("session_key").is_none(), "engine-only fields stay local");
}

#[test]
fn stop_failure_is_failed_priority() {
    let req = speech_for(&event(Agent::ClaudeCode, "claude_stop_failure.json")).unwrap();
    assert_eq!((req.kind, req.priority), (SpeechKind::StopFailure, Priority::Failed));
    assert_eq!(req.error.as_deref(), Some("rate_limit | 429 Too Many Requests | API Error: Rate limit reached"));
}

#[test]
fn prompts_are_not_spoken() {
    assert!(speech_for(&event(Agent::ClaudeCode, "claude_prompt.json")).is_none());
}

#[test]
fn questions_to_the_user_raise_priority() {
    assert!(asks_user("I found two libraries. Should I use OAuth or API keys?"));
    assert!(!asks_user("Done. Want me to also add caching?"));
    assert!(!asks_user("All tests pass."));
    let payload = json!({"hook_event_name": "Stop", "cwd": "/x/web", "last_assistant_message": "Which database should I use?"});
    let ev = hearagent_core::event::AgentEvent::from_hook_payload(Agent::ClaudeCode, &payload).unwrap();
    assert_eq!(speech_for(&ev).unwrap().priority, Priority::NeedsYou);
}
