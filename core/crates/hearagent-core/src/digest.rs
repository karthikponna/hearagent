//! Condenses one finished turn of a Claude Code transcript (everything after
//! the user's last prompt) into the facts the summary model needs.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;

const MAX_COMMANDS: usize = 8;
const MAX_FAILURES: usize = 6;
const MAX_FILES: usize = 12;

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct TurnDigest {
    pub prompt: String,
    pub files_changed: Vec<String>,
    pub commands: Vec<String>,
    /// "npm test: Exit code 1 ..." for each tool call that failed, in order.
    pub failures: Vec<String>,
    pub tool_calls: u32,
    pub final_reply: String,
}

pub fn claude_turn_digest(transcript: &Path) -> Option<TurnDigest> {
    let file = File::open(transcript).ok()?;
    let entries: Vec<Value> = BufReader::new(file)
        .lines()
        .map_while(Result::ok)
        .filter_map(|l| serde_json::from_str(&l).ok())
        .collect();
    let start = entries.iter().rposition(is_user_prompt)?;
    let mut digest = TurnDigest { prompt: truncate(&prompt_text(&entries[start]), 300), ..Default::default() };
    let mut commands_by_id: HashMap<String, String> = HashMap::new();

    for entry in &entries[start + 1..] {
        let Some(content) = entry.pointer("/message/content").and_then(Value::as_array) else { continue };
        match entry.get("type").and_then(Value::as_str) {
            Some("assistant") => {
                let mut texts = vec![];
                for item in content {
                    match item.get("type").and_then(Value::as_str) {
                        Some("tool_use") => record_tool_use(&mut digest, &mut commands_by_id, item),
                        Some("text") => {
                            if let Some(t) = item.get("text").and_then(Value::as_str).filter(|t| !t.trim().is_empty()) {
                                texts.push(t.trim());
                            }
                        }
                        _ => {}
                    }
                }
                if !texts.is_empty() {
                    digest.final_reply = texts.join("\n");
                }
            }
            Some("user") => {
                for item in content {
                    if item.get("type").and_then(Value::as_str) == Some("tool_result")
                        && item.get("is_error").and_then(Value::as_bool) == Some(true)
                        && digest.failures.len() < MAX_FAILURES
                    {
                        let id = item.get("tool_use_id").and_then(Value::as_str).unwrap_or_default();
                        let what = commands_by_id.get(id).cloned().unwrap_or_else(|| "a tool".into());
                        digest.failures.push(format!("{what}: {}", truncate(&result_text(item), 160)));
                    }
                }
            }
            _ => {}
        }
    }
    digest.final_reply = truncate(&digest.final_reply, 4000);
    Some(digest)
}

fn record_tool_use(digest: &mut TurnDigest, commands_by_id: &mut HashMap<String, String>, item: &Value) {
    digest.tool_calls += 1;
    let name = item.get("name").and_then(Value::as_str).unwrap_or_default();
    let input = item.get("input").cloned().unwrap_or(Value::Null);
    let field = |k: &str| input.get(k).and_then(Value::as_str).unwrap_or_default().to_string();
    let label = match name {
        "Bash" => {
            let cmd = truncate(field("command").lines().next().unwrap_or_default(), 80);
            if digest.commands.len() < MAX_COMMANDS && !digest.commands.contains(&cmd) {
                digest.commands.push(cmd.clone());
            }
            cmd
        }
        "Edit" | "MultiEdit" | "Write" | "NotebookEdit" => {
            let path = if name == "NotebookEdit" { field("notebook_path") } else { field("file_path") };
            let file = Path::new(&path).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or(path);
            if digest.files_changed.len() < MAX_FILES && !digest.files_changed.contains(&file) {
                digest.files_changed.push(file.clone());
            }
            format!("{name} {file}")
        }
        other => other.to_string(),
    };
    if let Some(id) = item.get("id").and_then(Value::as_str) {
        commands_by_id.insert(id.to_string(), label);
    }
}

/// A prompt typed by the user, not a tool result or an injected meta message.
fn is_user_prompt(entry: &Value) -> bool {
    if entry.get("type").and_then(Value::as_str) != Some("user") || entry.get("isMeta").and_then(Value::as_bool) == Some(true) {
        return false;
    }
    match entry.pointer("/message/content") {
        Some(Value::String(s)) => !s.trim().is_empty(),
        Some(Value::Array(items)) => items.iter().any(|i| i.get("type").and_then(Value::as_str) == Some("text")),
        _ => false,
    }
}

fn prompt_text(entry: &Value) -> String {
    match entry.pointer("/message/content") {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(|i| i.get("text").and_then(Value::as_str))
            .collect::<Vec<_>>()
            .join(" "),
        _ => String::new(),
    }
}

fn result_text(item: &Value) -> String {
    let raw = match item.get("content") {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Array(parts)) => parts.iter().filter_map(|p| p.get("text").and_then(Value::as_str)).collect::<Vec<_>>().join(" "),
        _ => String::new(),
    };
    raw.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        format!("{}...", s.chars().take(max).collect::<String>())
    }
}
