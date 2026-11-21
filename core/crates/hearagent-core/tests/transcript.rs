use hearagent_core::event::Agent;
use hearagent_core::transcript::{apply_task_tool, chat, todos, ChatRole, TodoStatus};
use serde_json::json;
use std::io::Write;

fn write(lines: &[serde_json::Value]) -> tempfile::NamedTempFile {
    let mut f = tempfile::Builder::new().suffix(".jsonl").tempfile().unwrap();
    for l in lines {
        writeln!(f, "{l}").unwrap();
    }
    f
}

#[test]
fn claude_chat_groups_tools_and_skips_system_text() {
    let f = write(&[
        json!({"type": "user", "message": {"role": "user", "content": "<command-name>/clear</command-name>"}}),
        json!({"type": "user", "message": {"role": "user", "content": "Add passkey sign-in"}, "timestamp": "2026-11-13T10:00:00Z"}),
        json!({"type": "assistant", "message": {"content": [{"type": "text", "text": "Looking at auth first."}]}}),
        json!({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "/w/auth.ts"}}]}}),
        json!({"type": "user", "message": {"content": [{"type": "tool_result", "content": "..."}]}}),
        json!({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": "pnpm test"}}]}}),
        json!({"type": "assistant", "message": {"content": [{"type": "text", "text": "Done."}]}}),
    ]);
    let items = chat(f.path(), Agent::ClaudeCode);
    let roles: Vec<ChatRole> = items.iter().map(|i| i.role).collect();
    assert_eq!(roles, vec![ChatRole::User, ChatRole::Assistant, ChatRole::Tools, ChatRole::Assistant]);
    assert_eq!(items[0].text, "Add passkey sign-in");
    assert_eq!(items[2].tools, vec!["Read /w/auth.ts".to_string(), "Bash pnpm test".to_string()]);
}

#[test]
fn codex_chat_reads_response_items() {
    let f = write(&[
        json!({"type": "response_item", "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "<environment_context>..."}]}}),
        json!({"type": "response_item", "payload": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "Speed up search"}]}}),
        json!({"type": "response_item", "payload": {"type": "function_call", "name": "shell", "arguments": "{\"command\":\"rg search\"}"}}),
        json!({"type": "response_item", "payload": {"type": "message", "role": "assistant", "content": [{"type": "output_text", "text": "Added an index."}]}}),
    ]);
    let items = chat(f.path(), Agent::Codex);
    assert_eq!(items.len(), 3);
    assert_eq!(items[1].tools, vec!["Bash rg search".to_string()]);
}

#[test]
fn task_tools_build_a_list() {
    let f = write(&[
        json!({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "TaskCreate", "input": {"subject": "Server challenge"}}]}}),
        json!({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "TaskCreate", "input": {"subject": "Passkey button"}}]}}),
        json!({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "TaskUpdate", "input": {"taskId": "1", "status": "completed"}}]}}),
        json!({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "TaskUpdate", "input": {"taskId": "2", "status": "in_progress"}}]}}),
    ]);
    let list = todos(f.path());
    assert_eq!(list.len(), 2);
    assert_eq!(list[0].status, TodoStatus::Completed);
    assert_eq!(list[1].status, TodoStatus::InProgress);
    assert_eq!(list[1].content, "Passkey button");
}

#[test]
fn todo_write_replaces_the_list() {
    let mut list = vec![];
    assert!(apply_task_tool(&mut list, "TodoWrite", &json!({"todos": [{"content": "A", "status": "completed"}, {"content": "B", "status": "pending"}]})));
    assert_eq!(list.len(), 2);
    assert!(!apply_task_tool(&mut list, "Bash", &json!({})));
}
