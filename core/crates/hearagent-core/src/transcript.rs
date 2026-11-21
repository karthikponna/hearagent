//! Reads a session transcript into chat items for the dashboard, and the
//! agent's task list (TodoWrite, or TaskCreate / TaskUpdate).

use crate::event::{tool_subject, Agent};
use serde::Serialize;
use serde_json::Value;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ChatRole {
    User,
    Assistant,
    /// A run of tool calls between two messages.
    Tools,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct ChatItem {
    pub role: ChatRole,
    pub text: String,
    /// For `Tools`: one line per call, e.g. "Edit app/page.tsx".
    pub tools: Vec<String>,
    pub ts_ms: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum TodoStatus {
    Pending,
    InProgress,
    Completed,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Todo {
    pub id: String,
    pub content: String,
    pub status: TodoStatus,
}

/// The most items `chat` returns; older ones are dropped.
const MAX_ITEMS: usize = 400;

fn lines(path: &Path) -> impl Iterator<Item = Value> {
    let reader = File::open(path).ok().map(BufReader::new);
    reader.into_iter().flat_map(|r| r.lines().map_while(Result::ok)).filter_map(|l| serde_json::from_str(&l).ok())
}

fn s<'a>(v: &'a Value, key: &str) -> &'a str {
    v.get(key).and_then(Value::as_str).unwrap_or_default()
}

fn ts(v: &Value) -> i64 {
    crate::usage::parse_iso_ms(s(v, "timestamp")).unwrap_or(0)
}

/// One line for a tool call, e.g. "Bash pnpm test".
pub fn tool_line(tool: &str, input: Option<&Value>) -> String {
    let subject = tool_subject(tool, input);
    let subject = subject.lines().next().unwrap_or_default();
    let subject: String = subject.chars().take(120).collect();
    if subject.is_empty() {
        tool.to_string()
    } else {
        format!("{tool} {subject}")
    }
}

/// True for user text Claude Code writes itself (command wrappers, reminders, caveats).
fn is_system_text(t: &str) -> bool {
    let t = t.trim_start();
    t.is_empty()
        || t.starts_with("<command-")
        || t.starts_with("<local-command")
        || t.starts_with("<system-reminder>")
        || t.starts_with("Caveat:")
        || t.starts_with("[Request interrupted")
        || t.starts_with("# AGENTS.md")
        || t.starts_with("<environment_context>")
        || t.starts_with("<user_instructions>")
}

struct Builder {
    items: Vec<ChatItem>,
}

impl Builder {
    fn text(&mut self, role: ChatRole, text: &str, ts_ms: i64) {
        let text = text.trim();
        if text.is_empty() {
            return;
        }
        if let Some(last) = self.items.last_mut() {
            if last.role == role && role == ChatRole::Assistant {
                last.text.push_str("\n\n");
                last.text.push_str(text);
                return;
            }
        }
        self.items.push(ChatItem { role, text: text.to_string(), tools: vec![], ts_ms });
    }

    fn tool(&mut self, line: String, ts_ms: i64) {
        if let Some(last) = self.items.last_mut() {
            if last.role == ChatRole::Tools {
                last.tools.push(line);
                return;
            }
        }
        self.items.push(ChatItem { role: ChatRole::Tools, text: String::new(), tools: vec![line], ts_ms });
    }

    fn finish(mut self) -> Vec<ChatItem> {
        if self.items.len() > MAX_ITEMS {
            self.items.drain(..self.items.len() - MAX_ITEMS);
        }
        self.items
    }
}

pub fn chat(path: &Path, agent: Agent) -> Vec<ChatItem> {
    match agent {
        Agent::ClaudeCode => claude_chat(path),
        Agent::Codex => codex_chat(path),
    }
}

fn claude_chat(path: &Path) -> Vec<ChatItem> {
    let mut b = Builder { items: vec![] };
    for v in lines(path) {
        if v.get("isSidechain").and_then(Value::as_bool) == Some(true) || v.get("isMeta").and_then(Value::as_bool) == Some(true) {
            continue;
        }
        let t = ts(&v);
        let role = match s(&v, "type") {
            "user" => ChatRole::User,
            "assistant" => ChatRole::Assistant,
            _ => continue,
        };
        match v.pointer("/message/content") {
            Some(Value::String(text)) if role == ChatRole::User => {
                if !is_system_text(text) {
                    b.text(ChatRole::User, text, t)
                }
            }
            Some(Value::String(text)) => b.text(role, text, t),
            Some(Value::Array(blocks)) => {
                for block in blocks {
                    match s(block, "type") {
                        "text" if role == ChatRole::User && is_system_text(s(block, "text")) => {}
                        "text" => b.text(role, s(block, "text"), t),
                        "tool_use" => b.tool(tool_line(s(block, "name"), block.get("input")), t),
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }
    b.finish()
}

fn codex_chat(path: &Path) -> Vec<ChatItem> {
    let mut b = Builder { items: vec![] };
    for v in lines(path) {
        if s(&v, "type") != "response_item" {
            continue;
        }
        let t = ts(&v);
        let p = v.get("payload").cloned().unwrap_or(Value::Null);
        match s(&p, "type") {
            "message" => {
                let role = match s(&p, "role") {
                    "user" => ChatRole::User,
                    "assistant" => ChatRole::Assistant,
                    _ => continue,
                };
                for item in p.get("content").and_then(Value::as_array).into_iter().flatten() {
                    let text = s(item, "text");
                    if role == ChatRole::User && is_system_text(text) {
                        continue;
                    }
                    b.text(role, text, t);
                }
            }
            "function_call" | "custom_tool_call" | "local_shell_call" => {
                let name = match s(&p, "name") {
                    "" => "shell",
                    "shell" | "exec_command" => "Bash",
                    n => n,
                };
                let args = p
                    .get("arguments")
                    .and_then(Value::as_str)
                    .and_then(|a| serde_json::from_str::<Value>(a).ok())
                    .or_else(|| p.get("input").map(|i| if i.is_string() { serde_json::json!({ "command": i }) } else { i.clone() }))
                    .or_else(|| p.get("action").cloned());
                b.tool(tool_line(name, args.as_ref()), t);
            }
            _ => {}
        }
    }
    b.finish()
}

fn todo_status(s: &str) -> TodoStatus {
    match s {
        "in_progress" => TodoStatus::InProgress,
        "completed" => TodoStatus::Completed,
        _ => TodoStatus::Pending,
    }
}

/// Applies one task tool call to a running list. Returns whether it was a task tool.
pub fn apply_task_tool(todos: &mut Vec<Todo>, tool: &str, input: &Value) -> bool {
    match tool {
        "TodoWrite" => {
            let Some(list) = input.get("todos").and_then(Value::as_array) else { return true };
            *todos = list
                .iter()
                .enumerate()
                .map(|(i, t)| Todo {
                    id: (i + 1).to_string(),
                    content: [s(t, "content"), s(t, "subject")].into_iter().find(|c| !c.is_empty()).unwrap_or_default().to_string(),
                    status: todo_status(s(t, "status")),
                })
                .collect();
            true
        }
        "TaskCreate" => {
            let id = (todos.iter().filter_map(|t| t.id.parse::<u32>().ok()).max().unwrap_or(0) + 1).to_string();
            todos.push(Todo { id, content: s(input, "subject").to_string(), status: TodoStatus::Pending });
            true
        }
        "TaskUpdate" => {
            let id = match input.get("taskId") {
                Some(Value::String(s)) => s.clone(),
                Some(Value::Number(n)) => n.to_string(),
                _ => return true,
            };
            if let Some(todo) = todos.iter_mut().find(|t| t.id == id) {
                if !s(input, "status").is_empty() {
                    if s(input, "status") == "deleted" {
                        todos.retain(|t| t.id != id);
                        return true;
                    }
                    todo.status = todo_status(s(input, "status"));
                }
                if !s(input, "subject").is_empty() {
                    todo.content = s(input, "subject").to_string();
                }
            }
            true
        }
        _ => false,
    }
}

/// The task list as of the end of a Claude transcript.
pub fn todos(path: &Path) -> Vec<Todo> {
    let mut list = Vec::new();
    for v in lines(path) {
        if s(&v, "type") != "assistant" || v.get("isSidechain").and_then(Value::as_bool) == Some(true) {
            continue;
        }
        for block in v.pointer("/message/content").and_then(Value::as_array).into_iter().flatten() {
            if s(block, "type") == "tool_use" {
                apply_task_tool(&mut list, s(block, "name"), block.get("input").unwrap_or(&Value::Null));
            }
        }
    }
    list
}
