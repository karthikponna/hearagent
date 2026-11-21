//! Always-allow rules: approvals Hear Agent answers on its own.
//!
//! A rule is a tool name plus a pattern. Commands match exactly, or by prefix
//! when the pattern ends in `*`. Paths are matched relative to the session's
//! folder with `*` (within one segment) and `**` (any depth). An empty pattern
//! matches every call of the tool.

use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AllowRule {
    pub tool: String,
    #[serde(default)]
    pub pattern: String,
}

fn is_command_tool(tool: &str) -> bool {
    matches!(tool, "Bash" | "shell" | "exec_command" | "local_shell" | "Monitor")
}

fn is_path_tool(tool: &str) -> bool {
    matches!(tool, "Edit" | "MultiEdit" | "Write" | "Read" | "NotebookEdit" | "apply_patch")
}

/// The path as written in rules: relative to `cwd` when it lives inside it.
fn relative(path: &str, cwd: &str) -> String {
    let p = Path::new(path);
    if !cwd.is_empty() {
        if let Ok(rel) = p.strip_prefix(cwd) {
            return rel.to_string_lossy().into_owned();
        }
    }
    path.to_string()
}

pub fn matches(rule: &AllowRule, tool: &str, subject: &str, cwd: &str) -> bool {
    if rule.tool != tool {
        return false;
    }
    let pattern = rule.pattern.trim();
    if pattern.is_empty() {
        return true;
    }
    if is_path_tool(tool) {
        return glob(pattern, &relative(subject, cwd)) || glob(pattern, subject);
    }
    let subject = subject.trim();
    match pattern.strip_suffix('*') {
        Some(prefix) => subject.starts_with(prefix.trim_end()),
        None => subject == pattern,
    }
}

pub fn any_matches(rules: &[AllowRule], tool: &str, subject: &str, cwd: &str) -> bool {
    rules.iter().any(|r| matches(r, tool, subject, cwd))
}

/// The rule "Always allow" saves for a request.
pub fn suggest(tool: &str, subject: &str, cwd: &str) -> AllowRule {
    let pattern = if is_command_tool(tool) {
        subject.trim().to_string()
    } else if is_path_tool(tool) && !subject.is_empty() {
        let rel = relative(subject, cwd);
        match Path::new(&rel).parent().map(|p| p.to_string_lossy().into_owned()) {
            Some(dir) if !dir.is_empty() => format!("{dir}/**"),
            _ => rel,
        }
    } else {
        String::new()
    };
    AllowRule { tool: tool.to_string(), pattern }
}

/// `*` matches within one path segment, `**` across segments.
pub fn glob(pattern: &str, text: &str) -> bool {
    fn go(p: &[u8], t: &[u8]) -> bool {
        match p.first() {
            None => t.is_empty(),
            Some(b'*') if p.get(1) == Some(&b'*') => {
                let rest = if p.get(2) == Some(&b'/') { &p[3..] } else { &p[2..] };
                (0..=t.len()).any(|i| go(rest, &t[i..]))
            }
            Some(b'*') => (0..=t.len()).take_while(|&i| i == 0 || t[i - 1] != b'/').any(|i| go(&p[1..], &t[i..])),
            Some(c) => t.first() == Some(c) && go(&p[1..], &t[1..]),
        }
    }
    go(pattern.as_bytes(), text.as_bytes())
}
