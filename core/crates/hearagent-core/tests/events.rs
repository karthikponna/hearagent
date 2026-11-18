mod common;

use common::{event, fixture};
use hearagent_core::event::{Agent, AgentEvent, EventKind};
use serde_json::json;

#[test]
fn claude_stop_keeps_full_final_message() {
    let ev = event(Agent::ClaudeCode, "claude_stop.json");
    assert_eq!(ev.session_id, "cc-auth-1");
    assert_eq!(ev.location.project, "auth-service");
    match ev.kind {
        EventKind::Finished { message, digest } => {
            assert!(message.starts_with("I added **rate limiting**"));
            assert!(digest.is_none(), "transcript path does not exist");
        }
        other => panic!("unexpected {other:?}"),
    }
}

#[test]
fn claude_stop_builds_digest_from_transcript() {
    let ev = event(Agent::ClaudeCode, "claude_stop_transcript.json");
    let EventKind::Finished { message, digest } = ev.kind else { panic!() };
    assert_eq!(message, "The build is fixed. A missing import in main.rs was the cause.");
    let d = digest.unwrap();
    assert_eq!(d.prompt, "fix the cart test", "earlier turns and meta messages are skipped");
    assert_eq!(d.commands, vec!["npm test -- cart"]);
    assert_eq!(d.files_changed, vec!["cart.ts"]);
    assert_eq!(d.failures, vec!["npm test -- cart: Exit code 1 cart.test.ts: expected 3 items, got 2"]);
    assert_eq!(d.tool_calls, 3);
}

#[test]
fn claude_permission_uses_description() {
    let ev = event(Agent::ClaudeCode, "claude_permission.json");
    assert_eq!(ev.kind, EventKind::ApprovalNeeded { tool: "Bash".into(), action: "remove node_modules directory".into() });
}

#[test]
fn codex_permission_falls_back_to_command() {
    let ev = event(Agent::Codex, "codex_permission.json");
    assert_eq!(ev.kind, EventKind::ApprovalNeeded { tool: "Bash".into(), action: "run rm -rf build".into() });
}

#[test]
fn approval_actions_for_other_tools() {
    let action = |tool: &str, input: serde_json::Value| {
        let payload = json!({"hook_event_name": "PermissionRequest", "tool_name": tool, "tool_input": input});
        match AgentEvent::from_hook_payload(Agent::ClaudeCode, &payload).unwrap().kind {
            EventKind::ApprovalNeeded { action, .. } => action,
            other => panic!("{other:?}"),
        }
    };
    assert_eq!(action("Edit", json!({"file_path": "/r/src/login.rs"})), "edit login.rs");
    assert_eq!(action("WebFetch", json!({"url": "https://x"})), "fetch a web page");
    assert_eq!(action("mcp__github__create_issue", json!({})), "use the create issue tool from github");
    assert_eq!(
        action("Bash", json!({"command": "find . -name '*.log' -mtime +7 -exec rm {} \\; && echo done && ls -la /tmp"})),
        "run a command starting with find . -name"
    );
    assert_eq!(action("Bash", json!({"description": "NPM install deps"})), "NPM install deps");
}

#[test]
fn stop_failure_carries_the_error() {
    let ev = event(Agent::ClaudeCode, "claude_stop_failure.json");
    assert_eq!(
        ev.kind,
        EventKind::StoppedWithError {
            error: "rate_limit".into(),
            details: "429 Too Many Requests".into(),
            message: "API Error: Rate limit reached".into()
        }
    );
}

#[test]
fn prompt_submit_and_session_events() {
    assert_eq!(event(Agent::ClaudeCode, "claude_prompt.json").kind, EventKind::PromptSubmitted);
    let end = AgentEvent::from_hook_payload(Agent::ClaudeCode, &json!({"hook_event_name": "SessionEnd"})).unwrap();
    assert_eq!(end.kind, EventKind::SessionEnded);
}

#[test]
fn mid_run_events_are_ignored() {
    for name in ["PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification", "SubagentStop"] {
        let mut payload = fixture("claude_stop.json");
        payload["hook_event_name"] = json!(name);
        assert!(AgentEvent::from_hook_payload(Agent::ClaudeCode, &payload).is_none(), "{name}");
    }
}

#[test]
fn missing_fields_do_not_panic() {
    let ev = AgentEvent::from_hook_payload(Agent::Codex, &json!({"hook_event_name": "Stop"})).unwrap();
    assert_eq!(ev.session_id, "default");
    assert_eq!(ev.location.project, "your project");
}
