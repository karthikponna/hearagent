use crate::digest::{claude_turn_digest, TurnDigest};
use crate::location::Location;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Agent {
    ClaudeCode,
    Codex,
}

impl Agent {
    pub fn from_arg(s: &str) -> Option<Agent> {
        match s {
            "claude-code" | "claude" => Some(Agent::ClaudeCode),
            "codex" => Some(Agent::Codex),
            _ => None,
        }
    }

    pub fn display_name(self) -> &'static str {
        match self {
            Agent::ClaudeCode => "Claude",
            Agent::Codex => "Codex",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum EventKind {
    SessionStarted,
    SessionEnded,
    PromptSubmitted,
    /// The agent is blocked until the user approves a tool call.
    ApprovalNeeded { tool: String, action: String },
    /// The turn finished normally.
    Finished { message: String, digest: Option<TurnDigest> },
    /// The turn ended because of an API error (rate limit, overload, auth).
    StoppedWithError { error: String, details: String, message: String },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AgentEvent {
    pub agent: Agent,
    pub session_id: String,
    pub cwd: String,
    #[serde(default)]
    pub location: Location,
    pub kind: EventKind,
}

impl AgentEvent {
    /// Parses a raw hook payload. Returns `None` for events Hear Agent ignores.
    pub fn from_hook_payload(agent: Agent, payload: &Value) -> Option<AgentEvent> {
        let transcript = str_field(payload, "transcript_path");
        let kind = match str_field(payload, "hook_event_name").as_str() {
            "SessionStart" => EventKind::SessionStarted,
            "SessionEnd" => EventKind::SessionEnded,
            "UserPromptSubmit" => EventKind::PromptSubmitted,
            "PermissionRequest" => {
                let tool = str_field(payload, "tool_name");
                let action = approval_action(&tool, payload.get("tool_input"));
                EventKind::ApprovalNeeded { tool, action }
            }
            "Stop" => {
                let digest = match agent {
                    Agent::ClaudeCode if !transcript.is_empty() => claude_turn_digest(Path::new(&transcript)),
                    _ => None,
                };
                let mut message = str_field(payload, "last_assistant_message");
                if message.trim().is_empty() {
                    message = digest.as_ref().map(|d| d.final_reply.clone()).unwrap_or_default();
                }
                EventKind::Finished { message, digest }
            }
            "StopFailure" => EventKind::StoppedWithError {
                error: str_field(payload, "error"),
                details: str_field(payload, "error_details"),
                message: str_field(payload, "last_assistant_message"),
            },
            _ => return None,
        };
        let cwd = str_field(payload, "cwd");
        Some(AgentEvent {
            agent,
            session_id: non_empty(str_field(payload, "session_id"), "default"),
            location: Location::detect(Path::new(&cwd)),
            cwd,
            kind,
        })
    }
}

fn str_field(v: &Value, key: &str) -> String {
    v.get(key).and_then(Value::as_str).unwrap_or_default().to_string()
}

fn non_empty(s: String, fallback: &str) -> String {
    if s.trim().is_empty() {
        fallback.to_string()
    } else {
        s
    }
}

/// What the agent wants to do, phrased to follow "needs approval to ...".
fn approval_action(tool: &str, input: Option<&Value>) -> String {
    let get = |k: &str| input.and_then(|i| i.get(k)).and_then(Value::as_str).map(str::trim).filter(|s| !s.is_empty());
    let file = |k: &str| get(k).map(|p| Path::new(p).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or(p.into()));
    match tool {
        "Bash" | "shell" | "exec_command" | "local_shell" => {
            if let Some(desc) = get("description") {
                return lower_first(desc.trim_end_matches('.'));
            }
            let cmd = get("command").or_else(|| get("cmd")).unwrap_or("a command");
            let first_line = cmd.lines().next().unwrap_or(cmd);
            if first_line.chars().count() > 60 || cmd.contains('\n') {
                let head: String = first_line.split_whitespace().take(3).collect::<Vec<_>>().join(" ");
                format!("run a command starting with {head}")
            } else {
                format!("run {first_line}")
            }
        }
        "Edit" | "MultiEdit" => format!("edit {}", file("file_path").unwrap_or("a file".into())),
        "Write" => format!("write {}", file("file_path").unwrap_or("a file".into())),
        "NotebookEdit" => format!("edit {}", file("notebook_path").unwrap_or("a notebook".into())),
        "WebFetch" => "fetch a web page".into(),
        "WebSearch" => "search the web".into(),
        "Task" | "Agent" => "start a subagent".into(),
        t if t.starts_with("mcp__") => {
            let mut parts = t.splitn(3, "__").skip(1);
            let server = parts.next().unwrap_or("an MCP server");
            match parts.next() {
                Some(name) => format!("use the {} tool from {}", name.replace('_', " "), server.replace('_', " ")),
                None => format!("use a tool from {server}"),
            }
        }
        "" => "continue".into(),
        t => format!("use {t}"),
    }
}

fn lower_first(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        // Keep acronyms like "NPM" or "API" intact.
        Some(c) if chars.clone().next().is_some_and(char::is_lowercase) => c.to_lowercase().chain(chars).collect(),
        Some(c) => std::iter::once(c).chain(chars).collect(),
        None => String::new(),
    }
}
